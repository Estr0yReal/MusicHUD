import Foundation

/// Amplitude → dBFS, with a floor.
public enum DecibelScale {

    /// Silence maps here rather than to −∞, so the UI has a finite number to
    /// draw and can tell "silent" from "broken".
    public static let floor: Float = -120

    /// `20 · log10(amplitude)`.
    ///
    /// Guards the two cases that matter in practice: an amplitude of zero (which
    /// is `log10(0) = −∞`), and a negative amplitude (which is a caller error,
    /// but must not produce NaN in a live meter).
    public static func decibels(fromAmplitude amplitude: Float, floor: Float = DecibelScale.floor) -> Float {
        guard amplitude > 0, amplitude.isFinite else { return floor }
        let value = 20 * log10f(amplitude)
        guard value.isFinite else { return floor }
        return max(value, floor)
    }

    /// Normalises a dBFS reading to `0...1` for drawing a meter.
    ///
    /// `-infinity`… can't occur here because readings are already floored.
    public static func normalised(_ decibels: Float, floor: Float = DecibelScale.floor) -> Double {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(decibels, floor), 0)
        return Double((clamped - floor) / -floor)
    }
}

/// One measurement produced by `LevelAccumulator`.
public struct LevelMeasurement: Equatable, Sendable {
    public let rms: Float
    public let peak: Float
    public let sampleCount: Int
    public let nonZeroSampleCount: Int

    public init(rms: Float, peak: Float, sampleCount: Int, nonZeroSampleCount: Int) {
        self.rms = rms
        self.peak = peak
        self.sampleCount = sampleCount
        self.nonZeroSampleCount = nonZeroSampleCount
    }

    public static let empty = LevelMeasurement(rms: 0, peak: 0, sampleCount: 0, nonZeroSampleCount: 0)

    /// `true` when at least one sample was non-zero.
    public var hasSignal: Bool { nonZeroSampleCount > 0 }

    /// `true` when samples were examined and all of them were zero.
    ///
    /// This is `false` for an empty measurement, which is what separates
    /// "silent" from "nothing arrived".
    public var isSilent: Bool { sampleCount > 0 && nonZeroSampleCount == 0 }
}

/// Turns PCM into RMS and peak.
///
/// CHANNEL HANDLING
/// All channels are combined: the sum of squares is accumulated across every
/// channel and the RMS is taken over the total sample count. For the stereo
/// mixdown this project taps, that is equivalent to measuring either channel
/// when they are correlated, and it is the honest answer when they are not —
/// it cannot miss energy that is panned hard to one side.
///
/// REAL-TIME SAFETY
/// `add` performs no allocation, no locking, no logging and no ObjC. It is
/// called directly on the audio thread, and the whole point of keeping it in a
/// plain `struct` is that the audio thread touches nothing else.
public struct LevelAccumulator: Sendable {

    private var sumOfSquares: Double = 0
    private var sampleCount: Int = 0
    private var peak: Float = 0
    private var nonZeroSampleCount: Int = 0

    public init() {}

    /// Accumulates one buffer of samples.
    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        var localSum: Double = 0
        var localPeak: Float = 0
        var localNonZero = 0
        var localCount = 0

        for index in 0..<samples.count {
            let value = samples[index]
            // Non-finite samples are skipped entirely rather than counted as
            // zero. They are pathological in real PCM, but a single NaN would
            // otherwise poison the RMS and paint the meter with garbage for the
            // rest of the session. Counting only what was actually measured
            // also keeps `sampleCount` — and therefore the reported frame
            // count — consistent with the divisor used below.
            guard value.isFinite else { continue }
            localCount += 1

            let magnitude = abs(value)
            if magnitude > localPeak { localPeak = magnitude }
            if magnitude > 0 { localNonZero += 1 }
            localSum += Double(value) * Double(value)
        }

        sumOfSquares += localSum
        sampleCount += localCount
        if localPeak > peak { peak = localPeak }
        nonZeroSampleCount += localNonZero
    }

    public mutating func reset() {
        sumOfSquares = 0
        sampleCount = 0
        peak = 0
        nonZeroSampleCount = 0
    }

    /// The measurement for everything accumulated since the last reset.
    public var measurement: LevelMeasurement {
        guard sampleCount > 0 else { return .empty }
        let mean = sumOfSquares / Double(sampleCount)
        let rms = Float(mean.squareRoot())
        return LevelMeasurement(
            rms: rms,
            peak: peak,
            sampleCount: sampleCount,
            nonZeroSampleCount: nonZeroSampleCount
        )
    }
}

public extension LevelMeasurement {
    /// Frames covered, given the source's channel count.
    ///
    /// Samples are counted across all channels, so the frame count is the
    /// sample count divided by the channel count. A zero or unknown channel
    /// count falls back to treating one sample as one frame rather than
    /// dividing by zero.
    func frameCount(channelCount: Int) -> Int {
        guard channelCount > 0 else { return sampleCount }
        return sampleCount / channelCount
    }
}
