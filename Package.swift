// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeStamper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "timestamper", targets: ["TimeStamper"])],
    targets: [
        .executableTarget(name: "TimeStamper", path: "timestamper"),
        .testTarget(name: "TimeStamperTests", dependencies: ["TimeStamper"], path: "Tests")
    ]
)
