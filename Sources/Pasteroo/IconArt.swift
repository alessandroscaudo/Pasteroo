import AppKit
import SwiftUI

/// App icon artwork on the 1024 pt macOS grid: an 824 pt rounded square with drop shadow,
/// lime gradient ground, flowing lines and the kangaroo mark on a glass disc.
struct IconArt: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            Theme.ground
            RadialGradient(colors: [Theme.lilac.opacity(0.7), .clear],
                           center: .init(x: 0.95, y: 0.95), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [.white.opacity(0.45), .clear],
                           center: .init(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            Canvas { context, size in
                for i in 0..<5 {
                    var path = Path()
                    let phase = Double(i) * 0.8
                    let amp = 26 + Double(i) * 9
                    let midY = size.height * 0.8
                    path.move(to: CGPoint(x: 0, y: midY))
                    for x in stride(from: 0.0, through: size.width, by: 4) {
                        path.addLine(to: CGPoint(x: x, y: midY + sin(x / size.width * .pi * 2 + phase) * amp))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 3)
                }
            }
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 4))
                .frame(width: 560, height: 560)
                .shadow(color: Theme.ink.opacity(0.12), radius: 30, y: 16)
            LogoMark()
                .fill(Theme.ink, style: FillStyle(eoFill: true))
                .frame(width: 380, height: 380)
                .offset(x: -6, y: -4)
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 3))
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
