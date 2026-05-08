import Foundation

public struct NonInteractivePromptResolution: Equatable, Sendable {
    public let prompt: String
    public let stderrMessage: String?

    public init(prompt: String, stderrMessage: String? = nil) {
        self.prompt = prompt
        self.stderrMessage = stderrMessage
    }
}

public struct NonInteractiveLastMessageWriteResult: Equatable, Sendable {
    public let stderrMessages: [String]

    public init(stderrMessages: [String] = []) {
        self.stderrMessages = stderrMessages
    }
}

public enum NonInteractiveInputError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingPrompt
    case emptyStdinPrompt
    case stdinReadFailed(String)
    case outputSchemaReadFailed(path: String, message: String)
    case outputSchemaInvalidJSON(path: String, message: String)
    case notInsideTrustedDirectory

    public var description: String {
        switch self {
        case .missingPrompt:
            return "No prompt provided. Either specify one as an argument or pipe the prompt into stdin."
        case .emptyStdinPrompt:
            return "No prompt provided via stdin."
        case let .stdinReadFailed(message):
            return "Failed to read prompt from stdin: \(message)"
        case let .outputSchemaReadFailed(path, message):
            return "Failed to read output schema file \(path): \(message)"
        case let .outputSchemaInvalidJSON(path, message):
            return "Output schema file \(path) is not valid JSON: \(message)"
        case .notInsideTrustedDirectory:
            return "Not inside a trusted directory and --skip-git-repo-check was not specified."
        }
    }
}

public enum NonInteractiveInput {
    public typealias StdinReader = @Sendable () throws -> String
    public typealias FileReader = @Sendable (_ path: String) throws -> Data
    public typealias FileWriter = @Sendable (_ path: String, _ contents: String) throws -> Void
    public typealias GitRepoRootResolver = @Sendable (_ cwd: URL) -> URL?

    public static func resolvePrompt(
        _ promptArgument: String?,
        stdinIsTerminal: Bool,
        readStdin: StdinReader
    ) throws -> NonInteractivePromptResolution {
        if let promptArgument, promptArgument != "-" {
            return NonInteractivePromptResolution(prompt: promptArgument)
        }

        let forceStdin = promptArgument == "-"
        if stdinIsTerminal, !forceStdin {
            throw NonInteractiveInputError.missingPrompt
        }

        let input: String
        do {
            input = try readStdin()
        } catch {
            throw NonInteractiveInputError.stdinReadFailed(errorDescription(error))
        }

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonInteractiveInputError.emptyStdinPrompt
        }

        return NonInteractivePromptResolution(
            prompt: input,
            stderrMessage: forceStdin ? nil : "Reading prompt from stdin..."
        )
    }

    public static func loadOutputSchema(
        path: String?,
        readFile: FileReader
    ) throws -> JSONValue? {
        guard let path else {
            return nil
        }

        let data: Data
        do {
            data = try readFile(path)
        } catch {
            throw NonInteractiveInputError.outputSchemaReadFailed(
                path: path,
                message: errorDescription(error)
            )
        }

        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw NonInteractiveInputError.outputSchemaInvalidJSON(
                path: path,
                message: errorDescription(error)
            )
        }
    }

    public static func writeLastMessage(
        _ lastAgentMessage: String?,
        path: String?,
        writeFile: FileWriter
    ) -> NonInteractiveLastMessageWriteResult {
        guard let path else {
            return NonInteractiveLastMessageWriteResult()
        }

        var stderrMessages: [String] = []
        let contents = lastAgentMessage ?? ""
        do {
            try writeFile(path, contents)
        } catch {
            stderrMessages.append("Failed to write last message file \"\(path)\": \(errorDescription(error))")
        }

        if lastAgentMessage == nil {
            stderrMessages.append("Warning: no last agent message; wrote empty content to \(path)")
        }

        return NonInteractiveLastMessageWriteResult(stderrMessages: stderrMessages)
    }

    public static func enforceGitRepository(
        cwd: URL,
        skipGitRepoCheck: Bool,
        gitRepoRoot: GitRepoRootResolver = { cwd in GitInfoCollector.gitRepoRoot(baseDir: cwd) }
    ) throws {
        guard !skipGitRepoCheck else {
            return
        }
        guard gitRepoRoot(cwd) != nil else {
            throw NonInteractiveInputError.notInsideTrustedDirectory
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        return String(describing: error)
    }
}
