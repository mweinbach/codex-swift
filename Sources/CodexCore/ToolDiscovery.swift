import Foundation

public let requestPluginInstallApprovalKindValue = "tool_suggestion"
public let requestPluginInstallPersistKey = "persist"
public let requestPluginInstallPersistAlwaysValue = "always"
public let requestPluginInstallToolName = "request_plugin_install"
public let codexAppsMCPServerName = "codex_apps"
public let disallowedConnectorIDPrefix = "connector_openai_"
public let firstPartyChatOriginators: Set<String> = ["codex_atlas", "codex_chatgpt_desktop"]
public let disallowedConnectorIDs: Set<String> = [
    "asdk_app_6938a94a61d881918ef32cb999ff937c",
    "connector_2b0a9009c9c64bf9933a3dae3f2b1254",
    "connector_3f8d1a79f27c4c7ba1a897ab13bf37dc",
    "connector_68de829bf7648191acd70a907364c67c",
    "connector_68e004f14af881919eb50893d3d9f523",
    "connector_69272cb413a081919685ec3c88d1744e"
]
public let firstPartyChatDisallowedConnectorIDs: Set<String> = [
    "connector_0f9c9d4592e54d0a9a12b3f44a1e2010"
]

public enum DiscoverableToolType: String, Codable, Equatable, Sendable {
    case connector
    case plugin
}

public enum DiscoverableToolAction: String, Codable, Equatable, Sendable {
    case install
    case enable
}

public struct ToolSuggestDiscoverable: Equatable, Sendable {
    public let type: DiscoverableToolType
    public let id: String

    public init(type: DiscoverableToolType, id: String) {
        self.type = type
        self.id = id
    }

    public func normalized() -> ToolSuggestDiscoverable? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }
        return ToolSuggestDiscoverable(type: type, id: trimmedID)
    }
}

public struct ToolSuggestDisabledTool: Equatable, Hashable, Sendable {
    public let type: DiscoverableToolType
    public let id: String

    public init(type: DiscoverableToolType, id: String) {
        self.type = type
        self.id = id
    }

    public func normalized() -> ToolSuggestDisabledTool? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }
        return ToolSuggestDisabledTool(type: type, id: trimmedID)
    }
}

public struct ToolSuggestConfig: Equatable, Sendable {
    public var discoverables: [ToolSuggestDiscoverable]
    public var disabledTools: [ToolSuggestDisabledTool]

    public init(
        discoverables: [ToolSuggestDiscoverable] = [],
        disabledTools: [ToolSuggestDisabledTool] = []
    ) {
        self.discoverables = discoverables
        self.disabledTools = disabledTools
    }
}

public struct DiscoverableConnectorInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let installURL: String?
    public let isAccessible: Bool
    public let isEnabled: Bool
    public let pluginDisplayNames: [String]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        installURL: String? = nil,
        isAccessible: Bool,
        isEnabled: Bool,
        pluginDisplayNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.installURL = installURL
        self.isAccessible = isAccessible
        self.isEnabled = isEnabled
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct DiscoverablePluginInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let hasSkills: Bool
    public let mcpServerNames: [String]
    public let appConnectorIDs: [String]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        hasSkills: Bool,
        mcpServerNames: [String],
        appConnectorIDs: [String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
        self.appConnectorIDs = appConnectorIDs
    }
}

public struct RequestPluginInstallEntry: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let toolType: DiscoverableToolType
    public let hasSkills: Bool
    public let mcpServerNames: [String]
    public let appConnectorIDs: [String]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        toolType: DiscoverableToolType,
        hasSkills: Bool,
        mcpServerNames: [String],
        appConnectorIDs: [String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.toolType = toolType
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
        self.appConnectorIDs = appConnectorIDs
    }
}

public enum DiscoverableTool: Equatable, Sendable {
    case connector(DiscoverableConnectorInfo)
    case plugin(DiscoverablePluginInfo)

    public var toolType: DiscoverableToolType {
        switch self {
        case .connector:
            return .connector
        case .plugin:
            return .plugin
        }
    }

    public var id: String {
        switch self {
        case let .connector(connector):
            return connector.id
        case let .plugin(plugin):
            return plugin.id
        }
    }

    public var name: String {
        switch self {
        case let .connector(connector):
            return connector.name
        case let .plugin(plugin):
            return plugin.name
        }
    }

    public var installURL: String? {
        switch self {
        case let .connector(connector):
            return connector.installURL
        case .plugin:
            return nil
        }
    }
}

