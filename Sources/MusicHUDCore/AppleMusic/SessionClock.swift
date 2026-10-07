import Foundation

/// Accumulates how long music has actually been playing this session.
///
/// Phase 1 faked this value from the demo library, which was acceptable while
/// everything on the card was demo data. Now that real track data is displayed,
/// a fabricated session time sitting under it would be exactly the kind of
/// "looks like real playback state" the brief prohibits, so it is computed for
/// real.
///
/// Time only accrues while the transport is playing: pausing stops it, and
/// nothing here advances on its own.
public struct SessionClock: Equatable, Sendable {

    private var accumulated: TimeInterval = 0
    /// Monotonic timestamp the current playing stretch began at, if playing.
    private var runningSince: TimeInterval?
    private var didObservePlayback = false

    public init() {}

    /// `true` once any playback has been observed.
    public var hasStarted: Bool { didObservePlayback }

    /// Feeds the current transport state. Idempotent for a given state.
    public mutating func update(isPlaying: Bool, now: TimeInterval) {
        switch (isPlaying, runningSince) {
        case (true, nil):
            runningSince = now
            didObservePlayback = true
        case (false, .some(let started)):
            accumulated += max(now - started, 0)
            runningSince = nil
        case (true, .some), (false, nil):
            break
        }
    }

    /// Total playing time as of `now`.
    public func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let started = runningSince else { return accumulated }
        return accumulated + max(now - started, 0)
    }

    public mutating func reset() {
        accumulated = 0
        runningSince = nil
        didObservePlayback = false
    }
}
