import AppKit
import Combine

struct Clip: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date: Date
    var sourceBundleID: String?
    var sourceName: String?
    /// Custom name shown instead of the first line.
    var name: String?
    /// Set while pinned; pinned clips keep this order and never expire.
    var pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    /// Single-line title truncated to `length` characters.
    func title(length: Int) -> String {
        if let name, !name.isEmpty { return name }
        let line = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        let collapsed = line.replacingOccurrences(of: "\t", with: " ")
        guard collapsed.count > length else { return collapsed.isEmpty ? "(whitespace)" : collapsed }
        return String(collapsed.prefix(length)) + "…"
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || text.localizedCaseInsensitiveContains(query)
            || (name?.localizedCaseInsensitiveContains(query) ?? false)
            || (sourceName?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

/// History of clippings, newest first, persisted as JSON in Application Support.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?
    /// Serial, so saves land on disk in the order they were made.
    private let saveQueue = DispatchQueue(label: "it.scaudo.pasteroo.save", qos: .utility)

    init() {
        // PASTEROO_HOME overrides the data folder (used for screenshots and tests).
        let dir = ProcessInfo.processInfo.environment["PASTEROO_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pasteroo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    var pinned: [Clip] {
        clips.filter(\.isPinned).sorted { $0.pinnedAt! < $1.pinnedAt! }
    }

    var recent: [Clip] { clips.filter { !$0.isPinned } }

    func pinned(matching query: String) -> [Clip] { pinned.filter { $0.matches(query.trimmed) } }
    func recent(matching query: String) -> [Clip] { recent.filter { $0.matches(query.trimmed) } }
    func search(_ query: String) -> [Clip] { clips.filter { $0.matches(query.trimmed) } }

    /// Adds text at the top; an identical unpinned clipping is moved instead of duplicated.
    /// Text that is already pinned is not recorded again.
    func add(_ text: String, source: NSRunningApplication?) {
        if clips.contains(where: { $0.isPinned && $0.text == text }) { return }
        let name = clips.first { $0.text == text }?.name
        clips.removeAll { $0.text == text }
        clips.insert(Clip(text: text, date: Date(),
                          sourceBundleID: source?.bundleIdentifier,
                          sourceName: source?.localizedName, name: name), at: 0)
        trim()
        scheduleSave()
    }

    func moveToTop(_ clip: Clip) {
        guard !clip.isPinned, let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var item = clips.remove(at: index)
        item.date = Date()
        clips.insert(item, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: Clip.ID) {
        update(id) { $0.pinnedAt = $0.isPinned ? nil : Date() }
    }

    func rename(_ id: Clip.ID, to name: String?) {
        let trimmed = name?.trimmed
        update(id) { $0.name = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    func delete(ids: Set<Clip.ID>) {
        clips.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    /// Clears history. Pinned clippings survive unless `includingPinned`.
    func deleteAll(includingPinned: Bool = false) {
        clips.removeAll { includingPinned || !$0.isPinned }
        scheduleSave()
    }

    /// Drops the oldest unpinned clippings beyond the Remember limit.
    func trim() {
        let limit = max(1, min(Prefs.int(Prefs.rememberLimit), Prefs.maxRemember))
        var kept = 0
        let before = clips.count
        clips.removeAll { clip in
            guard !clip.isPinned else { return false }
            kept += 1
            return kept > limit
        }
        if clips.count != before { scheduleSave() }
    }

    private func update(_ id: Clip.ID, _ change: (inout Clip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[index])
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            clips = try decoder.decode([Clip].self, from: data)
        } catch {
            // Keep the unreadable file aside so the next save cannot overwrite it.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("history-broken-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            NSLog("Pasteroo: could not read history, moved it to \(aside.path): \(error)")
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = clips
        let url = fileURL
        let work = DispatchWorkItem { Self.write(snapshot, to: url) }
        saveWork = work
        saveQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes pending changes right away; called before the app quits.
    func saveNow() {
        guard let pending = saveWork, !pending.isCancelled else { return }
        pending.cancel()
        saveWork = nil
        let snapshot = clips
        let url = fileURL
        saveQueue.sync { Self.write(snapshot, to: url) }
    }

    nonisolated private static func write(_ clips: [Clip], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(clips) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
