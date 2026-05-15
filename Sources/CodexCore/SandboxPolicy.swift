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
    case readOnlyWithNetworkAccess
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
        case .readOnly, .readOnlyWithNetworkAccess, .workspaceWrite:
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
        case .readOnlyWithNetworkAccess:
            return true
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
            self = try container.decodeRustDefaulted(Bool.self, forKey: .networkAccess, defaultValue: false)
                ? .readOnlyWithNetworkAccess
                : .readOnly
        case .externalSandbox:
            self = .externalSandbox(
                networkAccess: try container.decodeRustDefaulted(
                    NetworkAccess.self,
                    forKey: .networkAccess,
                    defaultValue: .restricted
                )
            )
        case .workspaceWrite:
            self = .workspaceWrite(
                writableRoots: try container.decodeRustDefaulted(
                    [AbsolutePath].self,
                    forKey: .writableRoots,
                    defaultValue: []
                ),
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
        case .readOnly:
            try container.encode(PolicyType.readOnly, forKey: .type)
        case .readOnlyWithNetworkAccess:
            try container.encode(PolicyType.readOnly, forKey: .type)
            try container.encode(true, forKey: .networkAccess)
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
