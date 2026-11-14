import AppKit
import SwiftUI

/// Visual language: flat light-grey ground, white rounded cards, pastel yellow for
/// what is active or selected, black discs for primary actions, thin type.
enum Theme {
    static let ground = Color(white: 0.955)
    static let card = Color.white
    /// Second-level fill inside a card (rows, inputs).
    static let well = Color(white: 0.925)
    static let line = Color(white: 0.86)
    static let accent = Color(red: 0.97, green: 0.97, blue: 0.48)
    static let lilac = Color(red: 0.86, green: 0.85, blue: 0.95)
    static let mist = Color(red: 0.81, green: 0.87, blue: 0.88)
    static let ink = Color(white: 0.11)
    static let inkSoft = ink.opacity(0.5)

    static func title(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .light) }
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

extension View {
    /// Flat surface in the given shape. `tint` defaults to a white card.
    func surface<S: InsettableShape>(_ shape: S, _ tint: Color = Theme.card) -> some View {
        background(shape.fill(tint))
    }
}

/// ScrollView without indicators.
struct Scroller<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView { content }.scrollIndicators(.never)
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

/// Circular disc holding an app icon or a symbol.
struct Bubble<Content: View>: View {
    var size: CGFloat = 34
    var tint: Color = Theme.well
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .surface(Circle(), tint)
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

/// Circle button with an SF Symbol: pale by default, yellow when active, black when primary.
struct CircleButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    var primary = false
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(primary ? .white : Theme.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .surface(Circle(), primary ? Theme.ink : active ? Theme.accent : Theme.well)
        .help(L(help))
    }
}

/// Black capsule with white text: the one primary action of a view.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(L(title))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .surface(Capsule(), Theme.ink)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
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
            .background(Capsule().fill(Theme.well))
    }
}

extension Int64 {
    /// "1,2 GB" in the user's locale.
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
