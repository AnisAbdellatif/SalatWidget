// swift-tools-version: 6.0
import Foundation
import PackageDescription

let mawaKitPath = ProcessInfo.processInfo.environment["MAWAKIT_PATH"] ?? "../../MawaKit"

let package = Package(
    name: "SalatWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SalatWidget", targets: ["SalatWidget"]),
        .library(name: "SalatCore", targets: ["SalatCore"]),
    ],
    dependencies: [
        // The shared prayer-time core. Until it's published, it is the MawaKit git
        // submodule at the repo root; set MAWAKIT_PATH to use another checkout.
        .package(path: mawaKitPath),
    ],
    targets: [
        // Swift-side core: Apple networking and caching, plus a Swift-friendly layer over
        // MawaKit (the Rust prayer-time core).
        .target(name: "SalatCore", dependencies: [.product(name: "MawaKit", package: "MawaKit")]),

        // The menu bar app (SwiftUI + AppKit glue).
        .executableTarget(
            name: "SalatWidget",
            dependencies: ["SalatCore"],
            linkerSettings: [
                // Embed Info.plist so `swift run` gets a bundle identifier too.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ]),
            ]
        ),

        .testTarget(
            name: "SalatCoreTests",
            dependencies: ["SalatCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
