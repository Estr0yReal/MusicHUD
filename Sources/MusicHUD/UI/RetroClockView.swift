import MusicHUDCore
import SwiftUI

/// The big retro numeric display and its caption.
///
/// TWO DISPLAY MODES (Phase 6)
/// * `.track` — whatever `ClockMode` is configured (elapsed, progress, or local
///   time), captioned `TRACK`.
/// * `.worldClock(city)` — wall-clock time in a city, captioned `TOKYO · JST`.
///   Tapping the display advances the rotation; see `WorldClockCycle`.
///
/// DATA HONESTY
/// * Wall-clock values in either mode come from the real system clock through
///   `TimelineView`, which ticks once a second. There is no hand-rolled timer
///   pretending to be playback progress, and the digits are always derived from
///   the same source the rest of the card uses.
/// * `TimelineView` lives *inside* this view, so its one-second invalidation
///   cannot reach the spectrum's render path.
struct RetroClockView: View {
    /// Which of the two display modes is active.
    let displayMode: ClockDisplayMode
    let mode: ClockMode
    let style: ClockStyle
    let clockScale: Double
    let timeZoneIdentifier: String
    let captionOverride: String
    let showGhostSegments: Bool
    let snapshot: NowPlayingSnapshot
    let sessionElapsed: TimeInterval
    let metrics: HUDMetrics

    var body: some View {
        VStack(spacing: metrics.spacingAfterDigits) {
            digits
            caption
        }
        .contentShape(Rectangle())
        // The click/drag decision lives in the gesture modifier applied by
        // `HUDView`, so this view only has to describe itself. The whole block
        // is one control; the caption carries the state, so VoiceOver reads
        // "TOKYO · JST" rather than an unlabelled number.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L("hud.clock.cycleHint"))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        switch displayMode {
        case .track:
            return String(format: L("hud.clock.display"), captionText)
        case .worldClock(let city):
            return String(format: L("hud.clock.currentTimeIn"), city.displayName, city.timeString(at: Date()))
        }
    }

    // MARK: - Digits

    /// `true` when the digits show a wall clock and must tick once a second.
    private var needsWallClockTick: Bool {
        switch displayMode {
        case .worldClock: return true
        case .track: return mode.isWallClock
        }
    }

    @ViewBuilder
    private var digits: some View {
        if needsWallClockTick {
            // Real wall clock. `TimelineView` drives the one-second cadence;
            // there is no hand-rolled timer anywhere in the app.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                glyphRow(for: text(at: timeline.date))
            }
        } else {
            glyphRow(for: text(at: Date()))
        }
    }

    @ViewBuilder
    private func glyphRow(for text: String) -> some View {
        let height = metrics.digitHeight(clockScale: CGFloat(clockScale))

        Group {
            switch style {
            case .sevenSegment:
                let digitWidth = height * HUDMetrics.digitAspect
                let colonWidth = height * HUDMetrics.colonAspect
                let gap = height * HUDMetrics.glyphGapAspect

                HStack(spacing: gap) {
                    ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                        if character == ":" {
                            SevenSegmentColonView(color: HUDTheme.clockDigit)
                                .frame(width: colonWidth, height: height)
                        } else {
                            SevenSegmentDigitView(
                                mask: SevenSegmentFont.mask(for: character),
                                color: HUDTheme.clockDigit,
                                ghostColor: showGhostSegments ? HUDTheme.clockGhost : nil
                            )
                            .frame(width: digitWidth, height: height)
                        }
                    }
                }

            case .monospaced:
                Text(text)
                    .font(.system(size: height * 1.12, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .kerning(height * 0.05)
                    .foregroundStyle(HUDTheme.clockDigit)
                    // A whisper of drop shadow, which is what gives a real
                    // segmented display its sense of sitting behind glass.
                    .shadow(color: .black.opacity(0.38), radius: height * 0.03, x: 0, y: height * 0.016)
                    .frame(height: height)
            }
        }
        .frame(height: height)
    }

    // MARK: - Caption

    private var caption: some View {
        Text(captionText)
            .font(.system(size: metrics.captionFontSize, weight: .regular))
            .tracking(metrics.captionTracking)
            .foregroundStyle(HUDTheme.mutedText)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var captionText: String {
        let override = captionOverride.trimmingCharacters(in: .whitespaces)

        // In a world-clock mode the city label is the primary identity and must
        // never be replaced by a custom caption.
        if case .worldClock(let city) = displayMode {
            return city.caption(at: Date())
        }
        if !override.isEmpty { return override }

        switch mode {
        case .systemTime:
            return L("hud.clock.localTimeCaption")
        case .timeZoneTime:
            return HUDTimeFormatter.timeZoneName(timeZoneIdentifier)
        case .sessionElapsed:
            // The brief specifies the literal `TRACK` as the secondary mode
            // label, so the digits' provenance is stated in one short word
            // rather than a sentence.
            return snapshot.source.isDemo ? L("hud.clock.demoSuffix") : L("hud.clock.track")
        case .trackProgress:
            return snapshot.source.isDemo ? L("hud.clock.demoSuffix") : L("hud.clock.track")
        }
    }

    // MARK: - Value

    /// The string shown for the current mode, always in the reference's
    /// zero-padded `HH:MM:SS` shape.
    private func text(at date: Date) -> String {
        // A world-clock mode overrides the track-derived value entirely. The
        // conversion is done by `TimeZone`, never by arithmetic on offsets.
        if case .worldClock(let city) = displayMode {
            return city.timeString(at: date)
        }
        switch mode {
        case .systemTime:
            return HUDTimeFormatter.wallClock(date, timeZone: .current)

        case .timeZoneTime:
            let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
            return HUDTimeFormatter.wallClock(date, timeZone: zone)

        case .sessionElapsed:
            return HUDTimeFormatter.clockStyle(sessionElapsed)

        case .trackProgress:
            return HUDTimeFormatter.clockStyle(snapshot.position)
        }
    }
}
