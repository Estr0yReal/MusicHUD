import AppKit
import MusicHUDCore
import SwiftUI

/// Owns the HUD panel: creation, sizing, layering, hosting the SwiftUI card,
/// and remembering where the user put it.
///
/// All window behaviour lives here so no SwiftUI view ever has to reach into
/// the window server directly.
@MainActor
final class HUDWindowController: NSWindowController {

    private let state: AppState
    private let panel: HUDPanel
    /// Layer-backed container that carries the card's rounded mask.
    private let container = NSView()

    init(state: AppState) {
        self.state = state

        let size = Self.initialSize(from: state.settings)
        let origin = Self.initialOrigin(for: size, settings: state.settings)

        self.panel = HUDPanel(
            contentRect: NSRect(origin: origin, size: size),
            // `.nonactivatingPanel` lets the transport buttons work without
            // pulling focus away from the user's current app. `.resizable` is
            // included as a best-effort native resize; the visible corner grip
            // in `ResizeGrip` is what actually guarantees resizing, because
            // AppKit does not reliably give borderless windows edge-drag.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        WindowBehavior.applyInvariants(to: panel)
        WindowBehavior.apply(levelMode: state.settings.windowLevelMode, to: panel)

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(
            width: HUDSettings.minimumSize.width,
            height: HUDSettings.minimumSize.height
        )
        panel.maxSize = NSSize(
            width: HUDSettings.maximumSize.width,
            height: HUDSettings.maximumSize.height
        )

        buildContentView()

        state.windowBridge.window = panel
        state.applyHandler = { [weak self] settings in
            self?.apply(settings)
        }
        state.resetPositionHandler = { [weak self] in
            self?.resetPosition()
        }
        apply(state.settings)

        // Remember where the user leaves the panel.
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HUDWindowController is created in code only")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Content

    private func buildContentView() {
        // The container exists purely to mask the card's rounded corners at the
        // window-server level. Without it the vibrancy layer renders square
        // corners and the HUD looks like a rectangle with cut-off blur.
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let hosting = NSHostingView(rootView: HUDView(app: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container
    }

    // MARK: - Settings

    /// Pushes every window-affecting setting onto the live panel.
    func apply(_ settings: HUDSettings) {
        panel.alphaValue = CGFloat(settings.windowOpacity)
        // Click-through is a toggle rather than a permanent state precisely so
        // the transport buttons remain reachable: the status-bar menu can
        // always turn it back off.
        panel.ignoresMouseEvents = settings.clickThrough
        WindowBehavior.apply(levelMode: settings.windowLevelMode, to: panel)

        let radius = CGFloat(settings.cornerRadius)
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = radius > 0.5
    }

    // MARK: - Visibility

    func showHUD() {
        panel.orderFrontRegardless()
    }

    func hideHUD() {
        panel.orderOut(nil)
    }

    func toggleVisibility() {
        if panel.isVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// Moves the panel back to its default corner on the preferred screen.
    func resetPosition() {
        let origin = WindowBehavior.defaultOrigin(
            for: panel.frame.size,
            on: WindowBehavior.preferredScreen()
        )
        panel.setFrameOrigin(origin)
        state.persistWindowFrame()
    }

    /// Used by the status-bar menu when click-through mode is active: the user
    /// cannot click the panel, so we nudge it to a visible spot.
    func bringToFrontWithoutActivating() {
        panel.orderFrontRegardless()
    }

    // MARK: - Notifications

    @objc private func windowDidChangeFrame(_ note: Notification) {
        state.persistWindowFrame()
    }

    // MARK: - Initial geometry

    /// Snapshot-only size override (`MUSICHUD_SNAPSHOT_WINDOW_SIZE=240x348`).
    ///
    /// Test instrumentation, inert unless the variable is set. The brief asks
    /// for minimum- and maximum-size snapshots, and neither is reachable by
    /// dragging during an automated capture.
    private static func snapshotSizeOverride() -> NSSize? {
        guard let raw = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_WINDOW_SIZE"] else {
            return nil
        }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    private static func initialSize(from settings: HUDSettings) -> NSSize {
        if let override = snapshotSizeOverride() { return override }
        guard settings.rememberWindowFrame, let frame = settings.windowFrame else {
            return NSSize(width: HUDSettings.defaultFrame.width, height: HUDSettings.defaultFrame.height)
        }
        return NSSize(width: frame.width, height: frame.height)
    }

    private static func initialOrigin(for size: NSSize, settings: HUDSettings) -> NSPoint {
        if settings.rememberWindowFrame, let frame = settings.windowFrame,
           frame.x != 0 || frame.y != 0 {
            let restored = NSRect(x: frame.x, y: frame.y, width: size.width, height: size.height)
            return WindowBehavior.clampedToVisibleScreen(restored).origin
        }
        return WindowBehavior.defaultOrigin(for: size, on: WindowBehavior.preferredScreen())
    }
}
