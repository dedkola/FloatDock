// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FloatDock",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FloatDockCore", targets: ["FloatDockCore"]),
        .executable(name: "FloatDockApp", targets: ["FloatDockApp"]),
    ],
    targets: [
        .target(name: "FloatDockCore"),
        .executableTarget(name: "FloatDockApp", dependencies: ["FloatDockCore"]),
        .testTarget(name: "FloatDockCoreTests", dependencies: ["FloatDockCore"]),
    ],
    swiftLanguageModes: [.v6]
)
