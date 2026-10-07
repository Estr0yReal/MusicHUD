import XCTest
@testable import MusicHUDCore

/// Phase 6.2 tests: the arithmetic that converts pointer movement into a window
/// origin.
///
/// SCOPE
/// These pin the model, not the feel. Physical smoothness needs a human at the
/// mouse; what can be asserted here is that the formula is anchored to the
/// gesture's starting point (so nothing accumulates), that it is symmetric in
/// both axes, and that travel is measured as a Euclidean distance.
final class WindowDragMathTests: XCTestCase {

    private let initialOrigin = CGPoint(x: 1000, y: 500)
    private let initialPointer = CGPoint(x: 1200, y: 700)

    // MARK: - The core model

    func testNoMovementLeavesTheWindowExactlyWhereItWas() {
        XCTAssertEqual(
            WindowDragMath.origin(
                initialOrigin: initialOrigin,
                initialPointer: initialPointer,
                currentPointer: initialPointer
            ),
            initialOrigin
        )
    }

    func testPositiveDeltaMovesTheWindowByTheSameAmount() {
        let moved = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: CGPoint(x: initialPointer.x + 40, y: initialPointer.y + 25)
        )
        XCTAssertEqual(moved, CGPoint(x: 1040, y: 525))
    }

    func testNegativeDeltasInBothAxesIsSupported() {
        // Dragging left and down. Both axes are plain screen coordinates, so
        // neither needs inverting.
        let moved = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: CGPoint(x: initialPointer.x - 120, y: initialPointer.y - 75)
        )
        XCTAssertEqual(moved, CGPoint(x: 880, y: 425))
    }

    func testMixedSignDeltas() {
        let moved = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: CGPoint(x: initialPointer.x + 200, y: initialPointer.y - 10)
        )
        XCTAssertEqual(moved, CGPoint(x: 1200, y: 490))
    }

    // MARK: - No accumulation

    func testRepeatedCallsFromTheInitialOriginDoNotDrift() {
        // The whole point of anchoring: replaying a path must land in the same
        // place whether it is applied in one step or fifty.
        let destination = CGPoint(x: initialPointer.x + 333.7, y: initialPointer.y - 211.3)
        let oneStep = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: destination
        )

        var last = initialOrigin
        for step in 1...50 {
            let t = CGFloat(step) / 50
            let pointer = CGPoint(
                x: initialPointer.x + (destination.x - initialPointer.x) * t,
                y: initialPointer.y + (destination.y - initialPointer.y) * t
            )
            last = WindowDragMath.origin(
                initialOrigin: initialOrigin,
                initialPointer: initialPointer,
                currentPointer: pointer
            )
        }
        XCTAssertEqual(last.x, oneStep.x, accuracy: 0.0001)
        XCTAssertEqual(last.y, oneStep.y, accuracy: 0.0001)
    }

    func testReturningThePointerReturnsTheWindowToItsStartingOrigin() {
        // Drag out and back. A read-modify-write implementation could leave the
        // window offset; an anchored one cannot.
        _ = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: CGPoint(x: initialPointer.x + 500, y: initialPointer.y + 400)
        )
        let returned = WindowDragMath.origin(
            initialOrigin: initialOrigin,
            initialPointer: initialPointer,
            currentPointer: initialPointer
        )
        XCTAssertEqual(returned, initialOrigin)
    }

    // MARK: - Pointer-to-window offset

    func testThePointerToWindowOffsetIsInvariant() {
        let offsetBefore = CGPoint(
            x: initialPointer.x - initialOrigin.x,
            y: initialPointer.y - initialOrigin.y
        )

        for pointer in [
            CGPoint(x: initialPointer.x + 17, y: initialPointer.y - 3),
            CGPoint(x: initialPointer.x - 240, y: initialPointer.y + 90),
            CGPoint(x: initialPointer.x + 1, y: initialPointer.y + 1),
        ] {
            let origin = WindowDragMath.origin(
                initialOrigin: initialOrigin,
                initialPointer: initialPointer,
                currentPointer: pointer
            )
            XCTAssertEqual(pointer.x - origin.x, offsetBefore.x, accuracy: 0.0001)
            XCTAssertEqual(pointer.y - origin.y, offsetBefore.y, accuracy: 0.0001)
        }
    }

    // MARK: - Travel

    func testTravelIsEuclidean() {
        XCTAssertEqual(
            WindowDragMath.travel(from: .zero, to: CGPoint(x: 3, y: 4)),
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(WindowDragMath.travel(from: .zero, to: .zero), 0)
    }

    func testSubThresholdTravelIsRecognisedAsAClick() {
        // 3,4 travel is 5 — over a 4 pt threshold, even though neither axis
        // alone is. The decision must use the distance, not one axis.
        let threshold: CGFloat = 4
        XCTAssertTrue(
            PointerGestureDecision.isDrag(CGSize(width: 3, height: 4), threshold: threshold)
        )
        XCTAssertFalse(
            PointerGestureDecision.isDrag(CGSize(width: 2, height: 1), threshold: threshold)
        )
    }

    func testTravelMatchesTheGestureDecisionTheModifierUses() {
        // The modifier builds a CGSize from the two pointer positions and feeds
        // it to `PointerGestureDecision`; the two must agree.
        let current = CGPoint(x: initialPointer.x + 6, y: initialPointer.y - 8)
        let travel = WindowDragMath.travel(from: initialPointer, to: current)
        let size = CGSize(
            width: current.x - initialPointer.x,
            height: current.y - initialPointer.y
        )
        XCTAssertEqual(travel, PointerGestureDecision.distance(size), accuracy: 0.0001)
        XCTAssertEqual(
            travel >= Thresholds.clock,
            PointerGestureDecision.isDrag(size, threshold: Thresholds.clock)
        )
    }

    private enum Thresholds {
        static let clock = HUDMetrics(containerWidth: 300, containerHeight: 420).clockDragThreshold
    }
}
