import Foundation

public enum AppServerMcpAuthStatus: String, Codable, Equatable, Sendable {
    case unsupported
    case notLoggedIn
    case bearerToken
    case oAuth

    public init(coreStatus: McpAuthStatus) {
        switch coreStatus {
        case .unsupported:
            self = .unsupported
        case .notLoggedIn:
            self = .notLoggedIn
        case .bearerToken:
            self = .bearerToken
        case .oauth:
            self = .oAuth
        }
    }
}

extension AppServerProtocol {
    public enum McpServerStatusDetail: String, Codable, Equatable, Sendable {
        case full
        case toolsAndAuthOnly
    }

    public struct ListMcpServerStatusParams: Codable, Equatable, Sendable {
        public let cursor: String?
        public let limit: UInt32?
        public let detail: McpServerStatusDetail?

        private enum CodingKeys: String, CodingKey {
            case cursor
            case limit
            case detail
        }

        public init(cursor: String? = nil, limit: UInt32? = nil, detail: McpServerStatusDetail? = nil) {
            self.cursor = cursor
            self.limit = limit
            self.detail = detail
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(cursor, forKey: .cursor)
            try container.encodeNilOrValue(limit, forKey: .limit)
            try container.encodeNilOrValue(detail, forKey: .detail)
        }
    }

    public struct McpServerStatus: Codable, Equatable, Sendable {
        public let name: String
        public let tools: [String: McpTool]
        public let resources: [McpResource]
        public let resourceTemplates: [McpResourceTemplate]
        public let authStatus: AppServerMcpAuthStatus

        public init(
            name: String,
            tools: [String: McpTool],
            resources: [McpResource],
            resourceTemplates: [McpResourceTemplate],
            authStatus: AppServerMcpAuthStatus
        ) {
            self.name = name
            self.tools = tools
            self.resources = resources
            self.resourceTemplates = resourceTemplates
            self.authStatus = authStatus
        }
    }

    public struct ListMcpServerStatusResponse: Codable, Equatable, Sendable {
        public let data: [McpServerStatus]
        public let nextCursor: String?

        private enum CodingKeys: String, CodingKey {
            case data
            case nextCursor
        }

        public init(data: [McpServerStatus], nextCursor: String?) {
            self.data = data
            self.nextCursor = nextCursor
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(data, forKey: .data)
            try container.encodeNilOrValue(nextCursor, forKey: .nextCursor)
        }
    }

    public struct McpResourceReadParams: Codable, Equatable, Sendable {
        public let threadID: String?
        public let server: String
        public let uri: String

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case server
            case uri
        }

        public init(threadID: String? = nil, server: String, uri: String) {
            self.threadID = threadID
            self.server = server
            self.uri = uri
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(threadID, forKey: .threadID)
            try container.encode(server, forKey: .server)
            try container.encode(uri, forKey: .uri)
        }
    }

    public typealias McpResourceContent = McpEmbeddedResourceResource

    public struct McpResourceReadResponse: Codable, Equatable, Sendable {
        public let contents: [McpResourceContent]

        public init(contents: [McpResourceContent]) {
            self.contents = contents
        }
    }

    public struct McpServerToolCallParams: Codable, Equatable, Sendable {
        public let threadID: String
        public let server: String
        public let tool: String
        public let arguments: JSONValue?
        public let meta: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case server
            case tool
            case arguments
            case meta = "_meta"
        }

        public init(threadID: String, server: String, tool: String, arguments: JSONValue? = nil, meta: JSONValue? = nil) {
            self.threadID = threadID
            self.server = server
            self.tool = tool
            self.arguments = arguments
            self.meta = meta
        }
    }

    public struct McpServerToolCallResponse: Codable, Equatable, Sendable {
        public let content: [JSONValue]
        public let structuredContent: JSONValue?
        public let isError: Bool?
        public let meta: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case content
            case structuredContent
            case isError
            case meta = "_meta"
        }

        public init(content: [JSONValue], structuredContent: JSONValue? = nil, isError: Bool? = nil, meta: JSONValue? = nil) {
            self.content = content
            self.structuredContent = structuredContent
            self.isError = isError
            self.meta = meta
        }
    }

    public struct McpToolCallResult: Codable, Equatable, Sendable {
        public let content: [JSONValue]
        public let structuredContent: JSONValue?
        public let meta: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case content
            case structuredContent
            case meta = "_meta"
        }

        public init(content: [JSONValue], structuredContent: JSONValue?, meta: JSONValue?) {
            self.content = content
            self.structuredContent = structuredContent
            self.meta = meta
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(content, forKey: .content)
            try container.encodeNilOrValue(structuredContent, forKey: .structuredContent)
            try container.encodeNilOrValue(meta, forKey: .meta)
        }
    }

    public struct McpToolCallError: Codable, Equatable, Sendable {
        public let message: String

        public init(message: String) {
            self.message = message
        }
    }

    public struct McpServerRefreshParams: Codable, Equatable, Sendable {
        public init() {}
    }

    public struct McpServerRefreshResponse: Codable, Equatable, Sendable {
        public init() {}
    }

    public struct McpServerOauthLoginParams: Codable, Equatable, Sendable {
        public let name: String
        public let scopes: [String]?
        public let timeoutSeconds: Int64?

        private enum CodingKeys: String, CodingKey {
            case name
            case scopes
            case timeoutSeconds = "timeoutSecs"
        }

        public init(name: String, scopes: [String]? = nil, timeoutSeconds: Int64? = nil) {
            self.name = name
            self.scopes = scopes
            self.timeoutSeconds = timeoutSeconds
        }
    }

    public struct McpServerOauthLoginResponse: Codable, Equatable, Sendable {
        public let authorizationURL: String

        private enum CodingKeys: String, CodingKey {
            case authorizationURL = "authorizationUrl"
        }

        public init(authorizationURL: String) {
            self.authorizationURL = authorizationURL
        }
    }

    public struct McpToolCallProgressNotification: Codable, Equatable, Sendable {
        public static let method = "item/mcpToolCall/progress"

        public let threadID: String
        public let turnID: String
        public let itemID: String
        public let message: String

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case itemID = "itemId"
            case message
        }

        public init(threadID: String, turnID: String, itemID: String, message: String) {
            self.threadID = threadID
            self.turnID = turnID
            self.itemID = itemID
            self.message = message
        }
    }

    public struct McpServerOauthLoginCompletedNotification: Codable, Equatable, Sendable {
        public let name: String
        public let success: Bool
        public let error: String?

        public init(name: String, success: Bool, error: String? = nil) {
            self.name = name
            self.success = success
            self.error = error
        }
    }

    public enum McpServerStartupState: String, Codable, Equatable, Sendable {
        case starting
        case ready
        case failed
        case cancelled
    }

    public struct McpServerStatusUpdatedNotification: Codable, Equatable, Sendable {
        public let name: String
        public let status: McpServerStartupState
        public let error: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case status
            case error
        }

        public init(name: String, status: McpServerStartupState, error: String?) {
            self.name = name
            self.status = status
            self.error = error
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(status, forKey: .status)
            try container.encodeNilOrValue(error, forKey: .error)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
