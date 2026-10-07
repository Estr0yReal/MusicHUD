import CoreGraphics

/// Every dimension of the HUD, derived from the current window size.
///
/// The layout is proportional: one uniform `scale` drives all sizes, so the
/// component keeps the reference design's proportions at any window size and
/// can never overflow its own card. This lives in the logic target because it
/// is plain arithmetic and is unit tested.
public struct HUDMetrics: Equatable, Sendable {

    /// Size of the card the HUD is drawn into.
    public let containerWidth: CGFloat
    public let containerHeight: CGFloat
    /// Uniform scale factor, `1.0` at the 300 × 420 design size.
    public let scale: CGFloat

    /// The size every base measurement below is expressed against.
    public static let designSize = CGSize(width: 300, height: 420)
    /// Total height of the content stack at `scale == 1`.
    public static let designContentHeight: CGFloat = 400

    public init(containerWidth: CGFloat, containerHeight: CGFloat, minimumScale: CGFloat = 0.78, maximumScale: CGFloat = 2.1) {
        self.containerWidth = max(containerWidth, 1)
        self.containerHeight = max(containerHeight, 1)
        let horizontal = containerWidth / Self.designSize.width
        let vertical = containerHeight / Self.designSize.height
        self.scale = min(max(min(horizontal, vertical), minimumScale), maximumScale)
    }

    /// Scales a design-space value.
    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    // MARK: Horizontal rhythm

    /// Padding between the card edge and the content.
    public var padding: CGFloat { s(15) }
    /// Horizontal padding for the full-bleed bands (spectrum, rules).
    public var bleedPadding: CGFloat { s(11) }
    /// Width available to padded content.
    public var contentWidth: CGFloat { max(containerWidth - padding * 2, 1) }

    // MARK: Artwork

    /// The reference design keeps the artwork small — roughly a quarter of the card width.
    public var artworkSize: CGFloat { s(70) }
    public var artworkCornerRadius: CGFloat { s(7) }

    // MARK: Type

    /// Track title — the strongest metadata text.
    ///
    /// Phase 6 raised this from 11.5 and left the artist close to where it was,
    /// so the hierarchy comes from the *gap* rather than from making everything
    /// brighter. Visual order is title > artist > album.
    public var titleFontSize: CGFloat { s(13) }
    /// Artist line, under the title.
    public var subtitleFontSize: CGFloat { s(10.2) }
    /// Album / source rows in the detail list.
    public var detailFontSize: CGFloat { s(9.2) }
    public var transportFontSize: CGFloat { s(9.6) }

    /// Letter spacing for the uppercase transport labels.
    public var transportTracking: CGFloat { s(1.0) }
    /// Minimum hit width for a transport control.
    ///
    /// The glyphs are tiny by design, so the *target* is enlarged without
    /// enlarging anything visible.
    public var transportHitWidth: CGFloat { s(82) }
    public var captionFontSize: CGFloat { s(9.3) }
    public var badgeFontSize: CGFloat { s(7.4) }
    public var captionTracking: CGFloat { s(0.6) }
    public var titleTracking: CGFloat { s(0.9) }

    // MARK: Vertical rhythm

    public var spacingAfterArtwork: CGFloat { s(10) }
    public var spacingAfterTitle: CGFloat { s(3) }
    public var spacingBeforeRule: CGFloat { s(12) }
    public var spacingAfterRule: CGFloat { s(10) }
    public var spacingAfterTransport: CGFloat { s(10) }
    public var spacingAfterDetails: CGFloat { s(13) }
    public var spacingAfterSpectrum: CGFloat { s(15) }
    public var spacingAfterDigits: CGFloat { s(7) }

    public var ruleHeight: CGFloat { 1 }
    /// How far the pointer must move over the clock before the interaction
    /// becomes a window drag rather than a mode change.
    ///
    /// Deliberately larger than the 2 pt used by the drag-only regions of the
    /// card. Those regions only ever have to answer "is this a drag?"; the clock
    /// also has to tell a drag apart from a deliberate *click*, and a click is
    /// never perfectly stationary — a trackpad can easily drift a couple of
    /// points between press and release. 4 pt still begins a drag
    /// imperceptibly early.
    public var clockDragThreshold: CGFloat { s(4) }

    /// Horizontal inset for the metadata separator.
    ///
    /// The Phase 6 brief asks for a small inset so the rule reads as separating
    /// the metadata block rather than as a full-width band.
    public var separatorInset: CGFloat { s(8) }
    public var transportRowHeight: CGFloat { s(20) }
    public var detailRowHeight: CGFloat { s(15) }
    public var captionRowHeight: CGFloat { s(13) }

    // MARK: Bands

    /// Height of the horizontal spectrum band.
    public var spectrumHeight: CGFloat { s(58) }
    /// Preferred height of the seven-segment digits before width fitting.
    public var clockDigitHeight: CGFloat { s(55) }

    /// Natural height of the whole content stack at this scale.
    public var naturalContentHeight: CGFloat { Self.designContentHeight * scale }

    /// Extra vertical room to distribute, `0` when the content exactly fills the card.
    public var verticalSlack: CGFloat { max(containerHeight - naturalContentHeight, 0) }

    // MARK: Seven-segment geometry

    /// Digit width divided by digit height.
    public static let digitAspect: CGFloat = 0.70
    /// Colon width divided by digit height.
    public static let colonAspect: CGFloat = 0.30
    /// Gap between glyphs divided by digit height.
    public static let glyphGapAspect: CGFloat = 0.10

    /// Total horizontal extent of `HH:MM:SS`, expressed in units of digit height.
    public static let clockWidthInDigitHeights: CGFloat = 6 * digitAspect + 2 * colonAspect + 7 * glyphGapAspect

    /// The largest digit height that still fits the available width.
    public var maximumDigitHeightForWidth: CGFloat {
        max(contentWidth / Self.clockWidthInDigitHeights, 8)
    }

    /// The digit height actually used, after applying the user's clock scale and
    /// the available width.
    public func digitHeight(clockScale: CGFloat) -> CGFloat {
        min(clockDigitHeight * clockScale, maximumDigitHeightForWidth)
    }

    /// Stroke thickness of a lit segment, as a fraction of digit height.
    ///
    /// 0.16 is tuned against the reference: thicker than this and the counter
    /// of a `0` closes up into a slot, making the digits read as solid blocks.
    public static let segmentThicknessRatio: CGFloat = 0.16

    /// Stroke thickness of an *unlit* segment.
    ///
    /// Deliberately much thinner than a lit one. At the lit weight, all seven
    /// ghost strokes with round caps union into a filled rounded rectangle, so
    /// every digit sat on a dark plate instead of showing the faint outline of
    /// its unlit segments. A thinner stroke leaves visible gaps at the joints
    /// and reads as segment structure rather than as a backing tile.
    public static let ghostThicknessRatio: CGFloat = 0.095

    /// Blur radius of the lit-segment glow, as a fraction of segment thickness.
    ///
    /// The reference digits read as emissive components rather than printed
    /// shapes. Kept small so it reads as a glow and not as a bloom.
    public static let segmentGlowRadiusRatio: CGFloat = 0.55

    /// Opacity of the glow pass.
    public static let segmentGlowOpacity: Double = 0.55
}
