extension WindowsSandboxSetupMode: Codable {}

public struct WindowsWorldWritableWarningNotification: Equatable, Codable, Sendable {
    public let samplePaths: [String]
    public let extraCount: Int
    public let failedScan: Bool

    public init(samplePaths: [String], extraCount: Int, failedScan: Bool) {
        self.samplePaths = samplePaths
        self.extraCount = extraCount
        self.failedScan = failedScan
    }
}

public enum WindowsSandboxReadiness: String, Codable, Equatable, Sendable {
    case ready
    case notConfigured
    case updateRequired
}

public struct WindowsSandboxSetupStartParams: Equatable, Sendable {
    public let mode: WindowsSandboxSetupMode
    public let cwd: AbsolutePath?

    public init(mode: WindowsSandboxSetupMode, cwd: AbsolutePath? = nil) {
        self.mode = mode
        self.cwd = cwd
    }
}

extension WindowsSandboxSetupStartParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(WindowsSandboxSetupMode.self, forKey: .mode)
        cwd = try container.decodeIfPresent(AbsolutePath.self, forKey: .cwd)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeNilOrValue(cwd, forKey: .cwd)
    }
}

public struct WindowsSandboxSetupStartResponse: Equatable, Codable, Sendable {
    public let started: Bool

    public init(started: Bool) {
        self.started = started
    }
}

public struct WindowsSandboxReadinessResponse: Equatable, Codable, Sendable {
    public let status: WindowsSandboxReadiness

    public init(status: WindowsSandboxReadiness) {
        self.status = status
    }
}

public struct WindowsSandboxSetupCompletedNotification: Equatable, Sendable {
    public let mode: WindowsSandboxSetupMode
    public let success: Bool
    public let error: String?

    public init(mode: WindowsSandboxSetupMode, success: Bool, error: String? = nil) {
        self.mode = mode
        self.success = success
        self.error = error
    }
}

extension WindowsSandboxSetupCompletedNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case success
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(WindowsSandboxSetupMode.self, forKey: .mode)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(success, forKey: .success)
        try container.encodeNilOrValue(error, forKey: .error)
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
