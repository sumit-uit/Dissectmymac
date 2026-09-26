// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DissectMyMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DissectCore", targets: ["DissectCore"]),
        .executable(name: "DissectMyMac", targets: ["DissectMyMac"]),
    ],
    targets: [
        // All scanning, cleaning, licensing and system logic. No UI, fully unit-tested.
        .target(name: "DissectCore"),
        // SwiftUI app. `swift run DissectMyMac` for quick iteration; use project.yml (XcodeGen)
        // to produce a signed, notarizable .app bundle.
        .executableTarget(name: "DissectMyMac", dependencies: ["DissectCore"]),
        .testTarget(name: "DissectCoreTests", dependencies: ["DissectCore"]),
    ]
)
