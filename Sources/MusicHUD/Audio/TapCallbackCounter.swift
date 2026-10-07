import Foundation

/// Callback and frame counters, written from the audio thread.
///
/// Phase 3 used a richer shared state here because it computed RMS and peak in
/// the callback. Phase 4 moved all of that into `SpectrumAnalyzer`, which runs
/// on the analysis thread, so the audio thread now only counts. That is a
/// strictly smaller real-time footprint, and it is the reason the callback
/// duration went down rather than up when the FFT was added.
final class TapCallbackCounter: @unchecked Sendable {

    struct Drain {
        var callbacks: UInt64
        var frames: Int
        var totalCallbacks: UInt64
    }

    private var lock = os_unfair_lock_s()
    private var pendingCallbacks: UInt64 = 0
    private var pendingFrames: Int = 0
    private var totalCallbacks: UInt64 = 0

    init() {}

    /// AUDIO THREAD.
    func record(frames: Int) {
        os_unfair_lock_lock(&lock)
        pendingCallbacks += 1
        pendingFrames += frames
        totalCallbacks += 1
        os_unfair_lock_unlock(&lock)
    }

    func drain() -> Drain {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let drain = Drain(callbacks: pendingCallbacks, frames: pendingFrames, totalCallbacks: totalCallbacks)
        pendingCallbacks = 0
        pendingFrames = 0
        return drain
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        pendingCallbacks = 0
        pendingFrames = 0
        totalCallbacks = 0
        os_unfair_lock_unlock(&lock)
    }
}
