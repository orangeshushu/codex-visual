// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CodexVisual",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexVisual", targets: ["CodexVisual"])
    ],
    targets: [
        .executableTarget(
            name: "CodexVisual"
        )
    ]
)
