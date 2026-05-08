import Foundation

public enum McpConfigError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidServerName(String)
    case invalidEnvPair(String)
    case invalidTransport(String)
    case unsupportedBearerToken(String)
    case invalidStringValue(String)
    case invalidBoolValue(String)
    case invalidNumberValue(String)
    case invalidStringArrayValue(String)
    case invalidConfigLine(String)
    case invalidTableHeader(String)

    public var description: String {
        switch self {
        case let .invalidServerName(name):
            return "invalid server name '\(name)' (use letters, numbers, '-', '_')"
        case .invalidEnvPair:
            return "environment entries must be in KEY=VALUE form"
        case let .invalidTransport(server):
            return "mcp_servers.\(server) has invalid transport"
        case let .unsupportedBearerToken(server):
            return "mcp_servers.\(server) uses unsupported `bearer_token`; set `bearer_token_env_var`."
        case let .invalidStringValue(key):
            return "Invalid value for \(key): expected string"
        case let .invalidBoolValue(key):
            return "Invalid value for \(key): expected bool"
        case let .invalidNumberValue(key):
            return "Invalid value for \(key): expected number"
        case let .invalidStringArrayValue(key):
            return "Invalid value for \(key): expected array of strings"
        case let .invalidConfigLine(line):
            return "Invalid config line: \(line)"
        case let .invalidTableHeader(header):
            return "Invalid TOML table header: \(header)"
        }
    }
}

public enum McpServerTransportConfig: Equatable, Sendable {
    case stdio(command: String, args: [String], env: [String: String]?, envVars: [String], cwd: String?)
    case streamableHttp(
        url: String,
        bearerTokenEnvVar: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?
    )
}

public struct McpServerConfig: Equatable, Sendable {
    public var transport: McpServerTransportConfig
    public var enabled: Bool
    public var startupTimeoutSec: Double?
    public var toolTimeoutSec: Double?
    public var enabledTools: [String]?
    public var disabledTools: [String]?

    public init(
        transport: McpServerTransportConfig,
        enabled: Bool = true,
        startupTimeoutSec: Double? = nil,
        toolTimeoutSec: Double? = nil,
        enabledTools: [String]? = nil,
        disabledTools: [String]? = nil
    ) {
        self.transport = transport
        self.enabled = enabled
        self.startupTimeoutSec = startupTimeoutSec
        self.toolTimeoutSec = toolTimeoutSec
        self.enabledTools = enabledTools
        self.disabledTools = disabledTools
    }
}

public enum McpServerName {
    public static func validate(_ name: String) throws {
        let isValid = !name.isEmpty && name.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        guard isValid else {
            throw McpConfigError.invalidServerName(name)
        }
    }
}

