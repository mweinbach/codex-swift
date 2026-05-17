import Foundation

public enum McpToolApprovalPersistenceError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingConnectorID
    case mcpServerNotConfigured(String)
    case mcpServerNotConfiguredOrEnabledPlugin(String)

    public var description: String {
        switch self {
        case .missingConnectorID:
            return "codex_apps MCP tool approval persistence requires a connector_id"
        case let .mcpServerNotConfigured(server):
            return "MCP server `\(server)` is not configured in config.toml"
        case let .mcpServerNotConfiguredOrEnabledPlugin(server):
            return "MCP server `\(server)` is not configured in config.toml or an enabled plugin"
        }
    }
}

public struct PluginMcpToolApprovalSource: Equatable, Sendable {
    public var pluginConfigName: String
    public var mcpServers: Set<String>

    public init(pluginConfigName: String, mcpServers: Set<String>) {
        self.pluginConfigName = pluginConfigName
        self.mcpServers = mcpServers
    }
}

public enum McpToolApprovalPersistence {
    public static func persistMcpToolApproval(
        codexHome: URL,
        key: McpToolApprovalKey,
        configLayerStack: ConfigLayerStack? = nil,
        enabledPluginMcpServerSources: [PluginMcpToolApprovalSource] = [],
        remoteInstalledPlugins: [RemoteInstalledPluginReference] = [],
        fileManager: FileManager = .default
    ) throws {
        if key.server == codexAppsMCPServerName {
            guard let connectorID = key.connectorID else {
                throw McpToolApprovalPersistenceError.missingConnectorID
            }
            try persistCodexAppToolApproval(
                codexHome: codexHome,
                connectorID: connectorID,
                toolName: key.toolName,
                fileManager: fileManager
            )
            return
        }

        try persistCustomMcpToolApproval(
            codexHome: codexHome,
            serverName: key.server,
            toolName: key.toolName,
            configLayerStack: configLayerStack,
            enabledPluginMcpServerSources: enabledPluginMcpServerSources,
            remoteInstalledPlugins: remoteInstalledPlugins,
            fileManager: fileManager
        )
    }

    public static func persistCodexAppToolApproval(
        codexHome: URL,
        connectorID: String,
        toolName: String,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = fileManager.fileExists(atPath: configFile.path)
            ? try String(contentsOf: configFile, encoding: .utf8)
            : ""
        var next = existing
        next = setTomlAssignment(
            in: next,
            tablePath: ["apps", connectorID],
            key: "enabled",
            literal: "true"
        )
        next = setTomlAssignment(
            in: next,
            tablePath: ["apps", connectorID, "tools", toolName],
            key: "approval_mode",
            literal: tomlString(AppToolApproval.approve.rawValue)
        )
        try next.write(to: configFile, atomically: true, encoding: .utf8)
    }

    public static func persistCustomMcpToolApproval(
        codexHome: URL,
        serverName: String,
        toolName: String,
        configLayerStack: ConfigLayerStack? = nil,
        enabledPluginMcpServerSources: [PluginMcpToolApprovalSource] = [],
        remoteInstalledPlugins: [RemoteInstalledPluginReference] = [],
        fileManager: FileManager = .default
    ) throws {
        if let projectConfigFolder = projectMcpToolApprovalConfigFolder(
            serverName: serverName,
            configLayerStack: configLayerStack
        ) {
            try persistCustomMcpToolApprovalAt(
                configFolder: projectConfigFolder,
                serverName: serverName,
                toolName: toolName,
                fileManager: fileManager
            )
            return
        }

        let globalServers = try McpConfigStore.loadGlobalMcpServers(
            codexHome: codexHome,
            fileManager: fileManager
        )
        if globalServers[serverName] != nil {
            try persistCustomMcpToolApprovalAt(
                configFolder: codexHome,
                servers: globalServers,
                serverName: serverName,
                toolName: toolName,
                fileManager: fileManager
            )
            return
        }

        let pluginSources = enabledPluginMcpServerSources.isEmpty
            ? configuredPluginMcpToolApprovalSources(
                codexHome: codexHome,
                configLayerStack: configLayerStack,
                remoteInstalledPlugins: remoteInstalledPlugins,
                fileManager: fileManager
            )
            : enabledPluginMcpServerSources

        if let pluginConfigName = pluginConfigName(
            forServerName: serverName,
            in: pluginSources
        ) {
            try persistPluginMcpToolApproval(
                codexHome: codexHome,
                pluginConfigName: pluginConfigName,
                serverName: serverName,
                toolName: toolName,
                fileManager: fileManager
            )
            return
        }

        if pluginSources.isEmpty {
            throw McpToolApprovalPersistenceError.mcpServerNotConfigured(serverName)
        }
        throw McpToolApprovalPersistenceError.mcpServerNotConfiguredOrEnabledPlugin(serverName)
    }

