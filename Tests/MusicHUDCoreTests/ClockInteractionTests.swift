import XCTest
@testable import MusicHUDCore

/// Phase 6.1 tests: the click-versus-drag boundary on the large clock.
///
/// WHAT THESE CAN AND CANNOT COVER
/// They exercise the *decision* — the arithmetic that separates a click from a
/// drag — and confirm that the decision drives the clock rotation correctly.
/// They cannot exercise the real pointer, the SwiftUI gesture system or
/// `NSWindow.setFrameOrigin`; that needs a human with a mouse, and is recorded
/// as manually validated in the Phase 6.1 report rather than asserted here.
final class ClockInteractionTests: XCTestCase {

    /// The production threshold, read from the same place the view reads it.
    private var threshold: CGFloat {
        HUDMetrics(containerWidth: 300, containerHeight: 420).clockDragThreshold
    }

    // MARK: - The decision itself

    func testZeroMovementIsAClick() {
        XCTAssertFalse(PointerGestureDecision.isDrag(.zero, threshold: threshold))
    }

    func testTinyMovementBelowThresholdIsAClick() {
        // Trackpad drift during a deliberate press-and-release.
        let drift = CGSize(width: 1, height: -1)
        XCTAssertLessThan(PointerGestureDecision.distance(drift), threshold)
        XCTAssertFalse(PointerGestureDecision.isDrag(drift, threshold: threshold))
    }

    func testMovementExactlyAtThresholdIsDeterministic() {
        // The comparison is `>=`, so the boundary belongs to the drag side and
        // does not depend on floating-point luck.
        let exactly = CGSize(width: threshold, height: 0)
        XCTAssertTrue(PointerGestureDecision.isDrag(exactly, threshold: threshold))

        // And just under it is still a click.
        let justUnder = CGSize(width: threshold - 0.001, height: 0)
        XCTAssertFalse(PointerGestureDecision.isDrag(justUnder, threshold: threshold))
    }

    func testMovementAboveThresholdIsADrag() {
        XCTAssertTrue(
            PointerGestureDecision.isDrag(CGSize(width: 20, height: 0), threshold: threshold)
        )
        XCTAssertTrue(
            PointerGestureDecision.isDrag(CGSize(width: 0, height: -40), threshold: threshold)
        )
        XCTAssertTrue(
            PointerGestureDecision.isDrag(CGSize(width: 30, height: 30), threshold: threshold)
        )
    }

    func testDistanceIsEuclideanNotPerAxis() {
        // A 3,4 movement is 5 — checking either axis alone would call a
        // diagonal drag a click.
        XCTAssertEqual(PointerGestureDecision.distance(CGSize(width: 3, height: 4)), 5, accuracy: 0.0001)
        XCTAssertTrue(PointerGestureDecision.isDrag(CGSize(width: 3, height: 4), threshold: 5))
        XCTAssertFalse(PointerGestureDecision.isDrag(CGSize(width: 3, height: 1), threshold: 5))
    }

    func testThresholdIsSmallEnoughToFeelImmediate() {
        // The brief rules out a long press or an unnatural gesture; 4 pt at the
        // default scale is a couple of millimetres of pointer travel.
        XCTAssertGreaterThan(threshold, 2, "must tolerate click jitter")
        XCTAssertLessThanOrEqual(threshold, 8, "must not feel like a deliberate gesture")
    }

    // MARK: - The decision drives the clock correctly

    /// Mirrors what `WindowDragModifier` does on release: a drag moves the
    /// window and leaves the mode alone; a click advances the rotation.
    @discardableResult
    private func simulate(
        translation: CGSize,
        cycle: inout WorldClockCycle
    ) -> PointerGestureOutcome {
        if PointerGestureDecision.isDrag(translation, threshold: threshold) {
            return .drag
        }
        cycle.advance()
        return .click
    }

    func testAClickCyclesTheClockMode() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        XCTAssertEqual(cycle.mode, .track)

