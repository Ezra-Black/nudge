// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nudge", targets: ["Nudge"])
    ],
    targets: [
        .executableTarget(
            name: "Nudge",
            exclude: ["Brand/README.md"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(
            name: "NudgeTests",
            dependencies: ["Nudge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
