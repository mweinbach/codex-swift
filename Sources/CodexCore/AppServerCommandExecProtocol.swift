import Foundation

public struct CommandExecTerminalSize: Equatable, Codable, Sendable {
    public let rows: UInt16
    public let cols: UInt16

    public init(rows: UInt16, cols: UInt16) {
        self.rows = rows
        self.cols = cols
    }
}

public enum AppServerSandboxPolicy: Equatable, Sendable {
    case dangerFullAccess
    case readOnly(networkAccess: Bool = false)
    case externalSandbox(networkAccess: NetworkAccess = .restricted)
    case workspaceWrite(
        writableRoots: [String] = [],
        networkAccess: Bool = false,
        excludeTmpdirEnvVar: Bool = false,
        excludeSlashTmp: Bool = false
    )
}

extension AppServerSandboxPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case networkAccess
        case writableRoots
        case excludeTmpdirEnvVar
        case excludeSlashTmp
    }

    private enum PolicyType: String, Codable {
        case dangerFullAccess
        case readOnly
        case externalSandbox
        case workspaceWrite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PolicyType.self, forKey: .type) {
        case .dangerFullAccess:
            self = .dangerFullAccess
        case .readOnly:
            self = .readOnly(
                networkAccess: try container.decodeRustDefaulted(
                    Bool.self,
                    forKey: .networkAccess,
                    defaultValue: false
                )
            )
        case .externalSandbox:
            self = .externalSandbox(
                networkAccess: try container.decodeRustDefaulted(
                    NetworkAccess.self,
                    forKey: .networkAccess,
                    defaultValue: .restricted
                )
            )
        case .workspaceWrite:
            let writableRoots = try container.decodeRustDefaulted(
                [AbsolutePath].self,
                forKey: .writableRoots,
                defaultValue: []
            )
            self = .workspaceWrite(
                writableRoots: writableRoots.map(\.path),
                networkAccess: try container.decodeRustDefaulted(
                    Bool.self,
                    forKey: .networkAccess,
                    defaultValue: false
                ),
                excludeTmpdirEnvVar: try container.decodeRustDefaulted(
                    Bool.self,
                    forKey: .excludeTmpdirEnvVar,
                    defaultValue: false
                ),
                excludeSlashTmp: try container.decodeRustDefaulted(
                    Bool.self,
                    forKey: .excludeSlashTmp,
                    defaultValue: false
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dangerFullAccess:
            try container.encode(PolicyType.dangerFullAccess, forKey: .type)
        case let .readOnly(networkAccess):
            try container.encode(PolicyType.readOnly, forKey: .type)
            try container.encode(networkAccess, forKey: .networkAccess)
        case let .externalSandbox(networkAccess):
            try container.encode(PolicyType.externalSandbox, forKey: .type)
            try container.encode(networkAccess, forKey: .networkAccess)
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            try container.encode(PolicyType.workspaceWrite, forKey: .type)
            try container.encode(writableRoots, forKey: .writableRoots)
            try container.encode(networkAccess, forKey: .networkAccess)
            try container.encode(excludeTmpdirEnvVar, forKey: .excludeTmpdirEnvVar)
            try container.encode(excludeSlashTmp, forKey: .excludeSlashTmp)
        }
    }
}

extension AppServerSandboxPolicy {
    public init(core policy: SandboxPolicy) {
        switch policy {
        case .dangerFullAccess:
            self = .dangerFullAccess
        case .readOnly:
            self = .readOnly()
        case .readOnlyWithNetworkAccess:
            self = .readOnly(networkAccess: true)
        case let .externalSandbox(networkAccess):
            self = .externalSandbox(networkAccess: networkAccess)
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            self = .workspaceWrite(
                writableRoots: writableRoots.map(\.path),
                networkAccess: networkAccess,
                excludeTmpdirEnvVar: excludeTmpdirEnvVar,
                excludeSlashTmp: excludeSlashTmp
            )
        }
    }

    public var coreValue: SandboxPolicy {
        switch self {
        case .dangerFullAccess:
            return .dangerFullAccess
        case let .readOnly(networkAccess):
            return networkAccess ? .readOnlyWithNetworkAccess : .readOnly
        case let .externalSandbox(networkAccess):
            return .externalSandbox(networkAccess: networkAccess)
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            return .workspaceWrite(
                writableRoots: writableRoots.compactMap { try? AbsolutePath(absolutePath: $0) },
                networkAccess: networkAccess,
                excludeTmpdirEnvVar: excludeTmpdirEnvVar,
                excludeSlashTmp: excludeSlashTmp
            )
        }
    }
}

public typealias AppServerCommandExecSandboxPolicy = AppServerSandboxPolicy

public struct CommandExecParams: Equatable, Sendable {
    public let command: [String]
    public let processID: String?
    public let tty: Bool
    public let streamStdin: Bool
    public let streamStdoutStderr: Bool
    public let outputBytesCap: Int?
    public let disableOutputCap: Bool
    public let disableTimeout: Bool
    public let timeoutMs: Int64?
    public let cwd: String?
    public let env: [String: String?]?
    public let size: CommandExecTerminalSize?
    public let sandboxPolicy: AppServerCommandExecSandboxPolicy?
    public let permissionProfile: AppServerPermissionProfile?

