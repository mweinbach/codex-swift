import CryptoKit
import Foundation

public struct McpStartupUpdateEvent: Equatable, Codable, Sendable {
    public let server: String
    public let status: McpStartupStatus

    public init(server: String, status: McpStartupStatus) {
        self.server = server
        self.status = status
    }
}

public enum McpStartupStatus: Equatable, Codable, Sendable {
    case starting
    case ready
    case failed(error: String)
    case cancelled

    private enum CodingKeys: String, CodingKey {
        case state
        case error
    }

    private enum State: String, Codable {
        case starting
        case ready
        case failed
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .starting:
            self = .starting
        case .ready:
            self = .ready
        case .failed:
            self = .failed(error: try container.decode(String.self, forKey: .error))
        case .cancelled:
            self = .cancelled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .starting:
            try container.encode(State.starting, forKey: .state)
        case .ready:
            try container.encode(State.ready, forKey: .state)
        case let .failed(error):
            try container.encode(State.failed, forKey: .state)
            try container.encode(error, forKey: .error)
        case .cancelled:
            try container.encode(State.cancelled, forKey: .state)
        }
    }
}

public struct McpStartupCompleteEvent: Equatable, Codable, Sendable {
    public let ready: [String]
    public let failed: [McpStartupFailure]
    public let cancelled: [String]

    public init(ready: [String] = [], failed: [McpStartupFailure] = [], cancelled: [String] = []) {
        self.ready = ready
        self.failed = failed
        self.cancelled = cancelled
    }
}

public struct McpStartupFailure: Equatable, Codable, Sendable {
    public let server: String
    public let error: String

    public init(server: String, error: String) {
        self.server = server
        self.error = error
    }
}

public struct McpToolInfo: Equatable, Sendable {
    public let callableName: String
    public let callableNamespace: String
    public let serverName: String
    public let namespaceDescription: String?
    public let tool: McpTool

    public init(
        serverName: String,
        namespaceDescription: String? = nil,
        tool: McpTool,
        callableNamespace: String? = nil,
        callableName: String? = nil
    ) {
        self.callableName = callableName ?? tool.name
        self.callableNamespace = callableNamespace ?? "\(McpToolName.prefix)\(McpToolName.delimiter)\(serverName)\(McpToolName.delimiter)"
        self.serverName = serverName
        self.namespaceDescription = namespaceDescription
        self.tool = tool
    }

    public var canonicalToolName: String {
        "\(callableNamespace)\(callableName)"
    }
}

public enum McpToolName {
    public static let prefix = "mcp"
    public static let delimiter = "__"
    public static let maximumLength = 64
    private static let callableNameHashLength = 12

