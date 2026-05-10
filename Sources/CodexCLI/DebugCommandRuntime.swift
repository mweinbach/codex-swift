import CodexCore
import Foundation

public enum DebugCommandRuntime {
    public struct Dependencies {
        public var findCodexHome: () throws -> URL
        public var loadConfig: (URL, CliConfigOverrides) throws -> CodexRuntimeConfig
        public var makeStateStore: (URL, String) throws -> SQLiteAgentGraphStore
        public var loadRawModelCatalog: (URL, CodexRuntimeConfig) async throws -> ModelsResponse

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
            },
            loadRawModelCatalog: @escaping (URL, CodexRuntimeConfig) async throws -> ModelsResponse = { codexHome, config in
                let auth = try CodexAuthStorage.loadEffectiveAuthDotJSON(
                    codexHome: codexHome,
                    mode: config.cliAuthCredentialsStoreMode
                )
                return try await ModelsManager.rawModelCatalogOnlineIfUncached(
                    codexHome: codexHome,
                    config: config,
                    auth: auth,
                    transport: URLSessionAPITransport(),
                    clientVersion: ModelsManager.formatClientVersion(major: "0", minor: "0", patch: "0")
                )
            }
        ) {
            self.findCodexHome = findCodexHome
            self.loadConfig = loadConfig
            self.makeStateStore = makeStateStore
            self.loadRawModelCatalog = loadRawModelCatalog
        }
    }

    public static func run(
        _ request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies = Dependencies()
    ) async throws -> CodexCLI.CommandExecutionResult {
        switch request.action {
        case let .models(bundled):
            return try await runModels(bundled: bundled, request: request, dependencies: dependencies)
        case .appServerSendMessageV2:
            return pendingRuntime("debug app-server send-message-v2")
        case let .promptInput(prompt, imagePaths):
            return try runPromptInput(prompt: prompt, imagePaths: imagePaths, request: request, dependencies: dependencies)
        case let .traceReduce(traceBundle, output):
            return try runTraceReduce(traceBundle: traceBundle, output: output)
        case .clearMemories:
            return try await runClearMemories(request: request, dependencies: dependencies)
        }
    }

    private static func runModels(
        bundled: Bool,
        request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies
    ) async throws -> CodexCLI.CommandExecutionResult {
        let response: ModelsResponse
        if bundled {
            response = try ModelsManager.bundledModelsResponse()
        } else {
            let codexHome = try dependencies.findCodexHome()
            let config = try dependencies.loadConfig(codexHome, request.configOverrides)
            response = try await dependencies.loadRawModelCatalog(codexHome, config)
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        guard let output = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                response,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unable to encode model catalog as UTF-8"
                )
            )
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }

    private static func runPromptInput(
        prompt: String?,
        imagePaths: [String],
        request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies
    ) throws -> CodexCLI.CommandExecutionResult {
        let codexHome = try dependencies.findCodexHome()
        let config = try dependencies.loadConfig(codexHome, request.configOverrides)
        let input = makePromptInput(
            prompt: prompt,
            imagePaths: imagePaths,
            config: config
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(input)
        guard let output = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                input,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unable to encode debug prompt input as UTF-8"
                )
            )
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }

    private static func makePromptInput(
        prompt: String?,
        imagePaths: [String],
        config: CodexRuntimeConfig
    ) -> [ResponseItem] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let approvalPolicy = config.approvalPolicy ?? .onRequest
        let sandboxPolicy = config.legacySandboxPolicy()
        let projectInstructions = ProjectDoc.getUserInstructions(
            config: ProjectDocConfig(runtimeConfig: config, cwd: cwd)
        ).map { UserInstructions(directory: cwd.path, text: $0) }
        var input = NonInteractiveExec.makeInitialPromptInput(
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            shell: ShellResolver.defaultUserShell(),
            includeEnvironmentContext: config.includeEnvironmentContext,
            includePermissionsInstructions: config.includePermissionsInstructions,
            developerInstructions: config.developerInstructions,
            userInstructions: projectInstructions
        )

        var userInputs = imagePaths.map(UserInput.localImage(path:))
        if let prompt {
            userInputs.append(.text(prompt.replacingCRLFWithLF()))
        }
        if !userInputs.isEmpty {
            input.append(ResponseInputItem(userInputs: userInputs).responseItem())
        }

        return input
    }

    private static func pendingRuntime(_ command: String) -> CodexCLI.CommandExecutionResult {
        CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: command '\(command)' runtime port is not complete yet."
        )
    }

    private static func runTraceReduce(
        traceBundle: String,
        output: String?
    ) throws -> CodexCLI.CommandExecutionResult {
        let bundleURL = URL(fileURLWithPath: traceBundle, isDirectory: true)
        let outputURL = output.map { URL(fileURLWithPath: $0, isDirectory: false) }
            ?? bundleURL.appendingPathComponent("state.json", isDirectory: false)
        var reducer = try DebugTraceReducer(bundleURL: bundleURL)
        let reduced = try reducer.replay()
        let data = try JSONSerialization.data(
            withJSONObject: reduced,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: outputURL, options: Data.WritingOptions.atomic)
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "\(outputURL.path)\n")
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

private extension String {
    func replacingCRLFWithLF() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
