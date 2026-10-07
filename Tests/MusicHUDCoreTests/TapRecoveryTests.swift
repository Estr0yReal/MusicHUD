import XCTest
@testable import MusicHUDCore

/// Phase 7 tests: the policy for a process tap that started but never delivers.
///
/// WHAT THESE COVER
/// The decision boundary only — when to keep waiting, when to rebuild, and when
/// to stop. The underlying OS behaviour (a tap registering with coreaudiod and
/// then delivering nothing) is not reproducible on demand and is documented as an
/// observed environment condition, not asserted here.
final class TapRecoveryTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let timeout: TimeInterval = 8
    private let maxAttempts = 3

    private func action(
        tapExists: Bool = true,
        deviceStarted: Bool = true,
        everReceivedPCM: Bool = false,
        startedAt: Date? = nil,
        now: Date? = nil,
        attempts: Int = 0,
        maximumAttempts: Int? = nil
    ) -> TapRecoveryDecision.Action {
        TapRecoveryDecision.action(
            tapExists: tapExists,
            deviceStarted: deviceStarted,
            everReceivedPCM: everReceivedPCM,
            startedAt: startedAt ?? start,
            now: now ?? start,
            timeout: timeout,
            attempts: attempts,
            maximumAttempts: maximumAttempts ?? maxAttempts
        )
    }

    // MARK: - Waiting

    func testNoTapMeansNothingToRecover() {
        XCTAssertEqual(action(tapExists: false), .wait)
    }

    func testATapWhoseDeviceHasNotStartedIsLeftAlone() {
        // `AudioDeviceStart` legitimately blocks for tens of seconds. That is the
        // `.starting` state, not a stall, and must never trigger a rebuild.
        XCTAssertEqual(action(deviceStarted: false), .wait)
    }

    func testATapThatHasNeverHadAStartTimeIsLeftAlone() {
        // Called directly: the helper above substitutes a default for `nil`, so
        // it cannot express "no start time".
        XCTAssertEqual(
            TapRecoveryDecision.action(
                tapExists: true,
                deviceStarted: true,
                everReceivedPCM: false,
                startedAt: nil,
                now: start.addingTimeInterval(600),
                timeout: timeout,
                attempts: 0,
                maximumAttempts: maxAttempts
            ),
            .wait
        )
    }

    func testSilenceShorterThanTheTimeoutIsNotJudged() {
        XCTAssertEqual(action(now: start.addingTimeInterval(timeout - 0.1)), .wait)
    }

    func testExactlyAtTheTimeoutStillWaits() {
        // The comparison is `>`, so the boundary belongs to "not yet".
        XCTAssertEqual(action(now: start.addingTimeInterval(timeout)), .wait)
    }

    // MARK: - A tap that works is never rebuilt

    func testATapThatHasDeliveredAudioIsNeverRebuilt() {
        // This is the critical guard: silence from a working tap is just quiet
        // music. Rebuilding on it would tear down a healthy capture whenever a
        // track faded out.
        for elapsed in [10.0, 60.0, 600.0] {
            XCTAssertEqual(
                action(everReceivedPCM: true, now: start.addingTimeInterval(elapsed)),
                .wait,
                "a tap that has delivered must be left alone after \(elapsed)s of quiet"
            )
        }
    }

    // MARK: - Rebuilding

    func testASilentTapIsRebuiltOnceTheTimeoutPasses() {
        XCTAssertEqual(action(now: start.addingTimeInterval(timeout + 0.5)), .rebuild)
    }

    func testRebuildIsBounded() {
        // Attempts 0, 1, 2 rebuild; the fourth ask gives up. Without the cap this
        // would be a rebuild loop against a condition retrying cannot fix.
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 0), .rebuild)
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 1), .rebuild)
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 2), .rebuild)
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 3), .giveUp)
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 99), .giveUp)
    }

    func testTheCapIsConfigurable() {
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 1, maximumAttempts: 1), .giveUp)
        XCTAssertEqual(action(now: start.addingTimeInterval(60), attempts: 1, maximumAttempts: 4), .rebuild)
    }

    func testGiveUpWinsOverRebuildOnceTheCapIsReached() {
        // Even long past the timeout, the cap still governs.
        XCTAssertEqual(action(now: start.addingTimeInterval(3600), attempts: 3), .giveUp)
    }

    // MARK: - The sequence the app actually walks

    func testTheFullStallSequenceIsWaitThenBoundedRebuildsThenGiveUp() {
        var attempts = 0
        var log: [TapRecoveryDecision.Action] = []

        // One tick per second for a minute.
        for tick in 0...60 {
            let a = TapRecoveryDecision.action(
                tapExists: true,
                deviceStarted: true,
                everReceivedPCM: false,
                startedAt: start,
                now: start.addingTimeInterval(Double(tick)),
                timeout: timeout,
                attempts: attempts,
                maximumAttempts: maxAttempts
            )
            log.append(a)
            // A rebuild replaces the tap, which schedules a fresh attempt.
            if a == .rebuild { attempts += 1 }
            if a == .giveUp { break }
        }

        XCTAssertEqual(log.filter { $0 == .wait }.count, Int(timeout) + 1)
        XCTAssertEqual(log.filter { $0 == .rebuild }.count, maxAttempts)
        XCTAssertEqual(log.last, .giveUp)
        XCTAssertEqual(attempts, maxAttempts)
    }

    func testTheTimeoutIsShortEnoughToRecoverWithinAReasonableWait() {
        // A user should not have to stare at a dead spectrum for minutes.
        XCTAssertLessThanOrEqual(timeout, 15)
        XCTAssertGreaterThan(timeout, 2, "must not trip on a momentary gap")
    }
}
