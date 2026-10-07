import AppKit
import Foundation
import MusicHUDCore
import ServiceManagement

/// Launch-at-login, backed by `SMAppService`.
///
/// WHAT THIS DELIBERATELY IS NOT
/// No `LSSharedFileList`, no `SMLoginItemSetEnabled`, no LaunchAgent plist, no
/// shell script, no crontab, no third-party helper. `SMAppService.mainApp` is
/// the supported modern API and is the only thing this type talks to.
///
/// WHY THE STATE IS NOT A BOOL IN USERDEFAULTS
/// The real state lives in macOS, and the user can change it at any time in
/// System Settings → General → Login Items without telling the app. A cached
/// bool would immediately be a lie. `status` is read from the system every time
/// it is asked for; `UserDefaults` only records the user's *intent* so the UI can
/// tell "never enabled" apart from "enabled but needing approval".
enum LaunchAtLogin {

    /// What the system says right now. The type lives in Core so the mapping
    /// from system state to switch position is testable without registering a
    /// real login item.
    typealias Status = LoginItemStatus

    /// Reads the live status from macOS.
    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .disabled
        }
    }

    /// Whether this system can register at all.
    static var isSupported: Bool { true }

    /// Registers the app to launch at login.
    ///
    /// Idempotent by design: registering an already-registered app is reported by
    /// macOS as `.enabled`, so this never creates a duplicate login item.
    @discardableResult
    static func enable() -> Status {
        // Never re-register something that is already registered — that is how
        // duplicate login items get created.
        switch status {
        case .enabled, .requiresApproval:
            return status
        case .disabled, .notFound, .failed:
            break
        }

        do {
            try SMAppService.mainApp.register()
        } catch {
            return .failed(error.localizedDescription)
        }
        return status
    }

    /// Unregisters the app.
    @discardableResult
    static func disable() -> Status {
        switch status {
        case .disabled:
            return .disabled        // already off; nothing to do
        case .enabled, .requiresApproval, .notFound, .failed:
            break
        }

        do {
            try SMAppService.mainApp.unregister()
        } catch {
            return .failed(error.localizedDescription)
        }
        return status
    }

    /// Sets the desired state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Status {
        enabled ? enable() : disable()
    }

    /// Opens System Settings → General → Login Items.
    ///
    /// `SMAppService.openSystemSettingsLoginItems()` is the supported entry
    /// point; the URL fallback exists only for macOS versions where the call is
    /// unavailable.
    static func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

