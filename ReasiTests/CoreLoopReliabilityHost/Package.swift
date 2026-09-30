// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreLoopReliabilityHost",
    platforms: [.macOS(.v14)],
    targets: [.testTarget(name: "CoreLoopReliabilityTests", swiftSettings: [.define("CORE_LOOP_HOST_TESTS")])],
    swiftLanguageModes: [.v5]
)
