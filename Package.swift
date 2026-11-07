// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "ytd",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(name: "ytd", path: "Sources/YtdApp"),
    .testTarget(name: "ytdTests", dependencies: ["ytd"], path: "Tests/ytdTests")
  ]
)