public enum McpConfigStore {
    public static func loadGlobalMcpServers(
        codexHome: URL,
        fileManager: FileManager = .default
    ) throws -> [String: McpServerConfig] {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: configFile.path) else {
            return [:]
        }
        let contents = try String(contentsOf: configFile, encoding: .utf8)
        return try parseMcpServers(from: contents)
    }

    public static func replaceGlobalMcpServers(
        codexHome: URL,
        servers: [String: McpServerConfig],
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = fileManager.fileExists(atPath: configFile.path)
            ? try String(contentsOf: configFile, encoding: .utf8)
            : ""
        let next = replaceMcpServersSection(in: existing, with: servers)
        try next.write(to: configFile, atomically: true, encoding: .utf8)
    }

    public static func parseMcpServers(from contents: String) throws -> [String: McpServerConfig] {
        var builders: [String: McpServerBuilder] = [:]
        var section = McpConfigSection.other

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                section = try parseSectionHeader(line)
                if case let .server(name) = section {
                    if builders[name] == nil {
                        builders[name] = McpServerBuilder()
                    }
                }
                if case let .serverTable(name, _) = section {
                    if builders[name] == nil {
                        builders[name] = McpServerBuilder()
                    }
                }
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                if case .other = section {
                    continue
                }
                throw McpConfigError.invalidConfigLine(line)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = try ConfigValueParser.parseTomlLiteral(valueText)

            switch section {
            case .root, .other:
                continue
            case let .server(name):
                try builders[name, default: McpServerBuilder()].set(key: key, value: value, serverName: name)
            case let .serverTable(name, table):
                try builders[name, default: McpServerBuilder()].set(table: table, key: key, value: value)
            }
        }

        var servers: [String: McpServerConfig] = [:]
        for name in builders.keys.sorted() {
            servers[name] = try builders[name]?.build(serverName: name)
        }
        return servers
    }

    public static func parseMcpServers(from value: ConfigValue) throws -> [String: McpServerConfig] {
        guard case let .table(serverTable) = value else {
            return [:]
        }

        var servers: [String: McpServerConfig] = [:]
        for name in serverTable.keys.sorted() {
            guard case let .table(rawServer) = serverTable[name] else {
                throw McpConfigError.invalidTransport(name)
            }
            var builder = McpServerBuilder()
            for (key, value) in rawServer {
                if case let .table(nestedTable) = value, ["env", "http_headers", "env_http_headers"].contains(key) {
                    for (nestedKey, nestedValue) in nestedTable {
                        try builder.set(table: key, key: nestedKey, value: nestedValue)
                    }
                } else {
                    try builder.set(key: key, value: value, serverName: name)
                }
            }
            servers[name] = try builder.build(serverName: name)
        }
        return servers
    }

    public static func replaceMcpServersSection(
        in contents: String,
        with servers: [String: McpServerConfig]
    ) -> String {
        var keptLines: [String] = []
        var skippingMcpSection = false
        let hasTrailingNewline = contents.hasSuffix("\n")

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                skippingMcpSection = isMcpSectionHeader(trimmed)
            }
            if !skippingMcpSection {
                keptLines.append(line)
            }
        }

        var base = keptLines.joined(separator: "\n")
        if hasTrailingNewline, !base.isEmpty {
            base.append("\n")
        }
        base = trimTrailingBlankLines(base)

        let serialized = serializeMcpServers(servers)
        guard !serialized.isEmpty else {
            return base.isEmpty ? "" : base + "\n"
        }

        if base.isEmpty {
            return serialized
        }
        return base + "\n\n" + serialized
    }

    public static func serializeMcpServers(_ servers: [String: McpServerConfig]) -> String {
        guard !servers.isEmpty else { return "" }
        var blocks: [String] = []

        for name in servers.keys.sorted() {
            guard let server = servers[name] else { continue }
            let serverKey = tomlKey(name)
            var lines: [String] = ["[mcp_servers.\(serverKey)]"]
            switch server.transport {
            case let .stdio(command, args, env, envVars, cwd):
                lines.append("command = \(tomlString(command))")
                if !args.isEmpty {
                    lines.append("args = \(tomlStringArray(args))")
                }
                if !envVars.isEmpty {
                    lines.append("env_vars = \(tomlStringArray(envVars))")
                }
                if let cwd {
                    lines.append("cwd = \(tomlString(cwd))")
                }
                appendCommonServerFields(server, to: &lines)
                if let env, !env.isEmpty {
                    lines.append("")
                    lines.append("[mcp_servers.\(serverKey).env]")
                    for key in env.keys.sorted() {
                        lines.append("\(tomlKey(key)) = \(tomlString(env[key] ?? ""))")
                    }
                }
            case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
                lines.append("url = \(tomlString(url))")
                if let bearerTokenEnvVar {
                    lines.append("bearer_token_env_var = \(tomlString(bearerTokenEnvVar))")
                }
                appendCommonServerFields(server, to: &lines)
                if let httpHeaders, !httpHeaders.isEmpty {
                    lines.append("")
                    lines.append("[mcp_servers.\(serverKey).http_headers]")
                    for key in httpHeaders.keys.sorted() {
                        lines.append("\(tomlKey(key)) = \(tomlString(httpHeaders[key] ?? ""))")
                    }
                }
                if let envHttpHeaders, !envHttpHeaders.isEmpty {
                    lines.append("")
                    lines.append("[mcp_servers.\(serverKey).env_http_headers]")
                    for key in envHttpHeaders.keys.sorted() {
                        lines.append("\(tomlKey(key)) = \(tomlString(envHttpHeaders[key] ?? ""))")
                    }
                }
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func appendCommonServerFields(_ server: McpServerConfig, to lines: inout [String]) {
        if !server.enabled {
            lines.append("enabled = false")
        }
        if let startupTimeoutSec = server.startupTimeoutSec {
            lines.append("startup_timeout_sec = \(tomlNumber(startupTimeoutSec))")
        }
        if let toolTimeoutSec = server.toolTimeoutSec {
            lines.append("tool_timeout_sec = \(tomlNumber(toolTimeoutSec))")
        }
        if let enabledTools = server.enabledTools {
            lines.append("enabled_tools = \(tomlStringArray(enabledTools))")
        }
        if let disabledTools = server.disabledTools {
            lines.append("disabled_tools = \(tomlStringArray(disabledTools))")
        }
    }
}

public enum McpCommandFormatter {
    public static func list(
        servers: [String: McpServerConfig],
        json: Bool,
        authStatuses: [String: McpAuthStatus]? = nil
    ) throws -> String {
        let entries = servers.keys.sorted().compactMap { name -> (String, McpServerConfig)? in
            guard let config = servers[name] else { return nil }
            return (name, config)
        }

        if json {
            let values = entries.map { name, server in
                listJSONValue(
                    name: name,
                    server: server,
                    authStatus: authStatuses?[name] ?? McpAuthStatusResolver.authStatus(for: server)
                )
            }
            return try prettyJSON(.array(values))
        }

        if entries.isEmpty {
            return "No MCP servers configured yet. Try `codex mcp add my-tool -- my-command`."
        }

        var output: [String] = []
        var stdioRows: [[String]] = []
        var httpRows: [[String]] = []

        for (name, server) in entries {
            let status = server.enabled ? "enabled" : "disabled"
            let auth = (authStatuses?[name] ?? McpAuthStatusResolver.authStatus(for: server)).description
            switch server.transport {
            case let .stdio(command, args, env, envVars, cwd):
                stdioRows.append([
                    name,
                    command,
                    args.isEmpty ? "-" : args.joined(separator: " "),
                    EnvDisplay.formatEnvDisplay(env: env, envVars: envVars),
                    cwd?.isEmpty == false ? cwd! : "-",
                    status,
                    auth
                ])
            case let .streamableHttp(url, bearerTokenEnvVar, _, _):
                httpRows.append([
                    name,
                    url,
                    bearerTokenEnvVar ?? "-",
                    status,
                    auth
                ])
            }
        }

        if !stdioRows.isEmpty {
            output.append(table(headers: ["Name", "Command", "Args", "Env", "Cwd", "Status", "Auth"], rows: stdioRows))
        }
        if !stdioRows.isEmpty, !httpRows.isEmpty {
            output.append("")
        }
        if !httpRows.isEmpty {
            output.append(table(headers: ["Name", "Url", "Bearer Token Env Var", "Status", "Auth"], rows: httpRows))
        }

        return output.joined(separator: "\n")
    }

    public static func get(name: String, server: McpServerConfig, json: Bool) throws -> String {
        if json {
            return try prettyJSON(getJSONValue(name: name, server: server))
        }

        if !server.enabled {
            return "\(name) (disabled)"
        }

        var lines = [
            name,
            "  enabled: \(server.enabled)"
        ]
        if let enabledTools = server.enabledTools {
            lines.append("  enabled_tools: \(formatToolList(enabledTools))")
        }
        if let disabledTools = server.disabledTools {
            lines.append("  disabled_tools: \(formatToolList(disabledTools))")
        }

        switch server.transport {
        case let .stdio(command, args, env, envVars, cwd):
            lines.append("  transport: stdio")
            lines.append("  command: \(command)")
            lines.append("  args: \(args.isEmpty ? "-" : args.joined(separator: " "))")
            lines.append("  cwd: \(cwd?.isEmpty == false ? cwd! : "-")")
            lines.append("  env: \(EnvDisplay.formatEnvDisplay(env: env, envVars: envVars))")
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            lines.append("  transport: streamable_http")
            lines.append("  url: \(url)")
            lines.append("  bearer_token_env_var: \(bearerTokenEnvVar ?? "-")")
            lines.append("  http_headers: \(formatHeaderMap(httpHeaders, redactValues: true))")
            lines.append("  env_http_headers: \(formatHeaderMap(envHttpHeaders, redactValues: false))")
        }

        if let startupTimeoutSec = server.startupTimeoutSec {
            lines.append("  startup_timeout_sec: \(tomlNumber(startupTimeoutSec))")
        }
        if let toolTimeoutSec = server.toolTimeoutSec {
            lines.append("  tool_timeout_sec: \(tomlNumber(toolTimeoutSec))")
        }
        lines.append("  remove: codex mcp remove \(name)")
        return lines.joined(separator: "\n")
    }

    public static func listJSONValue(
        name: String,
        server: McpServerConfig,
        authStatus: McpAuthStatus? = nil
    ) -> JSONValue {
        .object([
            "name": .string(name),
            "enabled": .bool(server.enabled),
            "transport": transportJSONValue(server.transport),
            "startup_timeout_sec": secondsJSONValue(server.startupTimeoutSec),
            "tool_timeout_sec": secondsJSONValue(server.toolTimeoutSec),
            "auth_status": .string((authStatus ?? McpAuthStatusResolver.authStatus(for: server)).rawValue)
        ])
    }

    public static func getJSONValue(name: String, server: McpServerConfig) -> JSONValue {
        .object([
            "name": .string(name),
            "enabled": .bool(server.enabled),
            "transport": transportJSONValue(server.transport),
            "enabled_tools": stringArrayJSONValue(server.enabledTools),
            "disabled_tools": stringArrayJSONValue(server.disabledTools),
            "startup_timeout_sec": secondsJSONValue(server.startupTimeoutSec),
            "tool_timeout_sec": secondsJSONValue(server.toolTimeoutSec)
        ])
    }

    private static func transportJSONValue(_ transport: McpServerTransportConfig) -> JSONValue {
        switch transport {
        case let .stdio(command, args, env, envVars, cwd):
            return .object([
                "type": .string("stdio"),
                "command": .string(command),
                "args": .array(args.map(JSONValue.string)),
                "env": stringMapJSONValue(env),
                "env_vars": .array(envVars.map(JSONValue.string)),
                "cwd": cwd.map(JSONValue.string) ?? .null
            ])
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            return .object([
                "type": .string("streamable_http"),
                "url": .string(url),
                "bearer_token_env_var": bearerTokenEnvVar.map(JSONValue.string) ?? .null,
                "http_headers": stringMapJSONValue(httpHeaders),
                "env_http_headers": stringMapJSONValue(envHttpHeaders)
            ])
        }
    }

    private static func prettyJSON(_ value: JSONValue) throws -> String {
        try renderPrettyJSON(value, indent: 0)
    }

    private static func renderPrettyJSON(_ value: JSONValue, indent: Int) throws -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .integer(integer):
            return String(integer)
        case let .double(double):
            return tomlNumber(double)
        case let .string(string):
            return try jsonString(string)
        case let .array(values):
            guard !values.isEmpty else { return "[]" }
            let childIndent = indent + 2
            let childPrefix = String(repeating: " ", count: childIndent)
            let closingPrefix = String(repeating: " ", count: indent)
            let rendered = try values.map { value in
                "\(childPrefix)\(try renderPrettyJSON(value, indent: childIndent))"
            }.joined(separator: ",\n")
            return "[\n\(rendered)\n\(closingPrefix)]"
        case let .object(values):
            guard !values.isEmpty else { return "{}" }
            let childIndent = indent + 2
            let childPrefix = String(repeating: " ", count: childIndent)
            let closingPrefix = String(repeating: " ", count: indent)
            let rendered = try values.keys.sorted().map { key in
                "\(childPrefix)\(try jsonString(key)): \(try renderPrettyJSON(values[key]!, indent: childIndent))"
            }.joined(separator: ",\n")
            return "{\n\(rendered)\n\(closingPrefix)}"
        }
    }

    private static func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        var widths = headers.map(\.count)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }

        let allRows = [headers] + rows
        return allRows.map { row in
            row.enumerated().map { index, cell in
                cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private static func formatToolList(_ tools: [String]) -> String {
        tools.isEmpty ? "[]" : tools.joined(separator: ", ")
    }

    private static func formatHeaderMap(_ map: [String: String]?, redactValues: Bool) -> String {
        guard let map, !map.isEmpty else {
            return "-"
        }
        return map.keys.sorted().map { key in
            if redactValues {
                return "\(key)=*****"
            }
            return "\(key)=\(map[key] ?? "")"
        }.joined(separator: ", ")
    }

    private static func secondsJSONValue(_ value: Double?) -> JSONValue {
        guard let value else { return .null }
        return .double(value)
    }

    private static func stringMapJSONValue(_ value: [String: String]?) -> JSONValue {
        guard let value else { return .null }
        return .object(value.mapValues(JSONValue.string))
    }

    private static func stringArrayJSONValue(_ value: [String]?) -> JSONValue {
        guard let value else { return .null }
        return .array(value.map(JSONValue.string))
    }
}

public enum McpAuthStatusResolver {
    public static func authStatuses(for servers: [String: McpServerConfig]) -> [String: McpAuthStatus] {
        Dictionary(uniqueKeysWithValues: servers.map { name, server in
            (name, authStatus(for: server))
        })
    }

    public static func authStatuses(
        for servers: [String: McpServerConfig],
        codexHome: URL,
        storeMode: OAuthCredentialsStoreMode,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) -> [String: McpAuthStatus] {
        Dictionary(uniqueKeysWithValues: servers.map { name, server in
            (
                name,
                authStatus(
                    name: name,
                    server: server,
                    codexHome: codexHome,
                    storeMode: storeMode,
                    keyringStore: keyringStore
                )
            )
        })
    }

    public static func authStatus(for server: McpServerConfig) -> McpAuthStatus {
        switch server.transport {
        case .stdio:
            return .unsupported
        case let .streamableHttp(_, bearerTokenEnvVar, _, _):
            return bearerTokenEnvVar == nil ? .unsupported : .bearerToken
        }
    }

    public static func authStatus(
        name: String,
        server: McpServerConfig,
        codexHome: URL,
        storeMode: OAuthCredentialsStoreMode,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) -> McpAuthStatus {
        switch server.transport {
        case .stdio:
            return .unsupported
        case let .streamableHttp(url, bearerTokenEnvVar, _, _):
            if bearerTokenEnvVar != nil {
                return .bearerToken
            }
            do {
                return try McpOAuthCredentialStore.hasOAuthTokens(
                    serverName: name,
                    url: url,
                    codexHome: codexHome,
                    mode: storeMode,
                    keyringStore: keyringStore
                ) ? .oauth : .unsupported
            } catch {
                // Rust falls back to Unsupported when auth-status detection fails.
                return .unsupported
            }
        }
    }
}

private enum McpConfigSection: Equatable {
    case root
    case server(String)
    case serverTable(String, String)
    case other
}

private struct McpServerBuilder {
    var command: String?
    var args: [String] = []
    var env: [String: String]?
    var envVars: [String] = []
    var cwd: String?
    var url: String?
    var bearerTokenEnvVar: String?
    var bearerToken: String?
    var httpHeaders: [String: String]?
    var envHttpHeaders: [String: String]?
    var enabled = true
    var startupTimeoutSec: Double?
    var startupTimeoutMs: Double?
    var toolTimeoutSec: Double?
    var enabledTools: [String]?
    var disabledTools: [String]?

    mutating func set(key: String, value: ConfigValue, serverName: String) throws {
        switch key {
        case "command":
            command = try stringValue(value, key: "mcp_servers.\(serverName).command")
        case "args":
            args = try stringArrayValue(value, key: "mcp_servers.\(serverName).args")
        case "env_vars":
            envVars = try stringArrayValue(value, key: "mcp_servers.\(serverName).env_vars")
        case "cwd":
            cwd = try stringValue(value, key: "mcp_servers.\(serverName).cwd")
        case "url":
            url = try stringValue(value, key: "mcp_servers.\(serverName).url")
        case "bearer_token_env_var":
            bearerTokenEnvVar = try stringValue(value, key: "mcp_servers.\(serverName).bearer_token_env_var")
        case "bearer_token":
            bearerToken = try stringValue(value, key: "mcp_servers.\(serverName).bearer_token")
        case "enabled":
            enabled = try boolValue(value, key: "mcp_servers.\(serverName).enabled")
        case "startup_timeout_sec":
            startupTimeoutSec = try doubleValue(value, key: "mcp_servers.\(serverName).startup_timeout_sec")
        case "startup_timeout_ms":
            startupTimeoutMs = try doubleValue(value, key: "mcp_servers.\(serverName).startup_timeout_ms") / 1000
        case "tool_timeout_sec":
            toolTimeoutSec = try doubleValue(value, key: "mcp_servers.\(serverName).tool_timeout_sec")
        case "enabled_tools":
            enabledTools = try stringArrayValue(value, key: "mcp_servers.\(serverName).enabled_tools")
        case "disabled_tools":
            disabledTools = try stringArrayValue(value, key: "mcp_servers.\(serverName).disabled_tools")
        case "env", "http_headers", "env_http_headers":
            guard case let .table(table) = value else {
                throw McpConfigError.invalidConfigLine(key)
            }
            for (nestedKey, nestedValue) in table {
                try set(table: key, key: nestedKey, value: nestedValue)
            }
        default:
            break
        }
    }

    mutating func set(table: String, key: String, value: ConfigValue) throws {
        let rawValue = try stringValue(value, key: key)
        switch table {
        case "env":
            env = (env ?? [:])
            env?[key] = rawValue
        case "http_headers":
            httpHeaders = (httpHeaders ?? [:])
            httpHeaders?[key] = rawValue
        case "env_http_headers":
            envHttpHeaders = (envHttpHeaders ?? [:])
            envHttpHeaders?[key] = rawValue
        default:
            break
        }
    }

    func build(serverName: String) throws -> McpServerConfig {
        if bearerToken != nil {
            throw McpConfigError.unsupportedBearerToken(serverName)
        }

        let transport: McpServerTransportConfig
        if let command {
            guard url == nil, bearerTokenEnvVar == nil, httpHeaders == nil, envHttpHeaders == nil else {
                throw McpConfigError.invalidTransport(serverName)
            }
            transport = .stdio(command: command, args: args, env: env, envVars: envVars, cwd: cwd)
        } else if let url {
            guard args.isEmpty, env == nil, envVars.isEmpty, cwd == nil else {
                throw McpConfigError.invalidTransport(serverName)
            }
            transport = .streamableHttp(
                url: url,
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders
            )
        } else {
            throw McpConfigError.invalidTransport(serverName)
        }

        return McpServerConfig(
            transport: transport,
            enabled: enabled,
            startupTimeoutSec: startupTimeoutSec ?? startupTimeoutMs,
            toolTimeoutSec: toolTimeoutSec,
            enabledTools: enabledTools,
            disabledTools: disabledTools
        )
    }
}

private func parseSectionHeader(_ line: String) throws -> McpConfigSection {
    guard line.hasSuffix("]") else {
        throw McpConfigError.invalidTableHeader(line)
    }
    let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = try parseDottedKey(body)
    if parts.count == 1, parts[0] == "mcp_servers" {
        return .root
    }
    if parts.count == 2, parts[0] == "mcp_servers" {
        return .server(parts[1])
    }
    if parts.count == 3, parts[0] == "mcp_servers" {
        return .serverTable(parts[1], parts[2])
    }
    return .other
}

private func isMcpSectionHeader(_ line: String) -> Bool {
    guard line.hasSuffix("]") else { return false }
    let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    return (try? parseDottedKey(body).first) == "mcp_servers"
}

private func firstEqualsIndex(in line: String) -> String.Index? {
    var quote: Character?
    var previousWasBackslash = false
    for index in line.indices {
        let character = line[index]
        if let activeQuote = quote {
            if character == activeQuote && !previousWasBackslash {
                quote = nil
            }
            previousWasBackslash = character == "\\" && !previousWasBackslash
            if character != "\\" {
                previousWasBackslash = false
            }
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
            continue
        }
        if character == "=" {
            return index
        }
    }
    return nil
}

private func parseDottedKey(_ raw: String) throws -> [String] {
    var parts: [String] = []
    var current = String()
    var quote: Character?
    var previousWasBackslash = false

    for character in raw {
        if let activeQuote = quote {
            current.append(character)
            if character == activeQuote && !previousWasBackslash {
                quote = nil
            }
            previousWasBackslash = character == "\\" && !previousWasBackslash
            if character != "\\" {
                previousWasBackslash = false
            }
            continue
        }

        if character == "\"" || character == "'" {
            quote = character
            current.append(character)
            continue
        }
        if character == "." {
            parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingMatchingQuotes())
            current = ""
            continue
        }
        current.append(character)
    }
    parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingMatchingQuotes())
    return parts
}

