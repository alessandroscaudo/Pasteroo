import AppKit
import QuickLookThumbnailing
import SwiftUI

/// One scan at a time, its result and what the user ticked. Shared by every tool pane.
@MainActor
final class ScanModel<Result: Sendable>: ObservableObject {
    enum State { case idle, scanning(String), done(Result) }
    @Published var state: State = .idle
    @Published var selection: Set<URL> = []
    /// What the last scan looked at; kept here so it survives switching panes.
    @Published var roots: [URL] = []
    private var task: Task<Void, Never>?

    var isScanning: Bool { if case .scanning = state { true } else { false } }

    var result: Result? { if case let .done(r) = state { r } else { nil } }

    /// Runs `work` off the main thread; `preselect` decides what starts ticked.
    func scan(_ work: @escaping @Sendable (_ report: @escaping @Sendable (String) -> Void) -> Result,
              preselect: @escaping (Result) -> Set<URL>) {
        task?.cancel()
        state = .scanning("")
        selection = []
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = work { text in
                // A late progress report must not revive a scan that was stopped or has finished.
                Task { @MainActor in if case .scanning = self.state { self.state = .scanning(text) } }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.state = .done(result)
                self.selection = preselect(result)
            }
        }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    /// Asks, moves the ticked items to the Trash and drops them from the list via `remove`.
    func trashSelected(bytes: Int64, remove: (Set<URL>, Result) -> Result) {
        guard let result, !selection.isEmpty, askTrash(count: selection.count, bytes: bytes) else { return }
        let failed = DiskScanner.trash(Array(selection))
        let moved = selection.subtracting(failed.map(\.0))
        state = .done(remove(moved, result))
        selection = Set(failed.map(\.0))
        if let (url, error) = failed.first {
            let alert = NSAlert()
            alert.messageText = L("%d items could not be moved to the Trash", failed.count)
            alert.informativeText = "\(url.lastPathComponent): \(error.localizedDescription)"
            alert.runModal()
        }
    }
}

/// Always asks, whatever the "confirm before deleting" setting: these are the user's files, not clippings.
@MainActor
func askTrash(count: Int, bytes: Int64) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = L("Move %d items to the Trash?", count)
    alert.informativeText = L("Frees %@. You can put them back from the Trash.", bytes.bytes)
    alert.addButton(withTitle: L("Move to Trash"))
    alert.addButton(withTitle: L("Cancel"))
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func chooseFolders() -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = L("Scan")
    return panel.runModal() == .OK ? panel.urls : []
}

// MARK: - Shared pieces

/// Tickable row: icon, name, place, size.
private struct ItemRow<Leading: View>: View {
    let item: FoundItem
    @Binding var selection: Set<URL>
    var detail: String? = nil
    @ViewBuilder var leading: Leading

    var body: some View {
        let ticked = selection.contains(item.url)
        HStack(spacing: 10) {
            Button {
                if ticked { selection.remove(item.url) } else { selection.insert(item.url) }
            } label: {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(ticked ? Theme.ink : Theme.line)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Theme.title(13.5)).lineLimit(1)
                Text(detail ?? item.place).font(Theme.label(9.5)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(item.size.bytes).font(Theme.label(11))
            CircleButton(symbol: "arrow.up.right", help: "Show in Finder", size: 24) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous), ticked ? Theme.accent.opacity(0.45) : Theme.card)
    }
}

/// Footer: counts on the left, the one black button on the right.
private struct TrashBar: View {
    let summary: String
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack {
            Text(summary).font(Theme.label()).foregroundStyle(Theme.inkSoft)
            Spacer()
            PillButton(title: L("Move %d to Trash", count), symbol: "trash", enabled: count > 0, action: action)
        }
    }
}

