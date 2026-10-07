import AppKit
import MusicHUDCore
import SwiftUI

/// The whole component: one translucent card holding the three bands from the
/// reference design, top to bottom.
///
///   1. music info  — small centred artwork, title, `来自 <artist>`
///   2. spectrum    — near full-bleed band of fine vertical bars
///   3. retro clock — oversized rounded seven-segment digits and a caption
///
/// Every dimension comes from `HUDMetrics`, which is derived from the live
/// window size, so the card keeps the reference proportions at any size.
struct HUDView: View {
    @ObservedObject var app: AppState

    var body: some View {
        GeometryReader { geometry in
            let metrics = HUDMetrics(
                containerWidth: geometry.size.width,
                containerHeight: geometry.size.height
            )

            ZStack {
                cardBackground(metrics: metrics)

                content(metrics: metrics)

                statusBadges(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, metrics.padding * 0.65)
                    .padding(.top, metrics.padding * 0.65)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                ResizeGrip(bridge: app.windowBridge) {
                    app.persistWindowFrame()
                }
                .padding(metrics.padding * 0.22)
            }
        }
    }

    // MARK: - Background

    /// Layered glass: a real behind-window blur, a dark tint so the type stays
    /// readable over bright wallpapers, then a faint sheen and a hairline
    /// border. Nothing here is an opaque fill, which is what lets the wallpaper
    /// show through.
    private func cardBackground(metrics: HUDMetrics) -> some View {
        let radius = CGFloat(app.settings.cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return ZStack {
            VisualEffectBackground()
                .opacity(app.settings.blurStrength)

            Color.black.opacity(app.settings.panelTint)

            LinearGradient(
                colors: [HUDTheme.cardSheen, Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(HUDTheme.cardBorder, lineWidth: 1))
        .contentShape(shape)
        .modifier(WindowDragModifier(bridge: app.windowBridge, onCommit: app.persistWindowFrame))
    }

    // MARK: - Content

    private func content(metrics: HUDMetrics) -> some View {
        let settings = app.settings
        let drag = WindowDragModifier(bridge: app.windowBridge, onCommit: app.persistWindowFrame)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            // ── Band 1: music information ───────────────────────────────
            MusicInfoView(
                snapshot: app.snapshot,
                availability: app.availability,
                artworkImage: app.artworkImage,
                allowsProceduralArtwork: settings.dataSource == .demo,
                showArtwork: settings.showArtwork,
                showTrackInfo: settings.showTrackInfo,
                metrics: metrics
            )
            .padding(.horizontal, metrics.padding)
            .padding(.top, metrics.padding)
            .modifier(drag)

            // Metadata separator: a hairline with a small inset, so it reads as
            // dividing the metadata block rather than as a full-width band.
            Rectangle()
                .fill(HUDTheme.hairline)
                .frame(height: metrics.ruleHeight)
                .padding(.horizontal, metrics.separatorInset)
                .padding(.top, metrics.spacingBeforeRule)
                .modifier(drag)

            // ── Transport ───────────────────────────────────────────────
            if settings.showTransport {
                TransportRow(app: app, metrics: metrics)
                    .padding(.horizontal, metrics.padding)
                    .padding(.top, metrics.spacingAfterRule)
            }

            // ── Detail list ─────────────────────────────────────────────
            if settings.showDetailList {
                // Only a track that is actually being displayed gets listed.
                // When the card is in an idle state the rows show "—" rather
                // than the metadata of a track that is loaded but stopped,
                // which would contradict the headline above it.
                TrackDetailView(
                    metadata: app.availability.isReady ? app.snapshot.metadata : nil,
                    metrics: metrics
                )
                .padding(.horizontal, metrics.padding)
                .padding(.top, settings.showTransport
                         ? metrics.spacingAfterTransport
                         : metrics.spacingAfterRule)
                .modifier(drag)
            }

            // ── Band 2: spectrum ────────────────────────────────────────
            // Fed by the real FFT of the real PCM from Music.app. The view
            // knows nothing about Core Audio or vDSP.
            SpectrumView(
                display: app.audio.spectrumDisplay,
                barCount: settings.spectrumBarCount,
                tint: settings.spectrumTint,
                metrics: metrics
            )
            .padding(.horizontal, metrics.bleedPadding)
            .padding(.top, metrics.spacingAfterDetails)

            // ── Band 3: retro clock ─────────────────────────────────────
            RetroClockView(
                displayMode: app.clockDisplayMode,
                mode: settings.clockMode,
                style: settings.clockStyle,
                clockScale: settings.clockScale,
                timeZoneIdentifier: settings.timeZoneIdentifier,
                captionOverride: settings.clockCaptionOverride,
                showGhostSegments: settings.showGhostSegments,
                snapshot: app.snapshot,
                sessionElapsed: app.sessionElapsed,
                metrics: metrics
            )
            .padding(.horizontal, metrics.bleedPadding)
            .padding(.top, metrics.spacingAfterSpectrum)
            .padding(.bottom, metrics.padding)
            // One gesture, two outcomes (Phase 6.1). A release that never
            // crossed `clockDragThreshold` cycles the display mode; anything
            // further moves the window. Stacking a separate tap gesture on top
            // of a drag gesture is what made this unreliable in Phase 6 — with
            // a single gesture the two outcomes cannot both fire.
            .modifier(
                WindowDragModifier(
                    bridge: app.windowBridge,
                    onClick: app.advanceClockDisplay,
                    threshold: metrics.clockDragThreshold,
                    onCommit: app.persistWindowFrame
                )
            )

            Spacer(minLength: 0)
        }
    }

    // MARK: - Status badges

    /// Small, low-contrast badges that keep the prototype honest.
    ///
    /// The demo badge shows only while demo data is selected; the audio badge
    /// reports the live capture state (`RECEIVING AUDIO`, `SILENT`, …) from the
    /// real pipeline.
    @ViewBuilder
    private func statusBadges(metrics: HUDMetrics) -> some View {
        if app.settings.showStatusCaptions {
            VStack(alignment: .trailing, spacing: metrics.badgeFontSize * 0.45) {
                if app.snapshot.source.isDemo {
                    StatusBadge(text: "DEMO DATA", metrics: metrics)
                }
                StatusBadge(text: app.captureState.badgeText, metrics: metrics)
            }
        }
    }
}

// MARK: - Badge

private struct StatusBadge: View {
    let text: String
    let metrics: HUDMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .medium))
            .tracking(metrics.badgeFontSize * 0.09)
            .foregroundStyle(Color.white.opacity(0.42))
            .padding(.horizontal, metrics.badgeFontSize * 0.55)
            .padding(.vertical, metrics.badgeFontSize * 0.22)
            .background(
                Capsule(style: .continuous).fill(Color.white.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
            )
    }
}

