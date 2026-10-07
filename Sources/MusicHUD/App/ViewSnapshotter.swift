import AppKit

/// Renders the HUD's own view hierarchy to a PNG.
///
/// WHY THIS EXISTS
/// `screencapture` cannot be used to verify this app's appearance in every
/// environment. Without Screen Recording permission, macOS silently omits
/// *every other process's windows* from the capture: you get the wallpaper and
/// the menu bar and nothing else — including the window you are trying to
/// check. That is a permission artefact, not a rendering bug, and it is very
/// easy to misread as one.
///
/// Rendering the view hierarchy from inside the process sidesteps the problem
/// entirely and needs no permission at all. It is also the foundation for
/// automated visual regression checks from Phase 4 onward.
///
/// Triggered by setting `MUSICHUD_SNAPSHOT` to an output path:
///
///     MUSICHUD_SNAPSHOT=/tmp/hud.png ./MusicHUD.app/Contents/MacOS/MusicHUD
///
/// The app writes the PNG and exits. Intended for development and CI.
enum ViewSnapshotter {

    /// The output path from the environment, if snapshot mode is on.
    static var requestedOutputPath: String? {
        guard let path = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT"],
              !path.isEmpty
        else { return nil }
        return path
    }

    /// Optional second path, for the settings window.
    /// Where to write the Settings-window capture, or `nil` to skip it.
    ///
    /// Accepts either an explicit path or the flag `1` / `true`, in which case
    /// the path is derived from the HUD snapshot beside it.
    ///
    /// WHY THE FLAG FORM EXISTS
    /// This used to be path-only. Passing the obvious `MUSICHUD_SNAPSHOT_SETTINGS=1`
    /// therefore wrote the Settings view to a file literally named `1` in the
    /// working directory, while the file the caller asked for received the *HUD*
    /// capture — so a "settings" snapshot silently contained the HUD at HUD
    /// dimensions, and looked like the Settings window never opened at all.
    static var requestedSettingsPath: String? {
        guard let raw = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_SETTINGS"],
              !raw.isEmpty
        else { return nil }

        if raw == "1" || raw.lowercased() == "true" {
            guard let hud = requestedOutputPath else { return nil }
            return (hud as NSString).deletingPathExtension + "-settings.png"
        }
        return raw
    }

    /// Renders `view` and its subviews to PNG data.
    ///
    /// `cacheDisplay(in:to:)` is the AppKit path that works for layer-backed
    /// hierarchies such as `NSHostingView`. It draws the view tree itself, so
    /// SwiftUI content, text and the seven-segment `Canvas` all appear.
    ///
    /// The behind-window blur is the one thing it cannot reproduce — that is a
    /// window-server effect with no pixels of its own. So the snapshot paints a
    /// synthetic backdrop first: without it the card's translucent pixels would
    /// sit on transparency and the whole point of the design would be
    /// impossible to judge.
    @MainActor
    static func pngData(of view: NSView, backdrop: Bool = false) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }

        if backdrop {
            paintBackdrop(in: rep, bounds: bounds)
        }

        view.cacheDisplay(in: bounds, to: rep)

        return rep.representation(using: .png, properties: [:])
    }

    /// Stand-in for the desktop wallpaper, so translucency is visible in a
    /// snapshot. Deliberately not a flat grey: a gradient reads much more like
    /// a real wallpaper when judging whether the glass is too dark or too thin.
    @MainActor
    private static func paintBackdrop(in rep: NSBitmapImageRep, bounds: NSRect) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.24, green: 0.42, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.55, blue: 0.38, alpha: 1),
        ])
        gradient?.draw(in: bounds, angle: -55)
    }

    /// Writes a snapshot of `view` to `path`.
    ///
    /// Returns a human-readable result so the caller can print it to stderr.
    @MainActor
    @discardableResult
    static func writeSnapshot(of view: NSView, to path: String, backdrop: Bool = false) -> String {
        guard let data = pngData(of: view, backdrop: backdrop) else {
            return "snapshot failed: could not render \(view.bounds.size)"
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return "snapshot written: \(path) (\(data.count) bytes, \(Int(view.bounds.width))x\(Int(view.bounds.height)) pt)"
        } catch {
            return "snapshot failed: \(error.localizedDescription)"
        }
    }
}
