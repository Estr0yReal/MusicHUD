import Accelerate
import Foundation

/// The bridge between captured PCM and the renderer.
///
///     audio callback  →  ingest()              (mix to mono, push to ring buffer)
///     analysis worker →  processAvailable()    (pull hops, run FFTs, smooth)
///     UI thread       →  makeFrame()           (read the latest result)
///
/// The three entry points belong to three different threads and are documented as
/// such. No FFT, no allocation and no locking beyond the ring buffer's short
/// critical section happens on the audio thread.
///
/// This type knows nothing about Core Audio, taps or SwiftUI: it is handed
/// samples and produces a `SpectrumFrame`, which is why it can be driven by a
/// synthetic sine wave in the test suite.
public final class AudioAnalysisEngine: @unchecked Sendable {

    public private(set) var settings: SpectrumSettings
    public private(set) var sampleRate: Double

    private let ringBuffer: AudioRingBuffer
    private var analyzer: SpectrumAnalyzer

    private let fftSize: Int
    private let hopSize: Int

    /// Sliding analysis window, `fftSize` samples.
    private let windowBuffer: UnsafeMutablePointer<Float>
    /// One hop of samples pulled from the ring buffer.
    private let hopScratch: UnsafeMutablePointer<Float>
    /// Mono mixdown scratch, written only by the audio thread.
    private let monoscratch: UnsafeMutablePointer<Float>
    private let monoScratchCapacity: Int

    /// Total mono samples ever ingested, used to avoid analysing a window that
    /// is still partly zeros at startup.
    private var samplesIngested = 0

    /// FFTs actually executed, for diagnostics.
    public private(set) var fftCount = 0

    public init(settings: SpectrumSettings = SpectrumSettings(), sampleRate: Double = 48000) {
        let settings = settings.sanitized()
        self.settings = settings
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000
        self.fftSize = settings.fftSize
        self.hopSize = settings.hopSize

        self.analyzer = SpectrumAnalyzer(settings: settings, sampleRate: sampleRate)
        // Room for ~0.34 s of audio; far more than a hop needs, and bounded.
        self.ringBuffer = AudioRingBuffer(capacity: 16384)

        self.windowBuffer = .allocate(capacity: settings.fftSize)
        self.hopScratch = .allocate(capacity: settings.hopSize)
        self.monoScratchCapacity = 8192
        self.monoscratch = .allocate(capacity: 8192)

        windowBuffer.initialize(repeating: 0, count: settings.fftSize)
        hopScratch.initialize(repeating: 0, count: settings.hopSize)
        monoscratch.initialize(repeating: 0, count: 8192)
    }

    deinit {
        windowBuffer.deallocate()
        hopScratch.deallocate()
        monoscratch.deallocate()
    }

    // MARK: - Configuration

    /// Rebuilds the analyser for a new sample rate or new DSP settings.
    ///
    /// Only called when the tap format actually changes or the user changes a
    /// setting, never per frame.
    public func reconfigure(settings: SpectrumSettings? = nil, sampleRate: Double? = nil) {
        if let settings { self.settings = settings.sanitized() }
        if let sampleRate, sampleRate > 0 { self.sampleRate = sampleRate }
        analyzer = SpectrumAnalyzer(settings: self.settings, sampleRate: self.sampleRate)
        ringBuffer.reset()
        windowBuffer.update(repeating: 0, count: fftSize)
        samplesIngested = 0
        fftCount = 0
    }

    // MARK: - Audio thread