// MARK: - Dragging

/// Moves the window when the user drags a non-interactive part of the card.
///
/// DRAG-ONLY (the default)
/// `minimumDistance: 2` is deliberate: a plain click never starts a drag, so
/// clicks still reach the transport buttons cleanly. Regions that pass no
/// `onClick` behave exactly as they did before Phase 6.1.
///
/// CLICK OR DRAG (when `onClick` is supplied, as on the clock)
/// The gesture has to see the pointer *down* to be able to recognise a click,
/// so `minimumDistance` becomes 0 and the decision is made on release instead:
/// a release that never crossed `threshold` is a click, anything further is a
/// drag. One gesture, one outcome — which is why this replaced the Phase 6
/// arrangement of a tap gesture stacked on a drag gesture.
struct WindowDragModifier: ViewModifier {
    let bridge: WindowBridge
    /// Called when the pointer is released without ever exceeding the
    /// threshold. `nil` for regions that are drag-only.
    var onClick: (() -> Void)?
    /// Movement required before the interaction becomes a drag.
    var threshold: CGFloat = 2
    let onCommit: () -> Void

    /// Both values are captured once, when the pointer goes down, and are the
    /// only reference for the rest of the gesture.
    @State private var startOrigin: CGPoint?
    @State private var startPointer: CGPoint?
    /// Latches once the threshold is crossed, so a gesture that drags out and
    /// back still counts as a drag on release rather than flipping to a click.
    @State private var isDragging = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                // A click-only region must receive the pointer *down*: with
                // `minimumDistance: 2` a stationary click produces no gesture
                // events at all, so there would be nothing to distinguish it
                // from. Drag-only regions keep the original 2 pt activation so
                // their behaviour is untouched.
                DragGesture(minimumDistance: onClick == nil ? 2 : 0)
                    .onChanged { _ in
                        // The pointer is read from AppKit, not from the gesture.
                        //
                        // This is the Phase 6.2 fix. SwiftUI's default gesture
                        // coordinate space is the *view's* space, which moves
                        // with the window: the reported translation is
                        // `screenDelta - windowDelta`, so feeding it back as the
                        // window's movement makes the window follow the pointer
                        // at roughly half speed with a frame-varying gain. That
                        // read as shaking.
                        //
                        // `NSEvent.mouseLocation` is a screen coordinate, so it
                        // is unaffected by the window moving underneath the
                        // pointer, and it shares a coordinate system with
                        // `window.frame.origin` — no axis inversion is needed.
                        guard let window = bridge.window else { return }
                        let pointer = NSEvent.mouseLocation

                        if startOrigin == nil {
                            startOrigin = window.frame.origin
                            startPointer = pointer
                            isDragging = false
                        }

                        if !isDragging {
                            guard let from = startPointer,
                                  PointerGestureDecision.isDrag(
                                      CGSize(
                                          width: pointer.x - from.x,
                                          height: pointer.y - from.y
                                      ),
                                      threshold: threshold
                                  )
                            else { return }
                            isDragging = true
                        }

                        guard let origin = startOrigin, let from = startPointer else { return }
                        // Anchored to the origin captured at pointer-down, so the
                        // pointer-to-window offset is preserved exactly and the
                        // first dragged frame already accounts for the travel
                        // below the threshold — hence no jump when it begins.
                        let target = WindowDragMath.origin(
                            initialOrigin: origin,
                            initialPointer: from,
                            currentPointer: pointer
                        )
                        window.setFrameOrigin(target)
                    }
                    .onEnded { _ in
                        if isDragging {
                            onCommit()
                        } else {
                            onClick?()
                        }
                        startOrigin = nil
                        startPointer = nil
                        isDragging = false
                    }
            )
    }
}

