import Foundation

/// A plain colour triplet. The logic target stays free of CoreGraphics/SwiftUI.
public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// A procedural stand-in for album artwork.
///
/// PHASE 1 ONLY. This is generated from a seed so the prototype has something
/// artwork-shaped to lay out. Phase 2 replaces it with real Apple Music
/// artwork data; until then the UI labels its source as demo data.
public struct ArtworkPalette: Equatable, Sendable {
    public enum Motif: Int, Equatable, Sendable {
        /// Soft concentric rings.
        case rings
        /// Layered horizontal waves.
        case waves
        /// A sparse technical grid.
        case grid
    }

    public var top: RGB
    public var bottom: RGB
    public var accent: RGB
    public var motif: Motif

    public init(top: RGB, bottom: RGB, accent: RGB, motif: Motif) {
        self.top = top
        self.bottom = bottom
        self.accent = accent
        self.motif = motif
    }
}

public enum ArtworkPaletteLibrary {
    /// Deliberately dark and desaturated so the artwork never fights the HUD text.
    public static let palettes: [ArtworkPalette] = [
        ArtworkPalette(
            top: RGB(0.16, 0.19, 0.34),
            bottom: RGB(0.07, 0.09, 0.16),
            accent: RGB(0.45, 0.55, 0.95),
            motif: .rings
        ),
        ArtworkPalette(
            top: RGB(0.26, 0.15, 0.22),
            bottom: RGB(0.10, 0.07, 0.12),
            accent: RGB(0.95, 0.52, 0.55),
            motif: .waves
        ),
        ArtworkPalette(
            top: RGB(0.10, 0.24, 0.24),
            bottom: RGB(0.05, 0.11, 0.12),
            accent: RGB(0.42, 0.85, 0.78),
            motif: .grid
        ),
    ]

    /// Deterministic palette for a seed. Negative seeds are handled.
    public static func palette(forSeed seed: Int) -> ArtworkPalette {
        guard !palettes.isEmpty else {
            return ArtworkPalette(
                top: RGB(0.15, 0.15, 0.18),
                bottom: RGB(0.06, 0.06, 0.08),
                accent: RGB(0.6, 0.6, 0.65),
                motif: .rings
            )
        }
        let count = palettes.count
        let index = ((seed % count) + count) % count
        return palettes[index]
    }
}
