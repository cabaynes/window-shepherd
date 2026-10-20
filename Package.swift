// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WindowShepherd",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WindowShepherdCore", targets: ["WindowShepherdCore"]),
    ],
    targets: [
        .target(
            name: "WindowShepherdCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "wsctl", dependencies: ["WindowShepherdCore"]),
        .executableTarget(name: "TestWindows", dependencies: ["WindowShepherdCore"]),
        .testTarget(name: "WindowShepherdCoreTests", dependencies: ["WindowShepherdCore"]),
    ]
)
