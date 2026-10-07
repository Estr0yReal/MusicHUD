import AppKit
import CoreAudio
import Foundation
import MusicHUDCore

/// Builds and owns a Core Audio process tap on top of a private aggregate device.
///
/// This is the Phase 3 verified path:
///
///     Music.app  →  Core Audio process object
///                →  CATapDescription(stereoMixdownOfProcesses:)
///                →  AudioHardwareCreateProcessTap
///                →  private aggregate device carrying the tap
///                →  AudioDeviceCreateIOProcIDWithBlock
///                →  PCM in an AudioBufferList
///
/// Every call here is public Core Audio API, verified against the macOS 15.5
/// SDK headers rather than from memory.
///
/// `@unchecked Sendable`: creation runs on a background queue and the finished
/// object is handed to the main actor. Only one thread touches it at a time —
/// the setup queue while starting, the main actor afterwards — and the audio
/// thread only reaches the injected engine and counter.
final class CoreAudioTapCapture: @unchecked Sendable {

    /// How long `AudioDeviceStart` is given before we assume the audio-capture
    /// permission prompt is sitting unanswered.
    ///
    /// Measured behaviour: with permission granted, `AudioDeviceStart` returns
    /// in ~0.00 s. Without it, the call blocks for around 90 s while macOS waits
    /// for a TCC decision. Reporting after a few seconds is far more useful than
    /// appearing to hang.
    static let startTimeout: TimeInterval = 8

    /// The process-tap API itself requires macOS 14.2. The rest of the app runs
    /// on 14.0, so this is reported as a state rather than enforced by raising
    /// the whole package's deployment target.
    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    enum CaptureError: Error, CustomStringConvertible {
        case unsupportedOS
        case targetNotRunning(String)
        case processObjectUnavailable(String)
        case tapCreationFailed(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)

        var description: String {
            switch self {
            case .unsupportedOS:
                return "本系统不支持 Core Audio Process Tap（需要 macOS 14.2 或更新版本）"
            case .targetNotRunning(let name):
                return "\(name) 未在运行"
            case .processObjectUnavailable(let name):
                return "无法获取 \(name) 的 Core Audio 进程对象"
            case .tapCreationFailed(let status):
                return "创建 Process Tap 失败（\(describe(status))）"
            case .aggregateCreationFailed(let status):
                return "创建聚合设备失败（\(describe(status))）"
            case .ioProcCreationFailed(let status):
                return "创建 IOProc 失败（\(describe(status))）"
            case .deviceStartFailed(let status):
                return "启动音频设备失败（\(describe(status))）"
            }
        }
    }

    /// Callback counters, written from the audio thread.
    ///
    /// INJECTED, not created here. An earlier version made its own instance,
    /// which meant the service drained a different counter that never received
    /// anything: the capture worked and the spectrum drew correctly, while the
    /// state machine was convinced no audio was arriving and left the badge on
    /// STARTING. One shared counter, owned by the service.
    let counter: TapCallbackCounter
    /// Where captured PCM goes. The audio thread pushes samples into the
    /// engine's ring buffer and does nothing else — no FFT, no allocation.
    let engine: AudioAnalysisEngine
    private(set) var format: AudioStreamFormatInfo?
    private(set) var targetLabel: String = ""

    init(engine: AudioAnalysisEngine, counter: TapCallbackCounter) {
        self.engine = engine
        self.counter = counter
    }

    private var tapID = AudioObjectID(0)
    private var aggregateDeviceID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?

    /// Called on the main queue when `AudioDeviceStart` finally returns.
    var onDeviceStarted: ((Result<TimeInterval, CaptureError>) -> Void)?

    // MARK: - Lifecycle

    /// Creates a tap for `source` and starts reading it.
    ///
    /// Returns as soon as the tap and aggregate device exist. `AudioDeviceStart`
    /// is dispatched asynchronously because it is the call that blocks on the
    /// permission prompt.
    func start(source: AudioCaptureSource, musicBundleID: String) throws {
        stop()

        guard #available(macOS 14.2, *) else { throw CaptureError.unsupportedOS }

        let target = try resolveTarget(source: source, musicBundleID: musicBundleID)
        targetLabel = target.label

        let description: CATapDescription
        switch source {
        case .musicApp:
            guard let objectID = target.processObjectID else {
                throw CaptureError.processObjectUnavailable(target.label)
            }
            description = CATapDescription(stereoMixdownOfProcesses: [objectID])
        case .systemOutput:
            // Exclude ourselves so the HUD cannot visualise its own output.
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownObject = Self.processObjectID(forPID: ownPID)
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownObject.map { [$0] } ?? [])
        }

        description.name = "Music HUD Tap"
        description.uuid = UUID()
        description.isPrivate = true
        // Keep the music audible. A HUD must never mute what it is visualising.
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr, newTapID != 0 else {
            throw CaptureError.tapCreationFailed(tapStatus)
        }
        tapID = newTapID

