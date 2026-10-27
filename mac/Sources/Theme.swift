// Threader's look, itself Dialed's (dialedbeans.app): raised cards with big
// radii, a heavy display face, tracked uppercase labels, ink pill buttons.
import AppKit
import SwiftUI

struct Palette {
    var paper, raised, sunk, line, ink, inkSoft, accent, amber, teal, red, button, onButton: Color
    var card, cardInk, cardAccent: Color // title cards
    var cardTitle: Color? = nil // the card's title, if not cardInk

    /// Each pairs with the other of its family for b.
    static let themes: [(name: String, palette: Palette, light: Bool, pair: String)] = [
        ("sw1comm", .sw1comm, true, "ayugloom"), ("ayugloom", .ayugloom, false, "sw1comm"),
        ("everforest-light", .everforestLight, true, "everforest-dark"), ("everforest-dark", .everforestDark, false, "everforest-light"),
        ("minischeme2-light", .minischeme2Light, true, "minischeme2-dark"), ("minischeme2-dark", .minischeme2Dark, false, "minischeme2-light"),
    ]

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

    // sainnhe/everforest, medium contrast, green accent as in threader:
    // bg0, bg1, bg2, bg4, fg, grey1, green, yellow, aqua, red; cards on bg_green
    static let everforestDark = Palette(
        paper: Color(hex: 0x2d353b), raised: Color(hex: 0x343f44), sunk: Color(hex: 0x3d484d), line: Color(hex: 0x4f585e),
        ink: Color(hex: 0xd3c6aa), inkSoft: Color(hex: 0x859289), accent: Color(hex: 0xa7c080), amber: Color(hex: 0xdbbc7f),
        teal: Color(hex: 0x83c092), red: Color(hex: 0xe67e80), button: Color(hex: 0xa7c080), onButton: Color(hex: 0x2d353b),
        card: Color(hex: 0x425047), cardInk: Color(hex: 0xd3c6aa), cardAccent: Color(hex: 0xa7c080), cardTitle: Color(hex: 0xe69875))

    static let everforestLight = Palette(
        paper: Color(hex: 0xfdf6e3), raised: Color(hex: 0xfffbef), sunk: Color(hex: 0xefebd4), line: Color(hex: 0xe0dcc7),
        ink: Color(hex: 0x5c6a72), inkSoft: Color(hex: 0x939f91), accent: Color(hex: 0x8da101), amber: Color(hex: 0xdfa000),
        teal: Color(hex: 0x35a77c), red: Color(hex: 0xf85552), button: Color(hex: 0x8da101), onButton: Color(hex: 0xfdf6e3),
        card: Color(hex: 0xf0f1d2), cardInk: Color(hex: 0x5c6a72), cardAccent: Color(hex: 0x8da101), cardTitle: Color(hex: 0xf57d26))

    // echasnovski's minischeme2 (mini.hues): bg, bg_mid / bg_edge2, bg_edge / bg_mid,
    // bg_mid2, fg, fg_mid2, azure (the accent), orange, cyan, red; cards on accent_bg
    static let minischeme2Dark = Palette(
        paper: Color(hex: 0x081823), raised: Color(hex: 0x253642), sunk: Color(hex: 0x020f19), line: Color(hex: 0x435562),
        ink: Color(hex: 0xd5d7c0), inkSoft: Color(hex: 0x91937d), accent: Color(hex: 0xa1ddff), amber: Color(hex: 0xfcc9a0),
        teal: Color(hex: 0x94e6e5), red: Color(hex: 0xffc0c4), button: Color(hex: 0xa1ddff), onButton: Color(hex: 0x081823),
        card: Color(hex: 0x003851), cardInk: Color(hex: 0xd5d7c0), cardAccent: Color(hex: 0xa1ddff), cardTitle: Color(hex: 0xfcc9a0))

    static let minischeme2Light = Palette(
        paper: Color(hex: 0xf9f0db), raised: Color(hex: 0xfff7e3), sunk: Color(hex: 0xd8cfbb), line: Color(hex: 0xb7af9b),
        ink: Color(hex: 0x34394a), inkSoft: Color(hex: 0x6c7285), accent: Color(hex: 0x006699), amber: Color(hex: 0x835200),
        teal: Color(hex: 0x008064), red: Color(hex: 0x870600), button: Color(hex: 0x006699), onButton: Color(hex: 0xf9f0db),
        card: Color(hex: 0xc6e8ff), cardInk: Color(hex: 0x34394a), cardAccent: Color(hex: 0x006699), cardTitle: Color(hex: 0x835200))

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
