import AppKit
import MusicHUDCore
import SwiftUI

/// A behind-window blur, i.e. a real frosted-glass panel.
///
/// `blendingMode = .behindWindow` is the important part: it blurs what is
/// *behind the window* (the desktop wallpaper and any windows underneath),
/// which is what makes the HUD sit on the desktop instead of on top of it.
///
/// The view is pinned to the vibrancy-dark appearance so the material does not
/// flip to a light tint when the system is in light mode.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        // `.active` keeps the blur applied even when the app is not frontmost,
        // which is the normal state for a desktop HUD.
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
    }
}
