// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Screenroom",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Screenroom", targets: ["Screenroom"])
    ],
    targets: [
        .executableTarget(
            name: "Screenroom",
            path: "Sources/Screenroom"
        ),
        .testTarget(
            name: "ScreenroomTests",
            dependencies: ["Screenroom"],
            path: "Tests/ScreenroomTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
