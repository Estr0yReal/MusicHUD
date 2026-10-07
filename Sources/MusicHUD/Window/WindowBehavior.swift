import AppKit
import MusicHUDCore

/// Everything about how the panel sits relative to the desktop.
///
/// This is isolated from the controller so the layering rules can be reasoned
/// about (and changed) in one place.
enum WindowBehavior {

    /// Applies the window level and Space behaviour implied by `mode`.
    ///
    /// See `WindowLevelMode` for what each mode actually means and where its
    /// limits are. In short:
    ///
    /// * `.normal`   — `NSWindow.Level.normal`. Stacks with other apps.
    /// * `.floating` — `NSWindow.Level.floating`. This is the reliable
    ///                 "always on top" and the recommended mode.
    /// * `.desktop`  — one level above `CGWindowLevelForKey(.desktopWindow)`,
    ///                 i.e. above the wallpaper but below the desktop icons.
    ///                 Public API, but the Finder's desktop window still sits
    ///                 above it, so clicks may not arrive. Experimental.
    static func apply(levelMode mode: WindowLevelMode, to window: NSWindow) {
        switch mode {
        case .normal:
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        case .floating:
            window.level = .floating
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]

        case .desktop:
            let desktopLevel = CGWindowLevelForKey(.desktopWindow)
            window.level = NSWindow.Level(rawValue: Int(desktopLevel) + 1)
            window.collectionBehavior = [
                .stationary,
                .canJoinAllSpaces,
                .ignoresCycle,
            ]
        }
    }

    /// Configures the invariants that never change: no frame, no background,
    /// no window-server shadow artefacts, no implicit animations.
    static func applyInvariants(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false   // dragging is driven by SwiftUI
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none             // avoid resize flicker
        window.tabbingMode = .disallowed
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
    }

    /// The screen a first-run (or reset) HUD should appear on.
    ///
    /// Deliberately *not* `NSScreen.main`. That property follows keyboard focus,
    /// so on a machine with a virtual or secondary display attached it can
    /// return a screen the user cannot actually see — which is exactly what
    /// happened during development, where the panel opened on an off-screen
    /// virtual display. `NSScreen.screens.first` is the primary display, the
    /// one with the menu bar, and is the predictable choice.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    /// Picks a sensible first-run position: top-right of the preferred screen,
    /// inset from the menu bar and the screen edge.
    static func defaultOrigin(for size: CGSize, on screen: NSScreen?) -> NSPoint {
        guard let visible = (screen ?? preferredScreen())?.visibleFrame else {
            return NSPoint(x: 120, y: 120)
        }
        return NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        )
    }

    /// Clamps a stored frame back onto a currently-connected screen.
    ///
    /// Without this, a window remembered on a display that is no longer
    /// attached would be restored somewhere the user cannot reach.
    static func clampedToVisibleScreen(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }

        let isVisibleSomewhere = screens.contains { screen in
            screen.visibleFrame.intersects(frame.insetBy(dx: -8, dy: -8))
        }
        guard !isVisibleSomewhere else { return frame }

        let size = frame.size
        let origin = defaultOrigin(for: size, on: preferredScreen())
        return NSRect(origin: origin, size: size)
    }
}
