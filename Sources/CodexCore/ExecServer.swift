import Darwin
import Foundation

public let codexExecServerRemoteBearerTokenEnvironmentVariable = "CODEX_EXEC_SERVER_REMOTE_BEARER_TOKEN"

public let defaultExecServerListenURL = "ws://127.0.0.1:0"

public let execServerInitializeMethod = "initialize"
public let execServerInitializedMethod = "initialized"
public let execServerProcessStartMethod = "process/start"
public let execServerProcessReadMethod = "process/read"
public let execServerProcessWriteMethod = "process/write"
public let execServerProcessTerminateMethod = "process/terminate"
public let execServerProcessOutputDeltaMethod = "process/output"
public let execServerProcessExitedMethod = "process/exited"
public let execServerProcessClosedMethod = "process/closed"
public let execServerFsReadFileMethod = "fs/readFile"
public let execServerFsWriteFileMethod = "fs/writeFile"
public let execServerFsCreateDirectoryMethod = "fs/createDirectory"
public let execServerFsGetMetadataMethod = "fs/getMetadata"
public let execServerFsReadDirectoryMethod = "fs/readDirectory"
public let execServerFsRemoveMethod = "fs/remove"
public let execServerFsCopyMethod = "fs/copy"
public let execServerHttpRequestMethod = "http/request"
public let execServerHttpRequestBodyDeltaMethod = "http/request/bodyDelta"

public struct ExecServerByteChunk: Codable, Equatable, Sendable {
    public let bytes: [UInt8]

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public init(data: Data) {
        self.bytes = Array(data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encoded = try container.decode(String.self)
        guard let data = Data(base64Encoded: encoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid base64 byte chunk"
            )
        }
        self.bytes = Array(data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Data(bytes).base64EncodedString())
    }
}

public enum WindowsSandboxLevel: String, Codable, Equatable, Sendable {
    case disabled
    case restrictedToken = "restricted-token"
    case elevated
}

public struct FileSystemSandboxContext: Codable, Equatable, Sendable {
    public let permissions: PermissionProfile
    public let cwd: AbsolutePath?
    public let windowsSandboxLevel: WindowsSandboxLevel
    public let windowsSandboxPrivateDesktop: Bool
    public let useLegacyLandlock: Bool

    private enum CodingKeys: String, CodingKey {
        case permissions
        case cwd
        case windowsSandboxLevel
        case windowsSandboxPrivateDesktop
        case useLegacyLandlock
    }

    public init(
        permissions: PermissionProfile,
        cwd: AbsolutePath? = nil,
        windowsSandboxLevel: WindowsSandboxLevel = .disabled,
        windowsSandboxPrivateDesktop: Bool = false,
        useLegacyLandlock: Bool = false
    ) {
        self.permissions = permissions
        self.cwd = cwd
        self.windowsSandboxLevel = windowsSandboxLevel
        self.windowsSandboxPrivateDesktop = windowsSandboxPrivateDesktop
        self.useLegacyLandlock = useLegacyLandlock
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try container.decode(PermissionProfile.self, forKey: .permissions)
        cwd = try container.decodeIfPresent(AbsolutePath.self, forKey: .cwd)
        windowsSandboxLevel = try container.decode(WindowsSandboxLevel.self, forKey: .windowsSandboxLevel)
        windowsSandboxPrivateDesktop = try container.decodeIfPresent(Bool.self, forKey: .windowsSandboxPrivateDesktop) ?? false
        useLegacyLandlock = try container.decodeIfPresent(Bool.self, forKey: .useLegacyLandlock) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encode(windowsSandboxLevel, forKey: .windowsSandboxLevel)
        try container.encode(windowsSandboxPrivateDesktop, forKey: .windowsSandboxPrivateDesktop)
        try container.encode(useLegacyLandlock, forKey: .useLegacyLandlock)
    }
}

public struct ExecServerInitializeParams: Codable, Equatable, Sendable {
    public let clientName: String
    public let resumeSessionId: String?