    public init(
        command: [String],
        processID: String? = nil,
        tty: Bool = false,
        streamStdin: Bool = false,
        streamStdoutStderr: Bool = false,
        outputBytesCap: Int? = nil,
        disableOutputCap: Bool = false,
        disableTimeout: Bool = false,
        timeoutMs: Int64? = nil,
        cwd: String? = nil,
        env: [String: String?]? = nil,
        size: CommandExecTerminalSize? = nil,
        sandboxPolicy: AppServerCommandExecSandboxPolicy? = nil,
        permissionProfile: AppServerPermissionProfile? = nil
    ) {
        self.command = command
        self.processID = processID
        self.tty = tty
        self.streamStdin = streamStdin
        self.streamStdoutStderr = streamStdoutStderr
        self.outputBytesCap = outputBytesCap
        self.disableOutputCap = disableOutputCap
        self.disableTimeout = disableTimeout
        self.timeoutMs = timeoutMs
        self.cwd = cwd
        self.env = env
        self.size = size
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
    }
}

extension CommandExecParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case command
        case processID = "processId"
        case tty
        case streamStdin
        case streamStdoutStderr
        case outputBytesCap
        case disableOutputCap
        case disableTimeout
        case timeoutMs
        case cwd
        case env
        case size
        case sandboxPolicy
        case permissionProfile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            command: try container.decode([String].self, forKey: .command),
            processID: try container.decodeIfPresent(String.self, forKey: .processID),
            tty: try container.decodeRustDefaulted(Bool.self, forKey: .tty, defaultValue: false),
            streamStdin: try container.decodeRustDefaulted(Bool.self, forKey: .streamStdin, defaultValue: false),
            streamStdoutStderr: try container.decodeRustDefaulted(
                Bool.self,
                forKey: .streamStdoutStderr,
                defaultValue: false
            ),
            outputBytesCap: try container.decodeRustUsizeIfPresent(forKey: .outputBytesCap),
            disableOutputCap: try container.decodeRustDefaulted(
                Bool.self,
                forKey: .disableOutputCap,
                defaultValue: false
            ),
            disableTimeout: try container.decodeRustDefaulted(
                Bool.self,
                forKey: .disableTimeout,
                defaultValue: false
            ),
            timeoutMs: try container.decodeIfPresent(Int64.self, forKey: .timeoutMs),
            cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
            env: try container.decodeIfPresent([String: String?].self, forKey: .env),
            size: try container.decodeIfPresent(CommandExecTerminalSize.self, forKey: .size),
            sandboxPolicy: try container.decodeIfPresent(AppServerCommandExecSandboxPolicy.self, forKey: .sandboxPolicy),
            permissionProfile: try container.decodeIfPresent(AppServerPermissionProfile.self, forKey: .permissionProfile)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeNilOrValue(processID, forKey: .processID)
        if tty {
            try container.encode(tty, forKey: .tty)
        }
        if streamStdin {
            try container.encode(streamStdin, forKey: .streamStdin)
        }
        if streamStdoutStderr {
            try container.encode(streamStdoutStderr, forKey: .streamStdoutStderr)
        }
        try container.encodeNilOrValue(outputBytesCap, forKey: .outputBytesCap)
        if disableOutputCap {
            try container.encode(disableOutputCap, forKey: .disableOutputCap)
        }
        if disableTimeout {
            try container.encode(disableTimeout, forKey: .disableTimeout)
        }
        try container.encodeNilOrValue(timeoutMs, forKey: .timeoutMs)
        try container.encodeNilOrValue(cwd, forKey: .cwd)
        try container.encodeNilOrValue(env, forKey: .env)
        try container.encodeNilOrValue(size, forKey: .size)
        try container.encodeNilOrValue(sandboxPolicy, forKey: .sandboxPolicy)
        try container.encodeNilOrValue(permissionProfile, forKey: .permissionProfile)
    }
}

public struct CommandExecResponse: Equatable, Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct CommandExecWriteParams: Equatable, Sendable {
    public let processID: String
    public let deltaBase64: String?
    public let closeStdin: Bool

    public init(processID: String, deltaBase64: String? = nil, closeStdin: Bool = false) {
        self.processID = processID
        self.deltaBase64 = deltaBase64
        self.closeStdin = closeStdin
    }
}

extension CommandExecWriteParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case processID = "processId"
        case deltaBase64
        case closeStdin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            processID: try container.decode(String.self, forKey: .processID),
            deltaBase64: try container.decodeIfPresent(String.self, forKey: .deltaBase64),
            closeStdin: try container.decodeRustDefaulted(Bool.self, forKey: .closeStdin, defaultValue: false)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(processID, forKey: .processID)
        try container.encodeNilOrValue(deltaBase64, forKey: .deltaBase64)
        if closeStdin {
            try container.encode(closeStdin, forKey: .closeStdin)
        }
    }
}

public struct CommandExecWriteResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct CommandExecTerminateParams: Equatable, Codable, Sendable {
    public let processID: String

    private enum CodingKeys: String, CodingKey {
        case processID = "processId"
    }

    public init(processID: String) {
        self.processID = processID
    }
}

public struct CommandExecTerminateResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct CommandExecResizeParams: Equatable, Codable, Sendable {
    public let processID: String
    public let size: CommandExecTerminalSize

    private enum CodingKeys: String, CodingKey {
        case processID = "processId"
        case size
    }

    public init(processID: String, size: CommandExecTerminalSize) {
        self.processID = processID
        self.size = size
    }
}

public struct CommandExecResizeResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum CommandExecOutputStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
}

public struct CommandExecOutputDeltaNotification: Equatable, Codable, Sendable {
    public let processID: String
    public let stream: CommandExecOutputStream
    public let deltaBase64: String
    public let capReached: Bool

    private enum CodingKeys: String, CodingKey {
        case processID = "processId"
        case stream
        case deltaBase64
        case capReached
    }

    public init(processID: String, stream: CommandExecOutputStream, deltaBase64: String, capReached: Bool) {
        self.processID = processID
        self.stream = stream
        self.deltaBase64 = deltaBase64
        self.capReached = capReached
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
