import CoreGraphics

/// The arithmetic that turns pointer movement into a window origin.
///
/// WHY THIS IS A SEPARATE, PURE TYPE
/// Phase 6.2 fixed a drag that shook. The cause was not arithmetic but *which
/// coordinate space the pointer was measured in* — so the arithmetic is worth
/// stating explicitly, and worth testing, because the subtle failures here
/// (accumulated deltas, a jump when dragging begins, an inverted axis) are
/// invisible in a screenshot.
///
/// THE MODEL
/// The window origin is always recomputed from the origin captured when the
/// gesture began, never from the window's current origin:
///
///     newOrigin = initialOrigin + (currentPointer − initialPointer)
///
/// That keeps the pointer-to-window offset exactly constant for the whole
/// gesture. Feeding each frame's delta back into the previous frame's result
/// instead would accumulate rounding error, and — because the window moves in
/// response to the pointer — would also change the pointer's position *relative
/// to the window*, which is how the shake appeared.
///
/// COORDINATE SYSTEM
/// Both the pointer and the window origin are AppKit screen coordinates
/// (origin bottom-left of the primary display), so the delta applies directly
/// with **no axis inversion**. This was verified on the running system:
/// `NSEvent.mouseLocation` for a cursor placed inside the HUD's bounds falls
/// inside `NSWindow.frame`, and the x coordinates agree exactly.
public enum WindowDragMath {

    /// The window origin for a pointer at `currentPointer`.
    ///
    /// - Parameters:
    ///   - initialOrigin: `window.frame.origin` captured when the gesture began.
    ///   - initialPointer: `NSEvent.mouseLocation` captured at the same moment.
    ///   - currentPointer: the pointer's position now.
    public static func origin(
        initialOrigin: CGPoint,
        initialPointer: CGPoint,
        currentPointer: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: initialOrigin.x + (currentPointer.x - initialPointer.x),
            y: initialOrigin.y + (currentPointer.y - initialPointer.y)
        )
    }

    /// Straight-line pointer travel since the gesture began.
    public static func travel(from initialPointer: CGPoint, to currentPointer: CGPoint) -> CGFloat {
        let dx = currentPointer.x - initialPointer.x
        let dy = currentPointer.y - initialPointer.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
