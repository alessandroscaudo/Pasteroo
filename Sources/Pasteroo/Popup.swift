import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus without activating Pasteroo,
/// so the previously frontmost app still receives the paste.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Query and selection shared by the popup view and its keyboard handling.
@MainActor
final class PopupModel: ObservableObject {
    let store: ClipStore
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    private var bag: AnyCancellable?

    init(store: ClipStore) {
        self.store = store
        bag = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.clampSelection() }
        }
    }

    var pinned: [Clip] { store.pinned(matching: query) }
    var recent: [Clip] { store.recent(matching: query) }
    /// Pinned first, then recent: the order used by arrows and ⌘1–⌘9.
    var items: [Clip] { pinned + recent }

    var selected: Clip? {
        let list = items
        return list.indices.contains(selection) ? list[selection] : nil
    }

    func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func select(_ clip: Clip) {
        if let index = items.firstIndex(where: { $0.id == clip.id }) { selection = index }
    }

    func reset() {
        query = ""
        selection = 0
    }

    private func clampSelection() {
        selection = min(selection, max(items.count - 1, 0))
    }
}

@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let model: PopupModel
    private let onChoose: (Clip, _ paste: Bool) -> Void
    private let onRename: (Clip) -> Void
    private let onSettings: () -> Void
    private var panel: KeyPanel?
    private var keyMonitor: Any?

    init(store: ClipStore,
         onChoose: @escaping (Clip, Bool) -> Void,
         onRename: @escaping (Clip) -> Void,
         onSettings: @escaping () -> Void) {
        self.store = store
        self.model = PopupModel(store: store)
        self.onChoose = onChoose
        self.onRename = onRename
        self.onSettings = onSettings
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? close() : show()
    }

    func show(keepingState: Bool = false) {
        if !keepingState { model.reset() }
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func makePanel() -> KeyPanel {
        let size = NSSize(width: 780, height: 500)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PopupView(
            model: model,
            perform: { [weak self] action in self?.perform(action) }
        ).environment(\.colorScheme, .light))
        return panel
    }

    /// Centers the panel on the screen that contains the mouse, slightly above middle.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - size.height / 2 + frame.height * 0.08))
    }

    // MARK: Actions

    enum Action {
        case choose(Clip, paste: Bool)
        case togglePin(Clip)
        case rename(Clip)
        case delete(Clip)
        case settings
        case close
    }

    private func perform(_ action: Action) {
        switch action {
        case let .choose(clip, paste):
            close()
            onChoose(clip, paste)
        case let .togglePin(clip):
            store.togglePin(clip.id)
            DispatchQueue.main.async { self.model.select(clip) }
        case let .rename(clip):
            close()
            onRename(clip)
        case let .delete(clip):
            store.delete(ids: [clip.id])
        case .settings:
            close()
            onSettings()
        case .close:
            close()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Keyboard map: ↑↓ move, ↵ paste, ⌥↵ copy only, ⌘1–⌘9 paste item,
    /// ⌘P pin, ⌘R rename, ⌘⌫ delete, ⌘, settings, esc close.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch Int(event.keyCode) {
        case kVK_DownArrow: model.move(1); return true
        case kVK_UpArrow: model.move(-1); return true
        case kVK_Escape: close(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let clip = model.selected { perform(.choose(clip, paste: !flags.contains(.option))) }
            return true
        case kVK_Delete where flags == .command:
            if let clip = model.selected { perform(.delete(clip)) }
            return true
        default: break
        }

        guard flags == .command else { return false }
        if let digit = Int(key), (1...9).contains(digit) {
            let list = model.items
            if list.indices.contains(digit - 1) { perform(.choose(list[digit - 1], paste: true)) }
            return true
        }
        switch key {
        case "p": if let clip = model.selected { perform(.togglePin(clip)) }; return true
        case "r": if let clip = model.selected { perform(.rename(clip)) }; return true
        case ",": perform(.settings); return true
        default: return false
        }
    }
}

