import Foundation

/// Persists `HUDSettings` as JSON in `UserDefaults`.
///
/// The `UserDefaults` instance is injectable so tests can use a throwaway suite.
public struct HUDSettingsStore {
    private static let key = "MusicHUD.settings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads stored settings, falling back to defaults for anything missing or corrupt.
    public func load() -> HUDSettings {
        guard
            let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode(HUDSettings.self, from: data)
        else {
            return HUDSettings()
        }
        return decoded.sanitized()
    }

    /// Saves settings. Failures are non-fatal: the app keeps running with defaults.
    @discardableResult
    public func save(_ settings: HUDSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}

public extension HUDSettings {
    /// Clamps every value into its legal range.
    ///
    /// Applied on load so a hand-edited or stale defaults blob can never put the
    /// UI into an unrenderable state.
    func sanitized() -> HUDSettings {
        var s = self
        s.windowOpacity = s.windowOpacity.clamped(to: 0.15...1.0)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...44)
        s.blurStrength = s.blurStrength.clamped(to: 0...1)
        s.panelTint = s.panelTint.clamped(to: 0...0.85)
        s.clockScale = s.clockScale.clamped(to: 0.6...1.4)
        s.spectrumBarCount = Int(Double(s.spectrumBarCount).clamped(to: 16...96))
        s.spectrumFFTSize = SpectrumSettings.allowedFFTSizes.contains(s.spectrumFFTSize) ? s.spectrumFFTSize : 2048
        s.spectrumSensitivityDecibels = s.spectrumSensitivityDecibels.clamped(to: -20...20)
        s.spectrumNoiseFloorDecibels = s.spectrumNoiseFloorDecibels.clamped(to: -110 ... -30)
        s.spectrumSmoothing = s.spectrumSmoothing.clamped(to: 0...1)
        s.spectrumFrameRate = Int(Double(s.spectrumFrameRate).clamped(to: 15...120))
        s.metadataPollInterval = s.metadataPollInterval.clamped(to: 0.5...10)
        if TimeZone(identifier: s.timeZoneIdentifier) == nil {
            s.timeZoneIdentifier = TimeZone.current.identifier
        }
        if let frame = s.windowFrame {
            s.windowFrame = WindowFrame(
                x: frame.x,
                y: frame.y,
                width: frame.width.clamped(to: HUDSettings.minimumSize.width...HUDSettings.maximumSize.width),
                height: frame.height.clamped(to: HUDSettings.minimumSize.height...HUDSettings.maximumSize.height)
            )
        }
        return s
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
