import Foundation

/// A file or folder found by a scan.
struct FoundItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let date: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
    /// Folder shown under the name, with the home folder as "~".
    var place: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Read-only walks of the disk. Nothing here deletes; `trash` is the only move and it goes to the Trash.
/// All functions are synchronous and meant to run off the main thread; they stop early when the task is cancelled.
enum DiskScanner {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .contentModificationDateKey,
    ]

    private static let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    private static func lib(_ path: String) -> URL { home.appendingPathComponent("Library/" + path, isDirectory: true) }

    private static func item(_ url: URL, size: Int64? = nil) -> FoundItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let bytes = size ?? Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        return FoundItem(url: url, size: bytes, date: values.contentModificationDate ?? .distantPast)
    }

    /// Every regular file below `roots`, skipping hidden items and the insides of packages.
    static func files(under roots: [URL], where include: (URL) -> Bool = { _ in true }) -> [FoundItem] {
        var found: [FoundItem] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in walker {
                if Task.isCancelled { return found }
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isDirectory != true, values.isSymbolicLink != true, values.isPackage != true,
                      include(url) else { continue }
                found.append(FoundItem(url: url, size: Int64(values.fileSize ?? 0),
                                       date: values.contentModificationDate ?? .distantPast))
            }
        }
        return found
    }

    /// Bytes allocated by a file or a whole folder tree.
    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey],
                                                    options: [], errorHandler: { _, _ in true })
        while let child = walker?.nextObject() as? URL {
            if Task.isCancelled { return total }
            let v = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey])
            if v?.isSymbolicLink != true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// The entries directly inside `root`, hidden ones included (~/Library is usually the answer), folders summed, largest first.
    static func largest(in root: URL, count: Int = 40) -> [FoundItem] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        return children.filter { $0.lastPathComponent != ".Trash" }.compactMap { item($0, size: size(of: $0)) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(count).map { $0 }
    }

    /// Folder names that a build recreates: safe to throw away, slow to download again.
    static let artifactNames: Set<String> = ["node_modules", ".build", "target", "dist", "build", "DerivedData", ".next", ".gradle", "Pods"]
    /// Names people also use for ordinary folders: only counted next to a project file.
    private static let ambiguousNames: Set<String> = ["target", "dist", "build"]
    private static let projectMarkers = ["package.json", "Cargo.toml", "pom.xml", "build.gradle", "build.gradle.kts",
                                         "Package.swift", "CMakeLists.txt", "pyproject.toml", "setup.py", "go.mod", "Makefile"]

    /// Build artifacts below `roots`, without looking inside them.
    /// shortcut: `build`/`dist` may be tracked by git in some projects; check `git ls-files` before offering them if that bites.
    static func artifacts(under roots: [URL]) -> [FoundItem] {
        var found: [FoundItem] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in walker {
                if Task.isCancelled { return found }
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true else { continue }
                if name == "Library" && url.deletingLastPathComponent() == home { walker.skipDescendants(); continue }
                if name.hasPrefix(".") && !artifactNames.contains(name) { walker.skipDescendants(); continue }
                guard artifactNames.contains(name) else { continue }
                if ambiguousNames.contains(name) {
                    let parent = url.deletingLastPathComponent()
                    guard projectMarkers.contains(where: { FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path) }) else { continue }
                }
                walker.skipDescendants()
                if let hit = item(url, size: size(of: url)), hit.size > 0 { found.append(hit) }
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    /// Disk images and packages below `roots`.
    static func installers(under roots: [URL]) -> [FoundItem] {
        files(under: roots) { installerExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.size > $1.size }
    }

    /// Per-app cache and log folders, plus the big developer caches.
    static func caches() -> [FoundItem] {
        var found: [FoundItem] = []
        for parent in [lib("Caches"), lib("Logs")] {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for child in children {
                if Task.isCancelled { return found }
                if let hit = item(child, size: size(of: child)), hit.size > 0 { found.append(hit) }
            }
        }
        for extra in [lib("Developer/Xcode/DerivedData"), lib("Developer/CoreSimulator/Caches"),
                      home.appendingPathComponent(".npm/_cacache"), home.appendingPathComponent(".cache")] {
            if let hit = item(extra, size: size(of: extra)), hit.size > 0 { found.append(hit) }
        }
        return found.sorted { $0.size > $1.size }
    }

    /// Apps the user can uninstall: /Applications and ~/Applications, not the system's and not Pasteroo.
    static func apps() -> [FoundItem] {
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var found: [FoundItem] = []
        for folder in folders {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for app in children where app.pathExtension == "app" && app != Bundle.main.bundleURL
                && Bundle(url: app)?.bundleIdentifier != Bundle.main.bundleIdentifier {
                if Task.isCancelled { return found }
                if let hit = item(app, size: size(of: app)) { found.append(hit) }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Where macOS apps leave their data, relative to ~/Library.
    private static let leftoverHomes = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers", "LaunchAgents",
        "Logs", "Saved Application State", "HTTPStorages", "WebKit", "Application Scripts", "Cookies",
    ]

    /// The app itself, then everything in ~/Library named after its bundle identifier or its name.
    static func leftovers(of app: URL) -> [FoundItem] {
        let bundleID = Bundle(url: app)?.bundleIdentifier?.lowercased()
        let appName = app.deletingPathExtension().lastPathComponent.lowercased()
        var found = [item(app, size: size(of: app))].compactMap { $0 }
        for folder in leftoverHomes {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: lib(folder), includingPropertiesForKeys: Array(keys), options: [])) ?? []
            for child in children {
                if Task.isCancelled { return found }
                let name = child.lastPathComponent.lowercased()
                let byID = bundleID.map { name == $0 || name.hasPrefix($0 + ".") || name.hasPrefix($0 + " ") } ?? false
                // Names match only in folders where apps use their display name, so "Mail" does not match "Mailbox".
                let byName = ["Application Support", "Caches", "Logs"].contains(folder) && name == appName
                guard byID || byName, let hit = item(child, size: size(of: child)) else { continue }
                found.append(hit)
            }
        }
        return found
    }

    /// Moves each URL to the Trash. Returns the ones that could not be moved, with the reason.
    static func trash(_ urls: [URL]) -> [(URL, Error)] {
        var failed: [(URL, Error)] = []
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed.append((url, error)) }
        }
        return failed
    }
}