// MARK: - Views

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @ObservedObject private var store: ClipStore
    let perform: (PopupController.Action) -> Void

    @AppStorage(Prefs.recordHistory) private var recording = true
    @AppStorage(Prefs.hotKeyDisplay) private var hotKey = "⇧⌘V"
    @FocusState private var searchFocused: Bool

    init(model: PopupModel, perform: @escaping (PopupController.Action) -> Void) {
        self.model = model
        self.store = model.store
        self.perform = perform
    }

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        VStack(spacing: 16) {
            header
            searchBar
            HStack(alignment: .top, spacing: 16) {
                list.frame(width: 400)
                PreviewCard(clip: model.selected, perform: perform)
            }
            footer
        }
        .padding(22)
        .frame(width: 780, height: 500)
        .background(WaveGround())
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .foregroundStyle(Theme.ink)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Logo(size: 18)
            Text("Pasteroo").font(Theme.title(20))
            Spacer()
            Text(recording ? "recording" : "paused")
                .font(Theme.label())
                .foregroundStyle(Theme.inkSoft)
            CircleButton(symbol: recording ? "pause" : "record.circle",
                         help: recording ? "Pause recording (private mode)" : "Resume recording",
                         active: !recording, size: 30) { recording.toggle() }
            CircleButton(symbol: "gearshape", help: "Settings  ⌘,", size: 30) { perform(.settings) }
        }
    }

    /// Search pill with a green orb, after the reference's voice input.
    private var searchBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.orb)
                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Theme.green.opacity(0.5), radius: 8, y: 2)

            TextField("Search clippings", text: $model.query)
                .textFieldStyle(.plain)
                .font(Theme.title(17))
                .focused($searchFocused)

            Text("\(model.items.count)")
                .font(Theme.label(11))
                .foregroundStyle(Theme.inkSoft)
            KeyHint(text: hotKey)
        }
        .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 5)
        .glass(Capsule(), tint: .white.opacity(0.25))
    }

    private var list: some View {
        let pinned = model.pinned
        let recent = model.recent
        return ScrollViewReader { proxy in
            Scroller {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if pinned.isEmpty && recent.isEmpty {
                        EmptyState(searching: !model.query.isEmpty)
                    }
                    if !pinned.isEmpty {
                        SectionLabel(text: "pinned", count: pinned.count)
                        ForEach(Array(pinned.enumerated()), id: \.element.id) { index, clip in
                            row(clip, index: index)
                        }
                    }
                    if !recent.isEmpty {
                        SectionLabel(text: "recent", count: recent.count)
                            .padding(.top, pinned.isEmpty ? 0 : 8)
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, clip in
                            row(clip, index: pinned.count + index)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.selection) { _, new in
                withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func row(_ clip: Clip, index: Int) -> some View {
        ClipRow(clip: clip, index: index, selected: index == model.selection)
            .id(index)
            .onTapGesture(count: 2) { perform(.choose(clip, paste: true)) }
            .onTapGesture { model.selection = index }
            .contextMenu {
                Button("Paste") { perform(.choose(clip, paste: true)) }
                Button("Copy") { perform(.choose(clip, paste: false)) }
                Divider()
                Button(clip.isPinned ? "Unpin" : "Pin") { perform(.togglePin(clip)) }
                Button("Rename…") { perform(.rename(clip)) }
                Divider()
                Button("Delete", role: .destructive) { perform(.delete(clip)) }
            }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↵", "paste")
            hint("⌥↵", "copy")
            hint("⌘P", "pin")
            hint("⌘R", "rename")
            hint("⌘⌫", "delete")
            Spacer()
            Text("v \(Bundle.main.shortVersion)").font(Theme.label()).foregroundStyle(Theme.inkSoft)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(text: key)
            Text(label).font(Theme.label()).foregroundStyle(Theme.inkSoft)
        }
    }
}

private struct SectionLabel: View {
    let text: String
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(Theme.label(10)).textCase(.uppercase).tracking(1.2)
            Text("\(count)").font(Theme.label(10))
            Spacer()
        }
        .foregroundStyle(Theme.ink.opacity(0.6))
        .padding(.horizontal, 8)
    }
}

private struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 10) {
            Bubble(size: 32, tint: .white.opacity(selected ? 0.6 : 0.3)) {
                AppIcon(bundleID: clip.sourceBundleID, size: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title(length: 90))
                    .font(Theme.title(14))
                    .lineLimit(1)
                Text(meta)
                    .font(Theme.label(9.5))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if clip.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.green)
            }
            if index < 9 { KeyHint(text: "⌘\(index + 1)") }
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background {
            if selected {
                shape.fill(.white.opacity(0.01)).glass(shape, tint: .white.opacity(0.55))
                    .shadow(color: Theme.ink.opacity(0.08), radius: 10, y: 4)
            } else {
                shape.fill(.white.opacity(0.12))
            }
        }
        .contentShape(shape)
        .animation(.snappy(duration: 0.15), value: selected)
    }

    private var meta: String {
        var parts: [String] = []
        if let source = clip.sourceName { parts.append(source.lowercased()) }
        parts.append(clip.date.formatted(.relative(presentation: .named)))
        if clip.name != nil { parts.append(clip.text.trimmed.components(separatedBy: .newlines).first ?? "") }
        return parts.joined(separator: " · ")
    }
}

/// Right-hand card with the full clipping and its actions (CopyClip's Quick Look).
private struct PreviewCard: View {
    let clip: Clip?
    let perform: (PopupController.Action) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            if let clip {
                HStack(spacing: 10) {
                    Bubble(size: 38, tint: .white.opacity(0.5)) { AppIcon(bundleID: clip.sourceBundleID, size: 22) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clip.name ?? clip.sourceName ?? "Clipping").font(Theme.title(16)).lineLimit(1)
                        Text(clip.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.label()).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }

                Scroller {
                    Text(clip.text)
                        .font(.system(size: 12.5, weight: .regular, design: looksLikeCode(clip.text) ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.4)))

                Text(stats(clip)).font(Theme.label()).foregroundStyle(Theme.inkSoft)

                HStack(spacing: 8) {
                    Button { perform(.choose(clip, paste: true)) } label: {
                        Label("Paste", systemImage: "arrow.down.doc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 32)
                            .background(Capsule().fill(Theme.orb))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Theme.green.opacity(0.45), radius: 6, y: 2)
                    Spacer()
                    GlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            CircleButton(symbol: clip.isPinned ? "pin.slash" : "pin",
                                         help: clip.isPinned ? "Unpin  ⌘P" : "Pin  ⌘P",
                                         active: clip.isPinned) { perform(.togglePin(clip)) }
                            CircleButton(symbol: "pencil", help: "Rename  ⌘R") { perform(.rename(clip)) }
                            CircleButton(symbol: "doc.on.doc", help: "Copy without pasting  ⌥↵") {
                                perform(.choose(clip, paste: false))
                            }
                            CircleButton(symbol: "trash", help: "Delete  ⌘⌫") { perform(.delete(clip)) }
                        }
                    }
                }
            } else {
                Spacer()
                HStack { Spacer(); Logo(size: 40).opacity(0.25); Spacer() }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(shape, tint: .white.opacity(0.2))
    }

    private func stats(_ clip: Clip) -> String {
        let lines = clip.text.components(separatedBy: .newlines).count
        return "\(clip.text.count) chars · \(lines) \(lines == 1 ? "line" : "lines")"
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let markers = ["{", "}", ";", "=>", "func ", "def ", "</", "const ", "import "]
        return markers.filter { text.contains($0) }.count >= 2
    }
}

private struct EmptyState: View {
    let searching: Bool
    var body: some View {
        VStack(spacing: 10) {
            Logo(size: 34).opacity(0.3)
            Text(searching ? "No matches" : "Your clippings will appear here…")
                .font(Theme.title(14))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 110)
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
