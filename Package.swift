// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Timestamper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "timestamper", targets: ["Timestamper"])],
    targets: [
        .executableTarget(name: "Timestamper", path: "timestamper"),
        .testTarget(name: "TimestamperTests", dependencies: ["Timestamper"], path: "Tests")
    ]
)
