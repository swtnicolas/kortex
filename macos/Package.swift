// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kortex",
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "SMCKit", path: "Sources/SMCKit"),
        .executableTarget(name: "Kortex", dependencies: ["SMCKit"], path: "Sources/Kortex"),
        .executableTarget(name: "KortexFans", dependencies: ["SMCKit"], path: "Sources/KortexFans"),
        .testTarget(name: "KortexTests", dependencies: ["Kortex"], path: "Tests/KortexTests")
    ]
)
