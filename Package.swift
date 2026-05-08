// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "codex-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "codex", targets: ["codex"]),
        .library(name: "CodexCLI", targets: ["CodexCLI"]),
        .library(name: "CodexCore", targets: ["CodexCore"])
    ],
    targets: [
        .target(name: "CodexCore"),
        .target(
            name: "CodexCLI",
            dependencies: ["CodexCore"]
        ),
        .executableTarget(
            name: "codex",
            dependencies: ["CodexCLI"]
        ),
        .testTarget(
            name: "CodexCoreTests",
            dependencies: ["CodexCore"]
        ),
        .testTarget(
            name: "CodexCLITests",
            dependencies: ["CodexCLI"]
        )
    ]
)
