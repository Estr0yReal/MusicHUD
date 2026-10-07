import Foundation

/// A monotonic clock, used for playhead interpolation.
///
/// `systemUptime` is used instead of `Date` because it cannot jump: a wall-clock
/// change, a time-zone change or an NTP correction would otherwise make the
/// displayed playhead leap forwards or backwards for no musical reason.
public enum MonotonicClock {
    public static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// Advances the playhead between metadata polls, and — critically — stops
/// advancing when the music is not playing.
///
/// WHY THIS EXISTS
/// `player position` is only read once per metadata poll (1.5 s). Querying it
/// more often would mean an Apple Event round trip per frame, which the brief
/// rules out. So the displayed position is anchored to the last known value and
/// advanced locally.
///
/// WHAT IT MUST NOT DO
/// A local timer that keeps counting while Music.app is paused is exactly the
/// "fake playback progress" the brief prohibits. Every behaviour here is
/// therefore gated on `PlaybackState`:
///
/// * playing  → advances
/// * paused   → frozen at the anchored value
/// * stopped  → frozen
/// * new track → reset to the new anchor
///
/// The type holds no clock of its own: callers pass `now`, which makes every
/// one of those behaviours directly unit testable.
public struct PositionEstimator: Equatable, Sendable {

    /// How far the locally advanced position may drift from a freshly reported
    /// one before we treat it as a real seek rather than timer jitter.
    ///
    /// Re-anchoring on every tiny discrepancy would make the progress bar
    /// twitch; never re-anchoring would let a seek go unnoticed.
    public static let driftTolerance: TimeInterval = 1.0

    private var trackID: String = ""
    private var anchorPosition: TimeInterval = 0
    private var anchorTime: TimeInterval = 0
    private var advancing: Bool = false
    private var duration: TimeInterval = 0
    private var hasAnchor: Bool = false

    public init() {}

    /// `true` once a track has been anchored.
    public var isAnchored: Bool { hasAnchor }

    /// Feeds a fresh reading from Music.app.
    public mutating func synchronise(
        trackID: String,
        position: TimeInterval,
        duration: TimeInterval,
        state: PlaybackState,
        now: TimeInterval
    ) {
        let reported = max(position, 0)
        let stateChanged = advancing != (state == .playing)
        let trackChanged = !hasAnchor || trackID != self.trackID

        self.duration = max(duration, 0)

        // Hard re-anchor: a new track, the first reading, a transport change, or
        // a jump big enough to be a seek rather than jitter.
        let shouldReanchor: Bool
        if trackChanged || stateChanged {
            shouldReanchor = true
        } else {
            let drift = abs(reported - estimate(at: now))
            shouldReanchor = drift > Self.driftTolerance
        }

        guard shouldReanchor else { return }

        self.trackID = trackID
        self.anchorPosition = reported
        self.anchorTime = now
        self.advancing = (state == .playing)
        self.hasAnchor = true
    }

    /// Drops the anchor, e.g. when Music.app quits or nothing is playing.
    public mutating func reset() {
        trackID = ""
        anchorPosition = 0
        anchorTime = 0
        advancing = false
        duration = 0
        hasAnchor = false
    }

    /// The playhead at `now`.
    public func estimate(at now: TimeInterval) -> TimeInterval {
        guard hasAnchor else { return 0 }

        var value = anchorPosition
        if advancing {
            value += max(now - anchorTime, 0)
        }

        value = max(value, 0)

        // Never report past the end of the track; that would render as a
        // progress bar stuck at 100% with a negative remaining time.
        if duration > 0 {
            value = min(value, duration)
        }
        return value
    }
}
