import AppKit
import SwiftUI

/// Visual language: lime-green gradient grounds, frosted glass pills, thin type,
/// small monospaced labels. Glass uses Liquid Glass on macOS 26+, Material before.
enum Theme {
    static let green = Color(red: 0.47, green: 0.76, blue: 0.36)
    static let lime = Color(red: 0.81, green: 0.86, blue: 0.37)
    static let cream = Color(red: 0.91, green: 0.89, blue: 0.70)
    static let lilac = Color(red: 0.81, green: 0.78, blue: 0.94)
    static let ink = Color(red: 0.11, green: 0.12, blue: 0.10)
    static let inkSoft = ink.opacity(0.55)

    static let ground = LinearGradient(
        stops: [
            .init(color: green, location: 0),
            .init(color: lime, location: 0.55),
            .init(color: cream, location: 1),
        ],
        startPoint: .bottomLeading, endPoint: .topTrailing)

    static let orb = RadialGradient(
        colors: [Color(red: 0.72, green: 0.90, blue: 0.45), green],
        center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26)

    static func title(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .light) }
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

extension View {
    /// Frosted glass surface in the given shape.
    func glass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.strokeBorder(.white.opacity(0.55), lineWidth: 0.8))
        }
    }
}

/// ScrollView without indicators.
struct Scroller<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView { content }.scrollIndicators(.never)
    }
}

/// Container that lets neighbouring glass shapes blend on macOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Blurs whatever is behind the window, so the gradient on top reads as tinted glass.
struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Translucent gradient ground with faint flowing lines, as in the reference boards.
/// Needs a window with a clear background for the blur to show through.
struct WaveGround: View {
    var body: some View {
        ZStack {
            BackdropBlur()
            Theme.ground.opacity(0.6)
            RadialGradient(colors: [Theme.lilac.opacity(0.4), .clear],
                           center: .init(x: 0.85, y: 0.75), startRadius: 0, endRadius: 260)
            Canvas { context, size in
                for band in [0.18, 0.82] {
                    for i in 0..<4 {
                        var path = Path()
                        let phase = Double(i) * 0.9
                        let amp = 10 + Double(i) * 4
                        let midY = size.height * band
                        path.move(to: CGPoint(x: 0, y: midY))
                        for x in stride(from: 0.0, through: size.width, by: 6) {
                            let y = midY + sin(x / size.width * .pi * 2.2 + phase) * amp
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

/// Pasteroo mark: a seated kangaroo in profile, built from simple shapes on a 10×10 grid
/// and merged into one outline so it stays crisp as a menu bar template.
struct LogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 10
        let o = CGPoint(x: rect.midX - 5 * u, y: rect.midY - 5 * u)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ degrees: Double = 0) -> CGPath {
            var t = CGAffineTransform(translationX: p(cx, cy).x, y: p(cx, cy).y).rotated(by: degrees * .pi / 180)
            return CGPath(ellipseIn: CGRect(x: -rx * u, y: -ry * u, width: 2 * rx * u, height: 2 * ry * u), transform: &t)
        }

        // Tail: thick at the haunch, tapering to a point on the ground behind.
        let tail = CGMutablePath()
        tail.move(to: p(2.9, 5.9))
        tail.addQuadCurve(to: p(0.1, 9.75), control: p(1.3, 8.7))
        tail.addQuadCurve(to: p(4.4, 8.1), control: p(2.6, 9.5))
        tail.closeSubpath()
        // Foot: long and flat.
        let foot = CGMutablePath()
        foot.addRoundedRect(in: CGRect(origin: p(3.6, 8.75), size: CGSize(width: 4.0 * u, height: 0.85 * u)),
                            cornerWidth: 0.4 * u, cornerHeight: 0.4 * u)
        // Head: rounded at the back, tapering to the snout.
        let head = CGMutablePath()
        head.move(to: p(6.2, 2.3))
        head.addQuadCurve(to: p(7.0, 1.4), control: p(6.2, 1.5))
        head.addQuadCurve(to: p(8.9, 2.6), control: p(8.2, 1.6))
        head.addQuadCurve(to: p(6.6, 3.4), control: p(8.0, 3.4))
        head.closeSubpath()

        var shape = ellipse(4.3, 6.9, 1.95, 1.95)            // haunch
        for part in [
            ellipse(5.55, 4.6, 1.1, 2.35, 26),                  // torso leaning forward
            head, tail, foot,
            ellipse(6.35, 0.95, 0.3, 0.95, -8),                 // back ear
            ellipse(6.95, 0.9, 0.3, 0.95, 14),                  // front ear
            ellipse(6.95, 5.0, 0.85, 0.27, 52),                 // forearm
        ] { shape = shape.union(part) }
        return Path(shape.subtracting(ellipse(7.45, 2.15, 0.19, 0.19))) // eye
    }
}

struct Logo: View {
    var size: CGFloat = 18
    var body: some View {
        LogoMark().fill(Theme.ink, style: FillStyle(eoFill: true)).frame(width: size, height: size)
    }
}

extension NSImage {
    /// Template image of the logo for the menu bar.
    @MainActor
    static func pasterooStatusIcon() -> NSImage {
        let renderer = ImageRenderer(content:
            LogoMark().fill(.black, style: FillStyle(eoFill: true)).frame(width: 16, height: 16).padding(1))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

/// Circular glass bubble holding an app icon or a symbol.
struct Bubble<Content: View>: View {
    var size: CGFloat = 34
    var tint: Color? = .white.opacity(0.35)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .glass(Circle(), tint: tint)
    }
}

struct AppIcon: View {
    let bundleID: String?
    var size: CGFloat = 20

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "doc.on.clipboard").font(.system(size: size * 0.6, weight: .light))
                .foregroundStyle(Theme.ink)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

/// Glass circle button with an SF Symbol.
struct CircleButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(active ? .white : Theme.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), tint: active ? Theme.green : .white.opacity(0.3), interactive: true)
        .help(L(help))
    }
}

/// Small monospaced key hint, e.g. "⌘1".
struct KeyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.label(10))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.35)))
    }
}
