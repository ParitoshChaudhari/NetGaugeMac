import SwiftUI

// MARK: - Apple Notes / Google Keep Color Scheme

/// Global design system inspired by Apple Notes & Google Keep dark paper and amber gold.
/// Features warm espresso/charcoal background, soft parchment typography,
/// and iconic honey-amber accent highlights.
public enum NotesTheme {
    /// Warm dark background matching Apple Notes / Google Keep dark paper (#221E1A)
    public static let bgBase        = Color(red: 0.133, green: 0.118, blue: 0.102)
    /// Warm card container background (#2C2620)
    public static let bgCard        = Color(red: 0.173, green: 0.149, blue: 0.125)
    /// Slightly elevated surface for insets, hover states, and chips (#383028)
    public static let bgCardHover   = Color(red: 0.220, green: 0.188, blue: 0.157)
    /// Subtle warm border with gentle amber resonance
    public static let border        = Color(red: 0.360, green: 0.310, blue: 0.250)
    /// Highlight border with explicit Notes Amber glow
    public static let borderAccent  = Color(red: 0.961, green: 0.730, blue: 0.220).opacity(0.24)

    /// Signature Apple Notes / Google Keep honey-amber accent (#F5BA38)
    public static let accent        = Color(red: 0.961, green: 0.730, blue: 0.220)
    /// Brighter amber for hover and interactive highlights (#FFCC52)
    public static let accentHover   = Color(red: 1.000, green: 0.800, blue: 0.320)
    /// Subtle translucent amber fill for chips, pills, and icon circles
    public static let accentBg      = Color(red: 0.961, green: 0.730, blue: 0.220).opacity(0.12)
    /// Border tint for amber badges
    public static let accentBorder  = Color(red: 0.961, green: 0.730, blue: 0.220).opacity(0.35)

    /// Download traffic accent: warm bright amber (#F5BA38)
    public static let download      = Color(red: 0.961, green: 0.730, blue: 0.220)
    /// Upload traffic accent: warm terracotta / cinnamon complement (#E08559)
    public static let upload        = Color(red: 0.880, green: 0.520, blue: 0.350)

    /// Primary text: crisp warm parchment white (#FAF6EF)
    public static let textPrimary   = Color(red: 0.980, green: 0.964, blue: 0.937)
    /// Secondary text: warm muted beige (#B8ADA0)
    public static let textSecondary = Color(red: 0.720, green: 0.680, blue: 0.627)
    /// Tertiary / muted text: soft stone gray (#807567)
    public static let textMuted     = Color(red: 0.500, green: 0.460, blue: 0.404)

    /// Card dividers and rules (#3A332B)
    public static let divider       = Color(red: 0.227, green: 0.200, blue: 0.169)
    /// Softer organic green for success and granted permissions
    public static let green         = Color(red: 0.365, green: 0.722, blue: 0.420)
    /// Softer warm coral red for destructive actions
    public static let red           = Color(red: 0.898, green: 0.325, blue: 0.325)
}
