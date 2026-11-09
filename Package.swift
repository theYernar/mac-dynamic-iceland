// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"])
    ],
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            path: "Sources/DynamicIsland",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland"],
            path: "Tests/DynamicIslandTests"
        )
    ]
)

