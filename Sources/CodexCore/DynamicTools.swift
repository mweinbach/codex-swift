import Foundation

public struct DynamicToolValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public struct DynamicToolSpec: Codable, Equatable, Sendable {
    public let namespace: String?
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let deferLoading: Bool

    private enum CodingKeys: String, CodingKey {
        case namespace
        case name
        case description
        case inputSchema
        case deferLoading
        case exposeToContext
    }

    public init(
        namespace: String? = nil,
        name: String,
        description: String,
        inputSchema: JSONValue,
        deferLoading: Bool = false
    ) {
        self.namespace = namespace
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.deferLoading = deferLoading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        if let deferLoading = try container.decodeIfPresent(Bool.self, forKey: .deferLoading) {
            self.deferLoading = deferLoading
        } else if let exposeToContext = try container.decodeIfPresent(Bool.self, forKey: .exposeToContext) {
            self.deferLoading = !exposeToContext
        } else {
            self.deferLoading = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(namespace, forKey: .namespace)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        if deferLoading {
            try container.encode(true, forKey: .deferLoading)
        }
    }

    public static func validate(_ tools: [DynamicToolSpec]) throws {
        let nameMaximumLength = 128
        let namespaceMaximumLength = 64
        let reservedResponsesNamespaces: Set<String> = [
            "api_tool",
            "browser",
            "computer",
            "container",
            "file_search",
            "functions",
            "image_gen",
            "multi_tool_use",
            "python",
            "python_user_visible",
            "submodel_delegator",
            "terminal",
            "tool_search",
            "web"
        ]

        var seen = Set<DynamicToolIdentifier>()
        for tool in tools {
            let trimmedName = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw DynamicToolValidationError("dynamic tool name must not be empty")
            }
            guard trimmedName == tool.name else {
                throw DynamicToolValidationError(
                    "dynamic tool name has leading/trailing whitespace: \(escapedIdentifierForError(tool.name))"
                )
            }
            try validateIdentifier(trimmedName, label: "dynamic tool name", maximumLength: nameMaximumLength)
            if trimmedName == "mcp" || trimmedName.hasPrefix("mcp__") {
                throw DynamicToolValidationError("dynamic tool name is reserved: \(trimmedName)")
            }

            let trimmedNamespace = tool.namespace?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedNamespace {
                guard !trimmedNamespace.isEmpty else {
                    throw DynamicToolValidationError("dynamic tool namespace must not be empty for \(trimmedName)")
                }
                guard trimmedNamespace == tool.namespace else {
                    throw DynamicToolValidationError(
                        "dynamic tool namespace has leading/trailing whitespace for \(escapedIdentifierForError(trimmedName)): \(escapedIdentifierForError(trimmedNamespace))"
                    )
                }
                try validateNamespace(
                    trimmedNamespace,
                    maximumLength: namespaceMaximumLength
                )
                if trimmedNamespace == "mcp" || trimmedNamespace.hasPrefix("mcp__") {
                    throw DynamicToolValidationError(
                        "dynamic tool namespace is reserved for \(trimmedName): \(trimmedNamespace)"
                    )
                }
                if reservedResponsesNamespaces.contains(trimmedNamespace) {
                    throw DynamicToolValidationError(
                        "dynamic tool namespace collides with a reserved Responses API namespace for \(trimmedName): \(trimmedNamespace)"
                    )
                }
            }

            let identifier = DynamicToolIdentifier(namespace: trimmedNamespace, name: trimmedName)
            guard seen.insert(identifier).inserted else {
                if let trimmedNamespace {
                    throw DynamicToolValidationError(
                        "duplicate dynamic tool name in namespace \(trimmedNamespace): \(trimmedName)"
                    )
                }
                throw DynamicToolValidationError("duplicate dynamic tool name: \(trimmedName)")
            }
            if tool.deferLoading && trimmedNamespace == nil {
                throw DynamicToolValidationError("deferred dynamic tool must include a namespace: \(trimmedName)")
            }
            try validateInputSchema(tool.inputSchema, toolName: trimmedName)
        }
    }

    private static func validateIdentifier(_ value: String, label: String, maximumLength: Int) throws {
        let matchesResponsesPattern = value.utf8.allSatisfy { byte in
            byte.isASCIIAlphaNumeric || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }
        guard matchesResponsesPattern else {
            throw DynamicToolValidationError(
                "\(label) must match ^[a-zA-Z0-9_-]+$ to match Responses API: \(escapedIdentifierForError(value))"
            )
        }
        guard value.count <= maximumLength else {
            throw DynamicToolValidationError(
                "\(label) must be at most \(maximumLength) characters to match Responses API: \(escapedIdentifierForError(value))"
            )
        }
    }

