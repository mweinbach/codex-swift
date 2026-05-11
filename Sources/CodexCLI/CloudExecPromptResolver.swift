import Foundation

public struct CloudExecPrompt: Equatable, Sendable {
    public let prompt: String
    public let stderrMessage: String?

    public init(prompt: String, stderrMessage: String?) {
        self.prompt = prompt
        self.stderrMessage = stderrMessage
    }
}

public struct CloudExecPromptError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

public enum CloudExecPromptResolver {
    public static func resolve(
        query: String?,
        stdinIsTerminal: Bool,
        readStdin: () throws -> Data
    ) throws -> CloudExecPrompt {
        if let query, query != "-" {
            return CloudExecPrompt(prompt: query, stderrMessage: nil)
        }

        let forceStdin = query == "-"
        if stdinIsTerminal, !forceStdin {
            throw CloudExecPromptError(
                description: "no query provided. Pass one as an argument or pipe it via stdin."
            )
        }

        let data: Data
        do {
            data = try readStdin()
        } catch {
            throw CloudExecPromptError(description: "failed to read query from stdin: \(error)")
        }
        guard let input = String(data: data, encoding: .utf8) else {
            throw CloudExecPromptError(
                description: "failed to read query from stdin: stream did not contain valid UTF-8"
            )
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudExecPromptError(description: "no query provided via stdin (received empty input).")
        }

        let stderrMessage = forceStdin ? nil : "Reading query from stdin..."
        return CloudExecPrompt(prompt: input, stderrMessage: stderrMessage)
    }
}
