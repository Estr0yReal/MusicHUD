import AppKit
import MusicHUDCore
import SwiftUI

/// Album artwork slot.
///
/// Three sources, in priority order:
///
/// 1. **Real artwork** from Music.app, passed in as an already-decoded
///    `NSImage`. Decoding happens once per track change in `AppState`, not on
///    every render.
/// 2. **Procedural art** derived from the track's seed — demo mode only.
/// 3. **A neutral placeholder** when a real track genuinely has no cover.
///
/// The procedural path must never run for real Apple Music data; a generated
/// image standing in for missing artwork would be exactly the kind of
/// fabrication this phase is supposed to remove.
struct ArtworkView: View {
    let image: NSImage?
    let seed: Int
    /// Whether procedural fallback art is legitimate here (demo mode).
    let allowsProceduralFallback: Bool
    let hasTrack: Bool
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if allowsProceduralFallback {
                proceduralArt
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.38), radius: size * 0.07, x: 0, y: size * 0.025)
        // A gentle cross-fade when the cover changes, as the brief allows.
        .animation(.easeInOut(duration: 0.28), value: image)
        .opacity(hasTrack ? 1 : 0.5)
    }

    // MARK: - Fallbacks

    private var placeholder: some View {
        ZStack {
            HUDTheme.color(ArtworkPaletteLibrary.palette(forSeed: 0).bottom)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.30, weight: .light))
                .foregroundStyle(Color.white.opacity(0.22))
        }
    }

    private var proceduralArt: some View {
        let palette = ArtworkPaletteLibrary.palette(forSeed: seed)

        return ZStack {
            LinearGradient(
                colors: [HUDTheme.color(palette.top), HUDTheme.color(palette.bottom)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, canvasSize in
                drawMotif(palette.motif, accent: palette.accent, in: &context, size: canvasSize)
            }

            // A soft top-edge highlight so the cover does not look flat.
            LinearGradient(
                colors: [Color.white.opacity(0.16), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Procedural motifs (demo mode only)

    private func drawMotif(
        _ motif: ArtworkPalette.Motif,
        accent: RGB,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let accentColor = HUDTheme.color(accent)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        switch motif {
        case .rings:
            for index in 0..<4 {
                let radius = size.width * (0.18 + CGFloat(index) * 0.15)
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(accentColor.opacity(0.30 - Double(index) * 0.06)),
                    lineWidth: size.width * 0.018
                )
            }

        case .waves:
            for index in 0..<5 {
                let y = size.height * (0.22 + CGFloat(index) * 0.14)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                let amplitude = size.height * 0.05
                let steps = 24
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let wave = sin(t * .pi * 2.4 + CGFloat(index) * 0.7) * amplitude
                    path.addLine(to: CGPoint(x: t * size.width, y: y + wave))
                }
                context.stroke(
                    path,
                    with: .color(accentColor.opacity(0.34 - Double(index) * 0.05)),
                    style: StrokeStyle(lineWidth: size.width * 0.016, lineCap: .round)
                )
            }

        case .grid:
            let spacing = size.width / 6
            let lineWidth = size.width * 0.010
            for index in 1..<6 {
                let offset = CGFloat(index) * spacing
                var vertical = Path()
                vertical.move(to: CGPoint(x: offset, y: 0))
                vertical.addLine(to: CGPoint(x: offset, y: size.height))
                context.stroke(vertical, with: .color(accentColor.opacity(0.18)), lineWidth: lineWidth)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: offset))
                horizontal.addLine(to: CGPoint(x: size.width, y: offset))
                context.stroke(horizontal, with: .color(accentColor.opacity(0.18)), lineWidth: lineWidth)
            }
            let dot = size.width * 0.16
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - dot / 2,
                    y: center.y - dot / 2,
                    width: dot,
                    height: dot
                )),
                with: .color(accentColor.opacity(0.55))
            )
        }
    }
}
