import Foundation
import MusicHUDCore

/// The single, narrow observable that the spectrum renderer watches.
///
/// WHY THIS EXISTS (Phase 4.5 audit)
/// `SpectrumView` used to observe `AudioCaptureService` directly. That object
/// publishes a dozen unrelated things — `level`, `fftMilliseconds`, `peakHold`,
/// `framesPerSecond`, `overflowCount`, `logLines` — so *any* of them updating
/// invalidated the spectrum Canvas. With the music paused, where the drawn
/// bands never change, the view was still being re-rendered 30 times a second
/// because the diagnostics counters kept moving.
///
/// Narrowing the observation to one property that only changes when the picture
/// changes removes that coupling entirely. It also means the diagnostics panel
/// can be as chatty as it likes without touching the render path.
@MainActor
final class SpectrumDisplay: ObservableObject {

    /// The frame the renderer should draw. Only ever published on a visible change.
    @Published private(set) var frame: SpectrumFrame

    /// Frames actually delivered to the renderer, for diagnostics.
    private(set) var publishedFrameCount = 0

    init(initial: SpectrumFrame) {
        self.frame = initial
    }

    /// Publishes only when the drawn values differ.
    ///
    /// The timestamp is deliberately excluded: `makeFrame` stamps every frame
    /// with `.now`, so including it would make every frame unique and defeat the
    /// whole point.
    /// Forces a publish regardless of equality. Used when the analyser is
    /// rebuilt or stopped, where the change matters even if the numbers match.
    func replace(with next: SpectrumFrame) {
        frame = next
        publishedFrameCount += 1
    }

    @discardableResult
    func update(_ next: SpectrumFrame) -> Bool {
        let changed = next.bands != frame.bands
            || next.rms != frame.rms
            || next.peak != frame.peak

        guard changed else { return false }
        frame = next
        publishedFrameCount += 1
        return true
    }
}
