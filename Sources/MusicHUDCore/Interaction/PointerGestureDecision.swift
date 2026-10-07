import CoreGraphics

/// Decides whether a pointer interaction was a click or a drag.
///
/// WHY THIS IS A PURE FUNCTION
/// The clock area has to do two different things depending on how the pointer
/// moved: cycle the display mode, or drag the window. Getting that boundary
/// wrong is exactly the regression Phase 6 introduced, and it is the kind of
/// thing that is invisible to a screenshot and awkward to verify by hand. Kept
/// as arithmetic here, the boundary can be tested directly.
public enum PointerGestureDecision {

    /// Straight-line distance moved since the pointer went down.
    public static func distance(_ translation: CGSize) -> CGFloat {
        (translation.width * translation.width + translation.height * translation.height).squareRoot()
    }

    /// `true` once the movement is large enough to count as a drag.
    ///
    /// Movement exactly at the threshold counts as a drag: the comparison is
    /// `>=`, so the boundary is deterministic rather than depending on
    /// floating-point luck.
    public static func isDrag(_ translation: CGSize, threshold: CGFloat) -> Bool {
        distance(translation) >= threshold
    }
}

/// The outcome of a pointer interaction, for logging and tests.
public enum PointerGestureOutcome: Equatable, Sendable {
    case click
    case drag
}
