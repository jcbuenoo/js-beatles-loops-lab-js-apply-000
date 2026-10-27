// swift-tools-version:5.9
import PackageDescription

// PauseCore is plain Foundation (models, rules, reports) so it builds and tests anywhere.
// The Pause app target uses AppKit/SwiftUI and only builds on macOS.
var targets: [Target] = [
    .target(name: "PauseCore"),
    .testTarget(name: "PauseCoreTests", dependencies: ["PauseCore"]),
]

#if os(macOS)
targets.append(.executableTarget(name: "Pause", dependencies: ["PauseCore"]))
#endif

let package = Package(
    name: "Pause",
    platforms: [.macOS(.v13)],
    targets: targets
)