    public static func qualifiedToolName(serverName: String, toolName: String) -> String {
        var qualifiedName = "\(prefix)\(delimiter)\(serverName)\(delimiter)\(toolName)"
        guard qualifiedName.utf8.count > maximumLength else {
            return qualifiedName
        }

        let digest = Insecure.SHA1.hash(data: Data(qualifiedName.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        let prefixLength = maximumLength - suffix.count
        qualifiedName = String(decoding: qualifiedName.utf8.prefix(prefixLength), as: UTF8.self) + suffix
        return qualifiedName
    }

    public static func splitQualifiedToolName(_ qualifiedName: String) -> (serverName: String, toolName: String)? {
        let parts = qualifiedName.components(separatedBy: delimiter)
        guard parts.first == prefix, parts.count >= 2 else {
            return nil
        }

        let toolName = parts.dropFirst(2).joined(separator: delimiter)
        guard !toolName.isEmpty else {
            return nil
        }

        return (serverName: parts[1], toolName: toolName)
    }

    public static func groupToolsByServer(_ tools: [String: McpTool]) -> [String: [String: McpTool]] {
        var grouped: [String: [String: McpTool]] = [:]
        for (qualifiedName, tool) in tools {
            guard let split = splitQualifiedToolName(qualifiedName) else {
                continue
            }
            grouped[split.serverName, default: [:]][split.toolName] = tool
        }
        return grouped
    }

    public static func qualifyTools(_ tools: [(serverName: String, tool: McpTool)]) -> [String: McpTool] {
        var qualifiedTools: [String: McpTool] = [:]
        var usedNames = Set<String>()
        for entry in tools {
            let qualifiedName = qualifiedToolName(serverName: entry.serverName, toolName: entry.tool.name)
            guard !usedNames.contains(qualifiedName) else {
                continue
            }
            usedNames.insert(qualifiedName)
            qualifiedTools[qualifiedName] = entry.tool
        }
        return qualifiedTools
    }

    public static func normalizeToolsForModel(_ tools: [McpToolInfo]) -> [McpToolInfo] {
        var seenRawNames = Set<String>()
        var candidates: [CallableToolCandidate] = []
        for tool in tools {
            let rawNamespaceIdentity = [
                tool.serverName,
                tool.callableNamespace,
                tool.tool.connectorID ?? ""
            ].joined(separator: "\0")
            let rawToolIdentity = [
                rawNamespaceIdentity,
                tool.callableName,
                tool.tool.name
            ].joined(separator: "\0")
            guard seenRawNames.insert(rawToolIdentity).inserted else {
                continue
            }

            candidates.append(CallableToolCandidate(
                tool: tool,
                rawNamespaceIdentity: rawNamespaceIdentity,
                rawToolIdentity: rawToolIdentity,
                callableNamespace: sanitizeResponsesAPIToolName(tool.callableNamespace),
                callableName: sanitizeResponsesAPIToolName(tool.callableName)
            ))
        }

        let namespaceIdentitiesByBase = Dictionary(grouping: candidates, by: \.callableNamespace)
            .mapValues { Set($0.map(\.rawNamespaceIdentity)) }
        let collidingNamespaces = Set(namespaceIdentitiesByBase.compactMap { namespace, identities in
            identities.count > 1 ? namespace : nil
        })
        for index in candidates.indices where collidingNamespaces.contains(candidates[index].callableNamespace) {
            candidates[index].callableNamespace = appendNamespaceHashSuffix(
                to: candidates[index].callableNamespace,
                rawIdentity: candidates[index].rawNamespaceIdentity
            )
        }

        let toolIdentitiesByBase = Dictionary(grouping: candidates) { candidate in
            CallableToolKey(namespace: candidate.callableNamespace, name: candidate.callableName)
        }.mapValues { Set($0.map(\.rawToolIdentity)) }
        let collidingTools = Set(toolIdentitiesByBase.compactMap { key, identities in
            identities.count > 1 ? key : nil
        })
        for index in candidates.indices {
            let key = CallableToolKey(namespace: candidates[index].callableNamespace, name: candidates[index].callableName)
            if collidingTools.contains(key) {
                candidates[index].callableName = appendHashSuffix(
                    to: candidates[index].callableName,
                    rawIdentity: candidates[index].rawToolIdentity
                )
            }
        }

        candidates.sort { $0.rawToolIdentity < $1.rawToolIdentity }

        var normalizedTools: [McpToolInfo] = []
        var usedNames = Set<String>()
        for candidate in candidates {
            let parts = uniqueCallableParts(
                namespace: candidate.callableNamespace,
                toolName: candidate.callableName,
                rawIdentity: candidate.rawToolIdentity,
                usedNames: &usedNames
            )
            normalizedTools.append(McpToolInfo(
                serverName: candidate.tool.serverName,
                namespaceDescription: candidate.tool.namespaceDescription,
                tool: candidate.tool.tool,
                callableNamespace: parts.namespace,
                callableName: parts.name
            ))
        }
        return normalizedTools
    }

    private static func sanitizeResponsesAPIToolName(_ name: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            if (CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII) || scalar == "_" {
                sanitized.unicodeScalars.append(scalar)
            } else {
                sanitized.append("_")
            }
        }
        return sanitized.isEmpty ? "_" : sanitized
    }

    private static func callableNameHashSuffix(rawIdentity: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(rawIdentity.utf8))
        return "_" + digest.map { String(format: "%02x", $0) }.joined().prefix(callableNameHashLength)
    }

    private static func appendHashSuffix(to value: String, rawIdentity: String) -> String {
        value + callableNameHashSuffix(rawIdentity: rawIdentity)
    }

    private static func appendNamespaceHashSuffix(to namespace: String, rawIdentity: String) -> String {
        if namespace.hasSuffix(delimiter) {
            return String(namespace.dropLast(delimiter.count))
                + callableNameHashSuffix(rawIdentity: rawIdentity)
                + delimiter
        }
        return appendHashSuffix(to: namespace, rawIdentity: rawIdentity)
    }

    private static func truncateName(_ value: String, maximumCount: Int) -> String {
        String(value.prefix(maximumCount))
    }