    /// Ingests interleaved PCM from the audio callback.
    ///
    /// AUDIO THREAD ONLY. Mixes to mono with `(left + right) / 2`, which is what
    /// the brief asks for, then pushes to the ring buffer. No allocation: the
    /// mono scratch is preallocated.
    public func ingest(interleaved: UnsafeBufferPointer<Float>, channels: Int) {
        guard !interleaved.isEmpty else { return }
        let channelCount = max(channels, 1)

        if channelCount == 1 {
            ringBuffer.write(interleaved)
            samplesIngested += interleaved.count
            return
        }

        let frames = interleaved.count / channelCount
        guard frames > 0 else { return }

        // Chunk so an unexpectedly large buffer cannot overflow the scratch.
        var processed = 0
        while processed < frames {
            let chunk = min(frames - processed, monoScratchCapacity)
            let base = processed * channelCount

            if channelCount == 2 {
                // Stereo: average the pair. Unrolled because this is the hot path.
                for frame in 0..<chunk {
                    monoscratch[frame] = (interleaved[base + frame * 2]
                                          + interleaved[base + frame * 2 + 1]) * 0.5
                }
            } else {
                for frame in 0..<chunk {
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += interleaved[base + frame * channelCount + channel]
                    }
                    monoscratch[frame] = sum / Float(channelCount)
                }
            }

            ringBuffer.write(UnsafeBufferPointer(start: monoscratch, count: chunk))
            samplesIngested += chunk
            processed += chunk
        }
    }

    /// Ingests already-mono samples. AUDIO THREAD ONLY.
    public func ingest(mono: UnsafeBufferPointer<Float>) {
        guard !mono.isEmpty else { return }
        ringBuffer.write(mono)
        samplesIngested += mono.count
    }

    // MARK: - Analysis thread

    /// Pulls complete hops and runs an FFT for each.
    ///
    /// ANALYSIS THREAD ONLY. Bounded by `maximumFFTs` so a backlog cannot stall
    /// the worker: staying current matters more than replaying every hop.
    ///
    /// - Returns: how many FFTs ran.
    @discardableResult
    public func processAvailable(maximumFFTs: Int = 4, deltaTime: Double = 1.0 / 60) -> Int {
        // Do not analyse until a full window of real samples exists; otherwise
        // the first frames are partly zeros and the spectrum starts attenuated.
        guard samplesIngested >= fftSize else { return 0 }

        let available = ringBuffer.availableCount
        let hopsReady = available / hopSize
        guard hopsReady > 0 else { return 0 }

        let hops = min(hopsReady, max(maximumFFTs, 1))
        var ran = 0

        for _ in 0..<hops {
            guard ringBuffer.read(into: hopScratch, count: hopSize) == hopSize else { break }

            // Slide the window left by one hop and append the new samples.
            memmove(
                windowBuffer,
                windowBuffer.advanced(by: hopSize),
                (fftSize - hopSize) * MemoryLayout<Float>.stride
            )
            windowBuffer.advanced(by: fftSize - hopSize).update(from: hopScratch, count: hopSize)

            if analyzer.process(windowBuffer, count: fftSize, deltaTime: deltaTime) {
                ran += 1
                fftCount += 1
            }
        }
        return ran
    }

    /// Decays every band toward zero without running an FFT.
    ///
    /// ANALYSIS THREAD ONLY. This is what makes the display fade out when the
    /// music stops instead of freezing on the last frame.
    public func decay(deltaTime: Double = 1.0 / 60) {
        analyzer.decay(deltaTime: deltaTime)
    }

    /// Drops buffered audio and clears the display, e.g. when the tap is rebuilt.
    public func reset() {
        ringBuffer.reset()
        analyzer.reset()
        windowBuffer.update(repeating: 0, count: fftSize)
        samplesIngested = 0
    }

    // MARK: - Any thread

    /// The current frame, ready to draw.
    public func makeFrame(isReceivingAudio: Bool) -> SpectrumFrame {
        let bands = analyzer.bands
        return SpectrumFrame(
            bands: bands,
            rms: analyzer.lastBlockRMS,
            peak: analyzer.lastBlockPeak,
            bassEnergy: Self.energy(bands, centres: analyzer.bandCentreFrequencies, lower: 0, upper: 250),
            midEnergy: Self.energy(bands, centres: analyzer.bandCentreFrequencies, lower: 250, upper: 4000),
            trebleEnergy: Self.energy(bands, centres: analyzer.bandCentreFrequencies, lower: 4000, upper: .greatestFiniteMagnitude),
            timestamp: .now,
            sampleRate: sampleRate,
            fftSize: settings.fftSize,
            isReceivingAudio: isReceivingAudio
        )
    }

    /// Samples dropped because the analyser fell behind.
    public var overflowCount: Int { ringBuffer.overflowCount }

    /// Samples waiting to be analysed.
    public var bufferedSampleCount: Int { ringBuffer.availableCount }

    /// Centre frequency of each band, for diagnostics.
    public var bandCentreFrequencies: [Double] { analyzer.bandCentreFrequencies }

    private static func energy(
        _ bands: [Float],
        centres: [Double],
        lower: Double,
        upper: Double
    ) -> Float {
        var sum: Float = 0
        var count = 0
        for (index, centre) in centres.enumerated() where index < bands.count {
            guard centre >= lower, centre < upper else { continue }
            sum += bands[index]
            count += 1
        }
        return count > 0 ? sum / Float(count) : 0
    }
}
