import Foundation

/// Decides what to do about a process tap that started but delivers no audio.
///
/// WHY THIS IS PURE
/// Phase 7 found a real stall: a tap can register with coreaudiod, have
/// `AudioDeviceStart` return successfully, and then never deliver a single
/// buffer — while the source is demonstrably playing. coreaudiod's log confirms
/// the registration succeeds, so this is *not* a permission problem, and it is
/// intermittent rather than a code defect.
///
/// The app previously had no answer to it: `attemptTapIfDue` is guarded by
/// `capture == nil`, so an existing-but-silent tap was never replaced and the
/// HUD could sit in `.idle` indefinitely with music playing.
///
/// The policy is small but it has a real boundary — how long to wait, and when
/// to stop — and getting it wrong means either a dead HUD or a rebuild loop. So
/// it lives here, where it can be tested, rather than inline in a timer
/// callback where it cannot.
public enum TapRecoveryDecision: Equatable, Sendable {

    /// What to do on this supervisor tick.
    public enum Action: Equatable, Sendable {
        /// Leave the tap alone; it has not been silent long enough to judge.
        case wait
        /// Tear the silent tap down and build a new one.
        case rebuild
        /// Out of attempts. Report the condition and stop churning.
        case giveUp
    }

    /// - Parameters:
    ///   - tapExists: whether a tap is currently installed.
    ///   - deviceStarted: whether `AudioDeviceStart` returned successfully.
    ///   - everReceivedPCM: whether this tap has *ever* delivered a buffer.
    ///   - startedAt: when the device finished starting.
    ///   - now: the current time.
    ///   - timeout: how long a started tap may stay silent.
    ///   - attempts: rebuilds already performed for this silence.
    ///   - maximumAttempts: the cap.
    public static func action(
        tapExists: Bool,
        deviceStarted: Bool,
        everReceivedPCM: Bool,
        startedAt: Date?,
        now: Date,
        timeout: TimeInterval,
        attempts: Int,
        maximumAttempts: Int
    ) -> Action {
        // Only a tap that is actually running and has never produced anything is
        // a candidate. A tap that has delivered once is left alone: silence from
        // it is just silence in the music, which is normal and must not cause a
        // rebuild.
        guard tapExists, deviceStarted, !everReceivedPCM, let startedAt else { return .wait }

        // Not silent for long enough to judge yet.
        guard now.timeIntervalSince(startedAt) > timeout else { return .wait }

        return attempts < maximumAttempts ? .rebuild : .giveUp
    }
}