public func collectRequestPluginInstallEntries(
    _ discoverableTools: [DiscoverableTool]
) -> [RequestPluginInstallEntry] {
    discoverableTools.map { tool in
        switch tool {
        case let .connector(connector):
            return RequestPluginInstallEntry(
                id: connector.id,
                name: connector.name,
                description: connector.description,
                toolType: .connector,
                hasSkills: false,
                mcpServerNames: [],
                appConnectorIDs: []
            )
        case let .plugin(plugin):
            return RequestPluginInstallEntry(
                id: plugin.id,
                name: plugin.name,
                description: plugin.description,
                toolType: .plugin,
                hasSkills: plugin.hasSkills,
                mcpServerNames: plugin.mcpServerNames,
                appConnectorIDs: plugin.appConnectorIDs
            )
        }
    }
}

public struct RequestPluginInstallArgs: Equatable, Codable, Sendable {
    public let toolType: DiscoverableToolType
    public let actionType: DiscoverableToolAction
    public let toolID: String
    public let suggestReason: String

    private enum CodingKeys: String, CodingKey {
        case toolType = "tool_type"
        case actionType = "action_type"
        case toolID = "tool_id"
        case suggestReason = "suggest_reason"
    }

    public init(
        toolType: DiscoverableToolType,
        actionType: DiscoverableToolAction,
        toolID: String,
        suggestReason: String
    ) {
        self.toolType = toolType
        self.actionType = actionType
        self.toolID = toolID
        self.suggestReason = suggestReason
    }
}

public struct RequestPluginInstallResult: Equatable, Codable, Sendable {
    public let completed: Bool
    public let userConfirmed: Bool
    public let toolType: DiscoverableToolType
    public let actionType: DiscoverableToolAction
    public let toolID: String
    public let toolName: String
    public let suggestReason: String

    private enum CodingKeys: String, CodingKey {
        case completed
        case userConfirmed = "user_confirmed"
        case toolType = "tool_type"
        case actionType = "action_type"
        case toolID = "tool_id"
        case toolName = "tool_name"
        case suggestReason = "suggest_reason"
    }
}

public struct RequestPluginInstallMeta: Equatable, Codable, Sendable {
    public let codexApprovalKind: String
    public let persist: String
    public let toolType: DiscoverableToolType
    public let suggestType: DiscoverableToolAction
    public let suggestReason: String
    public let toolID: String
    public let toolName: String
    public let installURL: String?

    private enum CodingKeys: String, CodingKey {
        case codexApprovalKind = "codex_approval_kind"
        case persist
        case toolType = "tool_type"
        case suggestType = "suggest_type"
        case suggestReason = "suggest_reason"
        case toolID = "tool_id"
        case toolName = "tool_name"
        case installURL = "install_url"
    }

    public init(
        toolType: DiscoverableToolType,
        suggestType: DiscoverableToolAction,
        suggestReason: String,
        toolID: String,
        toolName: String,
        installURL: String?
    ) {
        self.codexApprovalKind = requestPluginInstallApprovalKindValue
        self.persist = requestPluginInstallPersistAlwaysValue
        self.toolType = toolType
        self.suggestType = suggestType
        self.suggestReason = suggestReason
        self.toolID = toolID
        self.toolName = toolName
        self.installURL = installURL
    }
}

public func filterRequestPluginInstallDiscoverableToolsForClient(
    _ discoverableTools: [DiscoverableTool],
    appServerClientName: String?
) -> [DiscoverableTool] {
    guard appServerClientName == "codex-tui" else {
        return discoverableTools
    }
    return discoverableTools.filter { tool in
        if case .plugin = tool {
            return false
        }
        return true
    }
}

public func filterToolSuggestDiscoverableConnectors(
    directoryConnectors: [DiscoverableConnectorInfo],
    accessibleConnectors: [DiscoverableConnectorInfo],
    discoverableConnectorIDs: Set<String>,
    originatorValue: String
) -> [DiscoverableConnectorInfo] {
    let accessibleConnectorIDs = Set(
        accessibleConnectors
            .filter(\.isAccessible)
            .map(\.id)
    )
    return filterDisallowedConnectors(directoryConnectors, originatorValue: originatorValue)
        .filter { connector in !accessibleConnectorIDs.contains(connector.id) }
        .filter { connector in discoverableConnectorIDs.contains(connector.id) }
        .sorted {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id < $1.id
        }
}

public func filterDisallowedConnectors(
    _ connectors: [DiscoverableConnectorInfo],
    originatorValue: String
) -> [DiscoverableConnectorInfo] {
    connectors.filter { connector in
        isConnectorIDAllowed(connector.id, originatorValue: originatorValue)
    }
}

