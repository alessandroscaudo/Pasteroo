import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = ClipStore()
    private(set) lazy var monitor = ClipboardMonitor(store: store)
    /// Checks the appcast at SUFeedURL; inert in `swift run` builds, which have no Info.plist.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.bundleIdentifier != nil, updaterDelegate: nil, userDriverDelegate: nil)
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private lazy var popup = PopupController(
        store: store,
        onChoose: { [weak self] clip, paste in self?.choose(clip, paste: paste) },
        onRename: { [weak self] clip in self?.rename(clip) },
        onSettings: { [weak self] in self?.openSettings(returningToPopup: true) })
    private var settingsWindow: NSWindow?
    /// Whether closing settings brings the popup back.
    private var settingsReturnsToPopup = false
    /// App that was frontmost before settings activated Pasteroo; it gets focus back so pasting still works.
    private var appBeforeSettings: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        store.trim()
        monitor.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = .pasterooStatusIcon()
        statusItem.button?.toolTip = "Pasteroo"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKey = HotKey { [weak self] in
            guard let self else { return }
            if self.settingsWindow?.isVisible == true { self.backToPopup() } else { self.popup.toggle() }
        }
        reloadHotKey()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadHotKey()
                self?.store.trim()
                self?.statusItem.button?.appearsDisabled = !Prefs.bool(Prefs.recordHistory)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    func reloadHotKey() {
        hotKey.register(keyCode: Prefs.int(Prefs.hotKeyCode), carbonModifiers: Prefs.int(Prefs.hotKeyModifiers))
    }

    /// Puts a clipping on the pasteboard, moves it to the top and optionally pastes it.
    func choose(_ clip: Clip, paste: Bool = true) {
        monitor.write(clip.text)
        store.moveToTop(clip)
        if paste && Prefs.bool(Prefs.autoPaste) { Paster.pasteSoon() }
    }

    func rename(_ clip: Clip) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename clipping"
        alert.informativeText = "Leave empty to show the clipping's first line."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = clip.name ?? ""
        field.placeholderString = clip.title(length: 40)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            store.rename(clip.id, to: field.stringValue)
        }
        popup.show(keepingState: true)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let length = Prefs.int(Prefs.titleLength)
        let pinned = store.pinned
        let recent = store.recent.prefix(Prefs.int(Prefs.displayCount))

        if pinned.isEmpty && recent.isEmpty {
            let empty = NSMenuItem(title: "Your clippings will appear here…", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        if !pinned.isEmpty {
            menu.addItem(.sectionHeader(title: "Pinned"))
            for clip in pinned { menu.addItem(clipItem(clip, length: length, key: "")) }
            menu.addItem(.separator())
        }
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: "Recent"))
            for (index, clip) in recent.enumerated() {
                menu.addItem(clipItem(clip, length: length, key: index < 10 ? String((index + 1) % 10) : ""))
            }
        }

        menu.addItem(.separator())
        let search = NSMenuItem(title: "Open Pasteroo  \(Prefs.hotKeyDisplayValue)", action: #selector(showPopup), keyEquivalent: "")
        search.target = self
        menu.addItem(search)

        let record = NSMenuItem(title: "Record Clipboard History", action: #selector(toggleRecording), keyEquivalent: "")
        record.target = self
        record.state = Prefs.bool(Prefs.recordHistory) ? .on : .off
        menu.addItem(record)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.recent.isEmpty
        menu.addItem(clear)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let update = NSMenuItem(title: "Check for Updates…",
                                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        menu.addItem(NSMenuItem(title: "Quit Pasteroo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func clipItem(_ clip: Clip, length: Int, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: clip.title(length: length), action: #selector(pickFromMenu(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = []
        item.target = self
        item.representedObject = clip
        item.toolTip = String(clip.text.prefix(1000))
        if let icon = AppIcon.icon(for: clip.sourceBundleID)?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return item
    }

    @objc private func pickFromMenu(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? Clip else { return }
        choose(clip)
    }

    @objc private func showPopup() { popup.show() }

    @objc private func toggleRecording() {
        UserDefaults.standard.set(!Prefs.bool(Prefs.recordHistory), forKey: Prefs.recordHistory)
    }

    @objc private func clearHistory() {
        guard confirm("Delete \(store.recent.count) recent clippings?", detail: "Pinned clippings are kept.") else { return }
        store.deleteAll()
    }

    func confirm(_ message: String, detail: String = "This action cannot be undone.") -> Bool {
        guard Prefs.bool(Prefs.confirmDelete) else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc func showSettings() { openSettings(returningToPopup: false) }

    func openSettings(returningToPopup: Bool) {
        if settingsWindow == nil {
            let view = SettingsView(store: store,
                                    confirm: { [weak self] in self?.confirm($0) ?? false },
                                    onBack: { [weak self] in self?.backToPopup() })
                .environment(\.colorScheme, .light)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Pasteroo"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isVisible != true {
            settingsReturnsToPopup = returningToPopup
            let front = NSWorkspace.shared.frontmostApplication
            appBeforeSettings = front == .current ? nil : front
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Closes settings and reopens the popup over the app the user came from.
    func backToPopup() {
        settingsReturnsToPopup = true
        settingsWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        let reopen = settingsReturnsToPopup
        settingsReturnsToPopup = false
        appBeforeSettings?.activate()
        appBeforeSettings = nil
        guard reopen else { return }
        // Let the previous app take focus first, or the popup would lose key and close at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.popup.show(keepingState: true) }
    }
}

extension Prefs {
    static var hotKeyDisplayValue: String { UserDefaults.standard.string(forKey: hotKeyDisplay) ?? "" }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Pasteroo: login item change failed: \(error)")
        }
    }
}

extension NSApplication {
    /// Quits and reopens Pasteroo, e.g. so a changed privacy setting takes effect.
    func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        terminate(nil)
    }
}
