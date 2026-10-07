import MusicHUDCore
import SwiftUI

/// The Phase 3 diagnostics panel.
///
/// This is a **tool**, not the product UI. It is not the HUD, it does not
/// replace the HUD, and nothing here is meant to look like the reference design.
/// Its only job is to make the truth about the capture pipeline visible: real
/// numbers, real format, real state, and the raw diagnostic log.
struct AudioDiagnosticsView: View {
    @ObservedObject var service: AudioCaptureService

    private var format: AudioStreamFormatInfo? { service.format }
    private var rmsDecibels: Float { service.level?.rmsDecibels ?? DecibelScale.floor }
    private var peakDecibels: Float { service.level?.peakDecibels ?? DecibelScale.floor }
    private var peakHoldDecibels: Float {
        DecibelScale.decibels(fromAmplitude: service.peakHold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            meters
            Divider()
            formatTable
            Divider()
            fftTable
            Divider()
            statusRow
            Divider()
            logSection
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Diagnostics")
                    .font(.system(size: 16, weight: .semibold))
                Text(L(service, "diagnostics.pipeline"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(service.state.isActive ? L("diagnostics.stop") : L("diagnostics.start")) {
                if service.state.isActive {
                    service.stop()
                } else {
                    service.start()
                }
            }
        }
    }

    // MARK: - Meters

    private var meters: some View {
        VStack(alignment: .leading, spacing: 12) {
            MeterBar(
                label: "RMS",
                decibels: rmsDecibels,
                holdDecibels: nil,
                accent: Color(red: 0.42, green: 0.78, blue: 0.52)
            )
            MeterBar(
                label: "Peak",
                decibels: peakDecibels,
                holdDecibels: peakHoldDecibels,
                accent: Color(red: 0.86, green: 0.62, blue: 0.34)
            )

            if service.state == .silent {
                Text(L("diagnostics.silentNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Format

    private var formatTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PCM")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow { label("Sample Rate"); value(format.map { "\(Int($0.sampleRate)) Hz" } ?? "—") }
                GridRow { label("Channels"); value(format.map { "\($0.channelCount)" } ?? "—") }
                GridRow { label("Format"); value(format.map { "\($0.formatID)\($0.isFloat ? " / Float32" : "") / \($0.isInterleaved ? "interleaved" : "non-interleaved")" } ?? "—") }
                GridRow { label("Bytes / Frame"); value(format.map { "\($0.bytesPerFrame)" } ?? "—") }
                GridRow { label("Frames / s"); value(service.framesPerSecond > 0 ? String(format: "%.0f", service.framesPerSecond) : "—") }
                GridRow { label("Source"); value("\(service.source.localizedName) · \(service.targetLabel)") }
            }
        }
    }

    /// FFT and pipeline diagnostics.
    ///
    /// These are the numbers that prove the DSP is real and cheap: the FFT
    /// length actually in use, how long one analysis tick takes, how many frames
    /// per second reach the UI, and whether the ring buffer ever overflowed.
    private var fftTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FFT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow { label("FFT Size"); value("\(service.analysisSettings.fftSize)") }
                GridRow { label("Hop Size"); value("\(service.analysisSettings.hopSize)") }
                GridRow { label("Band Count"); value("\(service.analysisSettings.bandCount)") }
                GridRow { label("Window"); value("Hann") }
                GridRow { label("Noise Floor"); value(String(format: "%.0f dBFS", service.analysisSettings.noiseFloorDecibels)) }
                GridRow { label("FFT Time"); value(String(format: "%.2f ms / tick", service.fftMilliseconds)) }
                GridRow { label("UI FPS"); value(String(format: "%.0f", service.displayFramesPerSecond)) }
                GridRow { label("Ring Overflow"); value("\(service.overflowCount)") }
            }
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(service.state.badgeText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Picker("", selection: $service.source) {
                    ForEach(AudioCaptureSource.allCases) { source in
                        Text(source.localizedName).tag(source)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            if !service.statusDetail.isEmpty {
                Text(service.statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(service.source.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if service.state == .permissionDenied {
                permissionHelp
            }
        }
    }

    private var permissionHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("diagnostics.screenRecordingNote"))
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L("hud.transport.openSettings")) {
                    // Same deep link approach as the Music access prompt.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var statusColor: Color {
        switch service.state {
        case .receiving: return Color(red: 0.35, green: 0.80, blue: 0.45)
        case .silent: return Color(red: 0.95, green: 0.75, blue: 0.30)
        case .starting: return Color(red: 0.40, green: 0.65, blue: 0.95)
        case .permissionDenied, .failed: return Color(red: 0.92, green: 0.40, blue: 0.38)
        case .idle, .stopped, .unsupported: return Color.secondary
        }
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("diagnostics.logTitle"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("diagnostics.clear")) { service.clearLog() }
                    .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(service.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: service.logLines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .frame(minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
        }
    }

    // MARK: - Small helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .leading)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
    }
}

/// A horizontal dBFS bar with an optional peak-hold marker.
private struct MeterBar: View {
    let label: String
    let decibels: Float
    let holdDecibels: Float?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f dBFS", decibels))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent)
                        .frame(width: max(geometry.size.width * DecibelScale.normalised(decibels), 0))

                    if let holdDecibels {
                        let x = geometry.size.width * DecibelScale.normalised(holdDecibels)
                        Rectangle()
                            .fill(accent.opacity(0.85))
                            .frame(width: 2)
                            .offset(x: min(max(x - 1, 0), geometry.size.width - 2))
                    }
                }
            }
            .frame(height: 12)
        }
    }
}
