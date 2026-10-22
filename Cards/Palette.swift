import AppKit

/// Every color the app draws with: warm beige paper, a tan ribbon, brown ink.
enum Palette {
    /// Card and stack fill.
    static let paper = NSColor(hex: 0xF4ECDE)
    static let ribbon = NSColor(hex: 0xD8C5A2)
    static let ink = NSColor(hex: 0x2B2520)
    /// List markers, summary text, the card hover buttons and the edge-band chevron.
    static let inkSoft = NSColor(hex: 0x716453)
    /// The "Title" placeholder.
    static let inkFaint = NSColor(hex: 0xB3A68F)
    /// Ribbon buttons and the badge text.
    static let ribbonInk = NSColor(hex: 0x46361F)
    /// Card and stack border.
    static let line = NSColor(hex: 0x5A4630, alpha: 0.24)
    /// Fill of the hovered edge band.
    static let shade = NSColor(hex: 0x5A4630, alpha: 0.07)
    /// Stroke of the dashed slot guide.
    static let guide = NSColor(hex: 0x5A4630, alpha: 0.45)
    /// The editing border, the snapping slot guide and Clarity: On.
    static let accent = NSColor(hex: 0x823F1D)
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
