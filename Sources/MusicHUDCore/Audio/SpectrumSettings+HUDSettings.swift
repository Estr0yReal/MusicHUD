import Foundation

public extension SpectrumSettings {
    /// Builds DSP settings from the user's HUD settings.
    ///
    /// One mapping, in one place: the settings panel, the diagnostics panel and
    /// the analyser all read the same values, so nothing can silently diverge.
    ///
    /// `spectrumSmoothing` is a single 0…1 slider that scales the release
    /// coefficient. Attack stays fast on purpose — a slow attack would soften
    /// drum transients, which is the one thing the spectrum must not do.
    init(hud: HUDSettings) {
        self.init()
        fftSize = hud.spectrumFFTSize
        hopSize = max(hud.spectrumFFTSize / 4, 1)   // 75% overlap
        bandCount = hud.spectrumBarCount
        sensitivityDecibels = Float(hud.spectrumSensitivityDecibels)
        noiseFloorDecibels = Float(hud.spectrumNoiseFloorDecibels)
        release = Float(0.06 + hud.spectrumSmoothing * 0.20)
    }
}
