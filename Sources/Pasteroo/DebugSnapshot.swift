import AppKit
import SwiftUI

/// `--snapshot <dir>` renders the popup and settings to PNGs, for checking
/// layout without screen-recording permission. Glass renders as a flat approximation.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(store: ClipStore) {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)

        let model = PopupModel(store: store)
        model.selection = 2
        render(PopupView(model: model, perform: { _ in }), size: NSSize(width: 780, height: 500),
               to: dir.appendingPathComponent("popup.png"))
        render(SettingsView(store: store, confirm: { _ in false }), size: NSSize(width: 640, height: 520),
               to: dir.appendingPathComponent("settings.png"))
        NSApp.terminate(nil)
    }

    private static func render(_ view: some View, size: NSSize, to url: URL) {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, .light)
            .environment(\.isSnapshot, true)
            .frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