    private static func fitCallablePartsWithHash(
        namespace: String,
        toolName: String,
        rawIdentity: String
    ) -> (namespace: String, name: String) {
        let suffix = callableNameHashSuffix(rawIdentity: rawIdentity)
        let maximumToolLength = max(0, maximumLength - namespace.count)
        if maximumToolLength >= suffix.count {
            let prefixLength = maximumToolLength - suffix.count
            return (namespace, truncateName(toolName, maximumCount: prefixLength) + suffix)
        }

        let maximumNamespaceLength = maximumLength - suffix.count
        return (truncateName(namespace, maximumCount: maximumNamespaceLength), suffix)
    }

    private static func uniqueCallableParts(
        namespace: String,
        toolName: String,
        rawIdentity: String,
        usedNames: inout Set<String>
    ) -> (namespace: String, name: String) {
        let modelName = namespace + toolName
        if modelName.count <= maximumLength, usedNames.insert(modelName).inserted {
            return (namespace, toolName)
        }

        var attempt: UInt32 = 0
        while true {
            let hashInput = attempt == 0 ? rawIdentity : "\(rawIdentity)\0\(attempt)"
            let parts = fitCallablePartsWithHash(namespace: namespace, toolName: toolName, rawIdentity: hashInput)
            if usedNames.insert(parts.namespace + parts.name).inserted {
                return parts
            }
            attempt = attempt == UInt32.max ? UInt32.max : attempt + 1
        }
    }
}

private struct CallableToolCandidate {
    let tool: McpToolInfo
    let rawNamespaceIdentity: String
    let rawToolIdentity: String
    var callableNamespace: String
    var callableName: String
}

private struct CallableToolKey: Hashable {
    let namespace: String
    let name: String
}

/// Port of codex-rs/core/src/mcp_connection_manager.rs ToolFilter.
public struct McpToolFilter: Equatable, Sendable {
    public var enabled: Set<String>?
    public var disabled: Set<String>

    public init(enabled: Set<String>? = nil, disabled: Set<String> = []) {
        self.enabled = enabled
        self.disabled = disabled
    }

    public init(config: McpServerConfig) {
        self.enabled = config.enabledTools.map(Set.init)
        self.disabled = Set(config.disabledTools ?? [])
    }

    public func allows(_ toolName: String) -> Bool {
        if let enabled, !enabled.contains(toolName) {
            return false
        }
        return !disabled.contains(toolName)
    }

    public func filterTools(_ tools: [(serverName: String, tool: McpTool)]) -> [(serverName: String, tool: McpTool)] {
        tools.filter { allows($0.tool.name) }
    }
}

public enum McpRole: String, Codable, Equatable, Sendable {
    case assistant
    case user
}

public struct McpAnnotations: Equatable, Codable, Sendable {
    public let additionalProperties: [String: JSONValue]
    public let audience: [McpRole]?
    public let lastModified: String?
    public let priority: Double?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case audience
        case lastModified = "lastModified"
        case priority
    }

    public init(
        audience: [McpRole]? = nil,
        lastModified: String? = nil,
        priority: Double? = nil,
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.additionalProperties = additionalProperties
        self.audience = audience
        self.lastModified = lastModified
        self.priority = priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: McpDynamicCodingKey.self)
        var additionalProperties: [String: JSONValue] = [:]
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))

        audience = try? container.decodeIfPresent([McpRole].self, forKey: .audience)
        lastModified = try? container.decodeIfPresent(String.self, forKey: .lastModified)
        priority = try? container.decodeIfPresent(Double.self, forKey: .priority)

        for key in dynamicContainer.allKeys {
            let value = try dynamicContainer.decode(JSONValue.self, forKey: key)
            if !knownKeys.contains(key.stringValue)
                || (key.stringValue == CodingKeys.audience.rawValue && audience == nil)
                || (key.stringValue == CodingKeys.lastModified.rawValue && lastModified == nil)
                || (key.stringValue == CodingKeys.priority.rawValue && priority == nil) {
                additionalProperties[key.stringValue] = value
            }
        }
        self.additionalProperties = additionalProperties
    }

    public func encode(to encoder: Encoder) throws {
        var dynamicContainer = encoder.container(keyedBy: McpDynamicCodingKey.self)
        for key in additionalProperties.keys.sorted() {
            try dynamicContainer.encode(additionalProperties[key], forKey: McpDynamicCodingKey(stringValue: key))
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(audience, forKey: .audience)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encodeIfPresent(priority, forKey: .priority)
    }
}

