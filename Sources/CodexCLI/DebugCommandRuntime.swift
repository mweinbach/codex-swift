import CodexCore
import Foundation

public enum DebugCommandRuntime {
    public struct Dependencies {
        public var findCodexHome: () throws -> URL
        public var loadConfig: (URL, CliConfigOverrides) throws -> CodexRuntimeConfig
        public var loadConfigLayerStack: (URL, CliConfigOverrides) throws -> ConfigLayerStack
        public var makeStateStore: (URL, String) throws -> SQLiteAgentGraphStore
        public var loadRawModelCatalog: (URL, CodexRuntimeConfig) async throws -> ModelsResponse
        public var currentExecutable: () throws -> URL
        public var sendAppServerMessageV2: (URL, CliConfigOverrides, String) async throws -> CodexCLI.CommandExecutionResult

        public init(
            findCodexHome: @escaping () throws -> URL = { try CodexHome.find() },
            loadConfig: @escaping (URL, CliConfigOverrides) throws -> CodexRuntimeConfig = { codexHome, overrides in
                try CodexConfigLoader.load(
                    codexHome: codexHome,
                    cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
                    overrides: overrides
                )
            },
            loadConfigLayerStack: @escaping (URL, CliConfigOverrides) throws -> ConfigLayerStack = { codexHome, overrides in
                try CodexConfigLayerLoader.loadConfigLayerStack(
                    codexHome: codexHome,
                    cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
                    cliOverrides: overrides
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
            },
            currentExecutable: @escaping () throws -> URL = {
                if let executableURL = Bundle.main.executableURL {
                    return executableURL.standardizedFileURL
                }
                let rawPath = CommandLine.arguments.first ?? "codex"
                if rawPath.hasPrefix("/") {
                    return URL(fileURLWithPath: rawPath, isDirectory: false).standardizedFileURL
                }
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                    .appendingPathComponent(rawPath, isDirectory: false)
                    .standardizedFileURL
            },
            sendAppServerMessageV2: ((URL, CliConfigOverrides, String) async throws -> CodexCLI.CommandExecutionResult)? = nil
        ) {
            self.findCodexHome = findCodexHome
            self.loadConfig = loadConfig
            self.loadConfigLayerStack = loadConfigLayerStack
            self.makeStateStore = makeStateStore
            self.loadRawModelCatalog = loadRawModelCatalog
            self.currentExecutable = currentExecutable
            self.sendAppServerMessageV2 = sendAppServerMessageV2 ?? { executableURL, overrides, message in
                try await DebugCommandRuntime.sendAppServerMessageV2(
                    executableURL: executableURL,
                    configOverrides: overrides,
                    userMessage: message
                )
            }
        }
    }

    public static func run(
        _ request: CodexCLI.DebugCommandRequest,
        dependencies: Dependencies = Dependencies()
    ) async throws -> CodexCLI.CommandExecutionResult {
        switch request.action {
        case let .models(bundled):
            return try await runModels(bundled: bundled, request: request, dependencies: dependencies)
        case let .appServerSendMessageV2(message):
            return try await dependencies.sendAppServerMessageV2(
                dependencies.currentExecutable(),
                request.configOverrides,
                message
            )
        case let .promptInput(prompt, imagePaths):
            return try runPromptInput(
                prompt: prompt,
                imagePaths: imagePaths,
                configOverrides: request.configOverrides,
                dependencies: dependencies
            )
        case let .traceReduce(traceBundle, output):
            return try runTraceReduce(traceBundle: traceBundle, output: output)
        case .clearMemories:
            return try await runClearMemories(configOverrides: request.configOverrides, dependencies: dependencies)
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

    public static func sendAppServerMessageV2(
        executableURL: URL,
        configOverrides: CliConfigOverrides,
        userMessage: String
    ) async throws -> CodexCLI.CommandExecutionResult {
        try await Task.detached {
            try runAppServerSendMessageV2(
                executableURL: executableURL,
                configOverrides: configOverrides,
                userMessage: userMessage
            )
        }.value
    }

    private static func runAppServerSendMessageV2(
        executableURL: URL,
        configOverrides: CliConfigOverrides,
        userMessage: String
    ) throws -> CodexCLI.CommandExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = configOverrides.rawOverrides.flatMap { ["--config", $0] } + ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        if let executableDirectory = executableURL.deletingLastPathComponent().path.nilIfEmpty {
            let existingPath = environment["PATH"].map { ":\($0)" } ?? ""
            environment["PATH"] = executableDirectory + existingPath
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw DebugAppServerRuntimeError.launchFailed(executableURL.path, error)
        }

        let stdinHandle = stdin.fileHandleForWriting
        let stdoutHandle = stdout.fileHandleForReading
        var renderedOutput = ""

        let initialize = try sendAppServerDebugRequest(
            id: 1,
            method: "initialize",
            params: ["capabilities": ["experimentalApi": true]],
            stdin: stdinHandle,
            stdout: stdoutHandle,
            output: &renderedOutput
        )
        renderedOutput += "< initialize response: \(compactJSONObject(initialize))\n"

        let threadStart = try sendAppServerDebugRequest(
            id: 2,
            method: "thread/start",
            params: [:],
            stdin: stdinHandle,
            stdout: stdoutHandle,
            output: &renderedOutput
        )
        renderedOutput += "< thread/start response: \(compactJSONObject(threadStart))\n"

        guard let threadID = ((threadStart["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String else {
            throw DebugAppServerRuntimeError.missingField("thread/start result.thread.id")
        }

        let turnStart = try sendAppServerDebugRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": userMessage,
                        "textElements": []
                    ]
                ]
            ],
            stdin: stdinHandle,
            stdout: stdoutHandle,
            output: &renderedOutput
        )
        renderedOutput += "< turn/start response: \(compactJSONObject(turnStart))\n"
        stdinHandle.closeFile()