    public static func configuredPluginMcpToolApprovalSources(
        codexHome: URL,
        configLayerStack: ConfigLayerStack?,
        remoteInstalledPlugins: [RemoteInstalledPluginReference] = [],
        fileManager: FileManager = .default
    ) -> [PluginMcpToolApprovalSource] {
        guard let configLayerStack else {
            return []
        }
        let effectiveConfig = configLayerStack.effectiveConfig()
        guard configFeatureEnabled("plugins", in: effectiveConfig, defaultValue: true) else {
            return []
        }

        var pluginEnablement: [String: Bool] = [:]
        if let userConfig = configLayerStack.getUserLayer()?.config,
           let root = configTable(userConfig),
           let plugins = root["plugins"].flatMap(configTable) {
            for pluginID in plugins.keys {
                guard let pluginConfig = plugins[pluginID].flatMap(configTable) else {
                    continue
                }
                pluginEnablement[pluginID] = boolConfig(pluginConfig, "enabled") ?? true
            }
        }
        for plugin in remoteInstalledPlugins {
            guard let pluginID = remoteInstalledPluginID(plugin) else {
                continue
            }
            pluginEnablement[pluginID] = plugin.enabled
        }

        return pluginEnablement.keys.sorted().compactMap { pluginID in
            guard pluginEnablement[pluginID] == true,
                  let root = activeLocalPluginRoot(
                    id: pluginID,
                    codexHome: codexHome,
                    fileManager: fileManager
                  )
            else {
                return nil
            }
            let servers = pluginMcpServerNames(root: root, fileManager: fileManager)
            guard !servers.isEmpty else {
                return nil
            }
            return PluginMcpToolApprovalSource(pluginConfigName: pluginID, mcpServers: Set(servers))
        }
    }

    private static func persistPluginMcpToolApproval(
        codexHome: URL,
        pluginConfigName: String,
        serverName: String,
        toolName: String,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = fileManager.fileExists(atPath: configFile.path)
            ? try String(contentsOf: configFile, encoding: .utf8)
            : ""
        let next = setTomlAssignment(
            in: existing,
            tablePath: ["plugins", pluginConfigName, "mcp_servers", serverName, "tools", toolName],
            key: "approval_mode",
            literal: tomlString(AppToolApproval.approve.rawValue)
        )
        try next.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private static func pluginConfigName(
        forServerName serverName: String,
        in sources: [PluginMcpToolApprovalSource]
    ) -> String? {
        sources.first { $0.mcpServers.contains(serverName) }?.pluginConfigName
    }

    private static func persistCustomMcpToolApprovalAt(
        configFolder: URL,
        serverName: String,
        toolName: String,
        fileManager: FileManager
    ) throws {
        try persistCustomMcpToolApprovalAt(
            configFolder: configFolder,
            servers: try McpConfigStore.loadGlobalMcpServers(
                codexHome: configFolder,
                fileManager: fileManager
            ),
            serverName: serverName,
            toolName: toolName,
            fileManager: fileManager
        )
    }

    private static func persistCustomMcpToolApprovalAt(
        configFolder: URL,
        servers loadedServers: [String: McpServerConfig],
        serverName: String,
        toolName: String,
        fileManager: FileManager
    ) throws {
        var servers = loadedServers
        guard var server = servers[serverName] else {
            throw McpToolApprovalPersistenceError.mcpServerNotConfigured(serverName)
        }

        server.tools[toolName] = McpServerToolConfig(approvalMode: .approve)
        servers[serverName] = server
        try McpConfigStore.replaceGlobalMcpServers(
            codexHome: configFolder,
            servers: servers,
            fileManager: fileManager
        )
    }

    private static func projectMcpToolApprovalConfigFolder(
        serverName: String,
        configLayerStack: ConfigLayerStack?
    ) -> URL? {
        guard let configLayerStack else {
            return nil
        }

        for layer in configLayerStack.layersHighToLow() {
            guard case .project = layer.name,
                  let configFolder = layer.configFolder(),
                  case let .table(table) = layer.config,
                  let mcpServersValue = table["mcp_servers"],
                  let servers = try? McpConfigStore.parseMcpServers(from: mcpServersValue),
                  servers[serverName] != nil else {
                continue
            }
            return URL(fileURLWithPath: configFolder.path, isDirectory: true)
        }
        return nil
    }

    private static func pluginMcpServerNames(root: URL, fileManager: FileManager) -> [String] {
        let manifestPath = pluginManifestMcpPath(root: root, fileManager: fileManager)
        let mcpPath = manifestPath ?? root.appendingPathComponent(".mcp.json", isDirectory: false)
        guard let data = try? Data(contentsOf: mcpPath),
              case let .object(rootObject) = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return []
        }
        let rawServers: [String: JSONValue]
        if case let .object(servers)? = rootObject["mcpServers"] {
            rawServers = servers
        } else {
            rawServers = rootObject
        }

        var serverNames: [String] = []
        for name in rawServers.keys.sorted() {
            guard case var .object(serverObject)? = rawServers[name] else {
                continue
            }
            serverObject["type"] = nil
            serverObject["oauth"] = nil
            if case let .string(cwd)? = serverObject["cwd"],
               !cwd.hasPrefix("/") {
                serverObject["cwd"] = .string(root.appendingPathComponent(cwd, isDirectory: true).path)
            }
            let configValue = JSONToToml.convert(.object([name: .object(serverObject)]))
            if (try? McpConfigStore.parseMcpServers(from: configValue)[name]) != nil {
                serverNames.append(name)
            }
        }
        return serverNames
    }

