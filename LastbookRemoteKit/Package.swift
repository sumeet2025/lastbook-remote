// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LastbookRemoteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LastbookRemoteKit", targets: ["LastbookRemoteKit"]),
    ],
    targets: [
        .target(name: "LastbookRemoteKit"),
        .testTarget(name: "LastbookRemoteKitTests", dependencies: ["LastbookRemoteKit"]),
    ]
)
