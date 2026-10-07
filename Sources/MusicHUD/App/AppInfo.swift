import Foundation

/// Version and build identity, read from the bundle rather than hardcoded.
///
/// WHY THIS EXISTS
/// The status menu previously displayed the literal string
/// `阶段：Phase 1 · 静态 UI 原型`, which was written during Phase 1 and never
/// revisited — it was still claiming Phase 1 six phases later. Reading the real
/// version makes that class of staleness impossible.
enum AppInfo {

    /// `CFBundleShortVersionString`, or `"dev"` when running unbundled.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// `CFBundleVersion`, or `nil` when running unbundled.
    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// `"1.0 (7)"`, or `"dev"` outside a bundle.
    static var displayVersion: String {
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
