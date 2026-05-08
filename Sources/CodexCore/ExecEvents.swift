import Foundation

public enum ExecCommandSource: String, Codable, Equatable, Sendable {
    case agent
    case userShell = "user_shell"
    case unifiedExecStartup = "unified_exec_startup"
    case unifiedExecInteraction = "unified_exec_interaction"

    public static let `default`: ExecCommandSource = .agent
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
