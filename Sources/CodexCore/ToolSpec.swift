import Foundation

public enum ConfigShellToolType: String, Codable, CaseIterable, Equatable, Sendable {
    case `default`
    case local
    case unifiedExec = "unified_exec"
    case disabled
    case shellCommand = "shell_command"
}

public enum ApplyPatchToolType: String, Codable, CaseIterable, Equatable, Sendable {
    case freeform
}

public enum ToolEnvironmentMode: Equatable, Sendable {
    case single
    case multiple
}

public enum WebSearchToolType: String, Codable, CaseIterable, Equatable, Sendable {
    case text
    case textAndImage = "text_and_image"
}

public enum JSONSchemaAdditionalProperties: Equatable, Codable, Sendable {
    case boolean(Bool)
    case schema(JSONSchema)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
            return
        }
        self = .schema(try container.decode(JSONSchema.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .boolean(value):
            try container.encode(value)
        case let .schema(schema):
            try container.encode(schema)
        }
    }
}

public indirect enum JSONSchema: Equatable, Codable, Sendable {
    case boolean(description: String?)
    case string(description: String?)
    case stringEnum(values: [JSONValue], description: String?)
    case number(description: String?)
    case integer(description: String?)
    case null(description: String?)
    case array(items: JSONSchema, description: String?)
    case object(
        properties: [String: JSONSchema],
        required: [String]?,
        additionalProperties: JSONSchemaAdditionalProperties?
    )
    case anyOf(variants: [JSONSchema], description: String?)
    case typeUnion(
        types: [String],
        description: String?,
        enumValues: [JSONValue]?,
        items: JSONSchema?,
        properties: [String: JSONSchema]?,
        required: [String]?,
        additionalProperties: JSONSchemaAdditionalProperties?
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case items
        case properties
        case required
        case additionalProperties
        case anyOf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        if let variants = try container.decodeIfPresent([JSONSchema].self, forKey: .anyOf),
           !container.contains(.type)
        {
            self = .anyOf(variants: variants, description: description)
            return
        }
        if let types = try? container.decode([String].self, forKey: .type) {
            self = .typeUnion(
                types: types,
                description: description,
                enumValues: try container.decodeIfPresent([JSONValue].self, forKey: .enumValues),
                items: try container.decodeIfPresent(JSONSchema.self, forKey: .items),
                properties: try container.decodeIfPresent([String: JSONSchema].self, forKey: .properties),
                required: try container.decodeIfPresent([String].self, forKey: .required),
                additionalProperties: try container.decodeIfPresent(
                    JSONSchemaAdditionalProperties.self,
                    forKey: .additionalProperties
                )
            )
            return
        }
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "boolean":
            self = .boolean(description: description)
        case "string":
            if let enumValues = try container.decodeIfPresent([JSONValue].self, forKey: .enumValues) {
                self = .stringEnum(values: enumValues, description: description)
            } else {
                self = .string(description: description)
            }
        case "number":
            self = .number(description: description)
        case "integer":
            self = .integer(description: description)
        case "null":
            self = .null(description: description)
        case "array":
            self = .array(
                items: try container.decode(JSONSchema.self, forKey: .items),
                description: description
            )
        case "object":
            self = .object(
                properties: try container.decode([String: JSONSchema].self, forKey: .properties),
                required: try container.decodeIfPresent([String].self, forKey: .required),
                additionalProperties: try container.decodeIfPresent(
                    JSONSchemaAdditionalProperties.self,
                    forKey: .additionalProperties
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported JSON schema type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .boolean(description):
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .string(description):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .stringEnum(values, description):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(values, forKey: .enumValues)
        case let .number(description):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .integer(description):
            try container.encode("integer", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .null(description):
            try container.encode("null", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .array(items, description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)
        case let .object(properties, required, additionalProperties):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
        case let .anyOf(variants, description):
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(variants, forKey: .anyOf)
        case let .typeUnion(types, description, enumValues, items, properties, required, additionalProperties):
            try container.encode(types, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(enumValues, forKey: .enumValues)
            try container.encodeIfPresent(items, forKey: .items)
            try container.encodeIfPresent(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
        }
    }

    public static func sanitized(from value: Any) -> JSONSchema {
        switch value {
        case is Bool:
            return .string(description: nil)
        case let dictionary as [String: Any]:
            return sanitized(fromObject: dictionary)
        case let dictionary as NSDictionary:
            return sanitized(fromObject: dictionary.reduce(into: [String: Any]()) { result, entry in
                guard let key = entry.key as? String else { return }
                result[key] = entry.value
            })
        default:
            return .string(description: nil)
        }
    }

    private static func sanitized(fromObject object: [String: Any]) -> JSONSchema {
        let description = object["description"] as? String
        if let variants = object["anyOf"] as? [Any], object["type"] == nil {
            return .anyOf(variants: variants.map(sanitized(from:)), description: description)
        }

        let types = normalizedTypes(for: object)
        let enumValues = enumValues(from: object)
        let properties = sanitizedProperties(object["properties"])
        let required = object["required"] as? [String]
        let additionalProperties = sanitizedAdditionalProperties(object["additionalProperties"])
        let items = object["items"].map(sanitized(from:))

        if types.count > 1 {
            return .typeUnion(
                types: types,
                description: description,
                enumValues: enumValues,
                items: types.contains("array") ? (items ?? .string(description: nil)) : items,
                properties: types.contains("object") ? properties : (object["properties"] == nil ? nil : properties),
                required: required,
                additionalProperties: additionalProperties
            )
        }

        switch types.first ?? "string" {
        case "boolean":
            return .boolean(description: description)
        case "array":
            return .array(items: items ?? .string(description: nil), description: description)
        case "object":
            return .object(
                properties: properties,
                required: required,
                additionalProperties: additionalProperties
            )
        case "number":
            return .number(description: description)
        case "integer":
            return .integer(description: description)
        case "null":
            return .null(description: description)
        case "string":
            fallthrough
        default:
            if let enumValues {
                return .stringEnum(values: enumValues, description: description)
            }
            return .string(description: description)
        }
    }

    private static func normalizedTypes(for object: [String: Any]) -> [String] {
        if let type = object["type"] as? String {
            return normalizedType(type, object: object).map { [$0] } ?? []
        }

        if let types = object["type"] as? [String],
           !types.isEmpty
        {
            return types.compactMap { normalizedType($0, object: object) }
        }

        if object["properties"] != nil || object["required"] != nil || object["additionalProperties"] != nil {
            return ["object"]
        }
        if object["items"] != nil || object["prefixItems"] != nil {
            return ["array"]
        }
        if object["enum"] != nil || object["const"] != nil || object["format"] != nil {
            return ["string"]
        }
        if object["minimum"] != nil || object["maximum"] != nil
            || object["exclusiveMinimum"] != nil || object["exclusiveMaximum"] != nil
            || object["multipleOf"] != nil
        {
            return ["number"]
        }

        return ["string"]
    }

    private static func normalizedType(_ type: String, object: [String: Any]) -> String? {
        switch type {
        case "object", "array", "string", "number", "integer", "boolean", "null":
            return type
        case "enum" where object["enum"] != nil || object["const"] != nil:
            return "string"
        case "const" where object["enum"] != nil || object["const"] != nil:
            return "string"
        default:
            return nil
        }
    }

    private static func sanitizedProperties(_ value: Any?) -> [String: JSONSchema] {
        guard let properties = value as? [String: Any] else {
            return [:]
        }
        return properties.mapValues(sanitized(from:))
    }

    private static func sanitizedAdditionalProperties(_ value: Any?) -> JSONSchemaAdditionalProperties? {
        guard let value else {
            return nil
        }
        if let bool = value as? Bool {
            return .boolean(bool)
        }
        return .schema(sanitized(from: value))
    }

    private static func enumValues(from object: [String: Any]) -> [JSONValue]? {
        if let values = object["enum"] as? [Any] {
            return values.compactMap(jsonValue)
        }
        if let const = object["const"],
           let value = jsonValue(from: const)
        {
            return [value]
        }
        return nil
    }

    private static func jsonValue(from value: Any) -> JSONValue? {
        switch value {
        case let value as JSONValue:
            return value
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as Double:
            return .double(value)
        case let value as String:
            return .string(value)
        case let values as [Any]:
            return .array(values.compactMap(jsonValue))
        case let object as [String: Any]:
            return .object(object.compactMapValues(jsonValue))
        default:
            return nil
        }
    }
}

public struct ResponsesAPITool: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let strict: Bool
    public let deferLoading: Bool?
    public let parameters: JSONSchema
    public let outputSchema: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case strict
        case deferLoading = "defer_loading"
        case parameters
    }

    public init(
        name: String,
        description: String,
        strict: Bool = false,
        deferLoading: Bool? = nil,
        parameters: JSONSchema,
        outputSchema: JSONValue? = nil
    ) {
        self.name = name
        self.description = description
        self.strict = strict
        self.deferLoading = deferLoading
        self.parameters = parameters
        self.outputSchema = outputSchema
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.strict = try container.decode(Bool.self, forKey: .strict)
        self.deferLoading = try container.decodeIfPresent(Bool.self, forKey: .deferLoading)
        self.parameters = try container.decode(JSONSchema.self, forKey: .parameters)
        self.outputSchema = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(strict, forKey: .strict)
        try container.encodeIfPresent(deferLoading, forKey: .deferLoading)
        try container.encode(parameters, forKey: .parameters)
    }
}

public enum ResponsesAPINamespaceTool: Equatable, Codable, Sendable {
    case function(ResponsesAPITool)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case strict
        case deferLoading = "defer_loading"
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "function":
            self = .function(
                ResponsesAPITool(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    strict: try container.decode(Bool.self, forKey: .strict),
                    deferLoading: try container.decodeIfPresent(Bool.self, forKey: .deferLoading),
                    parameters: try container.decode(JSONSchema.self, forKey: .parameters)
                )
            )
        case let type:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported namespace tool type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .function(tool):
            try container.encode("function", forKey: .type)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.description, forKey: .description)
            try container.encode(tool.strict, forKey: .strict)
            try container.encodeIfPresent(tool.deferLoading, forKey: .deferLoading)
            try container.encode(tool.parameters, forKey: .parameters)
        }
    }
}

