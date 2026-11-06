// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlateCore", platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "PlateCore", targets: ["PlateCore"]), .executable(name: "PlateLocal", targets: ["PlateLocal"])],
    targets: [
        .target(name: "PlateCore", path: "Sources/Shared/Domain"),
        .executableTarget(name: "PlateLocal", dependencies: ["PlateCore"], path: "Sources", exclude: ["Shared/Domain", "iOS", "Widgets"]),
        .testTarget(name: "PlateCaptureTests", dependencies: ["PlateLocal", "PlateCore"], path: "Tests/PlateCaptureTests"),
        .testTarget(name: "PlateCoreTests", dependencies: ["PlateCore"], path: "Tests/PlateCoreTests")
    ]
)
