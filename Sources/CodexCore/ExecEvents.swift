import Foundation

public enum ExecCommandSource: String, Codable, Equatable, Sendable {
    case agent
    case userShell = "user_shell"
    case unifiedExecStartup = "unified_exec_startup"
    case unifiedExecInteraction = "unified_exec_interaction"

    public static let `default`: ExecCommandSource = .agent
}

public enum ExecCommandStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case declined
}

public struct ViewImageToolCallEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let path: String

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case path
    }

    public init(callID: String, path: String) {
        self.callID = callID
        self.path = path
    }
}

public enum ExecOutputStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
}

public struct ProtocolDuration: Equatable, Codable, Sendable {
    public let secs: UInt64
    public let nanos: UInt32

    public init(secs: UInt64, nanos: UInt32 = 0) {
        self.secs = secs
        self.nanos = nanos
    }

    public init(timeInterval: TimeInterval) {
        let clamped = max(0, timeInterval)
        let secs = UInt64(clamped.rounded(.down))
        let nanos = UInt32(((clamped - Double(secs)) * 1_000_000_000).rounded(.towardZero))
        self.init(secs: secs, nanos: nanos)
    }

    public var timeInterval: TimeInterval {
        TimeInterval(secs) + TimeInterval(nanos) / 1_000_000_000
    }
}

public struct ExecCommandBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let processID: String?
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let command: [String]
    public let cwd: String
    public let parsedCmd: [ParsedCommand]
    public let source: ExecCommandSource
    public let interactionInput: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case processID = "process_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case command
        case cwd
        case parsedCmd = "parsed_cmd"
        case source
        case interactionInput = "interaction_input"
    }

    public init(
        callID: String,
        processID: String? = nil,
        turnID: String,
        startedAtMilliseconds: Int64 = 0,
        command: [String],
        cwd: String,
        parsedCmd: [ParsedCommand],
        source: ExecCommandSource = .default,
        interactionInput: String? = nil
    ) {
        self.callID = callID
        self.processID = processID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.command = command
        self.cwd = cwd
        self.parsedCmd = parsedCmd
        self.source = source
        self.interactionInput = interactionInput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.processID = try container.decodeIfPresent(String.self, forKey: .processID)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.startedAtMilliseconds = try container.decodeRustDefaulted(
            Int64.self,
            forKey: .startedAtMilliseconds,
            defaultValue: 0
        )
        self.command = try container.decode([String].self, forKey: .command)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
        self.source = try container.decodeRustDefaulted(
            ExecCommandSource.self,
            forKey: .source,
            defaultValue: .default
        )
        self.interactionInput = try container.decodeIfPresent(String.self, forKey: .interactionInput)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encodeIfPresent(processID, forKey: .processID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(parsedCmd, forKey: .parsedCmd)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(interactionInput, forKey: .interactionInput)
    }
}

public struct ExecCommandEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let processID: String?
    public let turnID: String
    public let completedAtMilliseconds: Int64
    public let command: [String]
    public let cwd: String
    public let parsedCmd: [ParsedCommand]
    public let source: ExecCommandSource
    public let interactionInput: String?
    public let stdout: String
    public let stderr: String
    public let aggregatedOutput: String
    public let exitCode: Int32
    public let duration: ProtocolDuration
    public let formattedOutput: String
    public let status: ExecCommandStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case processID = "process_id"
        case turnID = "turn_id"
        case completedAtMilliseconds = "completed_at_ms"
        case command
        case cwd
        case parsedCmd = "parsed_cmd"
        case source
        case interactionInput = "interaction_input"
        case stdout
        case stderr
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
        case duration
        case formattedOutput = "formatted_output"
        case status
    }

    public init(
        callID: String,
        processID: String? = nil,
        turnID: String,
        completedAtMilliseconds: Int64 = 0,
        command: [String],
        cwd: String,
        parsedCmd: [ParsedCommand],
        source: ExecCommandSource = .default,
        interactionInput: String? = nil,
        stdout: String,
        stderr: String,
        aggregatedOutput: String = "",
        exitCode: Int32,
        duration: ProtocolDuration,
        formattedOutput: String,
        status: ExecCommandStatus? = nil
    ) {
        self.callID = callID
        self.processID = processID
        self.turnID = turnID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.command = command
        self.cwd = cwd
        self.parsedCmd = parsedCmd
        self.source = source
        self.interactionInput = interactionInput
        self.stdout = stdout
        self.stderr = stderr
        self.aggregatedOutput = aggregatedOutput
        self.exitCode = exitCode
        self.duration = duration
        self.formattedOutput = formattedOutput
        self.status = status ?? (exitCode == 0 ? .completed : .failed)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.processID = try container.decodeIfPresent(String.self, forKey: .processID)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.completedAtMilliseconds = try container.decodeRustDefaulted(
            Int64.self,
            forKey: .completedAtMilliseconds,
            defaultValue: 0
        )
        self.command = try container.decode([String].self, forKey: .command)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
        self.source = try container.decodeRustDefaulted(
            ExecCommandSource.self,
            forKey: .source,
            defaultValue: .default
        )
        self.interactionInput = try container.decodeIfPresent(String.self, forKey: .interactionInput)
        self.stdout = try container.decode(String.self, forKey: .stdout)
        self.stderr = try container.decode(String.self, forKey: .stderr)
        self.aggregatedOutput = try container.decodeRustDefaulted(
            String.self,
            forKey: .aggregatedOutput,
            defaultValue: ""
        )
        self.exitCode = try container.decode(Int32.self, forKey: .exitCode)
        self.duration = try container.decode(ProtocolDuration.self, forKey: .duration)
        self.formattedOutput = try container.decode(String.self, forKey: .formattedOutput)
        self.status = try container.decodeIfPresent(ExecCommandStatus.self, forKey: .status)
            ?? (exitCode == 0 ? .completed : .failed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encodeIfPresent(processID, forKey: .processID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(parsedCmd, forKey: .parsedCmd)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(interactionInput, forKey: .interactionInput)
        try container.encode(stdout, forKey: .stdout)
        try container.encode(stderr, forKey: .stderr)
        try container.encode(aggregatedOutput, forKey: .aggregatedOutput)
        try container.encode(exitCode, forKey: .exitCode)
        try container.encode(duration, forKey: .duration)
        try container.encode(formattedOutput, forKey: .formattedOutput)
        try container.encode(status, forKey: .status)
    }
}

public struct ExecCommandOutputDeltaEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let stream: ExecOutputStream
    public let chunk: [UInt8]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case stream
        case chunk
    }

    public init(callID: String, stream: ExecOutputStream, chunk: [UInt8]) {
        self.callID = callID
        self.stream = stream
        self.chunk = chunk
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.stream = try container.decode(ExecOutputStream.self, forKey: .stream)

        let encodedChunk = try container.decode(String.self, forKey: .chunk)
        guard let data = Data(base64Encoded: encodedChunk) else {
            throw DecodingError.dataCorruptedError(
                forKey: .chunk,
                in: container,
                debugDescription: "Expected base64-encoded command output bytes"
            )
        }
        self.chunk = Array(data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(stream, forKey: .stream)
        try container.encode(Data(chunk).base64EncodedString(), forKey: .chunk)
    }
}

public struct TerminalInteractionEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let processID: String
    public let stdin: String

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case processID = "process_id"
        case stdin
    }

    public init(callID: String, processID: String, stdin: String) {
        self.callID = callID
        self.processID = processID
        self.stdin = stdin
    }
}

public struct BackgroundEventEvent: Equatable, Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
