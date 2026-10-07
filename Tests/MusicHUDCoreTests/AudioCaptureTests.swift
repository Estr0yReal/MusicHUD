import XCTest
@testable import MusicHUDCore

/// Phase 3 tests.
///
/// These cover the arithmetic that turns PCM into a meter reading. They need no
/// audio device, no permission and no Music.app: the accumulator takes a plain
/// `UnsafeBufferPointer<Float>`, so every case below is fully deterministic.
final class AudioCaptureTests: XCTestCase {

    /// Runs samples through the exact production accumulator.
    private func measure(_ samples: [Float]) -> LevelMeasurement {
        var accumulator = LevelAccumulator()
        samples.withUnsafeBufferPointer { accumulator.add($0) }
        return accumulator.measurement
    }

    // MARK: - RMS

    func testFullScaleSquareWaveHasUnityRMS() {
        // The case from the brief: a full-scale alternating signal.
        let measurement = measure([1, -1, 1, -1])
        XCTAssertEqual(measurement.rms, 1.0, accuracy: 0.0001)
        XCTAssertEqual(measurement.peak, 1.0, accuracy: 0.0001)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: measurement.rms), 0, accuracy: 0.01)
    }

    func testHalfScaleRMSIsMinusSixDecibels() {
        // A 0.5 amplitude sine/square has RMS 0.5 → 20·log10(0.5) = −6.02 dBFS.
        let measurement = measure([0.5, -0.5, 0.5, -0.5])
        XCTAssertEqual(measurement.rms, 0.5, accuracy: 0.0001)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: measurement.rms), -6.0206, accuracy: 0.01)
    }

    func testRMSIsNotJustASingleSample() {
        // A single loud spike must not read as loud overall: RMS weighs the
        // whole window, which is the entire reason it is used instead of
        // grabbing one sample.
        var samples = [Float](repeating: 0, count: 1000)
        samples[500] = 1.0
        let measurement = measure(samples)

        XCTAssertEqual(measurement.peak, 1.0, accuracy: 0.0001, "peak still sees the spike")
        XCTAssertEqual(measurement.rms, Float(1.0 / 1000.0.squareRoot()), accuracy: 0.001)
        XCTAssertLessThan(measurement.rms, 0.05, "RMS must stay low for a single spike")
    }

    func testRMSOfConstantDCIsTheConstant() {
        let measurement = measure([Float](repeating: 0.25, count: 64))
        XCTAssertEqual(measurement.rms, 0.25, accuracy: 0.0001)
    }

    func testACSignalHasZeroMeanButNonZeroRMS() {
        // Sanity check that RMS is not accidentally implementing a mean.
        let samples: [Float] = (0..<256).map { index in
            index % 2 == 0 ? 0.8 : -0.8
        }
        let measurement = measure(samples)
        XCTAssertEqual(measurement.rms, 0.8, accuracy: 0.001)
    }

    // MARK: - Peak

    func testPeakUsesMagnitudeNotSignedValue() {
        // A large negative sample must not be missed.
        let measurement = measure([0.1, 0.2, -0.9, 0.3])
        XCTAssertEqual(measurement.peak, 0.9, accuracy: 0.0001)
    }

    func testPeakIsTheMaximumAcrossAllBuffers() {
        // Peak is a running maximum, not a per-buffer replacement: a transient
        // in an earlier buffer must still be visible.
        var accumulator = LevelAccumulator()
        [Float(0.9), 0.1].withUnsafeBufferPointer { accumulator.add($0) }
        [Float(0.2), 0.3].withUnsafeBufferPointer { accumulator.add($0) }
        XCTAssertEqual(accumulator.measurement.peak, 0.9, accuracy: 0.0001)
    }

    // MARK: - Silence

    func testAllZeroSamplesAreDetectedAsSilence() {
        let measurement = measure([0, 0, 0, 0])
        XCTAssertEqual(measurement.rms, 0)
        XCTAssertEqual(measurement.peak, 0)
        XCTAssertTrue(measurement.isSilent)
        XCTAssertFalse(measurement.hasSignal)
    }

    func testSilenceIsDistinctFromNoData() {
        // The distinction the brief insists on, and which live measurement
        // confirmed really occurs: Music.app paused mid-track delivers buffers
        // that are entirely zero, while Music.app idle delivers no buffers at
        // all. One is capture working on a quiet source; the other is nothing
        // flowing. They must not collapse into the same state.
        let silent = measure([Float](repeating: 0, count: 512))
        XCTAssertTrue(silent.isSilent)
        XCTAssertFalse(silent.hasSignal)
        XCTAssertEqual(silent.sampleCount, 512, "samples were examined")

        let nothing = LevelMeasurement.empty
        XCTAssertFalse(nothing.isSilent, "an empty window is not silence")
        XCTAssertFalse(nothing.hasSignal)
        XCTAssertEqual(nothing.sampleCount, 0)
    }

    func testOneNonZeroSampleMeansNotSilent() {
        // In real audio the noise floor is rarely exactly zero, but if a single
        // non-zero sample arrives we must not claim silence.
        var samples = [Float](repeating: 0, count: 512)
        samples[17] = 0.0001
        let measurement = measure(samples)
        XCTAssertFalse(measurement.isSilent)
        XCTAssertTrue(measurement.hasSignal)
    }

    // MARK: - dB conversion

    func testDecibelConversionOfKnownAmplitudes() {
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: 1.0), 0, accuracy: 0.001)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: 0.5), -6.0206, accuracy: 0.001)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: 0.1), -20, accuracy: 0.001)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: 0.01), -40, accuracy: 0.001)
    }

    func testZeroAmplitudeUsesTheFloorRatherThanNegativeInfinity() {
        // log10(0) is −∞, which cannot be drawn or compared.
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: 0), DecibelScale.floor)
        XCTAssertEqual(DecibelScale.floor, -120)
        XCTAssertTrue(DecibelScale.decibels(fromAmplitude: 0).isFinite)
    }

    func testDecibelConversionRejectsNonFiniteAndNegativeInput() {
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: -1), DecibelScale.floor)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: .nan), DecibelScale.floor)
        XCTAssertEqual(DecibelScale.decibels(fromAmplitude: .infinity), DecibelScale.floor)
    }

    func testDecibelNormalisationMapsFloorToZeroAndFullScaleToOne() {
        XCTAssertEqual(DecibelScale.normalised(-120), 0, accuracy: 0.0001)
        XCTAssertEqual(DecibelScale.normalised(0), 1, accuracy: 0.0001)
        XCTAssertEqual(DecibelScale.normalised(-60), 0.5, accuracy: 0.0001)
    }

    func testDecibelNormalisationClampsOutOfRangeInput() {
        XCTAssertEqual(DecibelScale.normalised(-500), 0, accuracy: 0.0001)
        XCTAssertEqual(DecibelScale.normalised(20), 1, accuracy: 0.0001)
    }

    // MARK: - Multi-channel

    func testStereoChannelsAreCombined() {
        // All channels are folded into one measurement. Feeding two identical
        // channels must give the same RMS as one, not double it: the RMS of
        // [L, L] over twice the samples equals the RMS of L.
        let mono = measure([0.5, -0.5, 0.5, -0.5])
        let stereo = measure([0.5, 0.5, -0.5, -0.5, 0.5, 0.5, -0.5, -0.5])
        XCTAssertEqual(stereo.rms, mono.rms, accuracy: 0.0001)
        XCTAssertEqual(stereo.peak, mono.peak, accuracy: 0.0001)
    }

    func testHardPannedEnergyIsNotMissed() {
        // Energy that exists in only one channel used to be invisible if you
        // measured a single "main" channel. Combining all channels still finds
        // it: nothing is missed.
        let left: [Float] = [0, 0, 0, 0]
        let right: [Float] = [0.8, -0.8, 0.8, -0.8]

        var accumulator = LevelAccumulator()
        left.withUnsafeBufferPointer { accumulator.add($0) }
        right.withUnsafeBufferPointer { accumulator.add($0) }

        let measurement = accumulator.measurement
        XCTAssertEqual(measurement.peak, 0.8, accuracy: 0.0001, "the peak is still the transient")

        // The RMS is taken over all eight delivered samples, four of which are
        // silent, so it reads lower than the active channel alone:
        // sqrt((4 x 0.64) / 8) = 0.5657. That is the documented consequence of
        // aggregating across channels — correlated stereo (the normal case for
        // music) is unaffected, because both channels carry the signal.
        XCTAssertEqual(measurement.rms, 0.5657, accuracy: 0.001)
        XCTAssertEqual(measurement.sampleCount, 8)
    }

    func testFrameCountDividesSamplesByChannelCount() {
        // 1024 interleaved stereo samples are 512 frames, which is the number
        // the UI reports.
        let measurement = LevelMeasurement(rms: 0, peak: 0, sampleCount: 1024, nonZeroSampleCount: 0)
        XCTAssertEqual(measurement.frameCount(channelCount: 2), 512)
        XCTAssertEqual(measurement.frameCount(channelCount: 1), 1024)
    }

    func testFrameCountDoesNotDivideByZero() {
        let measurement = LevelMeasurement(rms: 0, peak: 0, sampleCount: 1024, nonZeroSampleCount: 0)
        XCTAssertEqual(measurement.frameCount(channelCount: 0), 1024)
        XCTAssertEqual(measurement.frameCount(channelCount: -2), 1024)
    }

    // MARK: - Empty and invalid buffers

    func testEmptyBufferProducesAnEmptyMeasurement() {
        let measurement = measure([])
        XCTAssertEqual(measurement, .empty)
        XCTAssertEqual(measurement.rms, 0)
        XCTAssertEqual(measurement.peak, 0)
        XCTAssertFalse(measurement.hasSignal)
        XCTAssertFalse(measurement.isSilent)
    }

    func testEmptyBufferDoesNotChangeARunningAccumulator() {
        var accumulator = LevelAccumulator()
        [Float(0.5), -0.5].withUnsafeBufferPointer { accumulator.add($0) }
        let before = accumulator.measurement

        [Float]().withUnsafeBufferPointer { accumulator.add($0) }
        XCTAssertEqual(accumulator.measurement, before)
    }

    func testNaNandInfinitySamplesAreSkippedRatherThanPoisoningRMS() {
        // A single NaN would otherwise make the whole RMS NaN and paint the
        // meter with garbage for the rest of the session.
        //
        // Non-finite samples are skipped *entirely*: not summed, and not
        // counted. Four finite samples of magnitude 0.5 therefore give an RMS
        // of exactly 0.5 over a sample count of 4, rather than being diluted by
        // the two that were discarded.
        let measurement = measure([0.5, .nan, -0.5, .infinity, 0.5, -0.5])
        XCTAssertTrue(measurement.rms.isFinite)
        XCTAssertTrue(measurement.peak.isFinite)
        XCTAssertEqual(measurement.rms, 0.5, accuracy: 0.0001)
        XCTAssertEqual(measurement.peak, 0.5, accuracy: 0.0001)
        XCTAssertEqual(measurement.sampleCount, 4)
    }

    func testAccumulatorResetClearsEverything() {
        var accumulator = LevelAccumulator()
        [Float(1), -1].withUnsafeBufferPointer { accumulator.add($0) }
        XCTAssertEqual(accumulator.measurement.peak, 1)

        accumulator.reset()
        XCTAssertEqual(accumulator.measurement, .empty)
    }

    // MARK: - Level model

    func testLevelDecibelAccessors() {
        let level = AudioLevel(
            rms: 0.5,
            peak: 1.0,
            sampleRate: 48000,
            channelCount: 2,
            frameCount: 512,
            timestamp: .now
        )
        XCTAssertEqual(level.rmsDecibels, -6.0206, accuracy: 0.001)
        XCTAssertEqual(level.peakDecibels, 0, accuracy: 0.001)
        XCTAssertFalse(level.isSilent)
    }

    func testSilentLevelReportsTheFloor() {
        let level = AudioLevel(
            rms: 0, peak: 0, sampleRate: 48000, channelCount: 2, frameCount: 512, timestamp: .now
        )
        XCTAssertTrue(level.isSilent)
        XCTAssertEqual(level.rmsDecibels, DecibelScale.floor)
        XCTAssertEqual(level.peakDecibels, DecibelScale.floor)
    }

    // MARK: - Result / state mapping

    func testCaptureResultMapsToStates() {
        let level = AudioLevel(
            rms: 0.1, peak: 0.2, sampleRate: 48000, channelCount: 2, frameCount: 512, timestamp: .now
        )
        XCTAssertEqual(AudioCaptureResult.noData.state, .idle)
        XCTAssertEqual(AudioCaptureResult.silence(level).state, .silent)
        XCTAssertEqual(AudioCaptureResult.audio(level).state, .receiving)
    }

    func testCaptureResultExposesItsLevelExceptWhenThereIsNone() {
        let level = AudioLevel(
            rms: 0.1, peak: 0.2, sampleRate: 48000, channelCount: 2, frameCount: 512, timestamp: .now
        )
        XCTAssertNil(AudioCaptureResult.noData.level)
        XCTAssertEqual(AudioCaptureResult.silence(level).level, level)
        XCTAssertEqual(AudioCaptureResult.audio(level).level, level)
    }

    func testEveryCaptureStateHasABadgeAndALabel() {
        for state in AudioCaptureState.allCases {
            XCTAssertFalse(state.badgeText.isEmpty, "\(state) has no badge")
            XCTAssertFalse(state.localizedName.isEmpty, "\(state) has no label")
        }
    }

    func testOnlyReceivingAndSilentCountAsActive() {
        XCTAssertTrue(AudioCaptureState.receiving.isActive)
        XCTAssertTrue(AudioCaptureState.silent.isActive)
        XCTAssertFalse(AudioCaptureState.idle.isActive)
        XCTAssertFalse(AudioCaptureState.starting.isActive)
        XCTAssertFalse(AudioCaptureState.permissionDenied.isActive)
        XCTAssertFalse(AudioCaptureState.failed.isActive)
        XCTAssertFalse(AudioCaptureState.stopped.isActive)
    }

    func testCaptureSourceHasLocalisedNamesAndExplanations() {
        for source in AudioCaptureSource.allCases {
            XCTAssertFalse(source.localizedName.isEmpty)
            XCTAssertFalse(source.explanation.isEmpty)
        }
    }
}
