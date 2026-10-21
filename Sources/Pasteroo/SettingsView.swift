import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ClipStore
    let confirm: (String) -> Bool
    var onBack: () -> Void = {}

    enum Pane: String, CaseIterable {
        case general, ignored, history

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .ignored: "hand.raised"
            case .history: "clock"
            }
        }

        var title: String {
            switch self {
            case .general: "General"
            case .ignored: "Ignored apps"
            case .history: "History"
            }
        }
    }

    @Local private var pane: Pane = .general

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            rail
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.title).font(Theme.title(28))
                    Text("pasteroo · v \(Bundle.main.shortVersion)")
                        .font(Theme.label()).foregroundStyle(Theme.inkSoft)
                }
                Group {
                    switch pane {
                    case .general: GeneralPane()
                    case .ignored: IgnoredAppsPane()
                    case .history: HistoryPane(store: store, confirm: confirm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, 38).padding([.horizontal, .bottom], 22)
        .frame(width: 640, height: 520)
        .foregroundStyle(Theme.ink)
        .background(WaveGround().ignoresSafeArea())
    }

    private var rail: some View {
        VStack(spacing: 10) {
            Bubble(size: 42, tint: .white.opacity(0.6)) { Logo(size: 18) }
                .padding(.bottom, 8)
            GlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(Pane.allCases, id: \.self) { item in
                        CircleButton(symbol: item.symbol, help: item.title, active: pane == item, size: 38) {
                            withAnimation(.snappy(duration: 0.2)) { pane = item }
                        }
                    }
                }
            }
            Spacer()
            CircleButton(symbol: "chevron.left", help: "Back to clippings  esc", size: 38, action: onBack)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// Rounded glass card that groups settings rows.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: .white.opacity(0.35))
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title(14))
                    if let detail {
                        Text(detail).font(Theme.label(9.5)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                trailing
            }
            .padding(.vertical, 9)
            if divider { Rectangle().fill(Theme.ink.opacity(0.08)).frame(height: 1) }
        }
    }
}

/// − value + control drawn as a glass pill.
private struct NumberPill: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 4) {
            button("minus") { value = max(range.lowerBound, value - step) }
            Text("\(value)").font(Theme.label(12)).frame(minWidth: 44)
            button("plus") { value = min(range.upperBound, value + step) }
        }
        .padding(3)
        .glass(Capsule(), tint: .white.opacity(0.3))
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.white.opacity(0.5)))
    }
}

// MARK: General

private struct GeneralPane: View {
    @AppStorage(Prefs.recordHistory) private var recordHistory = true
    @AppStorage(Prefs.rememberLimit) private var rememberLimit = 200
    @AppStorage(Prefs.displayCount) private var displayCount = 20
    @AppStorage(Prefs.titleLength) private var titleLength = 50
    @AppStorage(Prefs.autoPaste) private var autoPaste = true
    @AppStorage(Prefs.confirmDelete) private var confirmDelete = true
    @Local private var startAtLogin = LoginItem.isEnabled
    @Local private var trusted = Paster.isTrusted

    var body: some View {
        Scroller {
            VStack(spacing: 12) {
                Card {
                    Row(title: "Open Pasteroo", detail: "global shortcut for the popup") { ShortcutRecorder() }
                    Row(title: "Record clipboard history", detail: "off = private mode") {
                        Toggle("", isOn: $recordHistory).labelsHidden()
                    }
                    if !ClipboardMonitor.canReadFreely {
                        Row(title: "Clipboard access",
                            detail: "asked on every copy · allow, then restart") {
                            HStack(spacing: 8) {
                                PillButton(title: "Open settings") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!)
                                }
                                PillButton(title: "Restart") { NSApp.relaunch() }
                            }
                        }
                    }
                    Row(title: "Start at login", divider: false) {
                        Toggle("", isOn: $startAtLogin).labelsHidden()
                            .onChange(of: startAtLogin) { _, on in LoginItem.set(on) }
                    }
                }
                Card {
                    Row(title: "Remember", detail: "pinned clippings never expire") {
                        NumberPill(value: $rememberLimit, range: 10...Prefs.maxRemember, step: 10)
                    }
                    Row(title: "Show in menu bar menu") {
                        NumberPill(value: $displayCount, range: 1...min(rememberLimit, 100))
                    }
                    Row(title: "Title length", detail: "characters", divider: false) {
                        NumberPill(value: $titleLength, range: 10...200, step: 5)
                    }
                }
                Card {
                    Row(title: "Paste after choosing", detail: trusted || !autoPaste ? nil : "needs accessibility permission") {
                        HStack(spacing: 8) {
                            if autoPaste && !trusted {
                                PillButton(title: "Grant") {
                                    Paster.requestPermission()
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                                }
                            }
                            Toggle("", isOn: $autoPaste).labelsHidden()
                        }
                    }
                    Row(title: "Confirm before deleting", divider: false) {
                        Toggle("", isOn: $confirmDelete).labelsHidden()
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.green)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = Paster.isTrusted
        }
    }
}

