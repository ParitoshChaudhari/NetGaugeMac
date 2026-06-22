// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetGaugeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NetGaugeMac", targets: ["NetGaugeMac"])
    ],
    targets: [
        .executableTarget(
            name: "NetGaugeMac",
            resources: [
                .process("AppIcon.png")   // logo bundled with the app
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