public func isConnectorIDAllowed(_ connectorID: String, originatorValue: String) -> Bool {
    if connectorID.hasPrefix(disallowedConnectorIDPrefix) {
        return false
    }
    if firstPartyChatOriginators.contains(originatorValue) {
        return !firstPartyChatDisallowedConnectorIDs.contains(connectorID)
    }
    return !disallowedConnectorIDs.contains(connectorID)
}

public func buildRequestPluginInstallElicitationRequest(
    serverName: String,
    threadID: String,
    turnID: String,
    args: RequestPluginInstallArgs,
    suggestReason: String,
    tool: DiscoverableTool
) throws -> AppServerProtocol.McpServerElicitationRequestParams {
    AppServerProtocol.McpServerElicitationRequestParams(
        threadID: threadID,
        turnID: turnID,
        serverName: serverName,
        request: .form(
            meta: try JSONValue.codexEncoded(RequestPluginInstallMeta(
                toolType: args.toolType,
                suggestType: args.actionType,
                suggestReason: suggestReason,
                toolID: tool.id,
                toolName: tool.name,
                installURL: tool.installURL
            )),
            message: suggestReason,
            requestedSchema: AppServerProtocol.McpElicitationSchema(
                properties: [:],
                required: nil
            )
        )
    )
}

public func allRequestedConnectorsPickedUp(
    expectedConnectorIDs: [String],
    accessibleConnectors: [DiscoverableConnectorInfo]
) -> Bool {
    expectedConnectorIDs.allSatisfy { connectorID in
        verifiedConnectorInstallCompleted(toolID: connectorID, accessibleConnectors: accessibleConnectors)
    }
}

public func verifiedConnectorInstallCompleted(
    toolID: String,
    accessibleConnectors: [DiscoverableConnectorInfo]
) -> Bool {
    accessibleConnectors.first { $0.id == toolID }?.isAccessible == true
}

public func requestPluginInstallResponseRequestsPersistentDisable(
    action: String,
    meta: JSONValue?
) -> Bool {
    guard action == "decline",
          case let .object(metaObject)? = meta,
          case let .string(persistValue)? = metaObject[requestPluginInstallPersistKey]
    else {
        return false
    }
    return persistValue == requestPluginInstallPersistAlwaysValue
}

public func disabledInstallRequest(for tool: DiscoverableTool) -> ToolSuggestDisabledTool {
    switch tool {
    case let .connector(connector):
        return ToolSuggestDisabledTool(type: .connector, id: connector.id)
    case let .plugin(plugin):
        return ToolSuggestDisabledTool(type: .plugin, id: plugin.id)
    }
}

@discardableResult
public func persistDisabledInstallRequest(
    codexHome: URL,
    tool: DiscoverableTool,
    fileManager: FileManager = .default
) throws -> ConfigValue {
    let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
    var config = try CodexConfigLayerLoader.readConfig(from: configFile, fileManager: fileManager) ?? .table([:])
    addToolSuggestDisabledTool(disabledInstallRequest(for: tool), to: &config)
    try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try ConfigTomlRenderer.render(config).write(to: configFile, atomically: true, encoding: .utf8)
    return config
}

public func addToolSuggestDisabledTool(
    _ disabledTool: ToolSuggestDisabledTool,
    to config: inout ConfigValue
) {
    guard let normalizedNew = disabledTool.normalized() else {
        return
    }
    var root: [String: ConfigValue]
    if case let .table(table) = config {
        root = table
    } else {
        root = [:]
    }
    var toolSuggest: [String: ConfigValue]
    if case let .table(table)? = root["tool_suggest"] {
        toolSuggest = table
    } else {
        toolSuggest = [:]
    }

    var seen: Set<ToolSuggestDisabledTool> = []
    var disabledTools: [ToolSuggestDisabledTool] = []
    for existing in existingToolSuggestDisabledTools(from: toolSuggest["disabled_tools"]) + [normalizedNew] {
        guard let normalized = existing.normalized(),
              seen.insert(normalized).inserted
        else {
            continue
        }
        disabledTools.append(normalized)
    }
    toolSuggest["disabled_tools"] = .array(disabledTools.map(configValue))
    root["tool_suggest"] = .table(toolSuggest)
    config = .table(root)
}

