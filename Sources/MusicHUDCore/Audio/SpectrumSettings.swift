import Foundation

/// Tunables for the real-time spectrum.
///
/// Every value here affects the DSP, not just the drawing. Nothing in this type
/// may be tuned to a particular song: the brief is explicit that the spectrum
/// has to come from the maths and not from per-track heuristics.
public struct SpectrumSettings: Equatable, Sendable {

    /// FFT length. Powers of two only. 1024 / 2048 / 4096 are offered.
    ///
    /// 2048 at 48 kHz gives 23.44 Hz per bin, which is a reasonable compromise
    /// between frequency resolution and latency, and is the default.
    public var fftSize: Int = 2048

    /// How far the analysis window advances per FFT, in samples.
    ///
    /// 512 against a 2048 window is 75% overlap: the spectrum updates about
    /// 94 times a second at 48 kHz, which is smooth without being expensive.
    public var hopSize: Int = 512

    /// Number of visual bands. The brief asks for 32–64, defaulting to 48.
    public var bandCount: Int = 48

    /// Lowest frequency represented. Below this the bins are ignored.
    public var minimumFrequency: Double = 20

    /// Highest frequency represented.
    public var maximumFrequency: Double = 20000

    /// Level mapped to a visual value of 0.
    public var noiseFloorDecibels: Float = -80

    /// Level mapped to a visual value of 1.
    public var maximumDecibels: Float = 0

    /// dB added to every band before mapping, i.e. a meter gain.
    ///
    /// This is the brief's "sensitivity" control. It shifts the whole scale
    /// rather than inventing structure, so the shape of the spectrum still comes
    /// entirely from the FFT.
    public var sensitivityDecibels: Float = 0

    /// Exponent applied after normalisation.
    ///
    /// 1.0 is strictly linear in dB. Values below 1 lift quiet bands so music
    /// does not look permanently short, while keeping the mapping monotonic and
    /// tied to the real measurement. 0.75 was chosen by looking at real music.
    public var dynamicRangeGamma: Float = 0.75

    /// Smoothing coefficient applied when a band rises. Large = fast attack.
    public var attack: Float = 0.35

    /// Smoothing coefficient applied when a band falls. Small = slow release.
    public var release: Float = 0.12

    public init() {}

    /// Allowed FFT sizes, for the settings UI.
    public static let allowedFFTSizes = [1024, 2048, 4096]

    /// Clamps every field into a range the analyser can actually honour.
    public func sanitized() -> SpectrumSettings {
        var s = self
        s.fftSize = Self.allowedFFTSizes.contains(s.fftSize) ? s.fftSize : 2048
        // The hop must divide the window into a sensible overlap.
        s.hopSize = min(max(s.hopSize, s.fftSize / 16), s.fftSize / 2)
        s.bandCount = min(max(s.bandCount, 8), 128)
        s.minimumFrequency = min(max(s.minimumFrequency, 10), 200)
        s.maximumFrequency = min(max(s.maximumFrequency, 1000), 22050)
        if s.maximumFrequency <= s.minimumFrequency * 4 {
            s.maximumFrequency = s.minimumFrequency * 100
        }
        s.noiseFloorDecibels = min(max(s.noiseFloorDecibels, -140), -20)
        s.maximumDecibels = min(max(s.maximumDecibels, s.noiseFloorDecibels + 10), 12)
        s.sensitivityDecibels = min(max(s.sensitivityDecibels, -30), 30)
        s.dynamicRangeGamma = min(max(s.dynamicRangeGamma, 0.25), 1.0)
        s.attack = min(max(s.attack, 0.01), 1.0)
        s.release = min(max(s.release, 0.01), 1.0)
        return s
    }

    /// Log₂ of the FFT size, which is what vDSP wants.
    public var log2FFTSize: Int {
        Int(log2(Double(fftSize)).rounded())
    }

    /// Number of usable frequency bins, i.e. `fftSize / 2`.
    public var binCount: Int { fftSize / 2 }

    /// Hz per bin.
    public func hertzPerBin(sampleRate: Double) -> Double {
        sampleRate / Double(fftSize)
    }
}