public struct ResponsesAPINamespace: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let tools: [ResponsesAPINamespaceTool]

    public init(name: String, description: String, tools: [ResponsesAPINamespaceTool]) {
        self.name = name
        self.description = description
        self.tools = tools
    }
}

public struct FreeformToolFormat: Equatable, Codable, Sendable {
    public let type: String
    public let syntax: String
    public let definition: String

    public init(type: String, syntax: String, definition: String) {
        self.type = type
        self.syntax = syntax
        self.definition = definition
    }
}

public struct FreeformTool: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let format: FreeformToolFormat

    public init(name: String, description: String, format: FreeformToolFormat) {
        self.name = name
        self.description = description
        self.format = format
    }
}

public enum WebSearchContextSize: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct ResponsesAPIWebSearchFilters: Equatable, Codable, Sendable {
    public let allowedDomains: [String]?

    private enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
    }

    public init(allowedDomains: [String]? = nil) {
        self.allowedDomains = allowedDomains
    }
}

public enum WebSearchUserLocationType: String, Codable, Equatable, Sendable {
    case approximate
}

public struct ResponsesAPIWebSearchUserLocation: Equatable, Codable, Sendable {
    public let type: WebSearchUserLocationType
    public let country: String?
    public let region: String?
    public let city: String?
    public let timezone: String?

    public init(
        type: WebSearchUserLocationType = .approximate,
        country: String? = nil,
        region: String? = nil,
        city: String? = nil,
        timezone: String? = nil
    ) {
        self.type = type
        self.country = country
        self.region = region
        self.city = city
        self.timezone = timezone
    }
}

public struct WebSearchConfig: Equatable, Sendable {
    public let filters: ResponsesAPIWebSearchFilters?
    public let userLocation: ResponsesAPIWebSearchUserLocation?
    public let searchContextSize: WebSearchContextSize?

    public init(
        filters: ResponsesAPIWebSearchFilters? = nil,
        userLocation: ResponsesAPIWebSearchUserLocation? = nil,
        searchContextSize: WebSearchContextSize? = nil
    ) {
        self.filters = filters
        self.userLocation = userLocation
        self.searchContextSize = searchContextSize
    }

    public func merging(overlay: WebSearchConfig) -> WebSearchConfig {
        WebSearchConfig(
            filters: overlay.filters ?? filters,
            userLocation: userLocation?.merging(overlay: overlay.userLocation) ?? overlay.userLocation,
            searchContextSize: overlay.searchContextSize ?? searchContextSize
        )
    }
}

private extension ResponsesAPIWebSearchUserLocation {
    func merging(overlay: ResponsesAPIWebSearchUserLocation?) -> ResponsesAPIWebSearchUserLocation {
        guard let overlay else {
            return self
        }
        return ResponsesAPIWebSearchUserLocation(
            type: overlay.type,
            country: overlay.country ?? country,
            region: overlay.region ?? region,
            city: overlay.city ?? city,
            timezone: overlay.timezone ?? timezone
        )
    }
}

public enum ToolSpec: Equatable, Codable, Sendable {
    case function(ResponsesAPITool)
    case namespace(ResponsesAPINamespace)
    case toolSearch(execution: String, description: String, parameters: JSONSchema)
    case localShell
    case imageGeneration(outputFormat: String)
    case webSearch(
        externalWebAccess: Bool? = nil,
        filters: ResponsesAPIWebSearchFilters? = nil,
        userLocation: ResponsesAPIWebSearchUserLocation? = nil,
        searchContextSize: WebSearchContextSize? = nil,
        searchContentTypes: [String]? = nil
    )
    case freeform(FreeformTool)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case execution
        case strict
        case deferLoading = "defer_loading"
        case parameters
        case tools
        case outputFormat = "output_format"
        case externalWebAccess = "external_web_access"
        case filters
        case userLocation = "user_location"
        case searchContextSize = "search_context_size"
        case searchContentTypes = "search_content_types"
        case format
    }

    public var name: String {
        switch self {
        case let .function(tool):
            return tool.name
        case let .namespace(namespace):
            return namespace.name
        case .toolSearch:
            return "tool_search"
        case .localShell:
            return "local_shell"
        case .imageGeneration:
            return "image_generation"
        case .webSearch:
            return "web_search"
        case let .freeform(tool):
            return tool.name
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "function":
            self = .function(
                ResponsesAPITool(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    strict: try container.decode(Bool.self, forKey: .strict),
                    deferLoading: try container.decodeIfPresent(Bool.self, forKey: .deferLoading),
                    parameters: try container.decode(JSONSchema.self, forKey: .parameters)
                )
            )
        case "namespace":
            self = .namespace(
                ResponsesAPINamespace(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    tools: try container.decode([ResponsesAPINamespaceTool].self, forKey: .tools)
                )
            )
        case "tool_search":
            self = .toolSearch(
                execution: try container.decode(String.self, forKey: .execution),
                description: try container.decode(String.self, forKey: .description),
                parameters: try container.decode(JSONSchema.self, forKey: .parameters)
            )
        case "local_shell":
            self = .localShell
        case "image_generation":
            self = .imageGeneration(outputFormat: try container.decode(String.self, forKey: .outputFormat))
        case "web_search":
            self = .webSearch(
                externalWebAccess: try container.decodeIfPresent(Bool.self, forKey: .externalWebAccess),
                filters: try container.decodeIfPresent(ResponsesAPIWebSearchFilters.self, forKey: .filters),
                userLocation: try container.decodeIfPresent(
                    ResponsesAPIWebSearchUserLocation.self,
                    forKey: .userLocation
                ),
                searchContextSize: try container.decodeIfPresent(WebSearchContextSize.self, forKey: .searchContextSize),
                searchContentTypes: try container.decodeIfPresent([String].self, forKey: .searchContentTypes)
            )
        case "custom":
            self = .freeform(
                FreeformTool(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    format: try container.decode(FreeformToolFormat.self, forKey: .format)
                )
            )
        case let type:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported tool type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .function(tool):
            try container.encode("function", forKey: .type)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.description, forKey: .description)
            try container.encode(tool.strict, forKey: .strict)
            try container.encodeIfPresent(tool.deferLoading, forKey: .deferLoading)
            try container.encode(tool.parameters, forKey: .parameters)
        case let .namespace(namespace):
            try container.encode("namespace", forKey: .type)
            try container.encode(namespace.name, forKey: .name)
            try container.encode(namespace.description, forKey: .description)
            try container.encode(namespace.tools, forKey: .tools)
        case let .toolSearch(execution, description, parameters):
            try container.encode("tool_search", forKey: .type)
            try container.encode(execution, forKey: .execution)
            try container.encode(description, forKey: .description)
            try container.encode(parameters, forKey: .parameters)
        case .localShell:
            try container.encode("local_shell", forKey: .type)
        case let .imageGeneration(outputFormat):
            try container.encode("image_generation", forKey: .type)
            try container.encode(outputFormat, forKey: .outputFormat)
        case let .webSearch(
            externalWebAccess,
            filters,
            userLocation,
            searchContextSize,
            searchContentTypes
        ):
            try container.encode("web_search", forKey: .type)
            try container.encodeIfPresent(externalWebAccess, forKey: .externalWebAccess)
            try container.encodeIfPresent(filters, forKey: .filters)
            try container.encodeIfPresent(userLocation, forKey: .userLocation)
            try container.encodeIfPresent(searchContextSize, forKey: .searchContextSize)
            try container.encodeIfPresent(searchContentTypes, forKey: .searchContentTypes)
        case let .freeform(tool):
            try container.encode("custom", forKey: .type)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.description, forKey: .description)
            try container.encode(tool.format, forKey: .format)
        }
    }
}

