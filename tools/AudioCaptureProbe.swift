// AudioCaptureProbe — Phase 3 minimal verification tool.
//
// Answers exactly one question: can this process obtain real PCM from Music.app
// via a Core Audio process tap? It deliberately does not touch the HUD, does not
// do FFT, and invents nothing: every number it prints comes from a real
// AudioBufferList.
//
// Build:
//   swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
//          Sources/MusicHUD/../tools/AudioCaptureProbe.swift -o build/AudioCaptureProbe
//
// Run:
//   ./build/AudioCaptureProbe --seconds 20

import AppKit
import CoreAudio
import Foundation

// MARK: - Logging

let startTime = Date()

/// Reads `--name value` from the command line.
func argument(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

/// Optional log file. Needed because a bundled app launched through `open`
/// has no attached stdout, and a bundled app is the only way to get a correct
/// TCC identity for the audio-capture permission.
let logFileHandle: FileHandle? = {
    guard let path = argument("--log") else { return nil }
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

func log(_ message: String) {
    let elapsed = Date().timeIntervalSince(startTime)
    let line = String(format: "[%6.2fs] %@\n", elapsed, message)
    print(line, terminator: "")
    fflush(stdout)
    logFileHandle?.write(Data(line.utf8))
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                 UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    let text = String(bytes: bytes, encoding: .ascii) ?? "????"
    return text.trimmingCharacters(in: .whitespaces).isEmpty ? "????" : text
}

func describe(_ status: OSStatus) -> String {
    if status == noErr { return "noErr" }
    let value = UInt32(bitPattern: status)
    return "\(status) '\(fourCC(value))'"
}

// MARK: - Shared capture statistics
//
// Written from the real-time IOProc, read from the main thread. A plain lock is
// used here because this is a diagnostic probe; the shipping service uses a
// wait-free snapshot instead. Either way, the callback itself does no
// allocation, no logging, no UI work and no I/O.

final class TapStats {
    private var lock = os_unfair_lock_s()

    private(set) var callbackCount: UInt64 = 0
    private(set) var frameCount: UInt64 = 0
    /// Sum of squares accumulated across all samples, for RMS.
    private var sumOfSquares: Double = 0
    private var sampleCount: UInt64 = 0
    private var peak: Float = 0
    private var nonZeroSamples: UInt64 = 0

    private var lastCallbackAt: Date?

    struct Snapshot {
        var callbackCount: UInt64
        var frameCount: UInt64
        var rms: Float
        var peak: Float
        var nonZeroSamples: UInt64
        var secondsSinceLastCallback: TimeInterval?
    }

    func record(frames: Int, sumOfSquares: Double, sampleCount: Int, peak: Float, nonZero: Int) {
        os_unfair_lock_lock(&lock)
        callbackCount += 1
        frameCount += UInt64(frames)
        self.sumOfSquares += sumOfSquares
        self.sampleCount += UInt64(sampleCount)
        self.peak = max(self.peak, peak)
        self.nonZeroSamples += UInt64(nonZero)
        lastCallbackAt = Date()
        os_unfair_lock_unlock(&lock)
    }

    /// Reads and resets the one-second window.
    func drain() -> Snapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let rms = sampleCount > 0 ? Float((sumOfSquares / Double(sampleCount)).squareRoot()) : 0
        let snapshot = Snapshot(
            callbackCount: callbackCount,
            frameCount: frameCount,
            rms: rms,
            peak: peak,
            nonZeroSamples: nonZeroSamples,
            secondsSinceLastCallback: lastCallbackAt.map { Date().timeIntervalSince($0) }
        )
        callbackCount = 0
        frameCount = 0
        sumOfSquares = 0
        sampleCount = 0
        peak = 0
        nonZeroSamples = 0
        return snapshot
    }
}

// MARK: - Core Audio helpers

func defaultOutputDeviceUID() -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    ) == noErr else { return nil }

    var uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    // `Unmanaged<CFString>?` rather than `CFString`: this property returns a +1
    // CF object, and forming an unsafe pointer to a plain CFString is incorrect
    // because it holds an object reference.
    var unmanagedUID: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &unmanagedUID) == noErr,
          let uid = unmanagedUID?.takeRetainedValue() else {
        return nil
    }
    return uid as String
}

/// PID -> Core Audio process object.
func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
    var pidValue = pid
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var objectID = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &objectID
    )
    guard status == noErr, objectID != 0 else { return nil }
    return objectID
}

func tapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr else {
        return nil
    }
    return asbd
}

// MARK: - Capture

final class ProcessTapCapture {
    private(set) var tapID = AudioObjectID(0)
    private(set) var aggregateDeviceID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?

    let stats = TapStats()
    private(set) var format: AudioStreamBasicDescription?

    /// Creates a tap on `processObjectID`, wraps it in a private aggregate
    /// device, and starts an IOProc reading it.
    func start(processObjectID: AudioObjectID, label: String) throws {
        log("[AUDIO] Creating process tap for \(label) (object \(processObjectID))")

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "MusicHUD Probe Tap"
        description.uuid = UUID()
        // A private tap is visible only to this process, which is all we need.
        description.isPrivate = true
        // `.unmuted` means the music keeps playing out of the speakers while we
        // capture it. `.muted` would silence playback, which is not what a HUD
        // should ever do.
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr, newTapID != 0 else {
            throw ProbeError.tapCreationFailed(tapStatus)
        }
        tapID = newTapID

        if let asbd = tapFormat(tapID) {
            format = asbd
            log("[AUDIO] Tap format: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, "
                + "\(asbd.mBitsPerChannel) bit, "
                + "format=\(fourCC(asbd.mFormatID)), "
                + "flags=0x\(String(asbd.mFormatFlags, radix: 16)), "
                + "bytesPerFrame=\(asbd.mBytesPerFrame), "
                + "nonInterleaved=\(asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)")
        } else {
            log("[AUDIO] WARNING: could not read tap format")
        }

        try createAggregateDevice(tapUUID: description.uuid, label: label)
        try startIOProc()
    }

    private func createAggregateDevice(tapUUID: UUID, label: String) throws {
        // The tap is not a device; it has to be hosted by an aggregate device
        // before an IOProc can read from it. This is the documented pattern.
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MusicHUD Probe Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        // Clocking the aggregate to the real output device keeps the tap's
        // sample clock consistent with what is actually being played.
        if let outputUID = defaultOutputDeviceUID() {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceClockDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [
                [kAudioSubDeviceUIDKey: outputUID, kAudioSubDeviceDriftCompensationKey: true]
            ]
            log("[AUDIO] Aggregate clocked to output device \(outputUID.prefix(24))…")
        } else {
            log("[AUDIO] WARNING: no default output device UID; tap-only aggregate")
        }

        var deviceID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr, deviceID != 0 else {
            throw ProbeError.aggregateCreationFailed(status)
        }
        aggregateDeviceID = deviceID
        log("[AUDIO] Aggregate device created (id \(deviceID))")
    }

    private func startIOProc() throws {
        let stats = self.stats
        let isNonInterleaved = (format?.mFormatFlags ?? 0) & kAudioFormatFlagIsNonInterleaved != 0

        var procID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID, aggregateDeviceID, nil
        ) { _, inputData, _, _, _ in
            // REAL-TIME THREAD. No allocation, no locks held across work, no
            // logging, no ObjC, no I/O. Just arithmetic into shared counters.
            let bufferList = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )

            var sumOfSquares: Double = 0
            var sampleCount = 0
            var peak: Float = 0
            var nonZero = 0
            var frames = 0

            for buffer in bufferList {
                guard let raw = buffer.mData else { continue }
                let sampleCountInBuffer = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard sampleCountInBuffer > 0 else { continue }

                let samples = raw.assumingMemoryBound(to: Float.self)
                for index in 0..<sampleCountInBuffer {
                    let value = samples[index]
                    let magnitude = abs(value)
                    if magnitude > peak { peak = magnitude }
                    if magnitude > 0 { nonZero += 1 }
                    sumOfSquares += Double(value) * Double(value)
                }
                sampleCount += sampleCountInBuffer

                if buffer.mNumberChannels > 0 {
                    frames += sampleCountInBuffer / Int(buffer.mNumberChannels)
                } else {
                    frames += sampleCountInBuffer
                }
            }

