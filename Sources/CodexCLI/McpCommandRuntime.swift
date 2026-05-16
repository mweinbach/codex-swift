import CodexCore
import Foundation

public enum McpCommandRuntime {
    public struct Dependencies {
        public var findCodexHome: @Sendable () throws -> URL
        public var loadConfig: @Sendable (URL, CliConfigOverrides) throws -> CodexRuntimeConfig
        public var loadGlobalMcpServers: @Sendable (URL) throws -> [String: McpServerConfig]
        public var replaceGlobalMcpServers: @Sendable (URL, [String: McpServerConfig]) throws -> Void
        public var authStatuses: @Sendable ([String: McpServerConfig], URL, OAuthCredentialsStoreMode, [String: String]) async -> [String: McpAuthStatus]
        public var oauthLoginDiscovery: @Sendable (String, [String: String]?, [String: String]?, [String: String]) async throws -> McpOAuthLoginDiscovery?
        public var discoverSupportedScopes: @Sendable (String, [String: String]?, [String: String]?, [String: String]) async -> [String]?
        public var performOAuthLogin: @Sendable (McpOAuthLoginRequest, @escaping McpOAuthLoginMessageSink) async throws -> Void
        public var deleteOAuthTokens: @Sendable (String, String, URL, OAuthCredentialsStoreMode) throws -> Bool
        public var environment: @Sendable () -> [String: String]
        public var stdout: @Sendable (String) -> Void
        public var messageSink: McpOAuthLoginMessageSink

        public init(
            findCodexHome: @escaping @Sendable () throws -> URL = { try CodexHome.find() },
            loadConfig: @escaping @Sendable (URL, CliConfigOverrides) throws -> CodexRuntimeConfig = { codexHome, overrides in
                try CodexConfigLoader.load(
                    codexHome: codexHome,
                    cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
                    overrides: overrides
                )
            },
            loadGlobalMcpServers: @escaping @Sendable (URL) throws -> [String: McpServerConfig] = { codexHome in
                try McpConfigStore.loadGlobalMcpServers(codexHome: codexHome)
            },
            replaceGlobalMcpServers: @escaping @Sendable (URL, [String: McpServerConfig]) throws -> Void = { codexHome, servers in
                try McpConfigStore.replaceGlobalMcpServers(codexHome: codexHome, servers: servers)
            },
            authStatuses: @escaping @Sendable ([String: McpServerConfig], URL, OAuthCredentialsStoreMode, [String: String]) async -> [String: McpAuthStatus] = { servers, codexHome, storeMode, environment in
                await McpAuthStatusResolver.authStatuses(
                    for: servers,
                    codexHome: codexHome,
                    storeMode: storeMode,
                    environment: environment
                )
            },
            oauthLoginDiscovery: @escaping @Sendable (String, [String: String]?, [String: String]?, [String: String]) async throws -> McpOAuthLoginDiscovery? = { url, httpHeaders, envHttpHeaders, environment in
                try await McpOAuthDiscovery.discoverOAuthLogin(
                    url: url,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    environment: environment
                )
            },
            discoverSupportedScopes: @escaping @Sendable (String, [String: String]?, [String: String]?, [String: String]) async -> [String]? = { url, httpHeaders, envHttpHeaders, environment in
                try? await McpOAuthDiscovery.discoverSupportedScopes(
                    url: url,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    environment: environment
                )
            },
            performOAuthLogin: @escaping @Sendable (McpOAuthLoginRequest, @escaping McpOAuthLoginMessageSink) async throws -> Void = { request, messageSink in
                try await McpOAuthLogin.perform(request: request, messageSink: messageSink)
            },
            deleteOAuthTokens: @escaping @Sendable (String, String, URL, OAuthCredentialsStoreMode) throws -> Bool = { serverName, url, codexHome, mode in
                try McpOAuthCredentialStore.deleteOAuthTokens(
                    serverName: serverName,
                    url: url,
                    codexHome: codexHome,
                    mode: mode
                )
            },
            environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
            stdout: @escaping @Sendable (String) -> Void = { print($0) },
            messageSink: @escaping McpOAuthLoginMessageSink = { message in
                switch message {
                case let .authorizationURL(serverName, authURL):
                    print("Authorize `\(serverName)` by opening this URL in your browser:\n\(authURL)\n")
                case .browserLaunchFailed:
                    print("(Browser launch failed; please copy the URL above manually.)")
                }
            }
        ) {
            self.findCodexHome = findCodexHome
            self.loadConfig = loadConfig
            self.loadGlobalMcpServers = loadGlobalMcpServers
            self.replaceGlobalMcpServers = replaceGlobalMcpServers
            self.authStatuses = authStatuses
            self.oauthLoginDiscovery = oauthLoginDiscovery
            self.discoverSupportedScopes = discoverSupportedScopes
            self.performOAuthLogin = performOAuthLogin
            self.deleteOAuthTokens = deleteOAuthTokens
            self.environment = environment
            self.stdout = stdout
            self.messageSink = messageSink
        }
    }

