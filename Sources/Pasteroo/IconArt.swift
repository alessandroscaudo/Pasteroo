import AppKit
import SwiftUI

/// App icon artwork on the 1024 pt macOS grid: an 824 pt light-grey rounded square,
/// a pastel yellow disc and the kangaroo mark in ink.
struct IconArt: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            Theme.ground
            Circle()
                .fill(Theme.accent)
                .frame(width: 560, height: 560)
            LogoMark()
                .fill(Theme.ink, style: FillStyle(eoFill: true))
                .frame(width: 380, height: 380)
                .offset(x: -6, y: -4)
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
        .frame(width: 1024, height: 1024)
    }

    /// `--icon <file.png>` writes the 1024 px artwork and exits; used by build-app.sh.
    @MainActor
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--icon"), args.indices.contains(flag + 1) else { return }
        let renderer = ImageRenderer(content: IconArt().environment(\.colorScheme, .light))
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: args[flag + 1])) } catch { exit(1) }
        exit(0)
    }
}
