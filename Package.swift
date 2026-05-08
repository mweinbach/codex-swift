// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "codex-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "codex", targets: ["codex"]),
        .executable(name: "apply_patch", targets: ["apply_patch"]),
        .library(name: "CodexApplyPatch", targets: ["CodexApplyPatch"]),
        .library(name: "CodexCLI", targets: ["CodexCLI"]),
        .library(name: "CodexCore", targets: ["CodexCore"])
    ],
    targets: [
        .target(name: "CodexCore"),
        .target(name: "CodexApplyPatch"),
        .target(
            name: "CodexCLI",
            dependencies: ["CodexCore"]
        ),
        .executableTarget(
            name: "apply_patch",
            dependencies: ["CodexApplyPatch"]
        ),
        .executableTarget(
            name: "codex",
            dependencies: ["CodexCLI"]
        ),
        .testTarget(
            name: "CodexApplyPatchTests",
            dependencies: ["CodexApplyPatch"]
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