private struct ScanProgress: View {
    let text: String
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.label()).foregroundStyle(Theme.inkSoft)
            Button(L("Stop"), action: cancel).buttonStyle(.plain).font(Theme.label(11)).underline()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Hint: View {
    let text: String
    var body: some View {
        Text(L(text)).font(Theme.title(13)).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Quick Look thumbnail, loaded once the row is on screen. Falls back to the file icon.
private struct Thumb: View {
    let url: URL
    var size: CGFloat = 44
    @Local private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().padding(8)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: 2, representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

// MARK: - Duplicates

struct DuplicatesPane: View {
    @ObservedObject var model: ScanModel<[DuplicateGroup]>
    @AppStorage("duplicatesMediaOnly") private var mediaOnly = true
    private var roots: [URL] { model.roots }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hint(text: "Finds files with identical contents even when their names differ, like photos recovered from a formatted disk. The oldest copy is kept; the others are ticked.")
            HStack(spacing: 8) {
                PillButton(title: roots.isEmpty ? "Choose folders…" : "Scan again", symbol: "magnifyingglass") {
                    if roots.isEmpty { model.roots = chooseFolders() }
                    guard !roots.isEmpty else { return }
                    start()
                }
                if !roots.isEmpty {
                    Button { let picked = chooseFolders(); if !picked.isEmpty { model.roots = picked; start() } } label: {
                        Text(roots.map { $0.lastPathComponent }.joined(separator: ", "))
                            .font(Theme.label(11)).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 12).frame(height: 32).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .surface(Capsule(), Theme.well)
                }
                Spacer()
                Toggle(L("Photos and videos only"), isOn: $mediaOnly).toggleStyle(.switch).controlSize(.small)
                    .font(Theme.label(11)).tint(Theme.accent)
            }

            switch model.state {
            case .idle:
                Spacer()
            case let .scanning(text):
                ScanProgress(text: text, cancel: model.cancel)
            case let .done(groups):
                if groups.isEmpty {
                    Text("No duplicates found").font(Theme.title(14)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Scroller {
                        LazyVStack(spacing: 10) {
                            ForEach(groups) { group in groupCard(group) }
                        }
                    }
                    TrashBar(summary: L("%d groups · %@ reclaimable", groups.count, groups.map(\.wasted).reduce(0, +).bytes),
                             count: model.selection.count) {
                        model.trashSelected(bytes: selectedBytes(groups)) { moved, groups in
                            groups.map { DuplicateGroup(id: $0.id, files: $0.files.filter { !moved.contains($0.url) }) }
                                .filter { $0.files.count > 1 }
                        }
                    }
                }
            }
        }
    }

    private func start() {
        let roots = roots, mediaOnly = mediaOnly
        model.scan({ report in
            DuplicateFinder.find(under: roots, mediaOnly: mediaOnly) { phase in
                switch phase {
                case let .listing(n): report(L("Listing files… %d", n))
                case let .comparing(done, total): report(L("Comparing %d of %d", done, total))
                }
            }
        }, preselect: { groups in Set(groups.flatMap { $0.copies.map(\.url) }) })
    }

    private func selectedBytes(_ groups: [DuplicateGroup]) -> Int64 {
        groups.flatMap(\.files).filter { model.selection.contains($0.url) }.map(\.size).reduce(0, +)
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("%d identical files · %@ each", group.files.count, group.size.bytes))
                    .font(Theme.label(10)).foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 6)
            ForEach(group.files) { file in
                ItemRow(item: file, selection: $model.selection,
                        detail: file.place + " · " + file.date.formatted(date: .abbreviated, time: .shortened)) {
                    Thumb(url: file.url)
                }
            }
        }
        .padding(8)
        .surface(RoundedRectangle(cornerRadius: 22, style: .continuous), Theme.well)
    }
}

// MARK: - Cleanup

struct CleanupPane: View {
    enum Preset: String, CaseIterable {
        case caches, artifacts, installers, largest

        var title: String {
            switch self {
            case .caches: "Caches & logs"
            case .artifacts: "Build artifacts"
            case .installers: "Installers"
            case .largest: "Largest"
            }
        }

        var hint: String {
            switch self {
            case .caches: "Per-app caches and logs from ~/Library. Apps rebuild them; signed-in sessions are not touched."
            case .artifacts: "node_modules, .build, target, dist, build, DerivedData and friends. A build recreates them."
            case .installers: "Disk images and packages left behind after installing."
            case .largest: "What takes the most space in a folder. Open a folder to look inside it."
            }
        }

        var defaultRoots: [URL] {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .caches: return []
            case .artifacts:
                return ["Developer", "Documents", "Projects", "Sites", "Code", "Desktop"].map { home.appendingPathComponent($0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            case .installers: return ["Downloads", "Desktop"].map { home.appendingPathComponent($0) }
            case .largest: return [home]
            }
        }

        /// Items start ticked only where throwing them away is routine.
        var preselects: Bool { self != .largest }
    }

    @ObservedObject var model: ScanModel<[FoundItem]>
    @AppStorage("cleanupPreset") private var preset: Preset = .caches
    private var roots: [URL] { model.roots }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Preset.allCases, id: \.self) { item in
                    Button {
                        preset = item
                        model.roots = item.defaultRoots
                        model.cancel()
                    } label: {
                        Text(L(item.title)).font(Theme.label(11))
                            .padding(.horizontal, 12).frame(height: 28).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .surface(Capsule(), preset == item ? Theme.accent : Theme.card)
                }
            }
            Hint(text: preset.hint)
            HStack(spacing: 8) {
                PillButton(title: "Scan", symbol: "magnifyingglass") { start() }
                if preset != .caches {
                    Button { let picked = chooseFolders(); if !picked.isEmpty { model.roots = picked; start() } } label: {
                        Text(roots.map { $0.lastPathComponent }.joined(separator: ", "))
                            .font(Theme.label(11)).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 12).frame(height: 32).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .surface(Capsule(), Theme.well)
                }
                if preset == .largest, let root = roots.first, root.path != "/" {
                    CircleButton(symbol: "arrow.up", help: "Enclosing folder") {
                        model.roots = [root.deletingLastPathComponent()]
                        start()
                    }
                }
            }

