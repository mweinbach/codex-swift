import Foundation

public enum UpdateCommandRuntime {
    public struct Dependencies: Sendable {
        public var isDebugBuild: @Sendable () -> Bool
        public var detectUpdateAction: @Sendable () -> UpdateAction?
        public var runProcess: @Sendable (String, [String]) throws -> ProcessStatus

        public init(
            isDebugBuild: @escaping @Sendable () -> Bool = { _isDebugAssertConfiguration() },
            detectUpdateAction: @escaping @Sendable () -> UpdateAction? = { UpdateAction.detectCurrent() },
            runProcess: @escaping @Sendable (String, [String]) throws -> ProcessStatus = { command, arguments in
                try ProcessStatus.run(command: command, arguments: arguments)
            }
        ) {
            self.isDebugBuild = isDebugBuild
            self.detectUpdateAction = detectUpdateAction
            self.runProcess = runProcess
        }
    }

    public struct ProcessStatus: Equatable, Sendable {
        public let isSuccess: Bool
        public let description: String

        public init(isSuccess: Bool, description: String) {
            self.isSuccess = isSuccess
            self.description = description
        }

        public static func run(command: String, arguments: [String]) throws -> ProcessStatus {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            try process.run()
            process.waitUntilExit()
            return ProcessStatus(
                isSuccess: process.terminationStatus == 0,
                description: statusDescription(process)
            )
        }

        private static func statusDescription(_ process: Process) -> String {
            switch process.terminationReason {
            case .exit:
                return "exit status: \(process.terminationStatus)"
            case .uncaughtSignal:
                return "signal: \(process.terminationStatus)"
            @unknown default:
                return "status: \(process.terminationStatus)"
            }
        }
    }

    public static func run(
        dependencies: Dependencies = Dependencies()
    ) throws -> CodexCLI.CommandExecutionResult {
        if dependencies.isDebugBuild() {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "`codex update` is not available in debug builds. Install a release build of Codex to use this command."
            )
        }

        guard let action = dependencies.detectUpdateAction() else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "Could not detect the Codex installation method. Please update manually: https://developers.openai.com/codex/cli/"
            )
        }

        return try runUpdateAction(action, runProcess: dependencies.runProcess)
    }

    public static func runUpdateAction(
        _ action: UpdateAction,
        runProcess: @Sendable (String, [String]) throws -> ProcessStatus = { command, arguments in
            try ProcessStatus.run(command: command, arguments: arguments)
        }
    ) throws -> CodexCLI.CommandExecutionResult {
        let renderedCommand = action.commandString()
        let normalizedArgs = action.normalizedCommandArgsForWSL()
        let status = try runProcess(normalizedArgs.command, normalizedArgs.arguments)
        if !status.isSuccess {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "`\(renderedCommand)` failed with status \(status.description)"
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "\nUpdating Codex via `\(renderedCommand)`...\n\n🎉 Update ran successfully! Please restart Codex."
        )
    }
}
