import AppKit

/// Process bootstrap.
enum MusicHUDApp {
    /// Configures `NSApplication` and runs the main event loop. Never returns.
    @MainActor
    static func run() -> Never {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // `.accessory` means: no Dock icon, no app-switcher entry. The HUD lives
        // on the desktop; the status-bar menu is how you get back to it and how
        // you quit. This is what keeps the component feeling like a desktop
        // ornament instead of an application window.
        app.setActivationPolicy(.accessory)

        app.run()
        exit(0)
    }
}
