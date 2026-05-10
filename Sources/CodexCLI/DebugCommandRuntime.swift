import CodexCore
import Foundation

public enum DebugCommandRuntime {
    public struct Dependencies {
        public var findCodexHome: () throws -> URL
        public var loadConfig: (URL, CliConfigOverrides) throws -> CodexRuntimeConfig
        public var makeStateStore: (URL, String) throws -> SQLiteAgentGraphStore

        public init(
            findCodexHome: @escaping () throws -> URL = { try CodexHome.find() },
            loadConfig: @escaping (URL, CliConfigOverrides) throws -> CodexRuntimeConfig = { codexHome, overrides in
                try CodexConfigLoader.load(
                    codexHome: codexHome,
                    cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
                    overrides: overrides
                )
            },
            makeStateStore: @escaping (URL, String) throws -> SQLiteAgentGraphStore = { databaseURL, modelProvider in
                try SQLiteAgentGraphStore(databaseURL: databaseURL, defaultProvider: modelProvider)
            }
        ) {
            self.findCodexHome = findCodexHome
            self.loadConfig = loadConfig
            self.makeStateStore = makeStateStore
        }
    }

    public static func run(
        _ request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies = Dependencies()
    ) async throws -> CodexCLI.CommandExecutionResult {
        switch request.action {
        case let .models(bundled):
            return try runModels(bundled: bundled)
        case .appServerSendMessageV2:
            return pendingRuntime("debug app-server send-message-v2")
        case .promptInput:
            return pendingRuntime("debug prompt-input")
        case .traceReduce:
            return pendingRuntime("debug trace-reduce")
        case .clearMemories:
            return try await runClearMemories(request: request, dependencies: dependencies)
        }
    }

    private static func runModels(bundled: Bool) throws -> CodexCLI.CommandExecutionResult {
        guard bundled else {
            return pendingRuntime("debug models")
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(try ModelsManager.bundledModelsResponse())
        guard let output = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                ModelsManager.bundledModels,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unable to encode bundled model catalog as UTF-8"
                )
            )
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }

    private static func pendingRuntime(_ command: String) -> CodexCLI.CommandExecutionResult {
        CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: command '\(command)' runtime port is not complete yet."
        )
    }

    private static func runClearMemories(
        request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies
    ) async throws -> CodexCLI.CommandExecutionResult {
        let codexHome = try dependencies.findCodexHome()
        let config = try dependencies.loadConfig(codexHome, request.configOverrides)
        let statePath = stateDatabasePath(codexHome: codexHome)

        let clearedStateDB: Bool
        if FileManager.default.fileExists(atPath: statePath.path) {
            let stateStore = try dependencies.makeStateStore(statePath, config.selectedModelProviderID)
            try await stateStore.clearMemoryData()
            clearedStateDB = true
        } else {
            clearedStateDB = false
        }

        try clearMemoryRootsContents(codexHome: codexHome)

        let stateMessage = clearedStateDB
            ? "Cleared memory state from \(statePath.path)."
            : "No state db found at \(statePath.path)."
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "\(stateMessage) Cleared memory directories under \(codexHome.path)."
        )
    }

    private static func stateDatabasePath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("state_5.sqlite", isDirectory: false)
    }

    private static func clearMemoryRootsContents(codexHome: URL) throws {
        for rootName in ["memories", "memories_extensions"] {
            try clearMemoryRootContents(codexHome.appendingPathComponent(rootName, isDirectory: true))
        }
    }

    private static func clearMemoryRootContents(_ root: URL) throws {
        if let isSymlink = try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
           isSymlink == true {
            throw CocoaError(
                .fileWriteInvalidFileName,
                userInfo: [
                    NSFilePathErrorKey: root.path,
                    NSLocalizedDescriptionKey: "refusing to clear symlinked memory root \(root.path)"
                ]
            )
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        for entry in entries {
            try FileManager.default.removeItem(at: entry)
        }
    }
}
