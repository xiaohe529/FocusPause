// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusPause",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FocusPauseHelperShared",
            path: "Sources/FocusPauseHelperShared"
        ),
        .executableTarget(
            name: "FocusPauseHelper",
            dependencies: ["FocusPauseHelperShared"],
            path: "Sources/FocusPauseHelper"
        ),
        .executableTarget(
            name: "FocusPause",
            dependencies: ["FocusPauseHelperShared"],
            path: "Sources/FocusPause"
        )
    ]
)
