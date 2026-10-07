import Foundation

/// Maps an arbitrary-length band array onto the number of bars being drawn.
///
/// The DSP produces a fixed number of log-spaced bands; the renderer may be
/// asked for a different bar count. This is the only piece that survives from
/// Phase 1's placeholder helper — the placeholder envelope itself was deleted
/// once real FFT data existed, because a synthetic spectrum that looks plausible
/// is exactly what the brief forbids.
public enum SpectrumBands {

    /// Linear resample from `input.count` bands to `count` bars.
    public static func resample(_ input: [Float], to count: Int) -> [Double] {
        guard count > 0, !input.isEmpty else { return [] }
        if input.count == count { return input.map(Double.init) }
        if input.count == 1 { return Array(repeating: Double(input[0]), count: count) }

        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1) * Double(input.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, input.count - 1)
            let fraction = position - Double(lower)
            let value = Double(input[lower]) * (1 - fraction) + Double(input[upper]) * fraction
            return min(max(value, 0), 1)
        }
    }
}
