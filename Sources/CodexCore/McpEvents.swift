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

public struct McpListToolsResponseEvent: Equatable, Codable, Sendable {
    public let tools: [String: McpTool]
    public let resources: [String: [McpResource]]
    public let resourceTemplates: [String: [McpResourceTemplate]]
    public let authStatuses: [String: McpAuthStatus]

    private enum CodingKeys: String, CodingKey {
        case tools
        case resources
        case resourceTemplates = "resource_templates"
        case authStatuses = "auth_statuses"
    }

    public init(
        tools: [String: McpTool],
        resources: [String: [McpResource]],
        resourceTemplates: [String: [McpResourceTemplate]],
        authStatuses: [String: McpAuthStatus]
    ) {
        self.tools = tools
        self.resources = resources
        self.resourceTemplates = resourceTemplates
        self.authStatuses = authStatuses
    }
}

public enum McpToolName {
    public static let prefix = "mcp"
    public static let delimiter = "__"
    public static let maximumLength = 64

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
    public let audience: [McpRole]?
    public let lastModified: String?
    public let priority: Double?

    private enum CodingKeys: String, CodingKey {
        case audience
        case lastModified = "lastModified"
        case priority
    }

    public init(audience: [McpRole]? = nil, lastModified: String? = nil, priority: Double? = nil) {
        self.audience = audience
        self.lastModified = lastModified
        self.priority = priority
    }
}

public struct McpResource: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let description: String?
    public let mimeType: String?
    public let name: String
    public let size: Int64?
    public let title: String?
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
        case mimeType = "mimeType"
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
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
        self.mimeType = mimeType
        self.name = name
        self.size = size
        self.title = title
        self.uri = uri
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
        case name
        case title
        case uriTemplate = "uriTemplate"
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
}

public struct McpTool: Equatable, Codable, Sendable {
    public let annotations: McpToolAnnotations?
    public let description: String?
    public let inputSchema: McpToolInputSchema
    public let name: String
    public let outputSchema: McpToolOutputSchema?
    public let title: String?

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
        case inputSchema = "inputSchema"
        case name
        case outputSchema = "outputSchema"
        case title
    }

    public init(
        name: String,
        inputSchema: McpToolInputSchema,
        annotations: McpToolAnnotations? = nil,
        description: String? = nil,
        outputSchema: McpToolOutputSchema? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
        self.inputSchema = inputSchema
        self.name = name
        self.outputSchema = outputSchema
        self.title = title
    }
}

public struct McpToolInputSchema: Equatable, Codable, Sendable {
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
}

public struct McpToolAnnotations: Equatable, Codable, Sendable {
    public let destructiveHint: Bool?
    public let idempotentHint: Bool?
    public let openWorldHint: Bool?
    public let readOnlyHint: Bool?
    public let title: String?

    private enum CodingKeys: String, CodingKey {
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
        title: String? = nil
    ) {
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
        self.readOnlyHint = readOnlyHint
        self.title = title
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

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case invocation
    }

    public init(callID: String, invocation: McpInvocation) {
        self.callID = callID
        self.invocation = invocation
    }
}

public struct McpToolCallEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let invocation: McpInvocation
    public let duration: ProtocolDuration
    public let result: McpToolCallResult

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case invocation
        case duration
        case result
    }

    public init(callID: String, invocation: McpInvocation, duration: ProtocolDuration, result: McpToolCallResult) {
        self.callID = callID
        self.invocation = invocation
        self.duration = duration
        self.result = result
    }

    public var isSuccess: Bool {
        guard case let .ok(result) = result else {
            return false
        }
        return !(result.isError ?? false)
    }
}

public enum McpToolCallResult: Equatable, Codable, Sendable {
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
}

public struct McpCallToolResult: Equatable, Codable, Sendable {
    public let content: [McpContentBlock]
    public let isError: Bool?
    public let structuredContent: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case content
        case isError = "isError"
        case structuredContent = "structuredContent"
    }

    public init(
        content: [McpContentBlock],
        isError: Bool? = nil,
        structuredContent: JSONValue? = nil
    ) {
        self.content = content
        self.isError = isError
        self.structuredContent = structuredContent
    }
}

public enum McpContentBlock: Equatable, Codable, Sendable {
    case text(McpTextContent)
    case image(McpImageContent)
    case audio(McpAudioContent)
    case resourceLink(McpResourceLink)
    case embeddedResource(McpEmbeddedResource)

    public init(from decoder: Decoder) throws {
        if let value = try? McpTextContent(from: decoder) {
            self = .text(value)
            return
        }
        if let value = try? McpImageContent(from: decoder) {
            self = .image(value)
            return
        }
        if let value = try? McpAudioContent(from: decoder) {
            self = .audio(value)
            return
        }
        if let value = try? McpResourceLink(from: decoder) {
            self = .resourceLink(value)
            return
        }
        if let value = try? McpEmbeddedResource(from: decoder) {
            self = .embeddedResource(value)
            return
        }
        throw DecodingError.typeMismatch(
            McpContentBlock.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected an MCP content block"
            )
        )
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
        }
    }
}

public struct McpTextContent: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let text: String
    public let type: String

    public init(text: String, type: String = "text", annotations: McpAnnotations? = nil) {
        self.annotations = annotations
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
}

public struct McpAudioContent: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let data: String
    public let mimeType: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case data
        case mimeType = "mimeType"
        case type
    }

    public init(data: String, mimeType: String, type: String = "audio", annotations: McpAnnotations? = nil) {
        self.annotations = annotations
        self.data = data
        self.mimeType = mimeType
        self.type = type
    }
}

public struct McpResourceLink: Equatable, Codable, Sendable {
    public let annotations: McpAnnotations?
    public let description: String?
    public let mimeType: String?
    public let name: String
    public let size: Int64?
    public let title: String?
    public let type: String
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case annotations
        case description
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
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil
    ) {
        self.annotations = annotations
        self.description = description
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
    public let resource: McpEmbeddedResourceResource
    public let type: String

    public init(resource: McpEmbeddedResourceResource, type: String = "resource", annotations: McpAnnotations? = nil) {
        self.annotations = annotations
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
    public let mimeType: String?
    public let text: String
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case mimeType = "mimeType"
        case text
        case uri
    }

    public init(text: String, uri: String, mimeType: String? = nil) {
        self.mimeType = mimeType
        self.text = text
        self.uri = uri
    }
}

public struct McpBlobResourceContents: Equatable, Codable, Sendable {
    public let blob: String
    public let mimeType: String?
    public let uri: String

    private enum CodingKeys: String, CodingKey {
        case blob
        case mimeType = "mimeType"
        case uri
    }

    public init(blob: String, uri: String, mimeType: String? = nil) {
        self.blob = blob
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