            switch model.state {
            case .idle:
                Spacer()
            case let .scanning(text):
                ScanProgress(text: text, cancel: model.cancel)
            case let .done(items):
                if items.isEmpty {
                    Text("Nothing found").font(Theme.title(14)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Scroller {
                        LazyVStack(spacing: 5) {
                            ForEach(items) { item in
                                ItemRow(item: item, selection: $model.selection) {
                                    if preset == .largest && item.url.hasDirectoryPath {
                                        CircleButton(symbol: "folder", help: "Open folder", size: 28) {
                                            model.roots = [item.url]
                                            start()
                                        }
                                    } else {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                            .resizable().frame(width: 28, height: 28)
                                    }
                                }
                            }
                        }
                    }
                    TrashBar(summary: L("%d items · %@", items.count, items.map(\.size).reduce(0, +).bytes),
                             count: model.selection.count) {
                        let bytes = items.filter { model.selection.contains($0.url) }.map(\.size).reduce(0, +)
                        model.trashSelected(bytes: bytes) { moved, items in items.filter { !moved.contains($0.url) } }
                    }
                }
            }
        }
        .onAppear { if model.roots.isEmpty { model.roots = preset.defaultRoots } }
    }

    private func start() {
        let preset = preset, roots = roots
        model.scan({ report in
            report(L("Measuring…"))
            switch preset {
            case .caches: return DiskScanner.caches()
            case .artifacts: return DiskScanner.artifacts(under: roots)
            case .installers: return DiskScanner.installers(under: roots)
            case .largest: return roots.first.map { DiskScanner.largest(in: $0) } ?? []
            }
        }, preselect: { items in preset.preselects ? Set(items.map(\.url)) : [] })
    }
}

// MARK: - Uninstall

struct UninstallPane: View {
    @ObservedObject var apps: ScanModel<[FoundItem]>
    @ObservedObject var leftovers: ScanModel<[FoundItem]>
    @Local private var query = ""
    /// Bumped when any app quits, so the "is running" check is redone.
    @Local private var quitCount = 0
    /// The app being uninstalled lives in `leftovers.roots`, so it survives switching panes.
    private var app: URL? { leftovers.roots.first }

    private func running(_ app: URL) -> NSRunningApplication? {
        _ = quitCount
        guard let id = Bundle(url: app)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }

    private func back() {
        leftovers.cancel()
        leftovers.roots = []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let app {
                HStack(spacing: 10) {
                    CircleButton(symbol: "chevron.left", help: "All apps", action: back)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 32, height: 32)
                    Text(app.deletingPathExtension().lastPathComponent).font(Theme.title(18))
                    Spacer()
                    if let process = running(app) {
                        Text("Still running").font(Theme.label(11)).foregroundStyle(Theme.inkSoft)
                        PillButton(title: "Quit app", symbol: "power") { process.terminate() }
                    }
                }
                Hint(text: "The app and what it left in ~/Library. Untick anything you want to keep, like documents or settings.")
                switch leftovers.state {
                case .idle, .scanning:
                    ScanProgress(text: L("Measuring…"), cancel: back)
                case let .done(items):
                    Scroller {
                        LazyVStack(spacing: 5) {
                            ForEach(items) { item in
                                ItemRow(item: item, selection: $leftovers.selection) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable().frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                    TrashBar(summary: L("%d items · %@", items.count, items.map(\.size).reduce(0, +).bytes),
                             count: running(app) == nil ? leftovers.selection.count : 0) {
                        let bytes = items.filter { leftovers.selection.contains($0.url) }.map(\.size).reduce(0, +)
                        leftovers.trashSelected(bytes: bytes) { moved, items in items.filter { !moved.contains($0.url) } }
                        if leftovers.result?.isEmpty == true { back(); listApps() }
                    }
                }
            } else {
                Hint(text: "Pick an app to see it with its caches, preferences and support files, then move them all to the Trash.")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                    TextField("Search apps", text: $query).textFieldStyle(.plain).font(Theme.title(14))
                }
                .padding(.horizontal, 14).frame(height: 36)
                .surface(Capsule())
                switch apps.state {
                case .idle, .scanning:
                    ScanProgress(text: L("Measuring…"), cancel: apps.cancel)
                case let .done(items):
                    Scroller {
                        LazyVStack(spacing: 5) {
                            ForEach(items.filter { query.trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(query.trimmed) }) { item in
                                appRow(item)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { if apps.result == nil { listApps() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            quitCount += 1
        }
    }

    private func appRow(_ item: FoundItem) -> some View {
        Button {
            leftovers.roots = [item.url]
            leftovers.scan({ _ in DiskScanner.leftovers(of: item.url) }, preselect: { Set($0.map(\.url)) })
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 28, height: 28)
                Text(item.url.deletingPathExtension().lastPathComponent).font(Theme.title(13.5)).lineLimit(1)
                Spacer()
                Text(item.size.bytes).font(Theme.label(11)).foregroundStyle(Theme.inkSoft)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func listApps() {
        apps.scan({ _ in DiskScanner.apps() }, preselect: { _ in [] })
    }
}