public struct ConfiguredToolSpec: Equatable, Sendable {
    public let spec: ToolSpec
    public let supportsParallelToolCalls: Bool

    public init(spec: ToolSpec, supportsParallelToolCalls: Bool) {
        self.spec = spec
        self.supportsParallelToolCalls = supportsParallelToolCalls
    }
}

private struct DeferredDynamicToolName: Hashable {
    let namespace: String?
    let name: String

    init(namespace: String?, name: String) {
        self.namespace = namespace
        self.name = name
    }

    init(tool: DynamicToolSpec) {
        self.namespace = tool.namespace
        self.name = tool.name
    }

    static func plain(_ name: String) -> DeferredDynamicToolName {
        DeferredDynamicToolName(namespace: nil, name: name)
    }

    static func namespaced(_ namespace: String, _ name: String) -> DeferredDynamicToolName {
        DeferredDynamicToolName(namespace: namespace, name: name)
    }
}

public struct UnavailableToolName: Equatable, Hashable, Sendable {
    public let namespace: String?
    public let name: String

    public init(namespace: String? = nil, name: String) {
        self.namespace = namespace
        self.name = name
    }

    public static func plain(_ name: String) -> UnavailableToolName {
        UnavailableToolName(name: name)
    }

    public static func namespaced(_ namespace: String, _ name: String) -> UnavailableToolName {
        UnavailableToolName(namespace: namespace, name: name)
    }

    public var flatName: String {
        (namespace ?? "") + name
    }
}

public struct ToolsConfig: Equatable, Sendable {
    public let shellType: ConfigShellToolType
    public let applyPatchToolType: ApplyPatchToolType?
    public let webSearchMode: WebSearchMode?
    public let webSearchConfig: WebSearchConfig?
    public let webSearchRequest: Bool
    public let includeViewImageTool: Bool
    public let canRequestOriginalImageDetail: Bool
    public let environmentMode: ToolEnvironmentMode
    public let includeComputerUseTools: Bool
    public let experimentalSupportedTools: [String]
    public let namespaceTools: Bool
    public let toolSearch: Bool
    public let toolSuggest: Bool
    public let allowLoginShell: Bool
    public let multiAgentV2Tools: Bool
    public let spawnAgentUsageHint: Bool
    public let spawnAgentUsageHintText: String?
    public let hideSpawnAgentMetadata: Bool
    public let maxConcurrentThreadsPerSession: Int?
    public let waitAgentMinTimeoutMS: Int64?
    public let agentJobTools: Bool
    public let agentJobWorkerTools: Bool

    public init(
        shellType: ConfigShellToolType,
        applyPatchToolType: ApplyPatchToolType? = nil,
        webSearchMode: WebSearchMode? = nil,
        webSearchConfig: WebSearchConfig? = nil,
        webSearchRequest: Bool = false,
        includeViewImageTool: Bool = true,
        canRequestOriginalImageDetail: Bool = false,
        environmentMode: ToolEnvironmentMode = .single,
        includeComputerUseTools: Bool = false,
        experimentalSupportedTools: [String] = [],
        namespaceTools: Bool = true,
        toolSearch: Bool = true,
        toolSuggest: Bool = true,
        allowLoginShell: Bool = true,
        multiAgentV2Tools: Bool = false,
        spawnAgentUsageHint: Bool = true,
        spawnAgentUsageHintText: String? = nil,
        hideSpawnAgentMetadata: Bool = false,
        maxConcurrentThreadsPerSession: Int? = nil,
        waitAgentMinTimeoutMS: Int64? = nil,
        agentJobTools: Bool = false,
        agentJobWorkerTools: Bool = false
    ) {
        self.shellType = shellType
        self.applyPatchToolType = applyPatchToolType
        self.webSearchMode = webSearchMode
        self.webSearchConfig = webSearchConfig
        self.webSearchRequest = webSearchRequest
        self.includeViewImageTool = includeViewImageTool
        self.canRequestOriginalImageDetail = canRequestOriginalImageDetail
        self.environmentMode = environmentMode
        self.includeComputerUseTools = includeComputerUseTools
        self.experimentalSupportedTools = experimentalSupportedTools
        self.namespaceTools = namespaceTools
        self.toolSearch = toolSearch
        self.toolSuggest = toolSuggest
        self.allowLoginShell = allowLoginShell
        self.multiAgentV2Tools = multiAgentV2Tools
        self.spawnAgentUsageHint = spawnAgentUsageHint
        self.spawnAgentUsageHintText = spawnAgentUsageHintText
        self.hideSpawnAgentMetadata = hideSpawnAgentMetadata
        self.maxConcurrentThreadsPerSession = maxConcurrentThreadsPerSession
        self.waitAgentMinTimeoutMS = waitAgentMinTimeoutMS
        self.agentJobTools = agentJobTools
        self.agentJobWorkerTools = agentJobWorkerTools
    }
}

public enum ToolSpecFactory {
    private static let spawnAgentInheritedModelGuidance = "Spawned agents inherit your current model by default. Omit `model` to use that preferred default; set `model` only when an explicit override is needed."
    private static let spawnAgentModelOverrideDescription = "Optional model override for the new agent. Leave unset to inherit the same model as the parent, which is the preferred default. Only set this when the user explicitly asks for a different model or the task clearly requires one."
    private static let defaultAgentTypeDescription = "Optional type name for the new agent. If omitted, `default` is used."
    private static let defaultWaitAgentTimeoutMS: Int64 = 30_000

    public static func buildSpecs(
        config: ToolsConfig,
        mcpTools: [String: McpTool]? = nil,
        deferredMcpTools: [String: McpTool]? = nil,
        dynamicTools: [DynamicToolSpec] = [],
        discoverableTools: [DiscoverableTool]? = nil,
        unavailableCalledTools: [UnavailableToolName] = []
    ) -> [ConfiguredToolSpec] {
        buildSpecs(
            config: config,
            mcpToolInfos: mcpTools.map(mcpToolInfos(from:)),
            deferredMcpToolInfos: deferredMcpTools.map(mcpToolInfos(from:)),
            dynamicTools: dynamicTools,
            discoverableTools: discoverableTools,
            unavailableCalledTools: unavailableCalledTools
        )
    }