    public init(clientName: String, resumeSessionId: String? = nil) {
        self.clientName = clientName
        self.resumeSessionId = resumeSessionId
    }
}

public struct ExecServerInitializeResponse: Codable, Equatable, Sendable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ExecServerExecEnvPolicy: Codable, Equatable, Sendable {
    public let inherit: ShellEnvironmentPolicyInherit
    public let ignoreDefaultExcludes: Bool
    public let exclude: [String]
    public let set: [String: String]
    public let includeOnly: [String]

    public init(
        inherit: ShellEnvironmentPolicyInherit,
        ignoreDefaultExcludes: Bool,
        exclude: [String],
        set: [String: String],
        includeOnly: [String]
    ) {
        self.inherit = inherit
        self.ignoreDefaultExcludes = ignoreDefaultExcludes
        self.exclude = exclude
        self.set = set
        self.includeOnly = includeOnly
    }
}

public struct ExecServerExecParams: Codable, Equatable, Sendable {
    public let processId: String
    public let argv: [String]
    public let cwd: String
    public let envPolicy: ExecServerExecEnvPolicy?
    public let env: [String: String]
    public let tty: Bool
    public let pipeStdin: Bool
    public let arg0: String?

    public init(
        processId: String,
        argv: [String],
        cwd: String,
        envPolicy: ExecServerExecEnvPolicy? = nil,
        env: [String: String],
        tty: Bool,
        pipeStdin: Bool = false,
        arg0: String? = nil
    ) {
        self.processId = processId
        self.argv = argv
        self.cwd = cwd
        self.envPolicy = envPolicy
        self.env = env
        self.tty = tty
        self.pipeStdin = pipeStdin
        self.arg0 = arg0
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processId = try container.decode(String.self, forKey: .processId)
        argv = try container.decode([String].self, forKey: .argv)
        cwd = try container.decode(String.self, forKey: .cwd)
        envPolicy = try container.decodeIfPresent(ExecServerExecEnvPolicy.self, forKey: .envPolicy)
        env = try container.decode([String: String].self, forKey: .env)
        tty = try container.decode(Bool.self, forKey: .tty)
        pipeStdin = try container.decodeIfPresent(Bool.self, forKey: .pipeStdin) ?? false
        arg0 = try container.decodeIfPresent(String.self, forKey: .arg0)
    }
}

public struct ExecServerExecResponse: Codable, Equatable, Sendable {
    public let processId: String

    public init(processId: String) {
        self.processId = processId
    }
}

public struct ExecServerReadParams: Codable, Equatable, Sendable {
    public let processId: String
    public let afterSeq: UInt64?
    public let maxBytes: Int?
    public let waitMs: UInt64?

    public init(processId: String, afterSeq: UInt64? = nil, maxBytes: Int? = nil, waitMs: UInt64? = nil) {
        self.processId = processId
        self.afterSeq = afterSeq
        self.maxBytes = maxBytes
        self.waitMs = waitMs
    }
}

public enum ExecServerOutputStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
    case pty
}

public struct ExecServerProcessOutputChunk: Codable, Equatable, Sendable {
    public let seq: UInt64
    public let stream: ExecServerOutputStream
    public let chunk: ExecServerByteChunk

    public init(seq: UInt64, stream: ExecServerOutputStream, chunk: ExecServerByteChunk) {
        self.seq = seq
        self.stream = stream
        self.chunk = chunk
    }
}

public struct ExecServerReadResponse: Codable, Equatable, Sendable {
    public let chunks: [ExecServerProcessOutputChunk]
    public let nextSeq: UInt64
    public let exited: Bool
    public let exitCode: Int32?
    public let closed: Bool
    public let failure: String?

