import Foundation

/// Localized UI text. Keys are the English strings; translations live in
/// Resources/<language>.lproj/Localizable.strings, which build-app.sh copies into the app.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Localized format string filled with the given values, e.g. `L("Delete %d clippings?", n)`.
func L(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }
