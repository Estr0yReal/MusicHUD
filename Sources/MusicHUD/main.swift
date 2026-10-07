import AppKit

// Music HUD boots through AppKit directly rather than the SwiftUI `App` lifecycle.
//
// Rationale: the entire UI is one borderless, non-activating NSPanel plus a
// status-bar menu. Every SwiftUI `Scene` would either create a stray window or
// fight the panel's window behaviour, so the AppKit bootstrap is both simpler
// and more predictable here. SwiftUI is still used for all of the content.
//
// `assumeIsolated` is accurate rather than a workaround: top-level code in
// `main.swift` runs synchronously on the main thread before the event loop
// starts, so the main actor's executor really is the current one.
MainActor.assumeIsolated {
    MusicHUDApp.run()
}
