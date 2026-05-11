import Foundation

public let memoriesMcpServerName = "memories"

public enum BuiltinMcpServer: Equatable, Hashable, Sendable {
    case memories

    public var name: String {
        metadata.name
    }

    public var supportsParallelToolCalls: Bool {
        metadata.supportsParallelToolCalls
    }

    public var pollutesMemory: Bool {
        metadata.pollutesMemory
    }

    private var metadata: BuiltinMcpServerMetadata {
        switch self {
        case .memories:
            return BuiltinMcpServerMetadata(
                name: memoriesMcpServerName,
                supportsParallelToolCalls: true,
                pollutesMemory: false
            )
        }
    }
}

public struct BuiltinMcpServerOptions: Equatable, Sendable {
    public var memoriesEnabled: Bool

    public init(memoriesEnabled: Bool) {
        self.memoriesEnabled = memoriesEnabled
    }
}

public struct RuntimeMcpConfig: Equatable, Sendable {
    public var configuredMcpServers: [String: McpServerConfig]
    public var builtinMcpServers: [BuiltinMcpServer]

    public init(
        configuredMcpServers: [String: McpServerConfig],
        builtinMcpServers: [BuiltinMcpServer]
    ) {
        self.configuredMcpServers = configuredMcpServers
        self.builtinMcpServers = builtinMcpServers
    }
}

public func enabledBuiltinMcpServers(options: BuiltinMcpServerOptions) -> [BuiltinMcpServer] {
    var servers: [BuiltinMcpServer] = []
    if options.memoriesEnabled {
        servers.append(.memories)
    }
    return servers
}

private struct BuiltinMcpServerMetadata {
    var name: String
    var supportsParallelToolCalls: Bool
    var pollutesMemory: Bool
}
