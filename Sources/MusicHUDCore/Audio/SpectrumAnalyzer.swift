import Accelerate
import Foundation

/// Turns a block of mono PCM into normalised spectrum bands.
///
/// The full chain, in order:
///
///     mono PCM
///       → Hann window                     (reduces spectral leakage)
///       → vDSP real FFT (`vDSP_fft_zrip`) (2048-point by default)
///       → magnitude                       (`vDSP_zvmags`, sqrt)
///       → amplitude normalisation         (window coherent gain + vDSP's 2× factor)
///       → dBFS                            (20·log10)
///       → log-spaced band aggregation     (48 bands, 20 Hz … 20 kHz)
///       → noise floor / dynamic range     (map to 0…1)
///       → asymmetric attack / release     (smoothing)
///       → SpectrumFrame
///
/// All buffers and the FFT setup are allocated once in `init`. `process` performs
/// no heap allocation, so it is safe to call at the ~94 Hz hop rate.
///
/// ### Two SDK details that had to be checked rather than assumed
///
/// * `vDSP_fft_zrip` applies a forward `scale = 2`, so its output is twice the
///   true DFT. That factor is divided out below; without it every reading would
///   be +6 dB too hot.
/// * `vDSP_hann_window` needs `vDSP_HANN_DENORM`, otherwise it multiplies by
///   `0.8165`, and its formula uses `N` rather than the `N-1` the brief
///   specifies. The window is therefore computed directly from the brief's
///   formula, once, at construction.
///
/// This type has no knowledge of Core Audio, threads or SwiftUI: it is handed
/// samples and produces numbers, which is what makes it unit testable.
public final class SpectrumAnalyzer {

    public let settings: SpectrumSettings
    public let sampleRate: Double

    private let fftSize: Int
    private let binCount: Int
    private let bandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?

    // Preallocated scratch. Owned raw memory rather than Swift arrays so the
    // hot path does no retain/release and no bounds checking.
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let realPart: UnsafeMutablePointer<Float>
    private let imagPart: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let smoothedBands: UnsafeMutablePointer<Float>
    private let rawBands: UnsafeMutablePointer<Float>

    /// Inclusive bin index ranges, one per visual band.
    private let bandLowerBins: [Int]
    private let bandUpperBins: [Int]

    /// Inverse of the coherent gain of the window, divided by vDSP's factor of 2.
    private let amplitudeScale: Float

    /// Sum of the window, used for the coherent-gain correction.
    public let windowCoherentGain: Float

    /// Centre frequency of each band, for diagnostics.
    public let bandCentreFrequencies: [Double]

    /// Inclusive bin range of each band, exposed so the mapping can be asserted
    /// on directly rather than inferred from the output.
    public var bandLowerBinsPublic: [Int] { bandLowerBins }
    public var bandUpperBinsPublic: [Int] { bandUpperBins }

    public init(settings: SpectrumSettings, sampleRate: Double) {
        let settings = settings.sanitized()
        self.settings = settings
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000

        self.fftSize = settings.fftSize
        self.binCount = settings.fftSize / 2
        self.bandCount = settings.bandCount
        self.log2n = vDSP_Length(settings.log2FFTSize)

        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(settings.log2FFTSize), FFTRadix(kFFTRadix2))

        self.window = .allocate(capacity: settings.fftSize)
        self.windowed = .allocate(capacity: settings.fftSize)
        self.realPart = .allocate(capacity: self.binCount)
        self.imagPart = .allocate(capacity: self.binCount)
        self.magnitudes = .allocate(capacity: self.binCount)
        self.smoothedBands = .allocate(capacity: settings.bandCount)
        self.rawBands = .allocate(capacity: settings.bandCount)

        window.initialize(repeating: 0, count: settings.fftSize)
        windowed.initialize(repeating: 0, count: settings.fftSize)
        realPart.initialize(repeating: 0, count: self.binCount)
        imagPart.initialize(repeating: 0, count: self.binCount)
        magnitudes.initialize(repeating: 0, count: self.binCount)
        smoothedBands.initialize(repeating: 0, count: settings.bandCount)
        rawBands.initialize(repeating: 0, count: settings.bandCount)

        // Hann window, exactly as the brief specifies:
        //     w[n] = 0.5 · (1 − cos(2πn / (N−1)))
        let n = settings.fftSize
        var windowSum: Float = 0
        for index in 0..<n {
            let value = 0.5 * (1 - cos(2 * Float.pi * Float(index) / Float(n - 1)))
            window[index] = value
            windowSum += value
        }
        self.windowCoherentGain = windowSum / Float(n)

        // |Z| = 2·|X| from vDSP, and |X_peak| = A/2·sum(w) for a bin-centred
        // sine, so A = |Z| / sum(w).
        let coherentSum = Float(n) * (windowSum / Float(n))
        self.amplitudeScale = coherentSum > 0 ? 1 / coherentSum : 0