    public init(
        chunks: [ExecServerProcessOutputChunk],
        nextSeq: UInt64,
        exited: Bool,
        exitCode: Int32? = nil,
        closed: Bool,
        failure: String? = nil
    ) {
        self.chunks = chunks
        self.nextSeq = nextSeq
        self.exited = exited
        self.exitCode = exitCode
        self.closed = closed
        self.failure = failure
    }
}

public struct ExecServerWriteParams: Codable, Equatable, Sendable {
    public let processId: String
    public let chunk: ExecServerByteChunk

    public init(processId: String, chunk: ExecServerByteChunk) {
        self.processId = processId
        self.chunk = chunk
    }
}

public enum ExecServerWriteStatus: String, Codable, Equatable, Sendable {
    case accepted
    case unknownProcess
    case stdinClosed
    case starting
}

public struct ExecServerWriteResponse: Codable, Equatable, Sendable {
    public let status: ExecServerWriteStatus

    public init(status: ExecServerWriteStatus) {
        self.status = status
    }
}

public struct ExecServerTerminateParams: Codable, Equatable, Sendable {
    public let processId: String

    public init(processId: String) {
        self.processId = processId
    }
}

public struct ExecServerTerminateResponse: Codable, Equatable, Sendable {
    public let running: Bool

    public init(running: Bool) {
        self.running = running
    }
}

public struct ExecServerFsReadFileParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.sandbox = sandbox
    }
}

public struct ExecServerFsReadFileResponse: Codable, Equatable, Sendable {
    public let dataBase64: String

    public init(dataBase64: String) {
        self.dataBase64 = dataBase64
    }
}

public struct ExecServerFsWriteFileParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let dataBase64: String
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, dataBase64: String, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.dataBase64 = dataBase64
        self.sandbox = sandbox
    }
}

public struct ExecServerFsWriteFileResponse: Codable, Equatable, Sendable {
    public init() {}
}

public struct ExecServerFsCreateDirectoryParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let recursive: Bool?
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, recursive: Bool? = nil, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.recursive = recursive
        self.sandbox = sandbox
    }
}

public struct ExecServerFsCreateDirectoryResponse: Codable, Equatable, Sendable {
    public init() {}
}

public struct ExecServerFsGetMetadataParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.sandbox = sandbox
    }
}

public struct ExecServerFsGetMetadataResponse: Codable, Equatable, Sendable {
    public let isDirectory: Bool
    public let isFile: Bool
    public let isSymlink: Bool
    public let createdAtMs: Int64
    public let modifiedAtMs: Int64

    public init(isDirectory: Bool, isFile: Bool, isSymlink: Bool, createdAtMs: Int64, modifiedAtMs: Int64) {
        self.isDirectory = isDirectory
        self.isFile = isFile
        self.isSymlink = isSymlink
        self.createdAtMs = createdAtMs
        self.modifiedAtMs = modifiedAtMs
    }
}

public struct ExecServerFsReadDirectoryParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.sandbox = sandbox
    }
}

public struct ExecServerFsReadDirectoryEntry: Codable, Equatable, Sendable {
    public let fileName: String
    public let isDirectory: Bool
    public let isFile: Bool

    public init(fileName: String, isDirectory: Bool, isFile: Bool) {
        self.fileName = fileName
        self.isDirectory = isDirectory
        self.isFile = isFile
    }
}

public struct ExecServerFsReadDirectoryResponse: Codable, Equatable, Sendable {
    public let entries: [ExecServerFsReadDirectoryEntry]

    public init(entries: [ExecServerFsReadDirectoryEntry]) {
        self.entries = entries
    }
}

public struct ExecServerFsRemoveParams: Codable, Equatable, Sendable {
    public let path: AbsolutePath
    public let recursive: Bool?
    public let force: Bool?
    public let sandbox: FileSystemSandboxContext?

    public init(path: AbsolutePath, recursive: Bool? = nil, force: Bool? = nil, sandbox: FileSystemSandboxContext? = nil) {
        self.path = path
        self.recursive = recursive
        self.force = force
        self.sandbox = sandbox
    }
}

