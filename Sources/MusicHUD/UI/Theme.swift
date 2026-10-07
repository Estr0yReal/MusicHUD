import MusicHUDCore
import SwiftUI

/// Every colour in the HUD, in one place.
///
/// The palette is intentionally narrow: a few steps of white on a dark tint.
/// The brief rules out saturated colour, and the reference design gets all of
/// its character from translucency and typography rather than hue.
enum HUDTheme {

    /// Track title — highest opacity on the card's text.
    static let primaryText = Color(white: 0.98)
    /// The `来自 <artist>` line — medium emphasis.
    static let tertiaryText = Color(white: 0.62)
    /// Detail values, e.g. the album name — lower opacity, still readable.
    static let secondaryText = Color(white: 0.50)
    /// Detail labels such as 标题 / 艺术家 / 专辑 — structural, not content.
    static let quaternaryText = Color(white: 0.30)
    /// Clock caption.
    static let mutedText = Color(white: 0.42)
    /// Transport labels. Raised from the caption grey in Phase 6 so
    /// `← PREVIOUS` and `NEXT →` are legible without competing with the title.
    static let transportText = Color(white: 0.54)

    /// Metadata separator.
    ///
    /// Fractionally stronger than the 0.10 used elsewhere so the rule reads as a
    /// deliberate division between metadata and controls, while staying a
    /// hairline rather than becoming a band.
    static let hairline = Color.white.opacity(0.13)
    /// Border around the card.
    static let cardBorder = Color.white.opacity(0.085)
    /// A slight sheen across the top of the card so it reads as glass.
    static let cardSheen = Color.white.opacity(0.045)

    /// Lit seven-segment strokes. Fully opaque on purpose: overlapping strokes
    /// would show seams if the colour carried any transparency.
    static let clockDigit = Color(white: 0.94)

    /// Unlit strokes, mimicking the faint "ghost" digits of a real LCD.
    ///
    /// This must be a faint *light* overlay, not a dark grey. A dark ghost is
    /// darker than the panel behind it, so unlit segments read as solid black
    /// bars and the digits become unreadable — which is exactly what happened
    /// on the first build.
    ///
    /// Lowered from 0.06 in Phase 5: the ghost should hint at the segment
    /// structure, not compete with the lit digits.
    static let clockGhost = Color.white.opacity(0.045)

    /// Halo drawn behind lit segments to make them read as emissive.
    static let clockGlow = Color(white: 0.92).opacity(0.30)

    /// Convert a palette entry from the logic layer into a SwiftUI colour.
    static func color(_ rgb: RGB, opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }
}