    private static func validateNamespace(_ value: String, maximumLength: Int) throws {
        let namespaceBody = value.hasSuffix("/") ? String(value.dropLast()) : value
        guard !namespaceBody.isEmpty else {
            throw DynamicToolValidationError(
                "dynamic tool namespace must match ^[a-zA-Z0-9_-]+/?$ to match Responses API: \(escapedIdentifierForError(value))"
            )
        }
        let matchesResponsesPattern = namespaceBody.utf8.allSatisfy { byte in
            byte.isASCIIAlphaNumeric || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }
        guard matchesResponsesPattern else {
            throw DynamicToolValidationError(
                "dynamic tool namespace must match ^[a-zA-Z0-9_-]+/?$ to match Responses API: \(escapedIdentifierForError(value))"
            )
        }
        guard value.count <= maximumLength else {
            throw DynamicToolValidationError(
                "dynamic tool namespace must be at most \(maximumLength) characters to match Responses API: \(escapedIdentifierForError(value))"
            )
        }
    }

    private static func validateInputSchema(_ schema: JSONValue, toolName: String) throws {
        let sanitized = JSONSchema.sanitized(from: jsonCompatibleValue(schema))
        if case .null = sanitized {
            throw DynamicToolValidationError(
                "dynamic tool input schema is not supported for \(toolName): singleton null schema is not supported"
            )
        }
    }

    private static func jsonCompatibleValue(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map(jsonCompatibleValue)
        case let .object(values):
            return values.mapValues(jsonCompatibleValue)
        }
    }

    private static func escapedIdentifierForError(_ value: String) -> String {
        value.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar.value {
            case 10:
                result += "\\n"
            case 13:
                result += "\\r"
            case 9:
                result += "\\t"
            case 34:
                result += "\\\""
            case 39:
                result += "\\'"
            case 92:
                result += "\\\\"
            case 32...126:
                result += String(scalar)
            default:
                result += "\\u{\(String(scalar.value, radix: 16))}"
            }
        }
    }
}

private struct DynamicToolIdentifier: Hashable {
    let namespace: String?
    let name: String
}

private extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
    }
}

public struct DynamicToolCallRequest: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let namespace: String?
    public let tool: String
    public let arguments: JSONValue

    private enum CodingKeys: String, CodingKey {
        case callID = "callId"
        case turnID = "turnId"
        case startedAtMilliseconds = "startedAtMs"
        case namespace
        case tool
        case arguments
    }

    public init(
        callID: String,
        turnID: String,
        startedAtMilliseconds: Int64 = 0,
        namespace: String? = nil,
        tool: String,
        arguments: JSONValue
    ) {
        self.callID = callID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.namespace = namespace
        self.tool = tool
        self.arguments = arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decode(String.self, forKey: .turnID)
        startedAtMilliseconds = try container.decodeRustDefaulted(
            Int64.self,
            forKey: .startedAtMilliseconds,
            defaultValue: 0
        )
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encodeIfPresentOrNull(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
    }
}

public struct DynamicToolResponse: Codable, Equatable, Sendable {
    public let contentItems: [DynamicToolCallOutputContentItem]
    public let success: Bool

    private enum CodingKeys: String, CodingKey {
        case contentItems
        case success
    }

    public init(contentItems: [DynamicToolCallOutputContentItem], success: Bool) {
        self.contentItems = contentItems
        self.success = success
    }
}

public struct DynamicToolCallResponseEvent: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let completedAtMilliseconds: Int64
    public let namespace: String?
    public let tool: String
    public let arguments: JSONValue
    public let contentItems: [DynamicToolCallOutputContentItem]
    public let success: Bool
    public let error: String?
    public let duration: ProtocolDuration

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case completedAtMilliseconds = "completed_at_ms"
        case namespace
        case tool
        case arguments
        case contentItems = "content_items"
        case success
        case error
        case duration
    }

    public init(
        callID: String,
        turnID: String,
        completedAtMilliseconds: Int64 = 0,
        namespace: String? = nil,
        tool: String,
        arguments: JSONValue,
        contentItems: [DynamicToolCallOutputContentItem],
        success: Bool,
        error: String? = nil,
        duration: ProtocolDuration
    ) {
        self.callID = callID
        self.turnID = turnID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.namespace = namespace
        self.tool = tool
        self.arguments = arguments
        self.contentItems = contentItems
        self.success = success
        self.error = error
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decode(String.self, forKey: .turnID)
        completedAtMilliseconds = try container.decodeRustDefaulted(
            Int64.self,
            forKey: .completedAtMilliseconds,
            defaultValue: 0
        )
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        contentItems = try container.decode([DynamicToolCallOutputContentItem].self, forKey: .contentItems)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        duration = try container.decode(ProtocolDuration.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encodeIfPresentOrNull(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(contentItems, forKey: .contentItems)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresentOrNull(error, forKey: .error)
        try container.encode(duration, forKey: .duration)
    }
}

public enum DynamicToolCallOutputContentItem: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "imageUrl"
    }

    private enum ItemType: String, Codable {
        case inputText
        case inputImage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .inputText:
            self = .text(try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .imageURL(try container.decode(String.self, forKey: .imageURL))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(ItemType.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(imageURL):
            try container.encode(ItemType.inputImage, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