public struct ExecServerFsRemoveResponse: Codable, Equatable, Sendable {
    public init() {}
}

public struct ExecServerFsCopyParams: Codable, Equatable, Sendable {
    public let sourcePath: AbsolutePath
    public let destinationPath: AbsolutePath
    public let recursive: Bool
    public let sandbox: FileSystemSandboxContext?

    public init(sourcePath: AbsolutePath, destinationPath: AbsolutePath, recursive: Bool, sandbox: FileSystemSandboxContext? = nil) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.recursive = recursive
        self.sandbox = sandbox
    }
}

public struct ExecServerFsCopyResponse: Codable, Equatable, Sendable {
    public init() {}
}

public struct ExecServerHttpHeader: Codable, Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ExecServerHttpRequestParams: Codable, Equatable, Sendable {
    public let method: String
    public let url: String
    public let headers: [ExecServerHttpHeader]
    public let body: ExecServerByteChunk?
    public let timeoutMs: UInt64?
    public let requestId: String
    public let streamResponse: Bool

    private enum CodingKeys: String, CodingKey {
        case method
        case url
        case headers
        case body = "bodyBase64"
        case timeoutMs
        case requestId
        case streamResponse
    }

    public init(
        method: String,
        url: String,
        headers: [ExecServerHttpHeader] = [],
        body: ExecServerByteChunk? = nil,
        timeoutMs: UInt64? = nil,
        requestId: String,
        streamResponse: Bool = false
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutMs = timeoutMs
        self.requestId = requestId
        self.streamResponse = streamResponse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)
        headers = try container.decodeIfPresent([ExecServerHttpHeader].self, forKey: .headers) ?? []
        body = try container.decodeIfPresent(ExecServerByteChunk.self, forKey: .body)
        timeoutMs = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs)
        requestId = try container.decode(String.self, forKey: .requestId)
        streamResponse = try container.decodeIfPresent(Bool.self, forKey: .streamResponse) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        try container.encode(url, forKey: .url)
        try container.encode(headers, forKey: .headers)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(timeoutMs, forKey: .timeoutMs)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(streamResponse, forKey: .streamResponse)
    }
}

public struct ExecServerHttpRequestResponse: Codable, Equatable, Sendable {
    public let status: UInt16
    public let headers: [ExecServerHttpHeader]
    public let body: ExecServerByteChunk

    private enum CodingKeys: String, CodingKey {
        case status
        case headers
        case body = "bodyBase64"
    }

    public init(status: UInt16, headers: [ExecServerHttpHeader], body: ExecServerByteChunk) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct ExecServerHttpRequestBodyDeltaNotification: Codable, Equatable, Sendable {
    public let requestId: String
    public let seq: UInt64
    public let delta: ExecServerByteChunk
    public let done: Bool
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case requestId
        case seq
        case delta = "deltaBase64"
        case done
        case error
    }

    public init(
        requestId: String,
        seq: UInt64,
        delta: ExecServerByteChunk,
        done: Bool = false,
        error: String? = nil
    ) {
        self.requestId = requestId
        self.seq = seq
        self.delta = delta
        self.done = done
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)
        seq = try container.decode(UInt64.self, forKey: .seq)
        delta = try container.decode(ExecServerByteChunk.self, forKey: .delta)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

public struct ExecServerOutputDeltaNotification: Codable, Equatable, Sendable {
    public let processId: String
    public let seq: UInt64
    public let stream: ExecServerOutputStream
    public let chunk: ExecServerByteChunk

    public init(processId: String, seq: UInt64, stream: ExecServerOutputStream, chunk: ExecServerByteChunk) {
        self.processId = processId
        self.seq = seq
        self.stream = stream
        self.chunk = chunk
    }
}

public struct ExecServerExitedNotification: Codable, Equatable, Sendable {
    public let processId: String
    public let seq: UInt64
    public let exitCode: Int32