public struct McpResource: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let description: String?
    public let icons: [JSONValue]?
    public let meta: JSONValue?
    public let mimeType: String?
    public let name: String
    public let size: Int64?
    public let title: String?
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
        case icons
        case meta = "_meta"
        case mimeType = "mimeType"
        case mimeTypeSnake = "mime_type"
        case name
        case size
        case title
        case uri
    }

    public init(
        name: String,
        uri: String,
        annotations: McpAnnotations? = nil,
        description: String? = nil,
        icons: [JSONValue]? = nil,
        meta: JSONValue? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
        self.icons = icons
        self.meta = meta
        self.mimeType = mimeType
        self.name = name
        self.size = size
        self.title = title
        self.uri = uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decodeIfPresent(McpAnnotations.self, forKey: .annotations)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icons = try container.decodeIfPresent([JSONValue].self, forKey: .icons)
        meta = try container.decodeIfPresent(JSONValue.self, forKey: .meta)
        if container.contains(.mimeType), container.contains(.mimeTypeSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .mimeType,
                in: container,
                debugDescription: "duplicate MCP resource mimeType field"
            )
        }
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
        name = try container.decode(String.self, forKey: .name)
        size = try Self.decodeLossySize(from: container)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        uri = try container.decode(String.self, forKey: .uri)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(icons, forKey: .icons)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(uri, forKey: .uri)
    }

    private static func decodeLossySize(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int64? {
        guard container.contains(.size) else {
            return nil
        }
        let value = try container.decode(JSONValue.self, forKey: .size)
        switch value {
        case .null:
            return nil
        case let .integer(size):
            return size
        case .double:
            return nil
        case .bool, .string, .array, .object:
            throw DecodingError.typeMismatch(
                Int64?.self,
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.size],
                    debugDescription: "Expected MCP resource size to be a JSON number"
                )
            )
        }
    }
}

public struct McpResourceTemplate: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let description: String?
    public let mimeType: String?
    public let name: String
    public let title: String?
    public let uriTemplate: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
        case mimeType = "mimeType"
        case mimeTypeSnake = "mime_type"
        case name
        case title
        case uriTemplate = "uriTemplate"
        case uriTemplateSnake = "uri_template"
    }

    public init(
        name: String,
        uriTemplate: String,
        annotations: McpAnnotations? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
        self.mimeType = mimeType
        self.name = name
        self.title = title
        self.uriTemplate = uriTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decodeIfPresent(McpAnnotations.self, forKey: .annotations)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        if container.contains(.mimeType), container.contains(.mimeTypeSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .mimeType,
                in: container,
                debugDescription: "duplicate MCP resource template mimeType field"
            )
        }
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        if container.contains(.uriTemplate), container.contains(.uriTemplateSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .uriTemplate,
                in: container,
                debugDescription: "duplicate MCP resource template uriTemplate field"
            )
        }
        uriTemplate = try container.decodeIfPresent(String.self, forKey: .uriTemplate)
            ?? container.decode(String.self, forKey: .uriTemplateSnake)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(uriTemplate, forKey: .uriTemplate)
    }
}

public struct McpTool: Equatable, Codable, Sendable {
    public let annotations: McpToolAnnotations?
    public let connectorID: String?
    public let connectorName: String?
    public let description: String?
    public let icons: [JSONValue]?
    public let inputSchema: McpToolInputSchema
    public let meta: JSONValue?
    public let name: String
    public let namespaceDescription: String?
    public let outputSchema: McpToolOutputSchema?
    public let pluginDisplayNames: [String]
    public let title: String?

    private enum CodingKeys: String, CodingKey {
        case annotations
        case connectorID = "connector_id"
        case connectorName = "connector_name"
        case description
        case icons
        case inputSchema = "inputSchema"
        case inputSchemaSnake = "input_schema"
        case meta = "_meta"
        case name
        case namespaceDescription = "namespace_description"
        case outputSchema = "outputSchema"
        case outputSchemaSnake = "output_schema"
        case pluginDisplayNames = "plugin_display_names"
        case title
    }