private func stripComment(from line: String) -> String {
    var result = String()
    var quote: Character?
    var previousWasBackslash = false
    for character in line {
        if let activeQuote = quote {
            result.append(character)
            if character == activeQuote && !previousWasBackslash {
                quote = nil
            }
            previousWasBackslash = character == "\\" && !previousWasBackslash
            if character != "\\" {
                previousWasBackslash = false
            }
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
            result.append(character)
            continue
        }
        if character == "#" {
            break
        }
        result.append(character)
    }
    return result
}

private func stringValue(_ value: ConfigValue, key: String) throws -> String {
    guard case let .string(string) = value else {
        throw McpConfigError.invalidStringValue(key)
    }
    return string
}

private func boolValue(_ value: ConfigValue, key: String) throws -> Bool {
    guard case let .bool(bool) = value else {
        throw McpConfigError.invalidBoolValue(key)
    }
    return bool
}

private func doubleValue(_ value: ConfigValue, key: String) throws -> Double {
    switch value {
    case let .integer(integer):
        return Double(integer)
    case let .double(double):
        return double
    default:
        throw McpConfigError.invalidNumberValue(key)
    }
}

private func stringArrayValue(_ value: ConfigValue, key: String) throws -> [String] {
    guard case let .array(values) = value else {
        throw McpConfigError.invalidStringArrayValue(key)
    }
    return try values.map { value in
        guard case let .string(string) = value else {
            throw McpConfigError.invalidStringArrayValue(key)
        }
        return string
    }
}

private func trimTrailingBlankLines(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.removeLast()
    }
    return lines.joined(separator: "\n")
}

private func tomlStringArray(_ values: [String]) -> String {
    "[" + values.map(tomlString).joined(separator: ", ") + "]"
}

private func tomlString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

private func tomlKey(_ value: String) -> String {
    let isBare = !value.isEmpty && value.allSatisfy { character in
        character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }
    return isBare ? value : tomlString(value)
}

private func tomlNumber(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
        return String(format: "%.1f", value)
    }
    return String(value)
}

private extension String {
    func trimmingMatchingQuotes() -> String {
        guard count >= 2 else { return self }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(dropFirst().dropLast())
        }
        return self
    }
}
