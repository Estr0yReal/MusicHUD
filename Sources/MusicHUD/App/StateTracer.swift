import Foundation
import MusicHUDCore

/// Streams the app's live now-playing state to a file, once a second.
///
/// WHY THIS EXISTS
/// A screenshot proves what the card looked like at one instant. It cannot show
/// that the playhead *stopped* when the music was paused, or that it *resumed*
/// from the same value — and those are exactly the behaviours Phase 2 has to
/// get right. Recording the state over time is the only way to actually verify
/// them rather than assume them.
///
/// Enabled by `MUSICHUD_TRACE`, with an optional `MUSICHUD_TRACE_DURATION` in
/// seconds (default 30). Development tool only; inert during normal use.
@MainActor
final class StateTracer {

    static var requestedOutputPath: String? {
        guard let path = ProcessInfo.processInfo.environment["MUSICHUD_TRACE"],
              !path.isEmpty
        else { return nil }
        return path
    }

    static var requestedDuration: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["MUSICHUD_TRACE_DURATION"],
              let value = TimeInterval(raw), value > 0
        else { return 30 }
        return value
    }

    private let url: URL
    private let started = Date()
    private var timer: Timer?

    init(path: String) {
        self.url = URL(fileURLWithPath: path)
    }

    /// Begins sampling. `onFinish` fires once the run is over.
    func start(state: AppState, duration: TimeInterval, onFinish: @escaping () -> Void) {
        var header = "# Music HUD state trace\n"
        header += "# elapsed | availability | playback | position | duration | session | title | artist | album | hasArtwork\n"
        try? header.write(to: url, atomically: true, encoding: .utf8)

        sample(state)   // immediate first sample

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            // The timer is scheduled on the main run loop, so this block does
            // run on the main actor; `assumeIsolated` states that rather than
            // hopping through a dispatch.
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.sample(state)
                if Date().timeIntervalSince(self.started) >= duration {
                    timer.invalidate()
                    self.timer = nil
                    onFinish()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample(_ state: AppState) {
        let snapshot = state.snapshot
        let elapsed = Date().timeIntervalSince(started)

        let line = [
            String(format: "%.1f", elapsed),
            "\(state.availability)",
            snapshot.state.rawValue,
            String(format: "%.2f", snapshot.position),
            String(format: "%.2f", snapshot.metadata?.duration ?? 0),
            String(format: "%.1f", state.sessionElapsed),
            snapshot.metadata?.title ?? "-",
            snapshot.metadata?.artist ?? "-",
            snapshot.metadata?.album ?? "-",
            state.artworkImage == nil ? "no" : "yes",
        ].joined(separator: " | ")

        append(line + "\n")
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
