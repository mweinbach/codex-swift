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
        .executable(name: "codex-responses-api-proxy", targets: ["codex-responses-api-proxy"]),
        .library(name: "CodexApplyPatch", targets: ["CodexApplyPatch"]),
        .library(name: "CodexAppServer", targets: ["CodexAppServer"]),
        .library(name: "CodexChatGPT", targets: ["CodexChatGPT"]),
        .library(name: "CodexCLI", targets: ["CodexCLI"]),
        .library(name: "CodexCore", targets: ["CodexCore"]),
        .library(name: "CodexMCPServer", targets: ["CodexMCPServer"]),
        .library(name: "CodexGit", targets: ["CodexGit"]),
        .library(name: "CodexResponsesAPIProxy", targets: ["CodexResponsesAPIProxy"]),
        .library(name: "CodexStdioToUDS", targets: ["CodexStdioToUDS"]),
        .executable(name: "codex-stdio-to-uds", targets: ["codex-stdio-to-uds"])
    ],
    targets: [
        .target(
            name: "CodexCore",
            dependencies: ["CodexApplyPatch"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "CodexApplyPatch",
            resources: [.process("Resources")]
        ),
        .target(name: "CodexGit"),
        .target(
            name: "CodexChatGPT",
            dependencies: ["CodexCore", "CodexGit"]
        ),
        .target(
            name: "CodexAppServer",
            dependencies: ["CodexCore"]
        ),
        .target(
            name: "CodexCLI",
            dependencies: ["CodexCore"]
        ),
        .target(
            name: "CodexMCPServer",
            dependencies: ["CodexCore"]
        ),
        .target(name: "CodexResponsesAPIProxy"),
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
            name: "codex-responses-api-proxy",
            dependencies: ["CodexCore", "CodexResponsesAPIProxy"]
        ),
        .executableTarget(
            name: "codex",
            dependencies: ["CodexAppServer", "CodexApplyPatch", "CodexChatGPT", "CodexCLI", "CodexCore", "CodexMCPServer", "CodexResponsesAPIProxy", "CodexStdioToUDS"]
        ),
        .testTarget(
            name: "CodexApplyPatchTests",
            dependencies: ["CodexApplyPatch"]
        ),
        .testTarget(
            name: "CodexAppServerTests",
            dependencies: ["CodexAppServer", "CodexCore"]
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
            name: "CodexMCPServerTests",
            dependencies: ["CodexMCPServer"]
        ),
        .testTarget(
            name: "CodexResponsesAPIProxyTests",
            dependencies: ["CodexResponsesAPIProxy"]
        ),
        .testTarget(
            name: "CodexStdioToUDSTests",
            dependencies: ["CodexStdioToUDS"]
        )
    ]
)