        var lower: [Int] = []
        var upper: [Int] = []
        var centres: [Double] = []
        lower.reserveCapacity(settings.bandCount)
        upper.reserveCapacity(settings.bandCount)
        centres.reserveCapacity(settings.bandCount)

        let ratio = settings.maximumFrequency / settings.minimumFrequency
        // Bin 0 (DC) is skipped: it carries any DC offset rather than music, and
        // contaminating the lowest visible band with it would be misleading.
        var previousUpper = 0
        for band in 0..<settings.bandCount {
            let lowerFraction = Double(band) / Double(settings.bandCount)
            let upperFraction = Double(band + 1) / Double(settings.bandCount)
            let lowerHz = settings.minimumFrequency * pow(ratio, lowerFraction)
            let upperHz = settings.minimumFrequency * pow(ratio, upperFraction)

            var lowerBin = Int((lowerHz / self.sampleRate) * Double(settings.fftSize))
            var upperBin = Int((upperHz / self.sampleRate) * Double(settings.fftSize)) - 1

            lowerBin = min(max(lowerBin, 1), self.binCount - 1)
            upperBin = min(max(upperBin, lowerBin), self.binCount - 1)
            // Keep the ranges strictly increasing so no band is empty and no bin
            // is silently skipped between consecutive bands.
            lowerBin = max(lowerBin, previousUpper + 1)
            upperBin = max(upperBin, lowerBin)
            if lowerBin > self.binCount - 1 {
                lowerBin = self.binCount - 1
                upperBin = self.binCount - 1
            }
            previousUpper = upperBin

            lower.append(lowerBin)
            upper.append(upperBin)
            centres.append(sqrt(lowerHz * upperHz))
        }

