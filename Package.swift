// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HandySwift",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "HandySwift",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .testTarget(name: "HandySwiftTests", dependencies: ["HandySwift"]),
    ]
)
