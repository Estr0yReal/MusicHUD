import MusicHUDCore
import SwiftUI

/// The horizontal real-time spectrum band.
///
/// This view knows exactly one thing: how to draw a `SpectrumFrame`. It has no
/// knowledge of Core Audio, `AudioBufferList`, process taps, vDSP, FFT sizes,
/// sample rates or Apple Music — which is what the brief asks for, and what
/// makes the DSP independently testable.
///
/// Every bar height comes from a real FFT of real PCM from Music.app. There is
/// no random data, no synthetic envelope and no per-track heuristics anywhere in
/// this file; when audio stops, the frames decay to zero and the band flattens.
struct SpectrumView: View {
    /// The latest analysed frame. `nil` before the first one arrives.
    /// The narrowest possible observation: one object, one property, published
    /// only when the drawn values change.
    ///
    /// Observing `AudioCaptureService` instead meant every diagnostics counter
    /// (`level`, `fftMilliseconds`, `peakHold`, `framesPerSecond`, …) invalidated
    /// this Canvas, so the spectrum was re-rendered 30 times a second even with
    /// the music paused and nothing on screen changing.
    @ObservedObject var display: SpectrumDisplay
    /// Bars to draw. Resampled from the frame's bands when they differ.
    let barCount: Int
    let tint: SpectrumTint
    let metrics: HUDMetrics

    /// Ratio of gap width to bar width. Tuned to the reference: fine, dense bars.
    private static let gapRatio: CGFloat = 0.45

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: metrics.spectrumHeight)
        // Decorative and deliberately non-interactive: the card must stay
        // draggable through the spectrum.
        .allowsHitTesting(false)
    }

    // MARK: - Levels

    /// Bar heights in `0...1`.
    ///
    /// An empty frame means "no analysis yet", which draws as a flat baseline
    /// rather than as motion.
    private var frame: SpectrumFrame { display.frame }

    private var levels: [Double] {
        guard !frame.bands.isEmpty else {
            return Array(repeating: 0, count: max(barCount, 1))
        }
        return SpectrumBands.resample(frame.bands, to: barCount)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let levels = levels
        guard !levels.isEmpty, size.width > 2, size.height > 2 else { return }

        let barWidth = size.width / (CGFloat(levels.count) + Self.gapRatio * CGFloat(levels.count - 1))
        let gap = barWidth * Self.gapRatio
        guard barWidth > 0.4 else { return }

        // A blurred pass underneath gives the soft haze the reference has,
        // where the bars bleed into the panel instead of sitting on top of it.
        var haze = context
        haze.addFilter(.blur(radius: barWidth * 1.6))
        haze.opacity = 0.28
        drawBars(into: &haze, size: size, levels: levels, barWidth: barWidth, gap: gap)

        drawBars(into: &context, size: size, levels: levels, barWidth: barWidth, gap: gap)
    }

    private func drawBars(
        into context: inout GraphicsContext,
        size: CGSize,
        levels: [Double],
        barWidth: CGFloat,
        gap: CGFloat
    ) {
        let rgb = tint.rgb
        let cornerRadius = barWidth * 0.5
        let barCount = levels.count

        // ONE gradient, built once per frame and shared by every bar.
        //
        // The previous version built a fresh `Gradient` and two `Color`s per
        // bar — 144 allocations per frame, 8600 per second at 60 FPS — purely
        // to vary each bar's alpha slightly. The variation was cosmetic and the
        // cost was real. One gradient for the whole band looks the same and
        // costs a fraction of the time.
        let gradient = Gradient(colors: [
            Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 0.42),
            Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 0.96),
        ])
        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        )

        // Hoisted out of the loop: `levels` is a [Double] and subscripting it
        // with bounds checking 48 times a frame is measurable at this rate.
        levels.withUnsafeBufferPointer { values in
            for index in 0..<barCount {
                let level = CGFloat(values[index])
                // At least one bar-width, so a silent band still reads as a
                // baseline rather than vanishing.
                let height = max(barWidth, level * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: size.height - height,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: cornerRadius),
                    with: shading
                )
            }
        }
    }

    /// Fixed, index-only variation. Not random.
    private static func alphaWave(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let x = Double(index) / Double(count - 1)
        return 0.5 + 0.5 * sin(x * 17.0 + 0.9)
    }
}
