// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CPAPSyncCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "CPAPSyncCore", targets: ["CPAPSyncCore"])],
    targets: [
        .target(name: "CPAPSyncCore"),
        .testTarget(name: "CPAPSyncCoreTests", dependencies: ["CPAPSyncCore"])
    ]
)