// MARK: - Resize grip

/// The bottom-right resize handle.
///
/// A borderless `NSPanel` gets no title bar and no resize affordance from
/// AppKit, so this draws an explicit grip and drives `setFrame` directly. This
/// is why sizing is guaranteed to work regardless of the window style mask.
struct ResizeGrip: View {
    let bridge: WindowBridge
    let onCommit: () -> Void

    @State private var startFrame: NSRect?
    @State private var hovering = false

    private let side: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            let colour = Color.white.opacity(hovering ? 0.55 : 0.26)
            for index in 0..<3 {
                let offset = CGFloat(index) * 4 + 3.5
                var path = Path()
                path.move(to: CGPoint(x: size.width - 3 - offset, y: size.height - 3))
                path.addLine(to: CGPoint(x: size.width - 3, y: size.height - 3 - offset))
                context.stroke(
                    path,
                    with: .color(colour),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityLabel(L("hud.resizeGrip"))
        .accessibilityHint(L("hud.resizeGripHint"))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let window = bridge.window else { return }
                    if startFrame == nil { startFrame = window.frame }
                    guard let start = startFrame else { return }

                    let width = start.width + value.translation.width
                    // Dragging down should shrink: AppKit y grows upward, so the
                    // top edge stays put and the origin moves with the height.
                    let height = start.height - value.translation.height

                    let frame = NSRect(
                        x: start.origin.x,
                        y: start.maxY - height,
                        width: width,
                        height: height
                    )
                    // `panel.minSize` / `maxSize` clamp this for us.
                    window.setFrame(frame, display: true)
                }
                .onEnded { _ in
                    startFrame = nil
                    onCommit()
                }
        )
    }
}