        if let asbd = Self.tapFormat(tapID) {
            format = AudioStreamFormatInfo(
                sampleRate: asbd.mSampleRate,
                channelCount: Int(asbd.mChannelsPerFrame),
                bytesPerFrame: Int(asbd.mBytesPerFrame),
                formatID: Self.fourCC(asbd.mFormatID),
                isFloat: asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                isInterleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            )
        }

        try createAggregateDevice(tapUUID: description.uuid)
        try createIOProc()
        startDeviceAsync()
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if tapID != 0 {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = 0
        }
        counter.reset()
        format = nil
    }

    var isRunning: Bool { ioProcID != nil }

    // MARK: - Target resolution

    private struct ResolvedTarget {
        var label: String
        var processObjectID: AudioObjectID?
    }

    private func resolveTarget(source: AudioCaptureSource, musicBundleID: String) throws -> ResolvedTarget {
        switch source {
        case .musicApp:
            guard let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == musicBundleID }) else {
                throw CaptureError.targetNotRunning("Music.app")
            }
            let label = app.localizedName ?? "Music"
            guard let objectID = Self.processObjectID(forPID: app.processIdentifier) else {
                throw CaptureError.processObjectUnavailable(label)
            }
            return ResolvedTarget(label: label, processObjectID: objectID)

        case .systemOutput:
            return ResolvedTarget(label: "系统输出", processObjectID: nil)
        }
    }

    // MARK: - Device plumbing

    private func createAggregateDevice(tapUUID: UUID) throws {
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Music HUD Aggregate",
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
        // sample clock consistent with what is being played.
        if let outputUID = Self.defaultOutputDeviceUID() {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceClockDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [
                [kAudioSubDeviceUIDKey: outputUID, kAudioSubDeviceDriftCompensationKey: true]
            ]
        }

        var deviceID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr, deviceID != 0 else {
            throw CaptureError.aggregateCreationFailed(status)
        }
        aggregateDeviceID = deviceID
    }

    private func createIOProc() throws {
        let counter = self.counter
        let engine = self.engine

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, nil) {
            _, inputData, _, _, _ in
            // ── REAL-TIME THREAD ──────────────────────────────────────────
            // Count, mix to mono, push into the ring buffer. No allocation, no
            // logging, no ObjC, no FFT, no locks held across work.
            let bufferList = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )

            let bufferCount = bufferList.count
            guard bufferCount > 0 else { return }

            // Frames, not samples: for interleaved stereo one frame carries two
            // samples, and reporting samples here showed 96 kHz for a 48 kHz
            // stream. `mBytesPerFrame` is the authoritative divisor.
            var frames = 0
            for buffer in bufferList {
                let bytesPerFrame = Int(buffer.mNumberChannels) * MemoryLayout<Float>.size
                guard bytesPerFrame > 0 else { continue }
                frames += Int(buffer.mDataByteSize) / bytesPerFrame
            }
            counter.record(frames: frames)

            if bufferCount == 1 {
                // Interleaved: one buffer carrying every channel. This is what
                // the process tap was measured to deliver (Float32, 2ch).
                let buffer = bufferList[0]
                guard let raw = buffer.mData, buffer.mDataByteSize > 0 else { return }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(
                    start: raw.assumingMemoryBound(to: Float.self),
                    count: count
                )
                engine.ingest(interleaved: samples, channels: Int(buffer.mNumberChannels))
            } else {
                // Non-interleaved: one buffer per channel. Not what this tap
                // produces, but handled rather than assumed away.
                for buffer in bufferList {
                    guard let raw = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = UnsafeBufferPointer(
                        start: raw.assumingMemoryBound(to: Float.self),
                        count: count
                    )
                    engine.ingest(mono: samples)
                }
            }
        }

        guard status == noErr, let procID else {
            throw CaptureError.ioProcCreationFailed(status)
        }
        ioProcID = procID
    }

    private func startDeviceAsync() {
        guard let procID = ioProcID else { return }
        let deviceID = aggregateDeviceID
        let callback = onDeviceStarted

        DispatchQueue.global(qos: .userInitiated).async {
            let startedAt = Date()
            let status = AudioDeviceStart(deviceID, procID)
            let elapsed = Date().timeIntervalSince(startedAt)

            DispatchQueue.main.async {
                if status == noErr {
                    callback?(.success(elapsed))
                } else {
                    callback?(.failure(.deviceStartFailed(status)))
                }
            }
        }
    }

    // MARK: - Core Audio queries

    static func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
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

    static func tapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
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

    static func defaultOutputDeviceUID() -> String? {
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
        // `Unmanaged<CFString>?` because the property returns a +1 CF object.
        var unmanaged: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &unmanaged) == noErr,
              let uid = unmanaged?.takeRetainedValue() else { return nil }
        return uid as String
    }

    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                     UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        let text = String(bytes: bytes, encoding: .ascii) ?? "????"
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func describe(_ status: OSStatus) -> String {
        status == noErr ? "noErr" : "\(status) '\(fourCC(UInt32(bitPattern: status)))'"
    }
}
