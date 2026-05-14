import Foundation

public enum ExternalAgentConfigMigrationItemType: String, Codable, Equatable, Sendable {
    case agentsMd = "AGENTS_MD"
    case config = "CONFIG"
    case skills = "SKILLS"
    case plugins = "PLUGINS"
    case mcpServerConfig = "MCP_SERVER_CONFIG"
    case subagents = "SUBAGENTS"
    case hooks = "HOOKS"
    case commands = "COMMANDS"
    case sessions = "SESSIONS"
}

public struct ExternalAgentPluginsMigration: Equatable, Codable, Sendable {
    public let marketplaceName: String
    public let pluginNames: [String]

    public init(marketplaceName: String, pluginNames: [String]) {
        self.marketplaceName = marketplaceName
        self.pluginNames = pluginNames
    }
}

public struct ExternalAgentSessionMigration: Equatable, Codable, Sendable {
    public let path: String
    public let cwd: String
    public let title: String?

    public init(path: String, cwd: String, title: String? = nil) {
        self.path = path
        self.cwd = cwd
        self.title = title
    }
}

public struct ExternalAgentMcpServerMigration: Equatable, Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ExternalAgentHookMigration: Equatable, Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ExternalAgentSubagentMigration: Equatable, Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ExternalAgentCommandMigration: Equatable, Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ExternalAgentMigrationDetails: Equatable, Sendable {
    public let plugins: [ExternalAgentPluginsMigration]
    public let sessions: [ExternalAgentSessionMigration]
    public let mcpServers: [ExternalAgentMcpServerMigration]
    public let hooks: [ExternalAgentHookMigration]
    public let subagents: [ExternalAgentSubagentMigration]
    public let commands: [ExternalAgentCommandMigration]

    public init(
        plugins: [ExternalAgentPluginsMigration] = [],
        sessions: [ExternalAgentSessionMigration] = [],
        mcpServers: [ExternalAgentMcpServerMigration] = [],
        hooks: [ExternalAgentHookMigration] = [],
        subagents: [ExternalAgentSubagentMigration] = [],
        commands: [ExternalAgentCommandMigration] = []
    ) {
        self.plugins = plugins
        self.sessions = sessions
        self.mcpServers = mcpServers
        self.hooks = hooks
        self.subagents = subagents
        self.commands = commands
    }
}

extension ExternalAgentMigrationDetails: Codable {
    private enum CodingKeys: String, CodingKey {
        case plugins
        case sessions
        case mcpServers
        case hooks
        case subagents
        case commands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            plugins: try container.decodeIfPresent([ExternalAgentPluginsMigration].self, forKey: .plugins) ?? [],
            sessions: try container.decodeIfPresent([ExternalAgentSessionMigration].self, forKey: .sessions) ?? [],
            mcpServers: try container.decodeIfPresent([ExternalAgentMcpServerMigration].self, forKey: .mcpServers) ?? [],
            hooks: try container.decodeIfPresent([ExternalAgentHookMigration].self, forKey: .hooks) ?? [],
            subagents: try container.decodeIfPresent([ExternalAgentSubagentMigration].self, forKey: .subagents) ?? [],
            commands: try container.decodeIfPresent([ExternalAgentCommandMigration].self, forKey: .commands) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plugins, forKey: .plugins)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(mcpServers, forKey: .mcpServers)
        try container.encode(hooks, forKey: .hooks)
        try container.encode(subagents, forKey: .subagents)
        try container.encode(commands, forKey: .commands)
    }
}

public struct ExternalAgentConfigMigrationItem: Equatable, Sendable {
    public let itemType: ExternalAgentConfigMigrationItemType
    public let description: String
    public let cwd: String?
    public let details: ExternalAgentMigrationDetails?

    public init(
        itemType: ExternalAgentConfigMigrationItemType,
        description: String,
        cwd: String? = nil,
        details: ExternalAgentMigrationDetails? = nil
    ) {
        self.itemType = itemType
        self.description = description
        self.cwd = cwd
        self.details = details
    }
}

extension ExternalAgentConfigMigrationItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case itemType
        case description
        case cwd
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            itemType: try container.decode(ExternalAgentConfigMigrationItemType.self, forKey: .itemType),
            description: try container.decode(String.self, forKey: .description),
            cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
            details: try container.decodeIfPresent(ExternalAgentMigrationDetails.self, forKey: .details)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(description, forKey: .description)
        try container.encodeNilOrValue(cwd, forKey: .cwd)
        try container.encodeNilOrValue(details, forKey: .details)
    }
}

public struct ExternalAgentConfigDetectResponse: Equatable, Codable, Sendable {
    public let items: [ExternalAgentConfigMigrationItem]

    public init(items: [ExternalAgentConfigMigrationItem]) {
        self.items = items
    }
}

public struct ExternalAgentConfigDetectParams: Equatable, Sendable {
    public let includeHome: Bool
    public let cwds: [String]?

    public init(includeHome: Bool = false, cwds: [String]? = nil) {
        self.includeHome = includeHome
        self.cwds = cwds
    }
}

extension ExternalAgentConfigDetectParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case includeHome
        case cwds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeHome = try container.decodeIfPresent(Bool.self, forKey: .includeHome) ?? false
        cwds = try container.decodeIfPresent([String].self, forKey: .cwds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if includeHome {
            try container.encode(includeHome, forKey: .includeHome)
        }
        try container.encodeNilOrValue(cwds, forKey: .cwds)
    }
}

public struct ExternalAgentConfigImportParams: Equatable, Codable, Sendable {
    public let migrationItems: [ExternalAgentConfigMigrationItem]

    public init(migrationItems: [ExternalAgentConfigMigrationItem]) {
        self.migrationItems = migrationItems
    }
}

public struct ExternalAgentConfigImportResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ExternalAgentConfigImportCompletedNotification: Equatable, Codable, Sendable {
    public init() {}
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
