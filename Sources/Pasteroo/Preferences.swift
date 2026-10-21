import AppKit
import Carbon.HIToolbox

/// UserDefaults keys and defaults, shared by AppKit code and SwiftUI @AppStorage.
enum Prefs {
    static let recordHistory = "recordHistory"
    static let rememberLimit = "rememberLimit"
    static let displayCount = "displayCount"
    static let titleLength = "titleLength"
    static let confirmDelete = "confirmDelete"
    static let autoPaste = "autoPaste"
    static let ignoredApps = "ignoredApps"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyDisplay = "hotKeyDisplay"

    static let maxRemember = 9_999

    /// Password managers ignored out of the box.
    static let defaultIgnoredApps: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.1password.1password", name: "1Password"),
        IgnoredApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        IgnoredApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords"),
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            recordHistory: true,
            rememberLimit: 200,
            displayCount: 20,
            titleLength: 50,
            confirmDelete: true,
            autoPaste: true,
            hotKeyCode: kVK_ANSI_V,
            hotKeyModifiers: cmdKey | shiftKey,
            hotKeyDisplay: "⇧⌘V",
        ])
        if UserDefaults.standard.data(forKey: ignoredApps) == nil {
            ignored = defaultIgnoredApps
        }
    }

    static var ignored: [IgnoredApp] {
        get {
            guard let data = UserDefaults.standard.data(forKey: ignoredApps) else { return [] }
            return (try? JSONDecoder().decode([IgnoredApp].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: ignoredApps)
        }
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
}

struct IgnoredApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}