        while let line = readAppServerDebugLine(from: stdoutHandle) {
            renderedOutput += "< notification: \(line)\n"
        }
        process.waitUntilExit()

        let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            return CodexCLI.CommandExecutionResult(
                exitCode: process.terminationStatus,
                stdoutMessage: renderedOutput.nilIfEmpty,
                stderrMessage: stderrText.nilIfEmpty
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: renderedOutput.nilIfEmpty,
            stderrMessage: stderrText.nilIfEmpty
        )
    }

    private static func sendAppServerDebugRequest(
        id: Int,
        method: String,
        params: [String: Any],
        stdin: FileHandle,
        stdout: FileHandle,
        output: inout String
    ) throws -> [String: Any] {
        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0A)
        try stdin.write(contentsOf: data)

        while let line = readAppServerDebugLine(from: stdout) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                output += "< notification: \(line)\n"
                continue
            }
            if (object["id"] as? Int) == id {
                if let error = object["error"] as? [String: Any] {
                    throw DebugAppServerRuntimeError.serverError(
                        method,
                        error["message"] as? String ?? compactJSONObject(error)
                    )
                }
                return object
            }
            output += "< notification: \(line)\n"
        }
        throw DebugAppServerRuntimeError.missingResponse(method)
    }

    private static func readAppServerDebugLine(from handle: FileHandle) -> String? {
        var data = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty {
                return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
            }
            if byte[byte.startIndex] == 0x0A {
                return String(decoding: data, as: UTF8.self)
            }
            data.append(byte)
        }
    }

    private static func compactJSONObject(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return String(describing: object)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func runPromptInput(
        prompt: String?,
        imagePaths: [String],
        configOverrides: CliConfigOverrides,
        dependencies: Dependencies
    ) throws -> CodexCLI.CommandExecutionResult {
        let codexHome = try dependencies.findCodexHome()
        let config = try dependencies.loadConfig(codexHome, configOverrides)
        let configLayerStack = try dependencies.loadConfigLayerStack(codexHome, configOverrides)
        let input = makePromptInput(
            prompt: prompt,
            imagePaths: imagePaths,
            codexHome: codexHome,
            config: config,
            configLayerStack: configLayerStack
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
        codexHome: URL,
        config: CodexRuntimeConfig,
        configLayerStack: ConfigLayerStack
    ) -> [ResponseItem] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let approvalPolicy = config.approvalPolicy ?? .onRequest
        let sandboxPolicy = config.legacySandboxPolicy()
        let projectInstructions = ProjectDoc.getUserInstructions(
            config: ProjectDocConfig(runtimeConfig: config, cwd: cwd)
        ).map { UserInstructions(directory: cwd.path, text: $0) }
        let memoryToolDeveloperInstructions = MemoryToolInstructions.build(codexHome: codexHome, config: config)
        let loadedSkills = config.includeSkillInstructions
            ? SkillLoader.load(cwd: cwd, codexHome: codexHome, configLayerStack: configLayerStack)
            : nil
        let model = config.model ?? ModelsManager.openAIDefaultAPIModel
        let modelFamily = ModelsManager.constructModelFamilyOffline(
            model: model,
            configOverrides: config.modelFamilyConfigOverrides
        )
        let availableSkills = loadedSkills.flatMap {
            Skills.buildAvailableSkills(
                outcome: $0,
                budget: Skills.defaultSkillMetadataBudget(contextWindow: modelFamily.contextWindow.map(Int.init))
            )
        }
        var input = NonInteractiveExec.makeInitialPromptInput(
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            shell: ShellResolver.defaultUserShell(),
            includeEnvironmentContext: config.includeEnvironmentContext,
            includePermissionsInstructions: config.includePermissionsInstructions,
            developerInstructions: config.developerInstructions,
            memoryToolDeveloperInstructions: memoryToolDeveloperInstructions,
            availableSkills: availableSkills,
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
        configOverrides: CliConfigOverrides,
        dependencies: Dependencies
    ) async throws -> CodexCLI.CommandExecutionResult {
        let codexHome = try dependencies.findCodexHome()
        let config = try dependencies.loadConfig(codexHome, configOverrides)
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

private enum DebugAppServerRuntimeError: Error, CustomStringConvertible {
    case launchFailed(String, Error)
    case missingResponse(String)
    case serverError(String, String)
    case missingField(String)

    var description: String {
        switch self {
        case let .launchFailed(path, error):
            return "failed to start `\(path)` app-server: \(error)"
        case let .missingResponse(method):
            return "app-server exited before responding to \(method)"
        case let .serverError(method, message):
            return "\(method) failed: \(message)"
        case let .missingField(field):
            return "app-server response missing \(field)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension String {
    func replacingCRLFWithLF() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