    public static func buildSpecs(
        config: ToolsConfig,
        mcpToolInfos: [McpToolInfo]?,
        deferredMcpToolInfos: [McpToolInfo]? = nil,
        dynamicTools: [DynamicToolSpec] = [],
        discoverableTools: [DiscoverableTool]? = nil,
        unavailableCalledTools: [UnavailableToolName] = []
    ) -> [ConfiguredToolSpec] {
        var specs: [ConfiguredToolSpec] = []

        switch config.shellType {
        case .default:
            specs.append(ConfiguredToolSpec(spec: createShellTool(), supportsParallelToolCalls: false))
        case .local:
            specs.append(ConfiguredToolSpec(spec: .localShell, supportsParallelToolCalls: false))
        case .unifiedExec:
            specs.append(ConfiguredToolSpec(
                spec: createExecCommandTool(allowLoginShell: config.allowLoginShell),
                supportsParallelToolCalls: false
            ))
            specs.append(ConfiguredToolSpec(spec: createWriteStdinTool(), supportsParallelToolCalls: false))
        case .disabled:
            break
        case .shellCommand:
            specs.append(ConfiguredToolSpec(
                spec: createShellCommandTool(allowLoginShell: config.allowLoginShell),
                supportsParallelToolCalls: false
            ))
        }

        specs.append(ConfiguredToolSpec(spec: createListMCPResourcesTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createListMCPResourceTemplatesTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createReadMCPResourceTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createPlanTool(), supportsParallelToolCalls: false))

        let deferredMcpToolsForSearch = config.namespaceTools ? deferredMcpToolInfos : nil
        let deferredDynamicTools = dynamicTools.filter { tool in
            tool.deferLoading && (config.namespaceTools || tool.namespace == nil)
        }
        if config.toolSearch,
           (deferredMcpToolsForSearch?.isEmpty == false || !deferredDynamicTools.isEmpty) {
            let index = ToolSearchIndex.deferredToolIndex(
                mcpTools: deferredMcpToolsForSearch ?? [],
                dynamicTools: deferredDynamicTools,
                namespaceTools: config.namespaceTools
            )
            specs.append(ConfiguredToolSpec(spec: index.toolSpec(), supportsParallelToolCalls: true))
        }

        if config.toolSuggest,
           let discoverableTools,
           !discoverableTools.isEmpty {
            specs.append(ConfiguredToolSpec(
                spec: createRequestPluginInstallTool(
                    entries: collectRequestPluginInstallEntries(discoverableTools)
                ),
                supportsParallelToolCalls: true
            ))
        }

        switch config.applyPatchToolType {
        case .freeform:
            specs.append(ConfiguredToolSpec(spec: createApplyPatchFreeformTool(), supportsParallelToolCalls: false))
        case nil:
            break
        }

        if config.experimentalSupportedTools.contains("grep_files") {
            specs.append(ConfiguredToolSpec(spec: createGrepFilesTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("read_file") {
            specs.append(ConfiguredToolSpec(spec: createReadFileTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("list_dir") {
            specs.append(ConfiguredToolSpec(spec: createListDirTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("test_sync_tool") {
            specs.append(ConfiguredToolSpec(spec: createTestSyncTool(), supportsParallelToolCalls: true))
        }
        if config.agentJobTools || config.experimentalSupportedTools.contains("spawn_agents_on_csv") {
            specs.append(ConfiguredToolSpec(spec: createSpawnAgentsOnCSVTool(), supportsParallelToolCalls: false))
        }
        if config.agentJobWorkerTools || config.experimentalSupportedTools.contains("report_agent_job_result") {
            specs.append(ConfiguredToolSpec(spec: createReportAgentJobResultTool(), supportsParallelToolCalls: false))
        }

        let webSearchMode = config.webSearchMode ?? (config.webSearchRequest ? .live : nil)
        switch webSearchMode {
        case .cached:
            specs.append(ConfiguredToolSpec(
                spec: .webSearch(
                    externalWebAccess: false,
                    filters: config.webSearchConfig?.filters,
                    userLocation: config.webSearchConfig?.userLocation,
                    searchContextSize: config.webSearchConfig?.searchContextSize
                ),
                supportsParallelToolCalls: false
            ))
        case .live:
            specs.append(ConfiguredToolSpec(
                spec: .webSearch(
                    externalWebAccess: true,
                    filters: config.webSearchConfig?.filters,
                    userLocation: config.webSearchConfig?.userLocation,
                    searchContextSize: config.webSearchConfig?.searchContextSize
                ),
                supportsParallelToolCalls: false
            ))
        case .disabled, nil:
            break
        }

        if config.includeViewImageTool {
            specs.append(ConfiguredToolSpec(
                spec: createViewImageTool(
                    canRequestOriginalImageDetail: config.canRequestOriginalImageDetail,
                    includeEnvironmentID: config.environmentMode == .multiple
                ),
                supportsParallelToolCalls: true
            ))
        }

        if config.multiAgentV2Tools {
            specs.append(contentsOf: createMultiAgentV2ToolSpecs(
                includeUsageHint: config.spawnAgentUsageHint,
                usageHintText: config.spawnAgentUsageHintText,
                hideAgentMetadata: config.hideSpawnAgentMetadata,
                maxConcurrentThreadsPerSession: config.maxConcurrentThreadsPerSession,
                waitAgentMinTimeoutMS: config.waitAgentMinTimeoutMS
            ).map {
                ConfiguredToolSpec(spec: $0, supportsParallelToolCalls: false)
            })
        }

        if config.includeComputerUseTools {
            specs.append(ConfiguredToolSpec(spec: createComputerScreenshotTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerClickTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerDragTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerScrollTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerTypeTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerKeyTool(), supportsParallelToolCalls: true))
        }

        if let mcpToolInfos, config.namespaceTools {
            for namespace in createMCPNamespaces(from: mcpToolInfos) {
                specs.append(ConfiguredToolSpec(spec: .namespace(namespace), supportsParallelToolCalls: false))
            }
        }

        for spec in createDynamicToolSpecs(from: dynamicTools) {
            if config.namespaceTools || !isNamespace(spec) {
                specs.append(ConfiguredToolSpec(spec: spec, supportsParallelToolCalls: false))
            }
        }

        appendUnavailableToolSpecs(
            &specs,
            unavailableCalledTools: unavailableCalledTools
        )

        return specs
    }

    public static func modelVisibleSpecs(
        from specs: [ConfiguredToolSpec],
        dynamicTools: [DynamicToolSpec]
    ) -> [ToolSpec] {
        let deferredDynamicTools = Set(
            dynamicTools.lazy.filter(\.deferLoading).map(DeferredDynamicToolName.init)
        )
        return specs.compactMap { configuredTool in
            filterDeferredDynamicToolSpec(
                configuredTool.spec,
                deferredDynamicTools: deferredDynamicTools
            )
        }
    }

    public static func createToolsJSONForResponsesAPI(_ tools: [ToolSpec]) throws -> [Any] {
        try tools.map { tool in
            let data = try JSONEncoder().encode(tool)
            return try JSONSerialization.jsonObject(with: data)
        }
    }

    public static func createToolsJSONForChatCompletionsAPI(_ tools: [ToolSpec]) throws -> [Any] {
        try createToolsJSONForResponsesAPI(tools).compactMap { tool in
            guard var object = tool as? [String: Any],
                  object["type"] as? String == "function"
            else {
                return nil
            }
            let name = object["name"] as? String ?? ""
            object.removeValue(forKey: "type")
            return [
                "type": "function",
                "name": name,
                "function": object
            ]
        }
    }

    public static func createMCPTool(fullyQualifiedName: String, tool: McpTool) -> ToolSpec {
        .function(createMCPResponsesAPITool(name: fullyQualifiedName, tool: tool))
    }

    public static func createRequestPluginInstallTool(entries: [RequestPluginInstallEntry]) -> ToolSpec {
        return functionTool(
            name: requestPluginInstallToolName,
            description: requestPluginInstallToolDescription(entries: entries),
            properties: [
                "tool_type": .string(description: "Type of discoverable tool to suggest. Use \"connector\" or \"plugin\"."),
                "action_type": .string(description: "Suggested action for the tool. Use \"install\"."),
                "tool_id": .string(description: "Connector or plugin id to suggest."),
                "suggest_reason": .string(description: "Concise one-line user-facing reason why this plugin or connector can help with the current request.")
            ],
            required: ["tool_type", "action_type", "tool_id", "suggest_reason"]
        )
    }

    public static func defaultNamespaceDescription(_ namespaceName: String) -> String {
        "Tools in the \(namespaceName) namespace."
    }

    private static func mcpToolInfos(from mcpTools: [String: McpTool]) -> [McpToolInfo] {
        mcpTools.compactMap { qualifiedName, tool in
            guard let split = McpToolName.splitQualifiedToolName(qualifiedName) else {
                return nil
            }
            return McpToolInfo(serverName: split.serverName, tool: tool)
        }
    }

    private static func createMCPNamespaces(from mcpTools: [McpToolInfo]) -> [ResponsesAPINamespace] {
        var groupedTools: [String: [(name: String, tool: McpTool)]] = [:]

        var namespaceDescriptions: [String: String] = [:]
        for toolInfo in McpToolName.normalizeToolsForModel(mcpTools) {
            let namespace = toolInfo.callableNamespace
            if namespaceDescriptions[namespace] == nil,
               let description = toolInfo.namespaceDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                namespaceDescriptions[namespace] = description
            }
            groupedTools[namespace, default: []].append((name: toolInfo.callableName, tool: toolInfo.tool))
        }

        return groupedTools.keys.sorted().compactMap { namespace in
            let tools = (groupedTools[namespace] ?? [])
                .sorted { $0.name < $1.name }
                .map { entry in
                    ResponsesAPINamespaceTool.function(createMCPResponsesAPITool(name: entry.name, tool: entry.tool))
                }

            guard !tools.isEmpty else {
                return nil
            }

            return ResponsesAPINamespace(
                name: namespace,
                description: namespaceDescriptions[namespace] ?? defaultNamespaceDescription(namespace),
                tools: tools
            )
        }
    }

    static func createDynamicToolSpecs(from dynamicTools: [DynamicToolSpec]) -> [ToolSpec] {
        var specs: [ToolSpec] = []
        for tool in dynamicTools {
            let function = createDynamicResponsesAPITool(name: tool.name, tool: tool)
            guard let namespaceName = tool.namespace else {
                specs.append(.function(function))
                continue
            }

            if let index = specs.firstIndex(where: { spec in
                guard case let .namespace(namespace) = spec else {
                    return false
                }
                return namespace.name == namespaceName
            }), case let .namespace(existingNamespace) = specs[index] {
                var tools = existingNamespace.tools
                tools.append(.function(function))
                specs[index] = .namespace(ResponsesAPINamespace(
                    name: existingNamespace.name,
                    description: existingNamespace.description,
                    tools: tools
                ))
            } else {
                specs.append(.namespace(ResponsesAPINamespace(
                    name: namespaceName,
                    description: defaultNamespaceDescription(namespaceName),
                    tools: [.function(function)]
                )))
            }
        }
        return specs
    }

    private static func isNamespace(_ spec: ToolSpec) -> Bool {
        if case .namespace = spec {
            return true
        }
        return false
    }

    private static func filterDeferredDynamicToolSpec(
        _ spec: ToolSpec,
        deferredDynamicTools: Set<DeferredDynamicToolName>
    ) -> ToolSpec? {
        guard !deferredDynamicTools.isEmpty else {
            return spec
        }

        switch spec {
        case let .function(tool):
            return deferredDynamicTools.contains(.plain(tool.name)) ? nil : spec
        case let .namespace(namespace):
            let tools = namespace.tools.filter { namespaceTool in
                guard case let .function(function) = namespaceTool else {
                    return true
                }
                return !deferredDynamicTools.contains(.namespaced(namespace.name, function.name))
            }
            guard !tools.isEmpty else {
                return nil
            }
            return .namespace(ResponsesAPINamespace(
                name: namespace.name,
                description: namespace.description,
                tools: tools
            ))
        default:
            return spec
        }
    }

    static func createDynamicResponsesAPITool(name: String, tool: DynamicToolSpec) -> ResponsesAPITool {
        ResponsesAPITool(
            name: name,
            description: tool.description,
            strict: false,
            deferLoading: tool.deferLoading ? true : nil,
            parameters: JSONSchema.sanitized(from: jsonCompatibleValue(tool.inputSchema))
        )
    }

    public static func collectUnavailableCalledTools(
        input: [ResponseItem],
        exposedToolNames: [UnavailableToolName]
    ) -> [UnavailableToolName] {
        let exposedFlatNames = Set(exposedToolNames.map(\.flatName))
        var unavailableByFlatName: [String: UnavailableToolName] = [:]
        for item in input {
            guard case let .functionCall(_, name, namespace, _, _) = item,
                  shouldCollectUnavailableTool(name: name, namespace: namespace)
            else {
                continue
            }
            let toolName = UnavailableToolName(namespace: namespace, name: name)
            guard !exposedFlatNames.contains(toolName.flatName) else {
                continue
            }
            if unavailableByFlatName[toolName.flatName] == nil {
                unavailableByFlatName[toolName.flatName] = toolName
            }
        }
        return unavailableByFlatName.keys.sorted().compactMap { unavailableByFlatName[$0] }
    }

    public static func shouldCollectUnavailableTool(name: String, namespace: String?) -> Bool {
        namespace?.hasPrefix("mcp__") == true || name.hasPrefix("mcp__")
    }

    public static func unavailableToolMessage(toolName: String, nextStep: String) -> String {
        "Tool `\(toolName)` is not currently available. It appeared in earlier tool calls in this conversation, but its implementation is not available in the current request. \(nextStep)"
    }

    public static func createUnavailableTool(_ toolName: UnavailableToolName) -> ToolSpec {
        functionTool(
            name: toolName.flatName,
            description: unavailableToolMessage(
                toolName: toolName.flatName,
                nextStep: "Calling this placeholder returns an error explaining that the tool is unavailable."
            ),
            properties: [:],
            required: nil
        )
    }

    private static func appendUnavailableToolSpecs(
        _ specs: inout [ConfiguredToolSpec],
        unavailableCalledTools: [UnavailableToolName]
    ) {
        guard !unavailableCalledTools.isEmpty else {
            return
        }
        var existingSpecNames = Set(specs.map(\.spec.name))
        for toolName in unavailableCalledTools.sorted(by: { $0.flatName < $1.flatName }) {
            guard existingSpecNames.insert(toolName.flatName).inserted else {
                continue
            }
            specs.append(ConfiguredToolSpec(
                spec: createUnavailableTool(toolName),
                supportsParallelToolCalls: false
            ))
        }
    }

    static func createMCPResponsesAPITool(
        name: String,
        tool: McpTool,
        deferLoading: Bool? = nil
    ) -> ResponsesAPITool {
        var inputSchema: [String: Any] = ["type": tool.inputSchema.type]
        if let properties = tool.inputSchema.properties {
            inputSchema["properties"] = jsonCompatibleValue(properties)
        } else if tool.inputSchema.type == "object" {
            inputSchema["properties"] = [String: Any]()
        }
        if let required = tool.inputSchema.required {
            inputSchema["required"] = required
        }

        return ResponsesAPITool(
            name: name,
            description: tool.description ?? "",
            strict: false,
            deferLoading: deferLoading,
            parameters: JSONSchema.sanitized(from: inputSchema),
            outputSchema: mcpCallToolResultOutputSchema(structuredContentSchema: tool.outputSchema?.jsonSchema ?? .object([:]))
        )
    }

    public static func mcpCallToolResultOutputSchema(structuredContentSchema: JSONValue = .object([:])) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "content": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object")
                    ])
                ]),
                "structuredContent": structuredContentSchema,
                "isError": .object([
                    "type": .string("boolean")
                ]),
                "_meta": .object([
                    "type": .string("object")
                ])
            ]),
            "required": .array([.string("content")]),
            "additionalProperties": .bool(false)
        ])
    }

    public static func createExecCommandTool(allowLoginShell: Bool = true) -> ToolSpec {
        var properties: [String: JSONSchema] = [
            "cmd": .string(description: "Shell command to execute."),
            "workdir": .string(description: "Optional working directory to run the command in; defaults to the turn cwd."),
            "shell": .string(description: "Shell binary to launch. Defaults to /bin/bash."),
            "yield_time_ms": .number(description: "How long to wait (in milliseconds) for output before yielding."),
            "max_output_tokens": .number(description: "Maximum number of tokens to return. Excess output will be truncated."),
            "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
            "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
        ]
        if allowLoginShell {
            properties["login"] = .boolean(description: "Whether to run the shell with -l/-i semantics. Defaults to true.")
        }
        return functionTool(
            name: "exec_command",
            description: "Runs a command in a PTY, returning output or a session ID for ongoing interaction.",
            properties: properties,
            required: ["cmd"]
        )
    }

    public static func createWriteStdinTool() -> ToolSpec {
        return functionTool(
            name: "write_stdin",
            description: "Writes characters to an existing unified exec session and returns recent output.",
            properties: [
                "session_id": .number(description: "Identifier of the running unified exec session."),
                "chars": .string(description: "Bytes to write to stdin (may be empty to poll)."),
                "yield_time_ms": .number(description: "How long to wait (in milliseconds) for output before yielding."),
                "max_output_tokens": .number(description: "Maximum number of tokens to return. Excess output will be truncated.")
            ],
            required: ["session_id"]
        )
    }

    public static func createShellTool() -> ToolSpec {
        functionTool(
            name: "shell",
            description: """
            Runs a shell command and returns its output.
            - The arguments to `shell` will be passed to execvp(). Most terminal commands should be prefixed with ["bash", "-lc"].
            - Always set the `workdir` param when using the shell function. Do not use `cd` unless absolutely necessary.
            """,
            properties: [
                "command": .array(items: .string(description: nil), description: "The command to execute"),
                "workdir": .string(description: "The working directory to execute the command in"),
                "timeout_ms": .number(description: "The timeout for the command in milliseconds"),
                "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
                "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
            ],
            required: ["command"]
        )
    }

    public static func createShellCommandTool(allowLoginShell: Bool = true) -> ToolSpec {
        var properties: [String: JSONSchema] = [
            "command": .string(description: "The shell script to execute in the user's default shell"),
            "workdir": .string(description: "The working directory to execute the command in"),
            "timeout_ms": .number(description: "The timeout for the command in milliseconds"),
            "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
            "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
        ]
        if allowLoginShell {
            properties["login"] = .boolean(description: "Whether to run the shell with login shell semantics. Defaults to true.")
        }
        return functionTool(
            name: "shell_command",
            description: """
            Runs a shell command and returns its output.
            - Always set the `workdir` param when using the shell_command function. Do not use `cd` unless absolutely necessary.
            """,
            properties: properties,
            required: ["command"]
        )
    }

    public static func createPlanTool() -> ToolSpec {
        functionTool(
            name: "update_plan",
            description: """
            Updates the task plan.
            Provide an optional explanation and a list of plan items, each with a step and status.
            At most one step can be in_progress at a time.

            """,
            properties: [
                "explanation": .string(description: nil),
                "plan": .array(
                    items: .object(
                        properties: [
                            "step": .string(description: nil),
                            "status": .string(description: "One of: pending, in_progress, completed")
                        ],
                        required: ["step", "status"],
                        additionalProperties: .boolean(false)
                    ),
                    description: "The list of steps"
                )
            ],
            required: ["plan"]
        )
    }

    public static func createApplyPatchFreeformTool() -> ToolSpec {
        .freeform(
            FreeformTool(
                name: "apply_patch",
                description: "Use the `apply_patch` tool to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON.",
                format: FreeformToolFormat(type: "grammar", syntax: "lark", definition: applyPatchLarkGrammar)
            )
        )
    }

    public static func createViewImageTool(
        canRequestOriginalImageDetail: Bool = false,
        includeEnvironmentID: Bool = false
    ) -> ToolSpec {
        var properties: [String: JSONSchema] = [
            "path": .string(description: "Local filesystem path to an image file")
        ]
        if canRequestOriginalImageDetail {
            properties["detail"] = .string(description: "Optional detail override. The only supported value is `original`; omit this field for default resized behavior. Use `original` to preserve the file's original resolution instead of resizing to fit. This is important when high-fidelity image perception or precise localization is needed, especially for CUA agents.")
        }
        if includeEnvironmentID {
            properties["environment_id"] = .string(description: "Optional selected environment id to target. Omit this to use the primary environment.")
        }

        return functionTool(
            name: "view_image",
            description: "View a local image from the filesystem (only use if given a full filepath by the user, and the image isn't already attached to the thread context within <image ...> tags).",
            properties: properties,
            required: ["path"],
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_url": .object([
                        "type": .string("string"),
                        "description": .string("Data URL for the loaded image.")
                    ]),
                    "detail": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Image detail hint returned by view_image. Returns `original` when original resolution is preserved, otherwise `null`.")
                    ])
                ]),
                "required": .array([.string("image_url"), .string("detail")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    public static func createComputerScreenshotTool() -> ToolSpec {
        functionTool(
            name: "computer_screenshot",
            description: "Capture a single on-demand screenshot of the GUI (1280x720 coordinate space).",
            properties: [:],
            required: nil
        )
    }

    public static func createComputerClickTool() -> ToolSpec {
        functionTool(
            name: "computer_click",
            description: "Move the mouse to a coordinate and click (coordinates are 1280x720).",
            properties: [
                "x": .number(description: "X coordinate in 1280x720 space."),
                "y": .number(description: "Y coordinate in 1280x720 space."),
                "button": .string(description: "Mouse button: left (default), right, or middle."),
                "double": .boolean(description: "Double-click when true.")
            ],
            required: ["x", "y"]
        )
    }

    public static func createComputerDragTool() -> ToolSpec {
        functionTool(
            name: "computer_drag",
            description: "Click-and-drag between two coordinates (coordinates are 1280x720).",
            properties: [
                "from_x": .number(description: "Start X coordinate in 1280x720 space."),
                "from_y": .number(description: "Start Y coordinate in 1280x720 space."),
                "to_x": .number(description: "End X coordinate in 1280x720 space."),
                "to_y": .number(description: "End Y coordinate in 1280x720 space."),
                "button": .string(description: "Mouse button: left (default), right, or middle.")
            ],
            required: ["from_x", "from_y", "to_x", "to_y"]
        )
    }

    public static func createComputerScrollTool() -> ToolSpec {
        functionTool(
            name: "computer_scroll",
            description: "Scroll the mouse wheel (coordinates are 1280x720 if provided).",
            properties: [
                "direction": .string(description: "Scroll direction: up or down."),
                "amount": .number(description: "Number of scroll ticks (defaults to 3)."),
                "x": .number(description: "Optional X coordinate in 1280x720 space."),
                "y": .number(description: "Optional Y coordinate in 1280x720 space.")
            ],
            required: ["direction"]
        )
    }

    public static func createComputerTypeTool() -> ToolSpec {
        functionTool(
            name: "computer_type",
            description: "Type text at the current focus.",
            properties: [
                "text": .string(description: "Text to type."),
                "delay_ms": .number(description: "Optional delay between keystrokes in milliseconds.")
            ],
            required: ["text"]
        )
    }

    public static func createComputerKeyTool() -> ToolSpec {
        functionTool(
            name: "computer_key",
            description: "Press a key or key chord.",
            properties: [
                "keys": .array(items: .string(description: nil), description: "Key chord, e.g. [\"ctrl\", \"c\"]."),
                "confirm": .boolean(description: "Required for destructive combos (Alt+F4, Ctrl+Q, Ctrl+W, etc.).")
            ],
            required: ["keys"]
        )
    }

    public static func createTestSyncTool() -> ToolSpec {
        functionTool(
            name: "test_sync_tool",
            description: "Internal synchronization helper used by Codex integration tests.",
            properties: [
                "sleep_before_ms": .number(description: "Optional delay in milliseconds before any other action"),
                "sleep_after_ms": .number(description: "Optional delay in milliseconds after completing the barrier"),
                "barrier": .object(
                    properties: [
                        "id": .string(description: "Identifier shared by concurrent calls that should rendezvous"),
                        "participants": .number(description: "Number of tool calls that must arrive before the barrier opens"),
                        "timeout_ms": .number(description: "Maximum time in milliseconds to wait at the barrier")
                    ],
                    required: ["id", "participants"],
                    additionalProperties: .boolean(false)
                )
            ],
            required: nil
        )
    }

    public static func createMultiAgentV2ToolSpecs(
        includeUsageHint: Bool = true,
        usageHintText: String? = nil,
        hideAgentMetadata: Bool = false,
        maxConcurrentThreadsPerSession: Int? = nil,
        waitAgentMinTimeoutMS: Int64? = nil
    ) -> [ToolSpec] {
        [
            createSpawnAgentV2Tool(
                includeUsageHint: includeUsageHint,
                usageHintText: usageHintText,
                hideAgentMetadata: hideAgentMetadata,
                maxConcurrentThreadsPerSession: maxConcurrentThreadsPerSession
            ),
            createSendMessageTool(),
            createFollowupTaskTool(),
            createWaitAgentV2Tool(minTimeoutMS: waitAgentMinTimeoutMS),
            createCloseAgentV2Tool(),
            createListAgentsTool()
        ]
    }

    public static func createSpawnAgentV2Tool(
        includeUsageHint: Bool = true,
        usageHintText: String? = nil,
        hideAgentMetadata: Bool = false,
        maxConcurrentThreadsPerSession: Int? = nil
    ) -> ToolSpec {
        var properties: [String: JSONSchema] = [
            "message": .string(description: "Initial plain-text task for the new agent."),
            "agent_type": .string(description: defaultAgentTypeDescription),
            "fork_turns": .string(description: "Optional number of turns to fork. Defaults to `all`. Use `none`, `all`, or a positive integer string such as `3` to fork only the most recent turns."),
            "model": .string(description: spawnAgentModelOverrideDescription),
            "reasoning_effort": .string(description: "Optional reasoning effort override for the new agent. Replaces the inherited reasoning effort."),
            "task_name": .string(description: "Task name for the new agent. Use lowercase letters, digits, and underscores.")
        ]
        if hideAgentMetadata {
            properties.removeValue(forKey: "agent_type")
            properties.removeValue(forKey: "model")
            properties.removeValue(forKey: "reasoning_effort")
        }

        return functionTool(
            name: "spawn_agent",
            description: spawnAgentV2Description(
                includeUsageHint: includeUsageHint,
                usageHintText: usageHintText,
                hideAgentMetadata: hideAgentMetadata,
                maxConcurrentThreadsPerSession: maxConcurrentThreadsPerSession
            ),
            properties: properties,
            required: ["task_name", "message"],
            outputSchema: spawnAgentV2OutputSchema(hideAgentMetadata: hideAgentMetadata)
        )
    }

    public static func createSendMessageTool() -> ToolSpec {
        functionTool(
            name: "send_message",
            description: "Send a message to an existing agent. The message will be delivered promptly. Does not trigger a new turn.",
            properties: [
                "target": .string(description: "Relative or canonical task name to message (from spawn_agent)."),
                "message": .string(description: "Message text to queue on the target agent.")
            ],
            required: ["target", "message"]
        )
    }

    public static func createFollowupTaskTool() -> ToolSpec {
        functionTool(
            name: "followup_task",
            description: "Send a message to an existing non-root target agent and trigger a turn in that target. If the target is currently mid-turn, the message is queued and will be used to start the target's next turn, after the current turn completes.",
            properties: [
                "target": .string(description: "Agent id or canonical task name to message (from spawn_agent)."),
                "message": .string(description: "Message text to send to the target agent.")
            ],
            required: ["target", "message"]
        )
    }

    public static func createWaitAgentV2Tool(minTimeoutMS: Int64? = nil) -> ToolSpec {
        let timeoutDescription = waitAgentTimeoutDescription(minTimeoutMS: minTimeoutMS)
        return functionTool(
            name: "wait_agent",
            description: "Wait for a mailbox update from any live agent, including queued messages and final-status notifications. Does not return the content; returns either a summary of which agents have updates (if any), or a timeout summary if no mailbox update arrives before the deadline.",
            properties: [
                "timeout_ms": .number(description: timeoutDescription)
            ],
            required: nil,
            outputSchema: waitAgentV2OutputSchema()
        )
    }

    public static func createCloseAgentV2Tool() -> ToolSpec {
        functionTool(
            name: "close_agent",
            description: "Close an agent and any open descendants when they are no longer needed, and return the target agent's previous status before shutdown was requested. Don't keep agents open for too long if they are not needed anymore.",
            properties: [
                "target": .string(description: "Agent id or canonical task name to close (from spawn_agent).")
            ],
            required: ["target"],
            outputSchema: closeAgentOutputSchema()
        )
    }

    public static func createListAgentsTool() -> ToolSpec {
        functionTool(
            name: "list_agents",
            description: "List live agents in the current root thread tree. Optionally filter by task-path prefix.",
            properties: [
                "path_prefix": .string(description: "Optional task-path prefix (not ending with trailing slash). Accepts the same relative or absolute task-path syntax.")
            ],
            required: nil,
            outputSchema: listAgentsOutputSchema()
        )
    }

    public static func createSpawnAgentsOnCSVTool() -> ToolSpec {
        functionTool(
            name: "spawn_agents_on_csv",
            description: "Process a CSV by spawning one worker sub-agent per row. The instruction string is a template where `{column}` placeholders are replaced with row values. Each worker must call `report_agent_job_result` with a JSON object (matching `output_schema` when provided); missing reports are treated as failures. This call blocks until all rows finish and automatically exports results to `output_csv_path` (or a default path).",
            properties: [
                "csv_path": .string(description: "Path to the CSV file containing input rows."),
                "instruction": .string(description: "Instruction template to apply to each CSV row. Use {column_name} placeholders to inject values from the row."),
                "id_column": .string(description: "Optional column name to use as stable item id."),
                "output_csv_path": .string(description: "Optional output CSV path for exported results."),
                "max_concurrency": .number(description: "Maximum concurrent workers for this job. Defaults to 16 and is capped by config."),
                "max_workers": .number(description: "Alias for max_concurrency. Set to 1 to run sequentially."),
                "max_runtime_seconds": .number(description: "Maximum runtime per worker before it is failed. Defaults to 1800 seconds."),
                "output_schema": .object(properties: [:], required: nil, additionalProperties: nil)
            ],
            required: ["csv_path", "instruction"]
        )
    }

    public static func createReportAgentJobResultTool() -> ToolSpec {
        functionTool(
            name: "report_agent_job_result",
            description: "Worker-only tool to report a result for an agent job item. Main agents should not call this.",
            properties: [
                "job_id": .string(description: "Identifier of the job."),
                "item_id": .string(description: "Identifier of the job item."),
                "result": .object(properties: [:], required: nil, additionalProperties: nil),
                "stop": .boolean(description: "Optional. When true, cancels the remaining job items after this result is recorded.")
            ],
            required: ["job_id", "item_id", "result"]
        )
    }

    public static func createGrepFilesTool() -> ToolSpec {
        functionTool(
            name: "grep_files",
            description: "Finds files whose contents match the pattern and lists them by modification time.",
            properties: [
                "pattern": .string(description: "Regular expression pattern to search for."),
                "include": .string(description: "Optional glob that limits which files are searched (e.g. \"*.rs\" or \"*.{ts,tsx}\")."),
                "path": .string(description: "Directory or file path to search. Defaults to the session's working directory."),
                "limit": .number(description: "Maximum number of file paths to return (defaults to 100).")
            ],
            required: ["pattern"]
        )
    }

    public static func createReadFileTool() -> ToolSpec {
        functionTool(
            name: "read_file",
            description: "Reads a local file with 1-indexed line numbers, supporting slice and indentation-aware block modes.",
            properties: [
                "file_path": .string(description: "Absolute path to the file"),
                "offset": .number(description: "The line number to start reading from. Must be 1 or greater."),
                "limit": .number(description: "The maximum number of lines to return."),
                "mode": .string(description: "Optional mode selector: \"slice\" for simple ranges (default) or \"indentation\" to expand around an anchor line."),
                "indentation": .object(
                    properties: [
                        "anchor_line": .number(description: "Anchor line to center the indentation lookup on (defaults to offset)."),
                        "max_levels": .number(description: "How many parent indentation levels (smaller indents) to include."),
                        "include_siblings": .boolean(description: "When true, include additional blocks that share the anchor indentation."),
                        "include_header": .boolean(description: "Include doc comments or attributes directly above the selected block."),
                        "max_lines": .number(description: "Hard cap on the number of lines returned when using indentation mode.")
                    ],
                    required: nil,
                    additionalProperties: .boolean(false)
                )
            ],
            required: ["file_path"]
        )
    }

    public static func createListDirTool() -> ToolSpec {
        functionTool(
            name: "list_dir",
            description: "Lists entries in a local directory with 1-indexed entry numbers and simple type labels.",
            properties: [
                "dir_path": .string(description: "Absolute path to the directory to list."),
                "offset": .number(description: "The entry number to start listing from. Must be 1 or greater."),
                "limit": .number(description: "The maximum number of entries to return."),
                "depth": .number(description: "The maximum directory depth to traverse. Must be 1 or greater.")
            ],
            required: ["dir_path"]
        )
    }

    public static func createListMCPResourcesTool() -> ToolSpec {
        functionTool(
            name: "list_mcp_resources",
            description: "Lists resources provided by MCP servers. Resources allow servers to share data that provides context to language models, such as files, database schemas, or application-specific information. Prefer resources over web search when possible.",
            properties: [
                "server": .string(description: "Optional MCP server name. When omitted, lists resources from every configured server."),
                "cursor": .string(description: "Opaque cursor returned by a previous list_mcp_resources call for the same server.")
            ],
            required: nil
        )
    }

    public static func createListMCPResourceTemplatesTool() -> ToolSpec {
        functionTool(
            name: "list_mcp_resource_templates",
            description: "Lists resource templates provided by MCP servers. Parameterized resource templates allow servers to share data that takes parameters and provides context to language models, such as files, database schemas, or application-specific information. Prefer resource templates over web search when possible.",
            properties: [
                "server": .string(description: "Optional MCP server name. When omitted, lists resource templates from all configured servers."),
                "cursor": .string(description: "Opaque cursor returned by a previous list_mcp_resource_templates call for the same server.")
            ],
            required: nil
        )
    }

    public static func createReadMCPResourceTool() -> ToolSpec {
        functionTool(
            name: "read_mcp_resource",
            description: "Read a specific resource from an MCP server given the server name and resource URI.",
            properties: [
                "server": .string(description: "MCP server name exactly as configured. Must match the 'server' field returned by list_mcp_resources."),
                "uri": .string(description: "Resource URI to read. Must be one of the URIs returned by list_mcp_resources.")
            ],
            required: ["server", "uri"]
        )
    }

    private static func functionTool(
        name: String,
        description: String,
        properties: [String: JSONSchema],
        required: [String]?,
        outputSchema: JSONValue? = nil
    ) -> ToolSpec {
        .function(
            ResponsesAPITool(
                name: name,
                description: description,
                strict: false,
                parameters: .object(
                    properties: properties,
                    required: required,
                    additionalProperties: .boolean(false)
                ),
                outputSchema: outputSchema
            )
        )
    }

    private static func spawnAgentV2Description(
        includeUsageHint: Bool,
        usageHintText: String?,
        hideAgentMetadata: Bool,
        maxConcurrentThreadsPerSession: Int?
    ) -> String {
        let modelGuidance = hideAgentMetadata
            ? ""
            : "No picker-visible model overrides are currently loaded.\n"
        let concurrencyGuidance = maxConcurrentThreadsPerSession.map {
            "This session is configured with `max_concurrent_threads_per_session = \($0)` for concurrently open agent threads."
        } ?? ""
        var description = """
        \(modelGuidance)Spawns an agent to work on the specified task. If your current task is `/root/task1` and you spawn_agent with task_name "task_3" the agent will have canonical task name `/root/task1/task_3`.
        You are then able to refer to this agent as `task_3` or `/root/task1/task_3` interchangeably. However an agent `/root/task2/task_3` would only be able to communicate with this agent via its canonical name `/root/task1/task_3`.
        The spawned agent will have the same tools as you and the ability to spawn its own subagents.
        \(spawnAgentInheritedModelGuidance)
        It will be able to send you and other running agents messages, and its final answer will be provided to you when it finishes.
        The new agent's canonical task name will be provided to it along with the message.
        \(concurrencyGuidance)
        """
        if includeUsageHint, let usageHintText {
            description += "\n\(usageHintText)"
        }
        return description
    }

    private static func waitAgentTimeoutDescription(minTimeoutMS: Int64?) -> String {
        let maxTimeoutMS = MultiAgentV2Config.maxWaitTimeoutMS
        let minTimeoutMS = Swift.min(
            Swift.max(minTimeoutMS ?? MultiAgentV2Config.defaultMinWaitTimeoutMS, 1),
            maxTimeoutMS
        )
        let defaultTimeoutMS = Swift.min(
            Swift.max(defaultWaitAgentTimeoutMS, minTimeoutMS),
            maxTimeoutMS
        )
        return "Optional timeout in milliseconds. Defaults to \(defaultTimeoutMS), min \(minTimeoutMS), max \(maxTimeoutMS)."
    }

    private static func spawnAgentV2OutputSchema(hideAgentMetadata: Bool) -> JSONValue {
        if hideAgentMetadata {
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "task_name": .object([
                        "type": .string("string"),
                        "description": .string("Canonical task name for the spawned agent.")
                    ])
                ]),
                "required": stringArray(["task_name"]),
                "additionalProperties": .bool(false)
            ])
        }

        return .object([
            "type": .string("object"),
            "properties": .object([
                "task_name": .object([
                    "type": .string("string"),
                    "description": .string("Canonical task name for the spawned agent.")
                ]),
                "nickname": .object([
                    "type": stringArray(["string", "null"]),
                    "description": .string("User-facing nickname for the spawned agent when available.")
                ])
            ]),
            "required": stringArray(["task_name", "nickname"]),
            "additionalProperties": .bool(false)
        ])
    }

    private static func waitAgentV2OutputSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "message": .object([
                    "type": .string("string"),
                    "description": .string("Brief wait summary without the agent's final content.")
                ]),
                "timed_out": .object([
                    "type": .string("boolean"),
                    "description": .string("Whether the wait call returned because no mailbox update arrived before the timeout.")
                ])
            ]),
            "required": stringArray(["message", "timed_out"]),
            "additionalProperties": .bool(false)
        ])
    }

    private static func closeAgentOutputSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "previous_status": .object([
                    "description": .string("The agent status observed before shutdown was requested."),
                    "allOf": .array([agentStatusOutputSchema()])
                ])
            ]),
            "required": stringArray(["previous_status"]),
            "additionalProperties": .bool(false)
        ])
    }

    private static func listAgentsOutputSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "agents": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "agent_name": .object([
                                "type": .string("string"),
                                "description": .string("Canonical task name for the agent when available, otherwise the agent id.")
                            ]),
                            "agent_status": .object([
                                "description": .string("Last known status of the agent."),
                                "allOf": .array([agentStatusOutputSchema()])
                            ]),
                            "last_task_message": .object([
                                "type": stringArray(["string", "null"]),
                                "description": .string("Most recent user or inter-agent instruction received by the agent, when available.")
                            ])
                        ]),
                        "required": stringArray(["agent_name", "agent_status", "last_task_message"]),
                        "additionalProperties": .bool(false)
                    ]),
                    "description": .string("Live agents visible in the current root thread tree.")
                ])
            ]),
            "required": stringArray(["agents"]),
            "additionalProperties": .bool(false)
        ])
    }

    private static func agentStatusOutputSchema() -> JSONValue {
        .object([
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": stringArray(["pending_init", "running", "interrupted", "shutdown", "not_found"])
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "completed": .object([
                            "type": stringArray(["string", "null"])
                        ])
                    ]),
                    "required": stringArray(["completed"]),
                    "additionalProperties": .bool(false)
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "errored": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": stringArray(["errored"]),
                    "additionalProperties": .bool(false)
                ])
            ])
        ])
    }

    private static func stringArray(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }

    private static func requestPluginInstallToolDescription(entries: [RequestPluginInstallEntry]) -> String {
        let discoverableTools = entries
            .sorted { left, right in
                if left.name == right.name {
                    return left.id < right.id
                }
                return left.name < right.name
            }
            .map { entry in
                "- \(entry.name) (id: `\(entry.id)`, type: \(entry.toolType.rawValue), action: install): \(requestPluginInstallDescription(for: entry))"
            }
            .joined(separator: "\n")

        return """
        # Request plugin/connector install

        Use this tool only to ask the user to install one known plugin or connector from the list below. The list contains known candidates that are not currently installed.

        Use this ONLY when all of the following are true:
        - The user explicitly asks to use a specific plugin or connector that is not already available in the current context or active `tools` list.
        - `tool_search` is not available, or it has already been called and did not find or make the requested tool callable.
        - The plugin or connector is one of the known installable plugins or connectors listed below. Only ask to install plugins or connectors from this list.

        Do not use this tool for adjacent capabilities, broad recommendations, or tools that merely seem useful. Only use when the user explicitly asks to use that exact listed plugin or connector.

        Known plugins/connectors available to install:
        \(discoverableTools)

        Workflow:

        1. Check the current context and active `tools` list first. If current active tools aren't relevant and `tool_search` is available, only call this tool after `tool_search` has already been tried and found no relevant tool.
        2. Match the user's explicit request against the known plugin/connector list above. Only proceed when one listed plugin or connector exactly fits.
        3. If we found both connectors and plugins to install, use plugins first, only use connectors if the corresponding plugin is installed but the connector is not.
        4. If one plugin or connector clearly fits, call `request_plugin_install` with:
           - `tool_type`: `connector` or `plugin`
           - `action_type`: `install`
           - `tool_id`: exact id from the known plugin/connector list above
           - `suggest_reason`: concise one-line user-facing reason this plugin or connector can help with the current request
        5. After the request flow completes:
           - if the user finished the install flow, continue by searching again or using the newly available plugin or connector
           - if the user did not finish, continue without that plugin or connector, and don't request it again unless the user explicitly asks for it.

        IMPORTANT: DO NOT call this tool in parallel with other tools.
        """
    }

    private static func requestPluginInstallDescription(for entry: RequestPluginInstallEntry) -> String {
        if let description = entry.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }

        guard entry.toolType == .plugin else {
            return "No description provided."
        }

        var capabilities: [String] = []
        if entry.hasSkills {
            capabilities.append("skills")
        }
        if !entry.mcpServerNames.isEmpty {
            capabilities.append("MCP servers: \(entry.mcpServerNames.joined(separator: ", "))")
        }
        if !entry.appConnectorIDs.isEmpty {
            capabilities.append("app connectors: \(entry.appConnectorIDs.joined(separator: ", "))")
        }
        return capabilities.isEmpty ? "No description provided." : capabilities.joined(separator: "; ")
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

    public static let applyPatchLarkGrammar = """
    start: begin_patch hunk+ end_patch
    begin_patch: "*** Begin Patch" LF
    end_patch: "*** End Patch" LF?

    hunk: add_hunk | delete_hunk | update_hunk
    add_hunk: "*** Add File: " filename LF add_line+
    delete_hunk: "*** Delete File: " filename LF
    update_hunk: "*** Update File: " filename LF change_move? change?

    filename: /(.+)/
    add_line: "+" /(.*)/ LF -> line

    change_move: "*** Move to: " filename LF
    change: (change_context | change_line)+ eof_line?
    change_context: ("@@" | "@@ " /(.+)/) LF
    change_line: ("+" | "-" | " ") /(.*)/ LF
    eof_line: "*** End of File" LF

    %import common.LF
    """
}