    public init(
        name: String,
        inputSchema: McpToolInputSchema,
        annotations: McpToolAnnotations? = nil,
        connectorID: String? = nil,
        connectorName: String? = nil,
        description: String? = nil,
        icons: [JSONValue]? = nil,
        meta: JSONValue? = nil,
        namespaceDescription: String? = nil,
        outputSchema: McpToolOutputSchema? = nil,
        pluginDisplayNames: [String] = [],
        title: String? = nil
    ) {
        self.annotations = annotations
        self.connectorID = connectorID
        self.connectorName = connectorName
        self.description = description
        self.icons = icons
        self.inputSchema = inputSchema
        self.meta = meta
        self.name = name
        self.namespaceDescription = namespaceDescription
        self.outputSchema = outputSchema
        self.pluginDisplayNames = pluginDisplayNames
        self.title = title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decodeIfPresent(McpToolAnnotations.self, forKey: .annotations)
        connectorID = try container.decodeIfPresent(String.self, forKey: .connectorID)
        connectorName = try container.decodeIfPresent(String.self, forKey: .connectorName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icons = try container.decodeIfPresent([JSONValue].self, forKey: .icons)
        if container.contains(.inputSchema), container.contains(.inputSchemaSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .inputSchema,
                in: container,
                debugDescription: "duplicate MCP tool inputSchema field"
            )
        }
        inputSchema = try container.decodeIfPresent(McpToolInputSchema.self, forKey: .inputSchema)
            ?? container.decodeIfPresent(McpToolInputSchema.self, forKey: .inputSchemaSnake)
            ?? McpToolInputSchema(rawValue: .null)
        meta = try container.decodeIfPresent(JSONValue.self, forKey: .meta)
        name = try container.decode(String.self, forKey: .name)
        namespaceDescription = try container.decodeIfPresent(String.self, forKey: .namespaceDescription)
        if container.contains(.outputSchema), container.contains(.outputSchemaSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .outputSchema,
                in: container,
                debugDescription: "duplicate MCP tool outputSchema field"
            )
        }
        outputSchema = try container.decodeIfPresent(McpToolOutputSchema.self, forKey: .outputSchema)
            ?? container.decodeIfPresent(McpToolOutputSchema.self, forKey: .outputSchemaSnake)
        pluginDisplayNames = try container.decodeRustDefaulted(
            [String].self,
            forKey: .pluginDisplayNames,
            defaultValue: []
        )
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encodeIfPresent(connectorID, forKey: .connectorID)
        try container.encodeIfPresent(connectorName, forKey: .connectorName)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(icons, forKey: .icons)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(namespaceDescription, forKey: .namespaceDescription)
        try container.encodeIfPresent(outputSchema, forKey: .outputSchema)
        if !pluginDisplayNames.isEmpty {
            try container.encode(pluginDisplayNames, forKey: .pluginDisplayNames)
        }
        try container.encodeIfPresent(title, forKey: .title)
    }
}

public struct McpToolInputSchema: Equatable, Codable, Sendable {
    public let rawValue: JSONValue

    private enum CodingKeys: String, CodingKey {
        case properties
        case required
        case type
    }

    public init(properties: JSONValue? = nil, required: [String]? = nil, type: String = "object") {
        var object: [String: JSONValue] = ["type": .string(type)]
        if let properties {
            object["properties"] = properties
        }
        if let required {
            object["required"] = .array(required.map(JSONValue.string))
        }
        self.rawValue = .object(object)
    }

    public init(rawValue: JSONValue) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        self.rawValue = try JSONValue(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    public var properties: JSONValue? {
        guard case let .object(object) = rawValue else {
            return nil
        }
        return object["properties"]
    }

    public var required: [String]? {
        guard case let .object(object) = rawValue,
              case let .array(values)? = object["required"]
        else {
            return nil
        }
        let strings = values.compactMap { value -> String? in
            guard case let .string(string) = value else {
                return nil
            }
            return string
        }
        return strings.count == values.count ? strings : nil
    }

    public var type: String {
        guard case let .object(object) = rawValue,
              case let .string(type)? = object["type"]
        else {
            return "object"
        }
        return type
    }
}

public struct McpToolOutputSchema: Equatable, Codable, Sendable {
    public let properties: JSONValue?
    public let required: [String]?
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case properties
        case required
        case type
    }

    public init(properties: JSONValue? = nil, required: [String]? = nil, type: String = "object") {
        self.properties = properties
        self.required = required
        self.type = type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.properties = try container.decodeIfPresent(JSONValue.self, forKey: .properties)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encode(type, forKey: .type)
    }

    var jsonSchema: JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type)
        ]
        if let properties {
            object["properties"] = properties
        }
        if let required {
            object["required"] = .array(required.map(JSONValue.string))
        }
        return .object(object)
    }
}

