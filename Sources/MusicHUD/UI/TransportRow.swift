import MusicHUDCore
import SwiftUI

/// The compact transport row.
///
/// The reference design uses tiny arrow-plus-word affordances rather than
/// chunky buttons, so previous/next are text controls and play/pause is a small
/// ghosted circle in the middle.
///
/// The row has a second job in Phase 2: when macOS has refused Automation
/// access it becomes the "open System Settings" affordance. That keeps the
/// layout stable — no new chrome, no new band — while still giving the user the
/// one action that fixes the problem.
struct TransportRow: View {
    @ObservedObject var app: AppState
    let metrics: HUDMetrics

    var body: some View {
        Group {
            if app.availability.offersSettingsButton {
                settingsButton
            } else {
                transportControls
            }
        }
        .frame(height: metrics.transportRowHeight)
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 0) {
            TransportTextButton(
                symbol: "arrow.left",
                title: "PREVIOUS",
                metrics: metrics,
                isEnabled: app.canControlTransport,
                action: app.previousTrack
            )

            Spacer(minLength: 0)

            TransportPlayButton(
                isPlaying: app.snapshot.state.isPlaying,
                metrics: metrics,
                isEnabled: app.canControlTransport,
                action: app.playPause
            )

            Spacer(minLength: 0)

            TransportTextButton(
                symbol: "arrow.right",
                title: "NEXT",
                trailingSymbol: true,
                metrics: metrics,
                isEnabled: app.canControlTransport,
                action: app.nextTrack
            )
        }
        // Dimmed rather than hidden when Music.app is not running or not
        // authorised: the row is part of the design, and its presence explains
        // that controls exist but are not currently reachable.
        .opacity(app.canControlTransport ? 1 : 0.35)
    }

    // MARK: - Access required

    private var settingsButton: some View {
        Button(action: app.openAutomationSettings) {
            HStack(spacing: metrics.transportFontSize * 0.6) {
                Image(systemName: "gearshape")
                    .font(.system(size: metrics.transportFontSize * 0.9, weight: .regular))
                Text("Open System Settings")
                    .font(.system(size: metrics.transportFontSize, weight: .medium))
            }
            .foregroundStyle(HUDTheme.primaryText)
            .padding(.horizontal, metrics.transportFontSize * 1.1)
            .frame(height: metrics.transportRowHeight)
            .background(
                Capsule(style: .continuous).fill(Color.white.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("hud.transport.openSettings"))
        .accessibilityHint(L("hud.transport.openSettingsHint"))
    }
}

/// `← Previous` / `Next →`.
private struct TransportTextButton: View {
    let symbol: String
    let title: String
    var trailingSymbol: Bool = false
    let metrics: HUDMetrics
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.transportFontSize * 0.5) {
                if !trailingSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.transportFontSize * 0.95, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: metrics.transportFontSize, weight: .medium))
                    .tracking(metrics.transportTracking)
                if trailingSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.transportFontSize * 0.95, weight: .semibold))
                }
            }
            .foregroundStyle(hovering && isEnabled ? HUDTheme.primaryText : HUDTheme.transportText)
            // The glyphs stay tiny by design, so the *target* is enlarged
            // instead: a taller, wider content shape with no visual change.
            .frame(minWidth: metrics.transportHitWidth, minHeight: metrics.transportRowHeight * 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        // The visible label is a bare `←`/`Next`; VoiceOver needs the verb.
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(isEnabled ? "" : L("hud.transport.musicUnavailable"))
    }

    private var accessibilityName: String {
        // `symbol`/`title` come from the call site, so map from the direction.
        switch (symbol, trailingSymbol) {
        case ("arrow.left", false): return L("hud.transport.previous")
        case ("arrow.right", true): return L("hud.transport.next")
        default: return title
        }
    }
}

/// Small ghosted circular play/pause.
private struct TransportPlayButton: View {
    let isPlaying: Bool
    let metrics: HUDMetrics
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let diameter = metrics.transportRowHeight * 1.05

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(hovering && isEnabled ? 0.16 : 0.10))
                Circle()
                    .strokeBorder(
                        Color.white.opacity(hovering && isEnabled ? 0.22 : 0.13),
                        lineWidth: 0.8
                    )
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(Color(white: hovering && isEnabled ? 0.98 : 0.86))
                    // `play.fill` is visually left-heavy inside a circle; nudge it.
                    .offset(x: isPlaying ? 0 : diameter * 0.045)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(L(isPlaying ? "hud.transport.pause" : "hud.transport.play"))
        .accessibilityHint(isEnabled ? "" : L("hud.transport.musicUnavailable"))
    }
}
