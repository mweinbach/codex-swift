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
    public var chatgptBaseURL: String
    public var appsMcpPathOverride: String?
    public var appsEnabled: Bool
    public var configuredMcpServers: [String: McpServerConfig]
    public var builtinMcpServers: [BuiltinMcpServer]

    public init(
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        appsMcpPathOverride: String? = nil,
        appsEnabled: Bool = false,
        configuredMcpServers: [String: McpServerConfig],
        builtinMcpServers: [BuiltinMcpServer]
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.appsMcpPathOverride = appsMcpPathOverride
        self.appsEnabled = appsEnabled
        self.configuredMcpServers = configuredMcpServers
        self.builtinMcpServers = builtinMcpServers
    }

    public func hostOwnedCodexAppsEnabled(usesCodexBackend: Bool) -> Bool {
        appsEnabled && usesCodexBackend
    }

    public func effectiveMcpServers(
        usesCodexBackend: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: EffectiveMcpServer] {
        var servers = Dictionary(uniqueKeysWithValues: configuredMcpServers.map { name, server in
            (name, EffectiveMcpServer.configured(server))
        })
        for builtinServer in builtinMcpServers {
            servers[builtinServer.name] = .builtin(builtinServer)
        }
        if hostOwnedCodexAppsEnabled(usesCodexBackend: usesCodexBackend) {
            servers[codexAppsMCPServerName] = .configured(codexAppsMcpServerConfig(environment: environment))
        } else {
            servers.removeValue(forKey: codexAppsMCPServerName)
        }
        return servers
    }

    public func codexAppsMcpServerConfig(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> McpServerConfig {
        McpServerConfig(
            transport: .streamableHttp(
                url: Self.codexAppsMcpURL(
                    baseURL: chatgptBaseURL,
                    appsMcpPathOverride: appsMcpPathOverride
                ),
                bearerTokenEnvVar: Self.codexAppsMcpBearerTokenEnvVar(environment: environment),
                httpHeaders: nil,
                envHttpHeaders: nil
            ),
            startupTimeoutSec: 30
        )
    }

    public static func codexAppsMcpURL(
        baseURL: String,
        appsMcpPathOverride: String?
    ) -> String {
        var normalizedBaseURL = baseURL
        while normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }
        if (normalizedBaseURL.hasPrefix("https://chatgpt.com")
            || normalizedBaseURL.hasPrefix("https://chat.openai.com"))
            && !normalizedBaseURL.contains("/backend-api")
        {
            normalizedBaseURL += "/backend-api"
        }

        let defaultPath: String
        if normalizedBaseURL.contains("/backend-api") {
            defaultPath = "wham/apps"
        } else if normalizedBaseURL.contains("/api/codex") {
            defaultPath = "apps"
        } else {
            normalizedBaseURL += "/api/codex"
            defaultPath = "apps"
        }

        var path = appsMcpPathOverride ?? defaultPath
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        return "\(normalizedBaseURL)/\(path)"
    }

    private static func codexAppsMcpBearerTokenEnvVar(environment: [String: String]) -> String? {
        guard let value = environment["CODEX_CONNECTORS_TOKEN"],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return "CODEX_CONNECTORS_TOKEN"
    }
}

public enum EffectiveMcpServer: Equatable, Sendable {
    case configured(McpServerConfig)
    case builtin(BuiltinMcpServer)

    public var configuredConfig: McpServerConfig? {
        switch self {
        case let .configured(config):
            return config
        case .builtin:
            return nil
        }
    }

    public var builtinServer: BuiltinMcpServer? {
        switch self {
        case .configured:
            return nil
        case let .builtin(server):
            return server
        }
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