public struct McpToolAnnotations: Equatable, Codable, Sendable {
    public let additionalProperties: [String: JSONValue]
    public let destructiveHint: Bool?
    public let idempotentHint: Bool?
    public let openWorldHint: Bool?
    public let readOnlyHint: Bool?
    public let title: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case destructiveHint = "destructiveHint"
        case idempotentHint = "idempotentHint"
        case openWorldHint = "openWorldHint"
        case readOnlyHint = "readOnlyHint"
        case title
    }

    public init(
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil,
        readOnlyHint: Bool? = nil,
        title: String? = nil,
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.additionalProperties = additionalProperties
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
        self.readOnlyHint = readOnlyHint
        self.title = title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: McpDynamicCodingKey.self)
        var additionalProperties: [String: JSONValue] = [:]
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))

        destructiveHint = try? container.decodeIfPresent(Bool.self, forKey: .destructiveHint)
        idempotentHint = try? container.decodeIfPresent(Bool.self, forKey: .idempotentHint)
        openWorldHint = try? container.decodeIfPresent(Bool.self, forKey: .openWorldHint)
        readOnlyHint = try? container.decodeIfPresent(Bool.self, forKey: .readOnlyHint)
        title = try? container.decodeIfPresent(String.self, forKey: .title)

        for key in dynamicContainer.allKeys {
            let value = try dynamicContainer.decode(JSONValue.self, forKey: key)
            if !knownKeys.contains(key.stringValue)
                || (key.stringValue == CodingKeys.destructiveHint.rawValue && destructiveHint == nil)
                || (key.stringValue == CodingKeys.idempotentHint.rawValue && idempotentHint == nil)
                || (key.stringValue == CodingKeys.openWorldHint.rawValue && openWorldHint == nil)
                || (key.stringValue == CodingKeys.readOnlyHint.rawValue && readOnlyHint == nil)
                || (key.stringValue == CodingKeys.title.rawValue && title == nil) {
                additionalProperties[key.stringValue] = value
            }
        }
        self.additionalProperties = additionalProperties
    }

    public func encode(to encoder: Encoder) throws {
        var dynamicContainer = encoder.container(keyedBy: McpDynamicCodingKey.self)
        for key in additionalProperties.keys.sorted() {
            try dynamicContainer.encode(additionalProperties[key], forKey: McpDynamicCodingKey(stringValue: key))
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(destructiveHint, forKey: .destructiveHint)
        try container.encodeIfPresent(idempotentHint, forKey: .idempotentHint)
        try container.encodeIfPresent(openWorldHint, forKey: .openWorldHint)
        try container.encodeIfPresent(readOnlyHint, forKey: .readOnlyHint)
        try container.encodeIfPresent(title, forKey: .title)
    }
}

private struct McpDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

public struct McpInvocation: Equatable, Codable, Sendable {
    public let server: String
    public let tool: String
    public let arguments: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case server
        case tool
        case arguments
    }

    public init(server: String, tool: String, arguments: JSONValue? = nil) {
        self.server = server
        self.tool = tool
        self.arguments = arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(server, forKey: .server)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
    }
}

public struct McpToolCallBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let invocation: McpInvocation
    public let mcpAppResourceURI: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case invocation
        case mcpAppResourceURI = "mcp_app_resource_uri"
    }

    public init(callID: String, invocation: McpInvocation, mcpAppResourceURI: String? = nil) {
        self.callID = callID
        self.invocation = invocation
        self.mcpAppResourceURI = mcpAppResourceURI
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(invocation, forKey: .invocation)
        try container.encodeIfPresent(mcpAppResourceURI, forKey: .mcpAppResourceURI)
    }
}

public struct McpToolCallEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let invocation: McpInvocation
    public let mcpAppResourceURI: String?
    public let duration: ProtocolDuration
    public let result: McpToolCallResult

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case invocation
        case mcpAppResourceURI = "mcp_app_resource_uri"
        case duration
        case result
    }

    public init(
        callID: String,
        invocation: McpInvocation,
        mcpAppResourceURI: String? = nil,
        duration: ProtocolDuration,
        result: McpToolCallResult
    ) {
        self.callID = callID
        self.invocation = invocation
        self.mcpAppResourceURI = mcpAppResourceURI
        self.duration = duration
        self.result = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(invocation, forKey: .invocation)
        try container.encodeIfPresent(mcpAppResourceURI, forKey: .mcpAppResourceURI)
        try container.encode(duration, forKey: .duration)
        try container.encode(result, forKey: .result)
    }

    public var isSuccess: Bool {
        guard case let .ok(result) = result else {
            return false
        }
        return !(result.isError ?? false)
    }
}