    private static func pluginManifestMcpPath(root: URL, fileManager: FileManager) -> URL? {
        for relativePath in [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"] {
            let manifest = root.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: manifest.path),
                  let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawPath = object["mcpServers"] as? String
            else {
                continue
            }
            return resolvedPluginManifestPath(root: root, rawPath: rawPath)
        }
        return nil
    }

    private static func resolvedPluginManifestPath(root: URL, rawPath: String) -> URL? {
        guard rawPath.hasPrefix("./"), rawPath.count > 2 else {
            return nil
        }
        let relative = String(rawPath.dropFirst(2))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.reduce(root) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL
    }

    private static func activeLocalPluginRoot(
        id: String,
        codexHome: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let version = activeLocalPluginVersion(
            id: id,
            codexHome: codexHome,
            fileManager: fileManager
        ) else {
            return nil
        }
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private static func activeLocalPluginVersion(
        id: String,
        codexHome: URL,
        fileManager: FileManager
    ) -> String? {
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        let installRoot = codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: installRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return entries
            .filter { isDirectory($0, fileManager: fileManager) }
            .map(\.lastPathComponent)
            .sorted()
            .last
    }

    private static func remoteInstalledPluginID(_ plugin: RemoteInstalledPluginReference) -> String? {
        guard isValidPluginSegment(plugin.pluginName),
              isValidPluginSegment(plugin.marketplaceName)
        else {
            return nil
        }
        return "\(plugin.pluginName)@\(plugin.marketplaceName)"
    }

    private static func isValidPluginSegment(_ segment: String) -> Bool {
        !segment.isEmpty && segment.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func configFeatureEnabled(
        _ key: String,
        in config: ConfigValue,
        defaultValue: Bool
    ) -> Bool {
        guard let root = configTable(config),
              let features = root["features"].flatMap(configTable),
              let value = features[key]
        else {
            return defaultValue
        }
        return boolConfigValue(value) ?? defaultValue
    }

    private static func configTable(_ value: ConfigValue) -> [String: ConfigValue]? {
        if case let .table(table) = value {
            return table
        }
        return nil
    }

    private static func boolConfig(_ table: [String: ConfigValue], _ key: String) -> Bool? {
        table[key].flatMap(boolConfigValue)
    }

    private static func boolConfigValue(_ value: ConfigValue) -> Bool? {
        if case let .bool(bool) = value {
            return bool
        }
        return nil
    }

    private static func setTomlAssignment(
        in contents: String,
        tablePath: [String],
        key: String,
        literal: String
    ) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines == [""] {
            lines = []
        }

        let header = "[\(tablePath.map(tomlKey).joined(separator: "."))]"
        if let tableStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            let tableEnd = nextTableIndex(in: lines, after: tableStart) ?? lines.endIndex
            if let assignmentIndex = lines[lines.index(after: tableStart)..<tableEnd].firstIndex(
                where: { lineContainsAssignment($0, key: key) }
            ) {
                lines[assignmentIndex] = "\(key) = \(literal)"
            } else {
                lines.insert("\(key) = \(literal)", at: lines.index(after: tableStart))
            }
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(header)
            lines.append("\(key) = \(literal)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func nextTableIndex(in lines: [String], after index: Int) -> Int? {
        lines[lines.index(after: index)...].firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }
    }

    private static func lineContainsAssignment(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("\(key) =") || trimmed.hasPrefix("\(key)=")
    }

    private static func tomlKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return tomlString(value)
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
