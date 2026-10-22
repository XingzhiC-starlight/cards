import AppKit

/// Every color the app draws with: warm beige paper, a tan ribbon, brown ink.
enum Palette {
    /// Tint over the frosted glass: the card body, and the stack's.
    static let paper = NSColor(hex: 0xF4ECDE, alpha: 0.78)
    static let ribbon = NSColor(hex: 0xE6D8BC, alpha: 0.85)
    /// The blur behind every card and the stack.
    static let glassMaterial: NSVisualEffectView.Material = .popover
    /// The soft light at a card's top edge.
    static let sheen = NSColor.white
    /// The bright specular edge just inside the outline.
    static let rim = NSColor.white
    static let ink = NSColor(hex: 0x2B2520)
    /// List markers, summary text, the card hover buttons, the edge-band chevron and Clarity when off.
    static let inkSoft = NSColor(hex: 0x716453)
    /// The "Title" placeholder.
    static let inkFaint = NSColor(hex: 0xB3A68F)
    /// New, the ribbon's icon buttons and the badge text.
    static let ribbonInk = NSColor(hex: 0x46361F)
    /// Card and stack border.
    static let line = NSColor(hex: 0x5A4630, alpha: 0.18)
    /// Fill of the hovered edge band.
    static let shade = NSColor(hex: 0x5A4630, alpha: 0.07)
    /// Stroke of the dashed slot guide.
    static let guide = NSColor(hex: 0x5A4630, alpha: 0.45)
    /// The snapping slot guide and Clarity when on.
    static let accent = NSColor(hex: 0x823F1D)
    /// The editing border: light caramel, so the card you type in is marked without a dark frame.
    static let focus = NSColor(hex: 0xDDB880)
    /// The "Desktop full" label.
    static let danger = NSColor(hex: 0x9A2818)
    /// Text selection background in the editor.
    static let highlight = NSColor(hex: 0xE8D5AE)
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