    public init(processId: String, seq: UInt64, exitCode: Int32) {
        self.processId = processId
        self.seq = seq
        self.exitCode = exitCode
    }
}

public struct ExecServerClosedNotification: Codable, Equatable, Sendable {
    public let processId: String
    public let seq: UInt64

    public init(processId: String, seq: UInt64) {
        self.processId = processId
        self.seq = seq
    }
}

public enum ExecServerListenTransport: Equatable, Sendable {
    case webSocket(host: String, port: UInt16)
    case stdio
}

public enum ExecServerListenURLParseError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedListenURL(String)
    case invalidWebSocketListenURL(String)

    public var description: String {
        switch self {
        case let .unsupportedListenURL(listenURL):
            return "unsupported --listen URL `\(listenURL)`; expected `ws://IP:PORT` or `stdio`"
        case let .invalidWebSocketListenURL(listenURL):
            return "invalid websocket --listen URL `\(listenURL)`; expected `ws://IP:PORT`"
        }
    }
}

public enum ExecServerConfigurationError: Error, CustomStringConvertible, Equatable, Sendable {
    case executorRegistryConfig(String)
    case executorRegistryAuth(String)

    public var description: String {
        switch self {
        case let .executorRegistryConfig(message):
            return "executor registry configuration error: \(message)"
        case let .executorRegistryAuth(message):
            return "executor registry authentication error: \(message)"
        }
    }
}

public struct ExecServerRemoteExecutorConfiguration: Equatable, Sendable {
    public let baseURL: String
    public let executorID: String
    public let name: String
    public let bearerToken: String

    public init(
        baseURL: String,
        executorID: String,
        name: String = "codex-exec-server",
        bearerToken: String
    ) throws {
        self.baseURL = try Self.normalizeBaseURL(baseURL)
        self.executorID = try Self.normalizeExecutorID(executorID)
        self.name = name
        self.bearerToken = try Self.normalizeBearerToken(bearerToken)
    }

    public static func fromEnvironment(
        baseURL: String,
        executorID: String,
        name: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        guard let bearerToken = environment[codexExecServerRemoteBearerTokenEnvironmentVariable] else {
            throw ExecServerConfigurationError.executorRegistryAuth(
                "executor registry bearer token environment variable `\(codexExecServerRemoteBearerTokenEnvironmentVariable)` is not set"
            )
        }
        return try Self(
            baseURL: baseURL,
            executorID: executorID,
            name: name ?? "codex-exec-server",
            bearerToken: bearerToken
        )
    }

    private static func normalizeBaseURL(_ baseURL: String) throws -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryConfig("executor registry base URL is required")
        }
        return trimmed
    }

    private static func normalizeExecutorID(_ executorID: String) throws -> String {
        let trimmed = executorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryConfig(
                "executor id is required for remote exec-server registration"
            )
        }
        return trimmed
    }

    private static func normalizeBearerToken(_ bearerToken: String) throws -> String {
        let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryAuth(
                "executor registry bearer token environment variable `\(codexExecServerRemoteBearerTokenEnvironmentVariable)` is empty"
            )
        }
        return trimmed
    }
}

public enum ExecServerListenURLParser {
    public static func parse(_ listenURL: String) throws -> ExecServerListenTransport {
        if listenURL == "stdio" || listenURL == "stdio://" {
            return .stdio
        }

        guard listenURL.hasPrefix("ws://") else {
            throw ExecServerListenURLParseError.unsupportedListenURL(listenURL)
        }
        guard let components = URLComponents(string: listenURL),
              components.scheme == "ws",
              let rawHost = components.host,
              let port = components.port,
              port >= 0,
              port <= UInt16.max,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let host = normalizedHost(rawHost),
              isIPAddress(host)
        else {
            throw ExecServerListenURLParseError.invalidWebSocketListenURL(listenURL)
        }

        return .webSocket(host: host, port: UInt16(port))
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &ipv6) } == 1
    }

    private static func normalizedHost(_ host: String) -> String? {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }
}