public enum McpToolCallResult: Equatable, Codable, Sendable {
    public static let eventResultMaxBytes = 1024 * 1024

    case ok(McpCallToolResult)
    case err(String)

    private enum CodingKeys: String, CodingKey {
        case ok = "Ok"
        case err = "Err"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(McpCallToolResult.self, forKey: .ok) {
            self = .ok(value)
            return
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .err) {
            self = .err(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            forKey: .ok,
            in: container,
            debugDescription: "Expected Rust Result shape with Ok or Err"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .ok(value):
            try container.encode(value, forKey: .ok)
        case let .err(value):
            try container.encode(value, forKey: .err)
        }
    }

    public func truncatedForEvent(maxBytes: Int = eventResultMaxBytes) -> McpToolCallResult {
        switch self {
        case let .ok(value):
            return .ok(value.truncatedForEvent(maxBytes: maxBytes))
        case let .err(message):
            return .err(Truncation.truncateText(message, policy: .bytes(maxBytes)))
        }
    }
}

public struct McpCallToolResult: Equatable, Codable, Sendable {
    public let content: [McpContentBlock]
    public let isError: Bool?
    public let structuredContent: JSONValue?
    public let meta: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case content
        case isError = "isError"
        case structuredContent = "structuredContent"
        case meta = "_meta"
    }

    public init(
        content: [McpContentBlock],
        isError: Bool? = nil,
        structuredContent: JSONValue? = nil,
        meta: JSONValue? = nil
    ) {
        self.content = content
        self.isError = isError
        self.structuredContent = structuredContent
        self.meta = meta
    }

    public func truncatedForEvent(maxBytes: Int = McpToolCallResult.eventResultMaxBytes) -> McpCallToolResult {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(self),
              encoded.count > maxBytes,
              let serialized = String(data: encoded, encoding: .utf8) else {
            return self
        }

        return McpCallToolResult(
            content: [.text(McpTextContent(text: Truncation.truncateText(serialized, policy: .bytes(maxBytes))))],
            isError: isError
        )
    }
}

public enum McpContentBlock: Equatable, Codable, Sendable {
    case text(McpTextContent)
    case image(McpImageContent)
    case audio(McpAudioContent)
    case resourceLink(McpResourceLink)
    case embeddedResource(McpEmbeddedResource)
    case unknown(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        guard let type = try container?.decodeIfPresent(String.self, forKey: .type) else {
            self = .unknown(try JSONValue(from: decoder))
            return
        }

        switch type {
        case "text":
            let value = try McpTextContent(from: decoder)
            self = .text(value)
        case "image":
            let value = try McpImageContent(from: decoder)
            self = .image(value)
        case "audio":
            let value = try McpAudioContent(from: decoder)
            self = .audio(value)
        case "resource_link":
            let value = try McpResourceLink(from: decoder)
            self = .resourceLink(value)
        case "resource":
            let value = try McpEmbeddedResource(from: decoder)
            self = .embeddedResource(value)
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(value):
            try value.encode(to: encoder)
        case let .image(value):
            try value.encode(to: encoder)
        case let .audio(value):
            try value.encode(to: encoder)
        case let .resourceLink(value):
            try value.encode(to: encoder)
        case let .embeddedResource(value):
            try value.encode(to: encoder)
        case let .unknown(value):
            try value.encode(to: encoder)
        }
    }
}

public struct McpTextContent: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let meta: JSONValue?
    public let text: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case meta = "_meta"
        case text
        case type
    }

    public init(text: String, type: String = "text", annotations: McpAnnotations? = nil, meta: JSONValue? = nil) {
        self.annotations = annotations
        self.meta = meta
        self.text = text
        self.type = type
    }
}

public struct McpImageContent: Equatable, Codable, Sendable {
    public static let imageDetailMetaKey = "codex/imageDetail"