            _ = isNonInterleaved
            stats.record(
                frames: frames,
                sumOfSquares: sumOfSquares,
                sampleCount: sampleCount,
                peak: peak,
                nonZero: nonZero
            )
        }

        guard createStatus == noErr, let procID else {
            throw ProbeError.ioProcCreationFailed(createStatus)
        }
        ioProcID = procID

        // `AudioDeviceStart` is where `kTCCServiceAudioCapture` is evaluated.
        // When the permission prompt is unanswered it blocks for around 90
        // seconds, so it is dispatched off the main thread — otherwise the
        // probe looks hung and produces no diagnostics at all.
        log("[AUDIO] Calling AudioDeviceStart (this is where TCC is checked)")
        let deviceID = aggregateDeviceID
        DispatchQueue.global(qos: .userInitiated).async {
            let startedAt = Date()
            let status = AudioDeviceStart(deviceID, procID)
            let took = Date().timeIntervalSince(startedAt)
            if status == noErr {
                log(String(format: "[AUDIO] IOProc started on aggregate device (took %.2fs)", took))
            } else {
                log(String(format: "[AUDIO] ERROR: AudioDeviceStart failed after %.2fs: %@",
                           took, describe(status)))
            }
        }
    }

    func stop() {
        log("[AUDIO] Stopping")
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
            log("[AUDIO] IOProc stopped and destroyed")
        }
        if aggregateDeviceID != 0 {
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            log("[AUDIO] Aggregate device destroyed (\(describe(status)))")
            aggregateDeviceID = 0
        }
        if tapID != 0 {
            let status = AudioHardwareDestroyProcessTap(tapID)
            log("[AUDIO] Tap destroyed (\(describe(status)))")
            tapID = 0
        }
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case musicNotFound
    case processObjectNotFound(pid_t)
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var description: String {
        switch self {
        case .musicNotFound:
            return "Music.app is not running"
        case .processObjectNotFound(let pid):
            return "no Core Audio process object for pid \(pid)"
        case .tapCreationFailed(let status):
            return "AudioHardwareCreateProcessTap failed: \(describe(status))"
        case .aggregateCreationFailed(let status):
            return "AudioHardwareCreateAggregateDevice failed: \(describe(status))"
        case .ioProcCreationFailed(let status):
            return "AudioDeviceCreateIOProcIDWithBlock failed: \(describe(status))"
        case .deviceStartFailed(let status):
            return "AudioDeviceStart failed: \(describe(status))"
        }
    }
}

// MARK: - dBFS

func dbfs(_ amplitude: Float, floor: Float = -120) -> Float {
    guard amplitude > 0 else { return floor }
    return max(20 * log10f(amplitude), floor)
}

// MARK: - Main

let runSeconds = TimeInterval(argument("--seconds") ?? "20") ?? 20
let targetBundleID = argument("--bundle") ?? "com.apple.Music"

log("[AUDIO] AudioCaptureProbe starting (target: \(targetBundleID), \(runSeconds)s)")

guard let app = NSWorkspace.shared.runningApplications
    .first(where: { $0.bundleIdentifier == targetBundleID }) else {
    log("[AUDIO] ERROR: \(targetBundleID) is not running")
    exit(2)
}

let pid = app.processIdentifier
log("[AUDIO] Process found: \(app.localizedName ?? "?") (pid \(pid))")

guard let objectID = processObjectID(forPID: pid) else {
    log("[AUDIO] ERROR: no Core Audio process object for pid \(pid)")
    exit(3)
}
log("[AUDIO] Core Audio process object: \(objectID)")

let capture = ProcessTapCapture()
do {
    try capture.start(processObjectID: objectID, label: app.localizedName ?? "?")
} catch {
    log("[AUDIO] ERROR: \(error)")
    capture.stop()
    exit(4)
}

// One-second diagnostic summary, as the brief requires — never per callback.
let deadline = Date().addingTimeInterval(runSeconds)
var summaryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    let snapshot = capture.stats.drain()
    let status: String
    if snapshot.callbackCount == 0 {
        status = "NO PCM"
    } else if snapshot.nonZeroSamples == 0 {
        status = "PCM but SILENT"
    } else {
        status = "RECEIVING"
    }
    log(String(
        format: "[AUDIO] %@ callbacks=%llu frames=%llu rms=%.4f (%.1f dBFS) peak=%.4f (%.1f dBFS) nonzero=%llu",
        status,
        snapshot.callbackCount,
        snapshot.frameCount,
        snapshot.rms, dbfs(snapshot.rms),
        snapshot.peak, dbfs(snapshot.peak),
        snapshot.nonZeroSamples
    ))
    if Date() >= deadline {
        summaryTimer.invalidate()
        summaryTimer = Timer()   // break the retain cycle for the run loop
        capture.stop()
        log("[AUDIO] Probe finished")
        exit(0)
    }
}

RunLoop.main.add(summaryTimer, forMode: .common)
RunLoop.main.run()
