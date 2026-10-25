// Threader's look, itself Dialed's (dialedbeans.app): raised cards with big
// radii, a heavy display face, tracked uppercase labels, ink pill buttons.
import AppKit
import SwiftUI

struct Palette {
    var paper, raised, sunk, line, ink, inkSoft, accent, amber, teal, red, button, onButton: Color
    var card, cardInk, cardAccent: Color // title cards
    var cardTitle: Color? = nil // the card's title, if not cardInk

    static let themes: [(name: String, palette: Palette, light: Bool)] = [("sw1comm", .sw1comm, true), ("ayugloom", .ayugloom, false)]

    static let ayugloom = Palette(
        paper: Color(hex: 0x0f131a), raised: Color(hex: 0x1a1f29), sunk: Color(hex: 0x2d2d42), line: Color(hex: 0x34344b),
        ink: Color(hex: 0xb3b1ad), inkSoft: Color(hex: 0x6f7f9b), accent: Color(hex: 0x57c0fe), amber: Color(hex: 0xffb179),
        teal: Color(hex: 0x94e5c9), red: Color(hex: 0xff795b), button: Color(hex: 0x57c0fe), onButton: Color(hex: 0x0f131a),
        card: Color(hex: 0x242b3f), cardInk: Color(hex: 0xb3b1ad), cardAccent: Color(hex: 0x57c0fe), cardTitle: Color(hex: 0xffb179))

    static let sw1comm = Palette(
        paper: Color(hex: 0xd4d4d4), raised: Color(hex: 0xe2e2e2), sunk: Color(hex: 0xc6c6c6), line: Color(hex: 0xb4b4bc),
        ink: Color(hex: 0x202020), inkSoft: Color(hex: 0x5f6078), accent: Color(hex: 0x0000a0), amber: Color(hex: 0x0048c8),
        teal: Color(hex: 0x45763c), red: Color(hex: 0xd00000), button: Color(hex: 0x0000a0), onButton: Color(hex: 0xd4d4d4),
        card: Color(hex: 0x0000a0), cardInk: Color(hex: 0xffffff), cardAccent: Color(hex: 0xa5c6f2))

    /// The palette inside a title card: the theme's heading colours.
    var onCard: Palette {
        var c = self
        c.raised = card; c.ink = cardInk; c.inkSoft = cardInk.opacity(0.7)
        c.sunk = .white.opacity(0.13); c.line = .white.opacity(0.18)
        c.accent = cardAccent; c.amber = cardAccent
        c.button = cardInk; c.onButton = card
        return c
    }

    /// The terminal app's priority dot: red, amber, teal, or a faint one for none.
    func priority(_ p: String) -> Color {
        switch p {
        case "high": red
        case "medium": amber
        case "low": teal
        default: line
        }
    }

    /// Overdue red, today teal, the next two days amber.
    func due(_ d: Date, _ now: Date = Date()) -> Color {
        let days = cal.dateComponents([.day], from: day(now), to: day(d)).day!
        return days < 0 ? red : days == 0 ? teal : days < 3 ? amber : inkSoft
    }

    /// A colour per list name, the same on every launch.
    func list(_ name: String) -> Color {
        let colors = [accent, teal, amber, red, inkSoft]
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return colors[h % colors.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

// One family throughout (Maple Mono unless set); missing, the system monospace stands in.
func display(_ size: CGFloat) -> Font { font(fontName, size, .bold) }
func face(_ size: CGFloat = 15, _ w: Font.Weight = .regular) -> Font { font(fontName, size, w) }

/// Makes the bundled Maple Mono available to this process.
func registerFonts() {
    let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
    CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil) // already installed: harmless failure
}

let installed = Set(NSFontManager.shared.availableFontFamilies) // after registerFonts

/// The text size setting over the default 15pt; views are
/// rebuilt when it changes (Store.fontSize).
var fontScale: CGFloat = 1
var fontName = "Maple Mono" // the font setting (Store.fontFamily)
var regularFace: String?    // PostScript name of the chosen style (Store.fontStyle), standing in for regular

/// Lists a family's upright styles, lightest first, with the
/// PostScript name of each.
func fontStyles(_ family: String) -> [(style: String, face: String)] {
    (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { m in
        guard m.count >= 4, let face = m[0] as? String, let style = m[1] as? String, let traits = m[3] as? Int,
              traits & Int(NSFontTraitMask.italicFontMask.rawValue) == 0 else { return nil }
        return (style, face)
    }
}

func font(_ family: String, _ size: CGFloat, _ w: Font.Weight) -> Font {
    let size = size * fontScale
    if w == .regular, family == fontName, let face = regularFace { return .custom(face, size: size) }
    return installed.contains(family) ? .custom(family, size: size).weight(w) : .system(size: size, weight: w, design: .monospaced)
}

/// The small tracked uppercase line Dialed puts over its cards.
struct Caps: View {
    let text: String
    var color: Color
    var size: CGFloat = 11
    var body: some View {
        Text(text.uppercased()).font(face(size, .semibold)).tracking(1.5).foregroundStyle(color)
    }
}

struct Pill: ButtonStyle {
    let p: Palette
    var primary = false
    func makeBody(configuration c: Configuration) -> some View { Label(c: c, p: p, primary: primary) }

    struct Label: View {
        let c: Configuration
        let p: Palette
        let primary: Bool
        @Environment(\.isEnabled) var enabled
        var body: some View {
            c.label.font(face(13, .semibold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(primary ? p.onButton : p.ink)
                .background(Capsule().fill(primary ? p.button : p.sunk))
                .opacity(!enabled ? 0.4 : c.isPressed ? 0.7 : 1)
        }
    }
}

/// Dialed's card: lifted off the paper, a hairline edge.
struct Raised: ViewModifier {
    let p: Palette
    var radius: CGFloat = 24
    var alpha = 1.0 // < 1 lets the window's see-through background show
    var shown = true // the cards setting: off, no fill, edge or shadow
    var glass = false
    @ViewBuilder func body(content: Content) -> some View {
        if !shown { content }
        else if glass, #available(macOS 26, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius)) }
        else { card(content) }
    }
    func card(_ content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(p.raised.opacity(alpha)))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(p.line))
            .shadow(color: .black.opacity(alpha < 1 ? 0 : 0.10), radius: 14, y: 8) // a shadow under glass reads as smudge
    }
}

extension Store {
    var p: Palette { Palette.themes.first { $0.name == theme }?.palette ?? .ayugloom }
    var light: Bool { Palette.themes.first { $0.name == theme }?.light ?? false }
}
