import MusicHUDCore
import SwiftUI

/// One seven-segment digit, drawn as seven round-capped strokes.
///
/// This is why the digits look like the reference: the strokes are lines with
/// `lineCap: .round` that overlap at shared corner points, so the joints blend
/// into the thick, rounded, "electronic" shapes the reference shows. Drawing
/// filled polygons instead would produce hard mitred corners.
///
/// Lit and unlit strokes are each emitted as a *single* path rather than one
/// stroke per segment. Overlapping round caps composite once per stroke call,
/// so batching avoids bright or dark dots appearing at every corner where two
/// semi-transparent segments meet.
///
/// Geometry is entirely relative to the incoming frame, so the digit scales
/// cleanly to any window size.
struct SevenSegmentDigitView: View {
    let mask: SevenSegmentMask
    let color: Color
    /// Colour for unlit strokes. `nil` hides them entirely.
    let ghostColor: Color?
    /// Shadow cast by the lit strokes only.
    ///
    /// It is applied inside the canvas rather than with a `.shadow()` view
    /// modifier on purpose. A view modifier shadows everything the canvas
    /// drew — including the ghost strokes, which cover most of the digit box.
    /// That produced a dark rectangle behind every digit instead of a shadow
    /// under the shape.
    var litShadow: Bool = true

    var body: some View {
        Canvas { context, size in
            let thickness = size.height * HUDMetrics.segmentThicknessRatio

            /// Segment endpoints, inset by half the stroke weight so a round cap
            /// lands exactly on the corner.
            func endpointPair(
                for position: SevenSegmentPosition,
                thickness: CGFloat
            ) -> (CGPoint, CGPoint) {
                let inset = thickness / 2
                let maxX = size.width - inset
                let maxY = size.height - inset
                let midY = size.height / 2
                switch position {
                case .top:
                    return (CGPoint(x: inset, y: inset), CGPoint(x: maxX, y: inset))
                case .middle:
                    return (CGPoint(x: inset, y: midY), CGPoint(x: maxX, y: midY))
                case .bottom:
                    return (CGPoint(x: inset, y: maxY), CGPoint(x: maxX, y: maxY))
                case .topLeft:
                    return (CGPoint(x: inset, y: inset), CGPoint(x: inset, y: midY))
                case .topRight:
                    return (CGPoint(x: maxX, y: inset), CGPoint(x: maxX, y: midY))
                case .bottomLeft:
                    return (CGPoint(x: inset, y: midY), CGPoint(x: inset, y: maxY))
                case .bottomRight:
                    return (CGPoint(x: maxX, y: midY), CGPoint(x: maxX, y: maxY))
                }
            }

            func path(for positions: [SevenSegmentPosition], thickness: CGFloat) -> Path {
                var path = Path()
                for position in positions {
                    path.move(to: endpointPair(for: position, thickness: thickness).0)
                    path.addLine(to: endpointPair(for: position, thickness: thickness).1)
                }
                return path
            }

            let all = SevenSegmentPosition.allCases
            let unlit = all.filter { !mask.contains($0) }
            let lit = all.filter { mask.contains($0) }

            // Unlit segments: thinner stroke so the round caps do not union
            // into a filled tile, and faint enough to stay behind the digits.
            if let ghostColor, !unlit.isEmpty {
                let ghostThickness = size.height * HUDMetrics.ghostThicknessRatio
                context.stroke(
                    path(for: unlit, thickness: ghostThickness),
                    with: .color(ghostColor),
                    style: StrokeStyle(
                        lineWidth: ghostThickness,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            guard !lit.isEmpty else { return }
            let litPath = path(for: lit, thickness: thickness)

            // Glow pass: the same strokes, blurred and dimmed, drawn underneath.
            // This is what makes the digits read as emissive elements rather
            // than as printed white shapes. Kept to a small radius so it never
            // blooms into the surrounding panel.
            var glowContext = context
            glowContext.addFilter(.blur(radius: thickness * HUDMetrics.segmentGlowRadiusRatio))
            glowContext.opacity = HUDMetrics.segmentGlowOpacity
            glowContext.stroke(
                litPath,
                with: .color(HUDTheme.clockGlow),
                style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
            )

            // Crisp pass on top.
            var litContext = context
            if litShadow {
                litContext.addFilter(
                    .shadow(
                        color: .black.opacity(0.45),
                        radius: thickness * 0.30,
                        x: 0,
                        y: thickness * 0.22
                    )
                )
            }
            litContext.stroke(
                litPath,
                with: .color(color),
                style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

/// The colon between `HH`, `MM` and `SS`: two round dots.
struct SevenSegmentColonView: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let dot = geometry.size.height * HUDMetrics.segmentThicknessRatio * 0.95
            let x = geometry.size.width / 2

            Canvas { context, size in
                for fraction in [0.345, 0.655] {
                    let rect = CGRect(
                        x: x - dot / 2,
                        y: size.height * fraction - dot / 2,
                        width: dot,
                        height: dot
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}