/// Small green capsule button for permission fixes.
private struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.label(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 24)
            .background(Capsule().fill(Theme.orb))
    }
}

private struct ShortcutRecorder: View {
    @AppStorage(Prefs.hotKeyDisplay) private var display = "⇧⌘V"
    @Local private var recording = false
    @Local private var monitor: Any? = nil

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "type shortcut…" : display)
                .font(Theme.label(12))
                .foregroundStyle(recording ? .white : Theme.ink)
                .padding(.horizontal, 14).frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), tint: recording ? Theme.green : .white.opacity(0.4), interactive: true)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            guard !flags.intersection([.command, .option, .control]).isEmpty,
                  let key = event.charactersIgnoringModifiers, !key.isEmpty else { return nil }
            let defaults = UserDefaults.standard
            defaults.set(Int(event.keyCode), forKey: Prefs.hotKeyCode)
            defaults.set(HotKey.carbonModifiers(from: flags), forKey: Prefs.hotKeyModifiers)
            display = HotKey.display(flags: flags, key: key == " " ? "Space" : key)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: Ignored apps

private struct IgnoredAppsPane: View {
    @Local private var apps = Prefs.ignored

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing copied while these apps are in front is recorded. Content marked as concealed, like passwords, is always skipped.")
                .font(Theme.title(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Scroller {
                VStack(spacing: 6) {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            Bubble(size: 30, tint: .white.opacity(0.4)) { AppIcon(bundleID: app.bundleID, size: 18) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(Theme.title(14))
                                Text(app.bundleID).font(Theme.label(9.5)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            CircleButton(symbol: "xmark", help: "Remove", size: 26) {
                                apps.removeAll { $0.id == app.id }
                            }
                        }
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.25)))
                    }
                }
            }

            Button(action: addApp) {
                Label("Add app", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(Theme.orb))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: Theme.green.opacity(0.45), radius: 6, y: 2)
        }
        .onChange(of: apps) { _, new in Prefs.ignored = new }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !apps.contains(where: { $0.bundleID == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(IgnoredApp(bundleID: id, name: name))
        }
    }
}

// MARK: History

private struct HistoryPane: View {
    @ObservedObject var store: ClipStore
    let confirm: (String) -> Bool
    @Local private var query = ""
    @Local private var selection: Set<Clip.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                TextField("Search clippings", text: $query).textFieldStyle(.plain).font(Theme.title(14))
            }
            .padding(.horizontal, 14).frame(height: 36)
            .glass(Capsule(), tint: .white.opacity(0.3))

            Scroller {
                LazyVStack(spacing: 5) {
                    ForEach(store.search(query)) { clip in
                        historyRow(clip)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("\(store.pinned.count) pinned · \(store.recent.count) recent")
                    .font(Theme.label()).foregroundStyle(Theme.inkSoft)
                Spacer()
                pillButton("Delete selected", enabled: !selection.isEmpty) {
                    let n = selection.count
                    if confirm(n == 1 ? "Delete the selected clipping?" : "Delete \(n) selected clippings?") {
                        store.delete(ids: selection)
                        selection = []
                    }
                }
                pillButton("Delete all", enabled: !store.clips.isEmpty) {
                    if confirm("Delete all \(store.clips.count) clippings, pinned included?") {
                        store.deleteAll(includingPinned: true)
                        selection = []
                    }
                }
            }
        }
    }

    private func historyRow(_ clip: Clip) -> some View {
        let isSelected = selection.contains(clip.id)
        return HStack(spacing: 10) {
            AppIcon(bundleID: clip.sourceBundleID, size: 16)
            Text(clip.title(length: 70)).font(Theme.title(13)).lineLimit(1)
            Spacer()
            Text(clip.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.label(9.5)).foregroundStyle(Theme.inkSoft)
            Button { store.togglePin(clip.id) } label: {
                Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(clip.isPinned ? Theme.green : Theme.inkSoft)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(clip.isPinned ? "Unpin" : "Pin")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(isSelected ? 0.7 : 0.22)))
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if isSelected { selection.remove(clip.id) } else { selection.insert(clip.id) }
            } else {
                selection = isSelected && selection.count == 1 ? [] : [clip.id]
            }
        }
    }

    private func pillButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(11))
                .padding(.horizontal, 12).frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), tint: .white.opacity(0.35), interactive: true)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}
