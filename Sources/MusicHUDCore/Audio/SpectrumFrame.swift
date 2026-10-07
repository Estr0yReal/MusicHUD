import Foundation

/// One analysed frame of spectrum, ready to draw.
///
/// This is the *only* thing the renderer sees. `SpectrumView` consumes this and
/// nothing else: it has no knowledge of Core Audio, `AudioBufferList`, vDSP, FFT
/// sizes or Apple Music.
///
/// It replaces the Phase 1 `AudioAnalysis` placeholder, which served the same
/// role but had no timestamp and was never populated by anything. Rather than
/// run two parallel contracts — the thing the brief explicitly rules out — this
/// type is a superset of the old one, so nothing was lost in the swap.
public struct SpectrumFrame: Equatable, Sendable {

    /// Normalised band levels in `0...1`, lowest frequency first.
    ///
    /// These are the *smoothed* values, i.e. what should actually be drawn.
    public let bands: [Float]

    /// Root-mean-square level of the analysed block, `0...1`.
    public let rms: Float

    /// Peak sample magnitude of the analysed block, `0...1`.
    public let peak: Float

    /// Coarse energy summaries in `0...1`, derived from the same bands.
    public let bassEnergy: Float
    public let midEnergy: Float
    public let trebleEnergy: Float

    /// When the frame was produced.
    public let timestamp: ContinuousClock.Instant

    /// Sample rate the frame was computed from.
    public let sampleRate: Double

    /// FFT length the frame was computed from, so diagnostics can report it.
    public let fftSize: Int

    /// `true` when real PCM was analysed. `false` for a decayed / idle frame.
    public let isReceivingAudio: Bool

    public init(
        bands: [Float],
        rms: Float = 0,
        peak: Float = 0,
        bassEnergy: Float = 0,
        midEnergy: Float = 0,
        trebleEnergy: Float = 0,
        timestamp: ContinuousClock.Instant = .now,
        sampleRate: Double = 0,
        fftSize: Int = 0,
        isReceivingAudio: Bool = false
    ) {
        self.bands = bands
        self.rms = rms
        self.peak = peak
        self.bassEnergy = bassEnergy
        self.midEnergy = midEnergy
        self.trebleEnergy = trebleEnergy
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.isReceivingAudio = isReceivingAudio
    }

    /// An all-zero frame of the given width.
    ///
    /// A renderer receiving this must draw a flat line. It must never invent
    /// motion to fill the gap.
    public static func silent(bandCount: Int, sampleRate: Double = 0, fftSize: Int = 0) -> SpectrumFrame {
        SpectrumFrame(
            bands: [Float](repeating: 0, count: max(bandCount, 0)),
            timestamp: .now,
            sampleRate: sampleRate,
            fftSize: fftSize,
            isReceivingAudio: false
        )
    }
}
