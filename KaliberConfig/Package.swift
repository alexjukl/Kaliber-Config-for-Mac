// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KaliberConfig",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KaliberHID", targets: ["KaliberHID"]),
        .executable(name: "KaliberConfig", targets: ["KaliberConfig"]),
    ],
    targets: [
        .target(name: "KaliberHID", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "KaliberConfig", dependencies: ["KaliberHID"]),
        .testTarget(name: "KaliberHIDTests", dependencies: ["KaliberHID"], resources: [.copy("Fixtures")]),
    ]
)
