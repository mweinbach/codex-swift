import Foundation

public enum NetworkAccess: String, Codable, Equatable, Sendable {
    case restricted
    case enabled

    public var isEnabled: Bool {
        self == .enabled
    }
}

public enum SandboxPolicy: Equatable, Sendable {
    case dangerFullAccess
    case readOnly
    case externalSandbox(networkAccess: NetworkAccess)
    case workspaceWrite(
        writableRoots: [AbsolutePath],
        networkAccess: Bool,
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    )

    public static func newReadOnlyPolicy() -> SandboxPolicy {
        .readOnly
    }

    public static func newWorkspaceWritePolicy() -> SandboxPolicy {
        .workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        )
    }

    public static func fromSandboxMode(_ mode: SandboxMode) -> SandboxPolicy {
        switch mode {
        case .dangerFullAccess:
            return .dangerFullAccess
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .newWorkspaceWritePolicy()
        }
    }

    public var hasFullDiskReadAccess: Bool {
        true
    }

    public var hasFullDiskWriteAccess: Bool {
        switch self {
        case .dangerFullAccess, .externalSandbox:
            return true
        case .readOnly, .workspaceWrite:
            return false
        }
    }

    public var hasFullNetworkAccess: Bool {
        switch self {
        case .dangerFullAccess:
            return true
        case let .externalSandbox(networkAccess):
            return networkAccess.isEnabled
        case .readOnly:
            return false
        case let .workspaceWrite(_, networkAccess, _, _):
            return networkAccess
        }
    }
}

extension SandboxPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case networkAccess = "network_access"
        case writableRoots = "writable_roots"
        case excludeTmpdirEnvVar = "exclude_tmpdir_env_var"
        case excludeSlashTmp = "exclude_slash_tmp"
    }

    private enum PolicyType: String, Codable {
        case dangerFullAccess = "danger-full-access"
        case readOnly = "read-only"
        case externalSandbox = "external-sandbox"
        case workspaceWrite = "workspace-write"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PolicyType.self, forKey: .type) {
        case .dangerFullAccess:
            self = .dangerFullAccess
        case .readOnly:
            self = .readOnly
        case .externalSandbox:
            self = .externalSandbox(networkAccess: try container.decodeIfPresent(NetworkAccess.self, forKey: .networkAccess) ?? .restricted)
        case .workspaceWrite:
            self = .workspaceWrite(
                writableRoots: try container.decodeIfPresent([AbsolutePath].self, forKey: .writableRoots) ?? [],
                networkAccess: try container.decodeIfPresent(Bool.self, forKey: .networkAccess) ?? false,
                excludeTmpdirEnvVar: try container.decodeIfPresent(Bool.self, forKey: .excludeTmpdirEnvVar) ?? false,
                excludeSlashTmp: try container.decodeIfPresent(Bool.self, forKey: .excludeSlashTmp) ?? false
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dangerFullAccess:
            try container.encode(PolicyType.dangerFullAccess, forKey: .type)
        case .readOnly:
            try container.encode(PolicyType.readOnly, forKey: .type)
        case let .externalSandbox(networkAccess):
            try container.encode(PolicyType.externalSandbox, forKey: .type)
            try container.encode(networkAccess, forKey: .networkAccess)
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            try container.encode(PolicyType.workspaceWrite, forKey: .type)
            if !writableRoots.isEmpty {
                try container.encode(writableRoots, forKey: .writableRoots)
            }
            try container.encode(networkAccess, forKey: .networkAccess)
            try container.encode(excludeTmpdirEnvVar, forKey: .excludeTmpdirEnvVar)
            try container.encode(excludeSlashTmp, forKey: .excludeSlashTmp)
        }
    }
}
