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
        .library(name: "CodexChatGPT", targets: ["CodexChatGPT"]),
        .library(name: "CodexCLI", targets: ["CodexCLI"]),
        .library(name: "CodexCore", targets: ["CodexCore"]),
        .library(name: "CodexGit", targets: ["CodexGit"]),
        .library(name: "CodexStdioToUDS", targets: ["CodexStdioToUDS"]),
        .executable(name: "codex-stdio-to-uds", targets: ["codex-stdio-to-uds"])
    ],
    targets: [
        .target(name: "CodexCore"),
        .target(name: "CodexApplyPatch"),
        .target(name: "CodexGit"),
        .target(
            name: "CodexChatGPT",
            dependencies: ["CodexCore", "CodexGit"]
        ),
        .target(
            name: "CodexCLI",
            dependencies: ["CodexCore"]
        ),
        .target(name: "CodexStdioToUDS"),
        .executableTarget(
            name: "apply_patch",
            dependencies: ["CodexApplyPatch"]
        ),
        .executableTarget(
            name: "codex-stdio-to-uds",
            dependencies: ["CodexStdioToUDS"]
        ),
        .executableTarget(
            name: "codex",
            dependencies: ["CodexChatGPT", "CodexCLI", "CodexCore", "CodexStdioToUDS"]
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
            name: "CodexGitTests",
            dependencies: ["CodexGit"]
        ),
        .testTarget(
            name: "CodexChatGPTTests",
            dependencies: ["CodexChatGPT", "CodexGit"]
        ),
        .testTarget(
            name: "CodexCLITests",
            dependencies: ["CodexCLI"]
        ),
        .testTarget(
            name: "CodexStdioToUDSTests",
            dependencies: ["CodexStdioToUDS"]
        )
    ]
)