        let outcome = simulate(translation: .zero, cycle: &cycle)
        XCTAssertEqual(outcome, .click)
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")
    }

    func testADragDoesNotCycleTheClockMode() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)

        let outcome = simulate(translation: CGSize(width: 60, height: 25), cycle: &cycle)
        XCTAssertEqual(outcome, .drag)
        XCTAssertEqual(
            cycle.mode,
            .track,
            "dragging the window must never change what the clock is showing"
        )
    }

    func testASubThresholdReleaseCyclesAndDoesNotDrag() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        let outcome = simulate(translation: CGSize(width: 2, height: 1), cycle: &cycle)
        XCTAssertEqual(outcome, .click)
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")
    }

    func testFullRotationByClickingOnly() {
        // TEST 3 of the brief's manual script, reproduced as arithmetic.
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)

        var visited: [String] = []
        for _ in 0..<WorldClockCatalogue.defaults.count {
            simulate(translation: .zero, cycle: &cycle)
            visited.append(cycle.mode.city?.displayName ?? "TRACK")
        }
        // Derived from the catalogue, so adding a city cannot silently break
        // this test's intent (every enabled city is visited, in order).
        XCTAssertEqual(visited, WorldClockCatalogue.defaults.map(\.displayName))

        // And one more click returns to Track.
        simulate(translation: .zero, cycle: &cycle)
        XCTAssertEqual(cycle.mode, .track)
    }

    func testInterleavedClickAndDragReachesTheSameSequence() {
        // Dragging between clicks must not skip or double-advance a step —
        // the "mode changed during a drag" failure the phase exists to fix.
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)

        simulate(translation: CGSize(width: 40, height: 0), cycle: &cycle)   // drag
        XCTAssertEqual(cycle.mode, .track)
        simulate(translation: .zero, cycle: &cycle)                          // click
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")
        simulate(translation: CGSize(width: -30, height: 12), cycle: &cycle) // drag
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")
        simulate(translation: CGSize(width: 3, height: 0), cycle: &cycle)    // tiny -> click
        XCTAssertEqual(cycle.mode.city?.displayName, "SHANGHAI")
    }

    func testDraggingRepeatedlyNeverChangesTheMode() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        for _ in 0..<10 {
            simulate(translation: CGSize(width: 120, height: -80), cycle: &cycle)
        }
        XCTAssertEqual(cycle.mode, .track)
    }

    func testDisabledCitiesAreStillSkippedWhenCyclingByClick() {
        // Phase 6 behaviour must survive the interaction change.
        // Disabled by identifier, not by index, so inserting a city into the
        // defaults cannot quietly change which city this test disables.
        var cities = WorldClockCatalogue.defaults
        let london = cities.firstIndex { $0.timeZoneIdentifier == "Europe/London" }!
        cities[london].isEnabled = false
        var cycle = WorldClockCycle(cities: cities)

        let enabled = cities.filter(\.isEnabled).map(\.displayName)
        var visited: [String] = []
        for _ in 0..<enabled.count {
            simulate(translation: .zero, cycle: &cycle)
            visited.append(cycle.mode.city?.displayName ?? "TRACK")
        }
        XCTAssertEqual(visited, enabled)
        XCTAssertFalse(visited.contains("LONDON"))
    }

    // MARK: - Threshold consistency with the rest of the card

    func testThresholdScalesWithTheWindowLikeEveryOtherMetric() {
        // The card is proportional; the interaction threshold has to follow, or
        // a small HUD would need a proportionally larger gesture.
        let small = HUDMetrics(containerWidth: 240, containerHeight: 348)
        let large = HUDMetrics(containerWidth: 600, containerHeight: 840)
        XCTAssertGreaterThan(large.clockDragThreshold, small.clockDragThreshold)
        XCTAssertGreaterThan(small.clockDragThreshold, 0)
    }
}
