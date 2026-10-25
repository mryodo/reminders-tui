// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Remind",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Remind", path: "Sources", resources: [.copy("Fonts")]),
        .testTarget(name: "RemindTests", dependencies: ["Remind"], path: "Tests"),
    ]
)