    public let annotations: McpAnnotations?
    public let data: String
    public let meta: JSONValue?
    public let mimeType: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case data
        case meta = "_meta"
        case mimeType = "mimeType"
        case mimeTypeSnake = "mime_type"
        case type
    }

    public init(
        data: String,
        mimeType: String,
        type: String = "image",
        annotations: McpAnnotations? = nil,
        meta: JSONValue? = nil
    ) {
        self.annotations = annotations
        self.data = data
        self.meta = meta
        self.mimeType = mimeType
        self.type = type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.annotations = try container.decodeIfPresent(McpAnnotations.self, forKey: .annotations)
        self.data = try container.decode(String.self, forKey: .data)
        self.meta = try container.decodeIfPresent(JSONValue.self, forKey: .meta)
        if container.contains(.mimeType), container.contains(.mimeTypeSnake) {
            throw DecodingError.dataCorruptedError(
                forKey: .mimeType,
                in: container,
                debugDescription: "duplicate MCP image content mimeType field"
            )
        }
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
            ?? "application/octet-stream"
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "image"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(annotations, forKey: .annotations)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(type, forKey: .type)
    }
}

public struct McpAudioContent: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let data: String
    public let meta: JSONValue?
    public let mimeType: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case data
        case meta = "_meta"
        case mimeType = "mimeType"
        case type
    }

    public init(
        data: String,
        mimeType: String,
        type: String = "audio",
        annotations: McpAnnotations? = nil,
        meta: JSONValue? = nil
    ) {
        self.annotations = annotations
        self.data = data
        self.meta = meta
        self.mimeType = mimeType
        self.type = type
    }
}

public struct McpResourceLink: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let description: String?
    public let icons: [JSONValue]?
    public let meta: JSONValue?
    public let mimeType: String?
    public let name: String
    public let size: Int64?
    public let title: String?
    public let type: String
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
        case icons
        case meta = "_meta"
        case mimeType = "mimeType"
        case name
        case size
        case title
        case type
        case uri
    }

    public init(
        name: String,
        uri: String,
        type: String = "resource_link",
        annotations: McpAnnotations? = nil,
        description: String? = nil,
        icons: [JSONValue]? = nil,
        meta: JSONValue? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
        self.icons = icons
        self.meta = meta
        self.mimeType = mimeType
        self.name = name
        self.size = size
        self.title = title
        self.type = type
        self.uri = uri
    }
}

public struct McpEmbeddedResource: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let meta: JSONValue?
    public let resource: McpEmbeddedResourceResource
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case meta = "_meta"
        case resource
        case type
    }

    public init(
        resource: McpEmbeddedResourceResource,
        type: String = "resource",
        annotations: McpAnnotations? = nil,
        meta: JSONValue? = nil
    ) {
        self.annotations = annotations
        self.meta = meta
        self.resource = resource
        self.type = type
    }
}

public enum McpEmbeddedResourceResource: Equatable, Codable, Sendable {
    case text(McpTextResourceContents)
    case blob(McpBlobResourceContents)

    public init(from decoder: Decoder) throws {
        if let value = try? McpTextResourceContents(from: decoder) {
            self = .text(value)
            return
        }
        if let value = try? McpBlobResourceContents(from: decoder) {
            self = .blob(value)
            return
        }
        throw DecodingError.typeMismatch(
            McpEmbeddedResourceResource.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected text or blob MCP resource contents"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(value):
            try value.encode(to: encoder)
        case let .blob(value):
            try value.encode(to: encoder)
        }
    }
}

public struct McpTextResourceContents: Equatable, Codable, Sendable {
    public let meta: JSONValue?
    public let mimeType: String?
    public let text: String
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case mimeType = "mimeType"
        case text
        case uri
    }

    public init(text: String, uri: String, mimeType: String? = nil, meta: JSONValue? = nil) {
        self.meta = meta
        self.mimeType = mimeType
        self.text = text
        self.uri = uri
    }
}

public struct McpBlobResourceContents: Equatable, Codable, Sendable {
    public let blob: String
    public let meta: JSONValue?
    public let mimeType: String?
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case blob
        case meta = "_meta"
        case mimeType = "mimeType"
        case uri
    }

    public init(blob: String, uri: String, mimeType: String? = nil, meta: JSONValue? = nil) {
        self.blob = blob
        self.meta = meta
        self.mimeType = mimeType
        self.uri = uri
    }
}

public enum McpAuthStatus: String, Codable, Equatable, Sendable {
    case unsupported
    case notLoggedIn = "not_logged_in"
    case bearerToken = "bearer_token"
    case oauth

    public var description: String {
        switch self {
        case .unsupported:
            return "Unsupported"
        case .notLoggedIn:
            return "Not logged in"
        case .bearerToken:
            return "Bearer token"
        case .oauth:
            return "OAuth"
        }
    }
}
