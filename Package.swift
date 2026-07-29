// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetGaugeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NetGaugeMac", targets: ["NetGaugeMac"]),
        .executable(name: "NetGaugeMacTestRunner", targets: ["NetGaugeMacTestRunner"])
    ],
    targets: [
        .executableTarget(
            name: "NetGaugeMac",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NetGaugeMacTestRunner",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation")
            ]
        )
    ]
)
