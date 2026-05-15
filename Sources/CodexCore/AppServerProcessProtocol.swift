public struct ProcessTerminalSize: Equatable, Codable, Sendable {
    public let rows: UInt16
    public let cols: UInt16

    public init(rows: UInt16, cols: UInt16) {
        self.rows = rows
        self.cols = cols
    }
}

public enum ProcessOutputBytesCap: Equatable, Sendable {
    case serverDefault
    case disabled
    case bytes(Int)
}

public enum ProcessTimeout: Equatable, Sendable {
    case serverDefault
    case disabled
    case milliseconds(Int64)
}

public struct ProcessSpawnParams: Equatable, Sendable {
    public let command: [String]
    public let processHandle: String
    public let cwd: AbsolutePath
    public let tty: Bool
    public let streamStdin: Bool
    public let streamStdoutStderr: Bool
    public let outputBytesCap: ProcessOutputBytesCap
    public let timeoutMs: ProcessTimeout
    public let env: [String: String?]?
    public let size: ProcessTerminalSize?

    public init(
        command: [String],
        processHandle: String,
        cwd: AbsolutePath,
        tty: Bool = false,
        streamStdin: Bool = false,
        streamStdoutStderr: Bool = false,
        outputBytesCap: ProcessOutputBytesCap = .serverDefault,
        timeoutMs: ProcessTimeout = .serverDefault,
        env: [String: String?]? = nil,
        size: ProcessTerminalSize? = nil
    ) {
        self.command = command
        self.processHandle = processHandle
        self.cwd = cwd
        self.tty = tty
        self.streamStdin = streamStdin
        self.streamStdoutStderr = streamStdoutStderr
        self.outputBytesCap = outputBytesCap
        self.timeoutMs = timeoutMs
        self.env = env
        self.size = size
    }
}

extension ProcessSpawnParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case command
        case processHandle
        case cwd
        case tty
        case streamStdin
        case streamStdoutStderr
        case outputBytesCap
        case timeoutMs
        case env
        case size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode([String].self, forKey: .command)
        processHandle = try container.decode(String.self, forKey: .processHandle)
        cwd = try container.decode(AbsolutePath.self, forKey: .cwd)
        tty = try container.decodeRustDefaulted(Bool.self, forKey: .tty, defaultValue: false)
        streamStdin = try container.decodeRustDefaulted(Bool.self, forKey: .streamStdin, defaultValue: false)
        streamStdoutStderr = try container.decodeRustDefaulted(Bool.self, forKey: .streamStdoutStderr, defaultValue: false)
        outputBytesCap = try container.decodeProcessOutputBytesCapIfPresent(forKey: .outputBytesCap) ?? .serverDefault
        timeoutMs = try container.decodeProcessTimeoutIfPresent(forKey: .timeoutMs) ?? .serverDefault
        env = try container.decodeIfPresent([String: String?].self, forKey: .env)
        size = try container.decodeIfPresent(ProcessTerminalSize.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(processHandle, forKey: .processHandle)
        try container.encode(cwd, forKey: .cwd)
        if tty {
            try container.encode(tty, forKey: .tty)
        }
        if streamStdin {
            try container.encode(streamStdin, forKey: .streamStdin)
        }
        if streamStdoutStderr {
            try container.encode(streamStdoutStderr, forKey: .streamStdoutStderr)
        }
        try container.encode(outputBytesCap, forKey: .outputBytesCap)
        try container.encode(timeoutMs, forKey: .timeoutMs)
        try container.encodeNilOrValue(env, forKey: .env)
        try container.encodeNilOrValue(size, forKey: .size)
    }
}

public struct ProcessSpawnResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ProcessWriteStdinParams: Equatable, Sendable {
    public let processHandle: String
    public let deltaBase64: String?
    public let closeStdin: Bool

    public init(processHandle: String, deltaBase64: String? = nil, closeStdin: Bool = false) {
        self.processHandle = processHandle
        self.deltaBase64 = deltaBase64
        self.closeStdin = closeStdin
    }
}

extension ProcessWriteStdinParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case processHandle
        case deltaBase64
        case closeStdin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processHandle = try container.decode(String.self, forKey: .processHandle)
        deltaBase64 = try container.decodeIfPresent(String.self, forKey: .deltaBase64)
        closeStdin = try container.decodeRustDefaulted(Bool.self, forKey: .closeStdin, defaultValue: false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(processHandle, forKey: .processHandle)
        try container.encodeNilOrValue(deltaBase64, forKey: .deltaBase64)
        if closeStdin {
            try container.encode(closeStdin, forKey: .closeStdin)
        }
    }
}

public struct ProcessWriteStdinResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ProcessKillParams: Equatable, Codable, Sendable {
    public let processHandle: String

    public init(processHandle: String) {
        self.processHandle = processHandle
    }
}

public struct ProcessKillResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ProcessResizePtyParams: Equatable, Codable, Sendable {
    public let processHandle: String
    public let size: ProcessTerminalSize

    public init(processHandle: String, size: ProcessTerminalSize) {
        self.processHandle = processHandle
        self.size = size
    }
}

public struct ProcessResizePtyResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum ProcessOutputStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
}

public struct ProcessOutputDeltaNotification: Equatable, Codable, Sendable {
    public let processHandle: String
    public let stream: ProcessOutputStream
    public let deltaBase64: String
    public let capReached: Bool

    public init(
        processHandle: String,
        stream: ProcessOutputStream,
        deltaBase64: String,
        capReached: Bool
    ) {
        self.processHandle = processHandle
        self.stream = stream
        self.deltaBase64 = deltaBase64
        self.capReached = capReached
    }
}

public struct ProcessExitedNotification: Equatable, Codable, Sendable {
    public let processHandle: String
    public let exitCode: Int32
    public let stdout: String
    public let stdoutCapReached: Bool
    public let stderr: String
    public let stderrCapReached: Bool

    public init(
        processHandle: String,
        exitCode: Int32,
        stdout: String,
        stdoutCapReached: Bool,
        stderr: String,
        stderrCapReached: Bool
    ) {
        self.processHandle = processHandle
        self.exitCode = exitCode
        self.stdout = stdout
        self.stdoutCapReached = stdoutCapReached
        self.stderr = stderr
        self.stderrCapReached = stderrCapReached
    }
}

private extension KeyedEncodingContainer {
    mutating func encode(_ value: ProcessOutputBytesCap, forKey key: Key) throws {
        switch value {
        case .serverDefault:
            break
        case .disabled:
            try encodeNil(forKey: key)
        case let .bytes(bytes):
            try encode(bytes, forKey: key)
        }
    }

    mutating func encode(_ value: ProcessTimeout, forKey key: Key) throws {
        switch value {
        case .serverDefault:
            break
        case .disabled:
            try encodeNil(forKey: key)
        case let .milliseconds(milliseconds):
            try encode(milliseconds, forKey: key)
        }
    }

    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeProcessOutputBytesCapIfPresent(forKey key: Key) throws -> ProcessOutputBytesCap? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return .disabled
        }
        return .bytes(try decode(Int.self, forKey: key))
    }

    func decodeProcessTimeoutIfPresent(forKey key: Key) throws -> ProcessTimeout? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return .disabled
        }
        return .milliseconds(try decode(Int64.self, forKey: key))
    }
}
