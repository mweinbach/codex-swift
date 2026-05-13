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
    public typealias StdinReader = @Sendable () throws -> Data
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

        let stdinData: Data
        do {
            stdinData = try readStdin()
        } catch {
            throw NonInteractiveInputError.stdinReadFailed(errorDescription(error))
        }

        let input: String
        do {
            input = try decodePromptBytes(stdinData)
        } catch let error as PromptDecodeError {
            throw NonInteractiveInputError.stdinReadFailed(error.description)
        }

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonInteractiveInputError.emptyStdinPrompt
        }

        return NonInteractivePromptResolution(
            prompt: input,
            stderrMessage: forceStdin ? nil : "Reading prompt from stdin..."
        )
    }

    public static func decodePromptBytes(_ data: Data) throws -> String {
        var bytes = Array(data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }

        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            throw PromptDecodeError.unsupportedBOM(encoding: "UTF-32LE")
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            throw PromptDecodeError.unsupportedBOM(encoding: "UTF-32BE")
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return try decodeUTF16Bytes(Array(bytes.dropFirst(2)), encoding: "UTF-16LE") {
                UInt16($0) | (UInt16($1) << 8)
            }
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return try decodeUTF16Bytes(Array(bytes.dropFirst(2)), encoding: "UTF-16BE") {
                (UInt16($0) << 8) | UInt16($1)
            }
        }

        if let invalidOffset = firstInvalidUTF8Offset(bytes) {
            throw PromptDecodeError.invalidUTF8(validUpTo: invalidOffset)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decodeUTF16Bytes(
        _ bytes: [UInt8],
        encoding: String,
        makeUnit: (_ first: UInt8, _ second: UInt8) -> UInt16
    ) throws -> String {
        guard bytes.count.isMultiple(of: 2) else {
            throw PromptDecodeError.invalidUTF16(encoding: encoding)
        }

        var scalarView = String.UnicodeScalarView()
        var index = 0
        while index < bytes.count {
            let unit = makeUnit(bytes[index], bytes[index + 1])
            index += 2

            if (0xD800...0xDBFF).contains(unit) {
                guard index < bytes.count else {
                    throw PromptDecodeError.invalidUTF16(encoding: encoding)
                }
                let low = makeUnit(bytes[index], bytes[index + 1])
                guard (0xDC00...0xDFFF).contains(low) else {
                    throw PromptDecodeError.invalidUTF16(encoding: encoding)
                }
                index += 2
                let highBits = UInt32(unit - 0xD800) << 10
                let lowBits = UInt32(low - 0xDC00)
                guard let scalar = UnicodeScalar(0x10000 + highBits + lowBits) else {
                    throw PromptDecodeError.invalidUTF16(encoding: encoding)
                }
                scalarView.append(scalar)
            } else if (0xDC00...0xDFFF).contains(unit) {
                throw PromptDecodeError.invalidUTF16(encoding: encoding)
            } else {
                guard let scalar = UnicodeScalar(UInt32(unit)) else {
                    throw PromptDecodeError.invalidUTF16(encoding: encoding)
                }
                scalarView.append(scalar)
            }
        }

        return String(scalarView)
    }

    private static func firstInvalidUTF8Offset(_ bytes: [UInt8]) -> Int? {
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                index += 1
            } else if (0xC2...0xDF).contains(byte) {
                guard hasContinuation(bytes, at: index + 1) else {
                    return index
                }
                index += 2
            } else if byte == 0xE0 {
                guard hasByte(bytes, at: index + 1, in: 0xA0...0xBF),
                      hasContinuation(bytes, at: index + 2)
                else {
                    return index
                }
                index += 3
            } else if (0xE1...0xEC).contains(byte) || (0xEE...0xEF).contains(byte) {
                guard hasContinuation(bytes, at: index + 1),
                      hasContinuation(bytes, at: index + 2)
                else {
                    return index
                }
                index += 3
            } else if byte == 0xED {
                guard hasByte(bytes, at: index + 1, in: 0x80...0x9F),
                      hasContinuation(bytes, at: index + 2)
                else {
                    return index
                }
                index += 3
            } else if byte == 0xF0 {
                guard hasByte(bytes, at: index + 1, in: 0x90...0xBF),
                      hasContinuation(bytes, at: index + 2),
                      hasContinuation(bytes, at: index + 3)
                else {
                    return index
                }
                index += 4
            } else if (0xF1...0xF3).contains(byte) {
                guard hasContinuation(bytes, at: index + 1),
                      hasContinuation(bytes, at: index + 2),
                      hasContinuation(bytes, at: index + 3)
                else {
                    return index
                }
                index += 4
            } else if byte == 0xF4 {
                guard hasByte(bytes, at: index + 1, in: 0x80...0x8F),
                      hasContinuation(bytes, at: index + 2),
                      hasContinuation(bytes, at: index + 3)
                else {
                    return index
                }
                index += 4
            } else {
                return index
            }
        }

        return nil
    }

    private static func hasContinuation(_ bytes: [UInt8], at index: Int) -> Bool {
        hasByte(bytes, at: index, in: 0x80...0xBF)
    }

    private static func hasByte(_ bytes: [UInt8], at index: Int, in range: ClosedRange<UInt8>) -> Bool {
        index < bytes.count && range.contains(bytes[index])
    }

    private enum PromptDecodeError: Error, CustomStringConvertible {
        case invalidUTF8(validUpTo: Int)
        case invalidUTF16(encoding: String)
        case unsupportedBOM(encoding: String)

        var description: String {
            switch self {
            case let .invalidUTF8(validUpTo):
                return "input is not valid UTF-8 (invalid byte at offset \(validUpTo)). Convert it to UTF-8 and retry (e.g., `iconv -f <ENC> -t UTF-8 prompt.txt`)."
            case let .invalidUTF16(encoding):
                return "input looked like \(encoding) but could not be decoded. Convert it to UTF-8 and retry."
            case let .unsupportedBOM(encoding):
                return "input appears to be \(encoding). Convert it to UTF-8 and retry."
            }
        }
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