        self.bandLowerBins = lower
        self.bandUpperBins = upper
        self.bandCentreFrequencies = centres
    }

    deinit {
        window.deallocate()
        windowed.deallocate()
        realPart.deallocate()
        imagPart.deallocate()
        magnitudes.deallocate()
        smoothedBands.deallocate()
        rawBands.deallocate()
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Analysis

    /// Runs one FFT over exactly `fftSize` mono samples and updates the bands.
    ///
    /// - Returns: `false` when the input length is wrong or the FFT setup could
    ///   not be created, in which case the bands are left untouched.
    /// One analysis tick. `deltaTime` is the wall-clock spacing between calls.
    ///
    /// Smoothing is expressed as a time constant and converted to a per-tick
    /// coefficient, so the spectrum looks the same at 30 FPS and at 60 FPS.
    /// A fixed per-frame coefficient would make the release twice as fast just
    /// because the display rate doubled.
    @discardableResult
    public func process(_ samples: UnsafePointer<Float>, count: Int, deltaTime: Double = 1.0 / 60) -> Bool {
        guard let fftSetup, count == fftSize else { return false }

        // RMS and peak of the raw block, before windowing.
        var blockRMS: Float = 0
        var blockPeak: Float = 0
        vDSP_rmsqv(samples, 1, &blockRMS, vDSP_Length(fftSize))
        vDSP_maxmgv(samples, 1, &blockPeak, vDSP_Length(fftSize))
        lastBlockRMS = blockRMS
        lastBlockPeak = blockPeak

        // 1. Window.
        vDSP_vmul(samples, 1, window, 1, windowed, 1, vDSP_Length(fftSize))

        // 2. Pack the real signal as a split-complex vector, then run the
        //    in-place real FFT.
        var split = DSPSplitComplex(realp: realPart, imagp: imagPart)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { pointer in
            vDSP_ctoz(pointer, 2, &split, 1, vDSP_Length(binCount))
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // 3. Magnitude squared, then magnitude.
        vDSP_zvmags(&split, 1, magnitudes, 1, vDSP_Length(binCount))

        // vDSP packs DC into realp[0] and Nyquist into imagp[0]; zvmags treats
        // them as a complex pair, which would fold Nyquist energy into DC. Only
        // DC is wanted in bin 0.
        magnitudes[0] = realPart[0] * realPart[0]

        var count = Int32(binCount)
        vvsqrtf(magnitudes, magnitudes, &count)

        // 4. Normalise to amplitude, so 0 dBFS means full scale regardless of
        //    FFT size or window.
        var scale = amplitudeScale
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, vDSP_Length(binCount))

        // 5. Aggregate into log-spaced bands, in dB, mapped to 0…1.
        let noiseFloor = settings.noiseFloorDecibels
        let span = max(settings.maximumDecibels - noiseFloor, 1)
        let gamma = settings.dynamicRangeGamma

        for band in 0..<bandCount {
            let lower = bandLowerBins[band]
            let upper = bandUpperBins[band]

            // RMS of the bin magnitudes across the band. Chosen over "max bin"
            // because a single bin peak jitters frame to frame and looks noisy;
            // RMS of the band is far steadier while still real.
            var sumOfSquares: Float = 0
            for bin in lower...upper {
                let magnitude = magnitudes[bin]
                sumOfSquares += magnitude * magnitude
            }
            let binTotal = Float(upper - lower + 1)
            let bandMagnitude = binTotal > 0 ? (sumOfSquares / binTotal).squareRoot() : 0

            let decibels = (bandMagnitude > 0 ? 20 * log10f(bandMagnitude) : -Float.infinity)
                + settings.sensitivityDecibels
            let normalised = min(max((decibels - noiseFloor) / span, 0), 1)
            rawBands[band] = normalised > 0 ? powf(normalised, gamma) : 0
        }

        // 6. Asymmetric smoothing: fast attack, slow release.
        //
        // The settings carry per-frame coefficients measured at 60 FPS; those
        // are converted to time constants once, then to a coefficient for the
        // actual tick spacing.
        let dt = min(max(deltaTime, 1.0 / 240), 0.5)
        let attack = Self.coefficient(perFrame: settings.attack, dt: dt)
        let release = Self.coefficient(perFrame: settings.release, dt: dt)
        for band in 0..<bandCount {
            let target = rawBands[band]
            let current = smoothedBands[band]
            let coefficient = target > current ? attack : release
            smoothedBands[band] = current + (target - current) * coefficient
        }

        return true
    }

    /// Converts a per-frame smoothing coefficient (defined at 60 FPS) into a
    /// coefficient for a tick of length `dt`.
    static func coefficient(perFrame: Float, dt: Double) -> Float {
        let clamped = min(max(perFrame, 0.0001), 0.9999)
        let timeConstant = -(1.0 / 60.0) / log(1.0 - Double(clamped))
        return Float(1 - exp(-dt / timeConstant))
    }

    /// Drives every band toward zero without running an FFT.
    ///
    /// Used when no PCM is arriving, so the display decays to nothing instead of
    /// freezing on the last frame. At the default release of 0.12 and 60 Hz this
    /// reaches ~5% of full scale in about 0.4 s, which matches the 200–500 ms the
    /// brief asks for.
    public func decay(deltaTime: Double = 1.0 / 60) {
        let release = Self.coefficient(perFrame: settings.release, dt: min(max(deltaTime, 1.0 / 240), 0.5))
        for band in 0..<bandCount {
            smoothedBands[band] += (0 - smoothedBands[band]) * release
            rawBands[band] = 0
        }
        lastBlockRMS = 0
        lastBlockPeak = 0
    }

    /// Zeroes everything immediately, e.g. when the tap is rebuilt.
    public func reset() {
        smoothedBands.update(repeating: 0, count: bandCount)
        rawBands.update(repeating: 0, count: bandCount)
        lastBlockRMS = 0
        lastBlockPeak = 0
    }

    // MARK: - Readings

    public private(set) var lastBlockRMS: Float = 0
    public private(set) var lastBlockPeak: Float = 0

    /// Current smoothed band values, `0...1`.
    public var bands: [Float] {
        Array(UnsafeBufferPointer(start: smoothedBands, count: bandCount))
    }

    /// Unsmoothed band values for the most recent frame, `0...1`.
    public var unsmoothedBands: [Float] {
        Array(UnsafeBufferPointer(start: rawBands, count: bandCount))
    }

    /// Linear amplitude magnitudes for the most recent frame.
    ///
    /// Allocates, so it is for diagnostics and tests rather than the hot path.
    public func magnitudeSpectrum() -> [Float] {
        Array(UnsafeBufferPointer(start: magnitudes, count: binCount))
    }

    /// Frequency of a bin, in Hz: `bin · sampleRate / fftSize`.
    public func frequency(ofBin bin: Int) -> Double {
        Double(bin) * sampleRate / Double(fftSize)
    }

    /// Bin index nearest a frequency, for tests and diagnostics.
    public func bin(forFrequency hertz: Double) -> Int {
        let raw = hertz * Double(fftSize) / sampleRate
        return min(max(Int(raw.rounded()), 0), binCount - 1)
    }

    /// The strongest bin in the most recent frame, ignoring DC.
    public var peakBin: Int {
        var best = 1
        var bestValue: Float = -1
        for bin in 1..<binCount where magnitudes[bin] > bestValue {
            bestValue = magnitudes[bin]
            best = bin
        }
        return best
    }

    /// Frequency of the strongest bin in the most recent frame.
    public var peakFrequency: Double {
        frequency(ofBin: peakBin)
    }
}
