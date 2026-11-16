// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "UltraShotKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "UltraShotCore", targets: ["UltraShotCore"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "AnnotateKit", targets: ["AnnotateKit"]),
        .library(name: "RecordingKit", targets: ["RecordingKit"]),
    ],
    targets: [
        .target(name: "UltraShotCore", swiftSettings: swiftSettings),
        .target(name: "CaptureKit", swiftSettings: swiftSettings),
        .target(name: "AnnotateKit", swiftSettings: swiftSettings),
        .target(name: "RecordingKit", swiftSettings: swiftSettings),
        .testTarget(name: "UltraShotCoreTests", dependencies: ["UltraShotCore"], swiftSettings: swiftSettings),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"], swiftSettings: swiftSettings),
        .testTarget(name: "AnnotateKitTests", dependencies: ["AnnotateKit"], swiftSettings: swiftSettings),
        .testTarget(name: "RecordingKitTests", dependencies: ["RecordingKit"], swiftSettings: swiftSettings),
    ],
    swiftLanguageModes: [.v6]
)