private func existingToolSuggestDisabledTools(from value: ConfigValue?) -> [ToolSuggestDisabledTool] {
    guard case let .array(entries)? = value else {
        return []
    }
    return entries.compactMap { entry in
        guard case let .table(table) = entry,
              case let .string(type)? = table["type"],
              case let .string(id)? = table["id"]
        else {
            return nil
        }
        switch type {
        case "connector":
            return ToolSuggestDisabledTool(type: .connector, id: id)
        case "plugin":
            return ToolSuggestDisabledTool(type: .plugin, id: id)
        default:
            return nil
        }
    }
}

private func configValue(for disabledTool: ToolSuggestDisabledTool) -> ConfigValue {
    .table([
        "type": .string(disabledTool.type.rawValue),
        "id": .string(disabledTool.id)
    ])
}

public func accessibleConnectorsFromMCPTools(
    _ tools: [String: McpTool],
    codexAppsServerName: String = codexAppsMCPServerName,
    originatorValue: String = "codex_swift"
) -> [DiscoverableConnectorInfo] {
    var connectorsByID: [String: (connector: DiscoverableConnectorInfo, pluginDisplayNames: Set<String>)] = [:]
    for (qualifiedName, tool) in tools where mcpToolServerName(from: qualifiedName) == codexAppsServerName {
        guard let rawConnectorID = tool.connectorID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawConnectorID.isEmpty
        else {
            continue
        }
        let connectorName = normalizeConnectorValue(tool.connectorName) ?? rawConnectorID
        let connectorDescription = normalizeConnectorValue(tool.namespaceDescription)
        let pluginDisplayNames = Set(tool.pluginDisplayNames)

        if var existing = connectorsByID[rawConnectorID] {
            var connector = existing.connector
            if connector.name == rawConnectorID, connectorName != rawConnectorID {
                connector = DiscoverableConnectorInfo(
                    id: connector.id,
                    name: connectorName,
                    description: connector.description,
                    installURL: connector.installURL,
                    isAccessible: connector.isAccessible,
                    isEnabled: connector.isEnabled,
                    pluginDisplayNames: connector.pluginDisplayNames
                )
            }
            if connector.description == nil, let connectorDescription {
                connector = DiscoverableConnectorInfo(
                    id: connector.id,
                    name: connector.name,
                    description: connectorDescription,
                    installURL: connector.installURL,
                    isAccessible: connector.isAccessible,
                    isEnabled: connector.isEnabled,
                    pluginDisplayNames: connector.pluginDisplayNames
                )
            }
            existing.pluginDisplayNames.formUnion(pluginDisplayNames)
            existing.connector = connector
            connectorsByID[rawConnectorID] = existing
        } else {
            connectorsByID[rawConnectorID] = (
                DiscoverableConnectorInfo(
                    id: rawConnectorID,
                    name: connectorName,
                    description: connectorDescription,
                    installURL: connectorInstallURL(name: connectorName, connectorID: rawConnectorID),
                    isAccessible: true,
                    isEnabled: true
                ),
                pluginDisplayNames
            )
        }
    }

    let connectors = connectorsByID.values
        .map { entry in
            DiscoverableConnectorInfo(
                id: entry.connector.id,
                name: entry.connector.name,
                description: entry.connector.description,
                installURL: connectorInstallURL(name: entry.connector.name, connectorID: entry.connector.id),
                isAccessible: true,
                isEnabled: true,
                pluginDisplayNames: entry.pluginDisplayNames.sorted()
            )
        }
        .sorted {
            if $0.isAccessible != $1.isAccessible {
                return $0.isAccessible && !$1.isAccessible
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id < $1.id
        }
    return filterDisallowedConnectors(connectors, originatorValue: originatorValue)
}

private extension JSONValue {
    static func codexEncoded<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private func mcpToolServerName(from qualifiedName: String) -> String {
    if qualifiedName.hasPrefix("mcp__") {
        let remainder = qualifiedName.dropFirst("mcp__".count)
        if let delimiterRange = remainder.range(of: "__") {
            return String(remainder[..<delimiterRange.lowerBound])
        }
    }
    if let slashIndex = qualifiedName.firstIndex(of: "/") {
        return String(qualifiedName[..<slashIndex])
    }
    return qualifiedName
}

private func normalizeConnectorValue(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func connectorInstallURL(name: String, connectorID: String) -> String {
    "https://chatgpt.com/apps/\(connectorNameSlug(name))/\(connectorID)"
}

private func connectorNameSlug(_ value: String) -> String {
    var slug = ""
    for scalar in value.unicodeScalars {
        if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
            slug.unicodeScalars.append(UnicodeScalar(String(scalar).lowercased())!)
        } else {
            slug.append("-")
        }
    }
    let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "app" : trimmed
}
