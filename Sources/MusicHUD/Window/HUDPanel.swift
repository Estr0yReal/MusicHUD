import AppKit
import MusicHUDCore

/// The HUD's window.
///
/// A borderless `NSPanel` rather than an `NSWindow`:
///
/// * `NSPanel` + `.nonactivatingPanel` lets the user click the transport
///   buttons without the HUD stealing focus from whatever they are doing.
/// * `canBecomeKey` is forced on, otherwise a borderless window can never
///   receive the clicks that make those buttons work at all.
/// * `canBecomeMain` stays off so the panel never becomes the app's main window.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
