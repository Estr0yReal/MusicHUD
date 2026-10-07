import Foundation

/// What macOS reports about the app's login item.
///
/// Lives in Core, separate from the `SMAppService` calls, because the mapping
/// from system state to switch position is the part that can be wrong in a way
/// the user would notice — and the only part testable without actually
/// registering a real login item.
public enum LoginItemStatus: Equatable, Sendable {

    /// Registered and will run at login.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but macOS requires the user to approve it in System Settings.
    case requiresApproval
    /// The app is not somewhere `SMAppService` can register it.
    case notFound
    /// The system refused the operation, with a description.
    case failed(String)

    /// Whether the toggle should read as on.
    ///
    /// `requiresApproval` counts as **on**: the registration was accepted and
    /// macOS is merely waiting for the user. Flipping the switch back to off
    /// would misreport what actually happened.
    public var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .disabled, .notFound, .failed: return false
        }
    }

    /// Whether the user still has something to do in System Settings.
    public var needsUserAction: Bool {
        switch self {
        case .requiresApproval, .notFound: return true
        case .enabled, .disabled, .failed: return false
        }
    }

    /// The localisation key describing this state.
    public var localizationKey: String {
        switch self {
        case .enabled: return "settings.launchAtLogin.registered"
        case .disabled: return "settings.launchAtLogin.notRegistered"
        case .requiresApproval: return "settings.launchAtLogin.requiresApproval"
        case .notFound: return "settings.launchAtLogin.notFound"
        case .failed: return "settings.launchAtLogin.failed"
        }
    }
}