    public static func run(
        _ request: CodexCLI.McpCommandRequest,
        dependencies: Dependencies = Dependencies()
    ) async throws -> CodexCLI.CommandExecutionResult {
        switch request.action {
        case let .list(json):
            let codexHome = try dependencies.findCodexHome()
            let settings = try dependencies.loadConfig(codexHome, request.configOverrides)
            let servers = settings.mcpServers
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: try McpCommandFormatter.list(
                    servers: servers,
                    json: json,
                    authStatuses: await dependencies.authStatuses(
                        servers,
                        codexHome,
                        settings.mcpOAuthCredentialsStoreMode,
                        dependencies.environment()
                    )
                )
            )

        case let .get(name, json):
            let codexHome = try dependencies.findCodexHome()
            let settings = try dependencies.loadConfig(codexHome, request.configOverrides)
            guard let server = settings.mcpServers[name] else {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "No MCP server named '\(name)' found."
                )
            }
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: try McpCommandFormatter.get(name: name, server: server, json: json)
            )

        case let .add(name, transport):
            let codexHome = try dependencies.findCodexHome()
            let settings = try dependencies.loadConfig(codexHome, request.configOverrides)
            try McpServerName.validate(name)
            var servers = try dependencies.loadGlobalMcpServers(codexHome)
            let serverTransport = try serverTransport(from: transport)
            servers[name] = McpServerConfig(transport: serverTransport)
            try dependencies.replaceGlobalMcpServers(codexHome, servers)

            let addedMessage = "Added global MCP server '\(name)'."
            if case let .streamableHttp(url, nil, httpHeaders, envHttpHeaders) = serverTransport {
                let oauthDiscovery: McpOAuthLoginDiscovery?
                do {
                    oauthDiscovery = try await dependencies.oauthLoginDiscovery(
                        url,
                        httpHeaders,
                        envHttpHeaders,
                        dependencies.environment()
                    )
                } catch {
                    return CodexCLI.CommandExecutionResult(
                        exitCode: 0,
                        stdoutMessage: "\(addedMessage)\nMCP server may or may not require login. Run `codex mcp login \(name)` to login."
                    )
                }
                if let oauthDiscovery {
                    dependencies.stdout(addedMessage)
                    dependencies.stdout("Detected OAuth support. Starting OAuth flow…")
                    let resolvedScopes = McpOAuthScopes.resolve(
                        explicitScopes: nil,
                        configuredScopes: nil,
                        discoveredScopes: oauthDiscovery.scopesSupported
                    )
                    try await performOAuthLogin(
                        serverName: name,
                        serverURL: url,
                        codexHome: codexHome,
                        settings: settings,
                        httpHeaders: httpHeaders,
                        envHttpHeaders: envHttpHeaders,
                        resolvedScopes: resolvedScopes,
                        oauthClientID: nil,
                        oauthResource: nil,
                        dependencies: dependencies
                    )
                    return CodexCLI.CommandExecutionResult(
                        exitCode: 0,
                        stdoutMessage: "Successfully logged in."
                    )
                }
            }
            return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: addedMessage)

        case let .remove(name):
            let codexHome = try dependencies.findCodexHome()
            _ = try request.configOverrides.parseOverrides()
            try McpServerName.validate(name)
            var servers = try dependencies.loadGlobalMcpServers(codexHome)
            let removed = servers.removeValue(forKey: name) != nil
            if removed {
                try dependencies.replaceGlobalMcpServers(codexHome, servers)
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stdoutMessage: "Removed global MCP server '\(name)'."
                )
            }
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: "No MCP server named '\(name)' found."
            )

        case let .login(name, scopes):
            let codexHome = try dependencies.findCodexHome()
            let settings = try dependencies.loadConfig(codexHome, request.configOverrides)
            guard let server = settings.mcpServers[name] else {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "No MCP server named '\(name)' found."
                )
            }
            guard case let .streamableHttp(url, _, httpHeaders, envHttpHeaders) = server.transport else {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "OAuth login is only supported for streamable HTTP servers."
                )
            }
            let explicitScopes = scopes.isEmpty ? nil : scopes
            let discoveredScopes: [String]? = if explicitScopes == nil && server.scopes == nil {
                await dependencies.discoverSupportedScopes(
                    url,
                    httpHeaders,
                    envHttpHeaders,
                    dependencies.environment()
                )
            } else {
                nil
            }
            let resolvedScopes = McpOAuthScopes.resolve(
                explicitScopes: explicitScopes,
                configuredScopes: server.scopes,
                discoveredScopes: discoveredScopes
            )
            try await performOAuthLogin(
                serverName: name,
                serverURL: url,
                codexHome: codexHome,
                settings: settings,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                resolvedScopes: resolvedScopes,
                oauthClientID: server.effectiveOAuthClientID,
                oauthResource: server.oauthResource,
                dependencies: dependencies
            )
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: "Successfully logged in to MCP server '\(name)'."
            )

        case let .logout(name):
            let codexHome = try dependencies.findCodexHome()
            let settings = try dependencies.loadConfig(codexHome, request.configOverrides)
            guard let server = settings.mcpServers[name] else {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "No MCP server named '\(name)' found in configuration."
                )
            }
            guard case let .streamableHttp(url, _, _, _) = server.transport else {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "OAuth logout is only supported for streamable_http transports."
                )
            }
            do {
                let removed = try dependencies.deleteOAuthTokens(
                    name,
                    url,
                    codexHome,
                    settings.mcpOAuthCredentialsStoreMode
                )
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stdoutMessage: removed
                        ? "Removed OAuth credentials for '\(name)'."
                        : "No OAuth credentials stored for '\(name)'."
                )
            } catch {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 1,
                    stderrMessage: "failed to delete OAuth credentials: \(String(describing: error))"
                )
            }
        }
    }

    private static func serverTransport(from transport: CodexCLI.McpAddTransport) throws -> McpServerTransportConfig {
        switch transport {
        case let .stdio(command, envPairs):
            guard let commandBin = command.first else {
                throw McpCommandRuntimeError.commandRequired
            }
            let env = envPairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: envPairs.map { ($0.key, $0.value) })
            return .stdio(
                command: commandBin,
                args: Array(command.dropFirst()),
                env: env,
                envVars: [],
                cwd: nil
            )
        case let .streamableHttp(url, bearerTokenEnvVar):
            return .streamableHttp(
                url: url,
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: nil,
                envHttpHeaders: nil
            )
        }
    }

    private static func performOAuthLogin(
        serverName: String,
        serverURL: String,
        codexHome: URL,
        settings: CodexRuntimeConfig,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        resolvedScopes: ResolvedMcpOAuthScopes,
        oauthClientID: String?,
        oauthResource: String?,
        dependencies: Dependencies
    ) async throws {
        do {
            try await performOAuthLoginAttempt(
                serverName: serverName,
                serverURL: serverURL,
                codexHome: codexHome,
                settings: settings,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                scopes: resolvedScopes.scopes,
                oauthClientID: oauthClientID,
                oauthResource: oauthResource,
                dependencies: dependencies
            )
        } catch {
            guard McpOAuthScopes.shouldRetryWithoutScopes(resolvedScopes, error: error) else {
                throw error
            }
            dependencies.stdout("OAuth provider rejected discovered scopes. Retrying without scopes…")
            try await performOAuthLoginAttempt(
                serverName: serverName,
                serverURL: serverURL,
                codexHome: codexHome,
                settings: settings,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                scopes: [],
                oauthClientID: oauthClientID,
                oauthResource: oauthResource,
                dependencies: dependencies
            )
        }
    }

    private static func performOAuthLoginAttempt(
        serverName: String,
        serverURL: String,
        codexHome: URL,
        settings: CodexRuntimeConfig,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        scopes: [String],
        oauthClientID: String?,
        oauthResource: String?,
        dependencies: Dependencies
    ) async throws {
        try await dependencies.performOAuthLogin(McpOAuthLoginRequest(
            serverName: serverName,
            serverURL: serverURL,
            codexHome: codexHome,
            storeMode: settings.mcpOAuthCredentialsStoreMode,
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: dependencies.environment(),
            scopes: scopes,
            oauthClientID: oauthClientID,
            oauthResource: oauthResource,
            callbackPort: settings.mcpOAuthCallbackPort,
            callbackURL: settings.mcpOAuthCallbackURL
        ), dependencies.messageSink)
    }
}

public enum McpCommandRuntimeError: Error, Equatable, CustomStringConvertible, Sendable {
    case commandRequired

    public var description: String {
        switch self {
        case .commandRequired:
            return "command is required"
        }
    }
}
