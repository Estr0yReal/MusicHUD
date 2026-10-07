// swift-tools-version: 6.0
//
//  Music HUD — a translucent desktop music HUD for macOS.
//
//  Target layout:
//    MusicHUDCore  — pure logic (models, settings, segment tables, metrics). No UI, no AppKit.
//    MusicHUD      — the AppKit/SwiftUI application (executable).
//    MusicHUDCoreTests — unit tests for the logic layer.
//
//  NOTE ON SWIFT LANGUAGE MODE
//  Both targets compile in Swift 5 language mode. Strict Swift 6 concurrency is not
//  useful for a single-threaded main-actor UI shell and would only add noise here.
//  This is a deliberate choice, not an oversight.

import PackageDescription

let package = Package(
    name: "MusicHUD",
    // Required for SwiftPM to treat the app target's .lproj directories as
    // localisations. `en` is the development language.
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MusicHUD", targets: ["MusicHUD"]),
        .library(name: "MusicHUDCore", targets: ["MusicHUDCore"]),
    ],
    targets: [
        .target(
            name: "MusicHUDCore",
            path: "Sources/MusicHUDCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MusicHUD",
            dependencies: ["MusicHUDCore"],
            path: "Sources/MusicHUD",
            // Localisation lives here. SwiftPM copies .lproj directories into a
            // resource bundle, which is what `Bundle.module` resolves.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MusicHUDCoreTests",
            dependencies: ["MusicHUDCore"],
            path: "Tests/MusicHUDCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
