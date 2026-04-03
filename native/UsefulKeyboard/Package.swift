// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsefulKeyboard",
    platforms: [
        .macOS("14.2"),
    ],
    products: [
        .library(name: "UsefulKeyboardCore", targets: ["UsefulKeyboardCore"]),
        .executable(name: "UsefulKeyboardApp", targets: ["UsefulKeyboardApp"]),
        .executable(name: "useful-keyboard-cli", targets: ["UsefulKeyboardCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.2"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "UsefulKeyboardCore",
            dependencies: [],
            path: "Sources/UsefulKeyboardCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "UsefulKeyboardApp",
            dependencies: [
                "UsefulKeyboardCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            path: "Sources/UsefulKeyboardApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "UsefulKeyboardCLI",
            dependencies: [
                "UsefulKeyboardCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/UsefulKeyboardCLI"
        ),
        .testTarget(
            name: "UsefulKeyboardTests",
            dependencies: ["UsefulKeyboardApp", "UsefulKeyboardCore", "UsefulKeyboardCLI"],
            path: "Tests/UsefulKeyboardTests",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
