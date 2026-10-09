// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LevelUpKit",
    defaultLocalization: "ru",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LevelUpKit", targets: ["LevelUpKit"]),
    ],
    targets: [
        .target(name: "LevelUpKit"),
        .testTarget(name: "LevelUpKitTests", dependencies: ["LevelUpKit"]),
    ]
)
