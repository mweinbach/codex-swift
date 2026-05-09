import Foundation

public enum AppServerProtocol {
    public enum ServerRequest: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, params: Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(requestID: RequestID, params: ChatGPTAuthTokensRefreshParams)
        case execCommandApproval(requestID: RequestID, params: ExecCommandApprovalParams)
        case applyPatchApproval(requestID: RequestID, params: ApplyPatchApprovalParams)
        case fileChangeRequestApproval(requestID: RequestID, params: FileChangeRequestApprovalParams)
        case commandExecutionRequestApproval(requestID: RequestID, params: CommandExecutionRequestApprovalParams)
        case toolRequestUserInput(requestID: RequestID, params: ToolRequestUserInputParams)
        case dynamicToolCall(requestID: RequestID, params: DynamicToolCallParams)
        case permissionsRequestApproval(requestID: RequestID, params: PermissionsRequestApprovalParams)
        case mcpServerElicitationRequest(requestID: RequestID, params: McpServerElicitationRequestParams)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            case let .execCommandApproval(requestID, _):
                requestID
            case let .applyPatchApproval(requestID, _):
                requestID
            case let .fileChangeRequestApproval(requestID, _):
                requestID
            case let .commandExecutionRequestApproval(requestID, _):
                requestID
            case let .toolRequestUserInput(requestID, _):
                requestID
            case let .dynamicToolCall(requestID, _):
                requestID
            case let .permissionsRequestApproval(requestID, _):
                requestID
            case let .mcpServerElicitationRequest(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
            case .execCommandApproval:
                ExecCommandApprovalParams.method
            case .applyPatchApproval:
                ApplyPatchApprovalParams.method
            case .fileChangeRequestApproval:
                FileChangeRequestApprovalParams.method
            case .commandExecutionRequestApproval:
                CommandExecutionRequestApprovalParams.method
            case .toolRequestUserInput:
                ToolRequestUserInputParams.method
            case .dynamicToolCall:
                DynamicToolCallParams.method
            case .permissionsRequestApproval:
                PermissionsRequestApprovalParams.method
            case .mcpServerElicitationRequest:
                McpServerElicitationRequestParams.method
            }
        }

        private enum CodingKeys: String, CodingKey {
            case method
            case id
            case params
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            switch method {
            case Attestation.generateMethod:
                self = .attestationGenerate(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(Attestation.GenerateParams.self, forKey: .params)
                )
            case ChatGPTAuthTokensRefreshParams.method:
                self = .chatGPTAuthTokensRefresh(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ChatGPTAuthTokensRefreshParams.self, forKey: .params)
                )
            case ExecCommandApprovalParams.method:
                self = .execCommandApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ExecCommandApprovalParams.self, forKey: .params)
                )
            case ApplyPatchApprovalParams.method:
                self = .applyPatchApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ApplyPatchApprovalParams.self, forKey: .params)
                )
            case FileChangeRequestApprovalParams.method:
                self = .fileChangeRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(FileChangeRequestApprovalParams.self, forKey: .params)
                )
            case CommandExecutionRequestApprovalParams.method:
                self = .commandExecutionRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(CommandExecutionRequestApprovalParams.self, forKey: .params)
                )
            case ToolRequestUserInputParams.method:
                self = .toolRequestUserInput(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ToolRequestUserInputParams.self, forKey: .params)
                )
            case DynamicToolCallParams.method:
                self = .dynamicToolCall(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(DynamicToolCallParams.self, forKey: .params)
                )
            case PermissionsRequestApprovalParams.method:
                self = .permissionsRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(PermissionsRequestApprovalParams.self, forKey: .params)
                )
            case McpServerElicitationRequestParams.method:
                self = .mcpServerElicitationRequest(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(McpServerElicitationRequestParams.self, forKey: .params)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "unknown app-server request method: \(method)"
                )
            }
        }

        public func redactingExperimentalFields(experimentalAPIEnabled: Bool) -> ServerRequest {
            switch self {
            case let .commandExecutionRequestApproval(requestID, params):
                .commandExecutionRequestApproval(
                    requestID: requestID,
                    params: params.redactingExperimentalFields(experimentalAPIEnabled: experimentalAPIEnabled)
                )
            default:
                self
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(method, forKey: .method)
            try container.encode(id, forKey: .id)
            switch self {
            case let .attestationGenerate(_, params):
                try container.encode(params, forKey: .params)
            case let .chatGPTAuthTokensRefresh(_, params):
                try container.encode(params, forKey: .params)
            case let .execCommandApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .applyPatchApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .fileChangeRequestApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .commandExecutionRequestApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .toolRequestUserInput(_, params):
                try container.encode(params, forKey: .params)
            case let .dynamicToolCall(_, params):
                try container.encode(params, forKey: .params)
            case let .permissionsRequestApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .mcpServerElicitationRequest(_, params):
                try container.encode(params, forKey: .params)
            }
        }
    }

    public enum ServerRequestPayload: Equatable, Sendable {
        case attestationGenerate(Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(ChatGPTAuthTokensRefreshParams)
        case execCommandApproval(ExecCommandApprovalParams)
        case applyPatchApproval(ApplyPatchApprovalParams)
        case fileChangeRequestApproval(FileChangeRequestApprovalParams)
        case commandExecutionRequestApproval(CommandExecutionRequestApprovalParams)
        case toolRequestUserInput(ToolRequestUserInputParams)
        case dynamicToolCall(DynamicToolCallParams)
        case permissionsRequestApproval(PermissionsRequestApprovalParams)
        case mcpServerElicitationRequest(McpServerElicitationRequestParams)

        public static func attestationGenerate() -> ServerRequestPayload {
            .attestationGenerate(Attestation.GenerateParams())
        }

        public func request(withID id: RequestID) -> ServerRequest {
            switch self {
            case let .attestationGenerate(params):
                .attestationGenerate(requestID: id, params: params)
            case let .chatGPTAuthTokensRefresh(params):
                .chatGPTAuthTokensRefresh(requestID: id, params: params)
            case let .execCommandApproval(params):
                .execCommandApproval(requestID: id, params: params)
            case let .applyPatchApproval(params):
                .applyPatchApproval(requestID: id, params: params)
            case let .fileChangeRequestApproval(params):
                .fileChangeRequestApproval(requestID: id, params: params)
            case let .commandExecutionRequestApproval(params):
                .commandExecutionRequestApproval(requestID: id, params: params)
            case let .toolRequestUserInput(params):
                .toolRequestUserInput(requestID: id, params: params)
            case let .dynamicToolCall(params):
                .dynamicToolCall(requestID: id, params: params)
            case let .permissionsRequestApproval(params):
                .permissionsRequestApproval(requestID: id, params: params)
            case let .mcpServerElicitationRequest(params):
                .mcpServerElicitationRequest(requestID: id, params: params)
            }
        }
    }

    public enum ServerResponse: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, response: Attestation.GenerateResponse)
        case chatGPTAuthTokensRefresh(requestID: RequestID, response: ChatGPTAuthTokensRefreshResponse)
        case execCommandApproval(requestID: RequestID, response: ExecCommandApprovalResponse)
        case applyPatchApproval(requestID: RequestID, response: ApplyPatchApprovalResponse)
        case fileChangeRequestApproval(requestID: RequestID, response: FileChangeRequestApprovalResponse)
        case commandExecutionRequestApproval(
            requestID: RequestID,
            response: CommandExecutionRequestApprovalResponse
        )
        case toolRequestUserInput(requestID: RequestID, response: ToolRequestUserInputResponse)
        case dynamicToolCall(requestID: RequestID, response: DynamicToolCallResponse)
        case permissionsRequestApproval(requestID: RequestID, response: PermissionsRequestApprovalResponse)
        case mcpServerElicitationRequest(
            requestID: RequestID,
            response: McpServerElicitationRequestResponse
        )

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            case let .execCommandApproval(requestID, _):
                requestID
            case let .applyPatchApproval(requestID, _):
                requestID
            case let .fileChangeRequestApproval(requestID, _):
                requestID
            case let .commandExecutionRequestApproval(requestID, _):
                requestID
            case let .toolRequestUserInput(requestID, _):
                requestID
            case let .dynamicToolCall(requestID, _):
                requestID
            case let .permissionsRequestApproval(requestID, _):
                requestID
            case let .mcpServerElicitationRequest(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
            case .execCommandApproval:
                ExecCommandApprovalParams.method
            case .applyPatchApproval:
                ApplyPatchApprovalParams.method
            case .fileChangeRequestApproval:
                FileChangeRequestApprovalParams.method
            case .commandExecutionRequestApproval:
                CommandExecutionRequestApprovalParams.method
            case .toolRequestUserInput:
                ToolRequestUserInputParams.method
            case .dynamicToolCall:
                DynamicToolCallParams.method
            case .permissionsRequestApproval:
                PermissionsRequestApprovalParams.method
            case .mcpServerElicitationRequest:
                McpServerElicitationRequestParams.method
            }
        }

        private enum CodingKeys: String, CodingKey {
            case method
            case id
            case response
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            switch method {
            case Attestation.generateMethod:
                self = .attestationGenerate(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(Attestation.GenerateResponse.self, forKey: .response)
                )
            case ChatGPTAuthTokensRefreshParams.method:
                self = .chatGPTAuthTokensRefresh(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ChatGPTAuthTokensRefreshResponse.self, forKey: .response)
                )
            case ExecCommandApprovalParams.method:
                self = .execCommandApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ExecCommandApprovalResponse.self, forKey: .response)
                )
            case ApplyPatchApprovalParams.method:
                self = .applyPatchApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ApplyPatchApprovalResponse.self, forKey: .response)
                )
            case FileChangeRequestApprovalParams.method:
                self = .fileChangeRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(FileChangeRequestApprovalResponse.self, forKey: .response)
                )
            case CommandExecutionRequestApprovalParams.method:
                self = .commandExecutionRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(CommandExecutionRequestApprovalResponse.self, forKey: .response)
                )
            case ToolRequestUserInputParams.method:
                self = .toolRequestUserInput(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ToolRequestUserInputResponse.self, forKey: .response)
                )
            case DynamicToolCallParams.method:
                self = .dynamicToolCall(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(DynamicToolCallResponse.self, forKey: .response)
                )
            case PermissionsRequestApprovalParams.method:
                self = .permissionsRequestApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(PermissionsRequestApprovalResponse.self, forKey: .response)
                )
            case McpServerElicitationRequestParams.method:
                self = .mcpServerElicitationRequest(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(McpServerElicitationRequestResponse.self, forKey: .response)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "unknown app-server response method: \(method)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(method, forKey: .method)
            try container.encode(id, forKey: .id)
            switch self {
            case let .attestationGenerate(_, response):
                try container.encode(response, forKey: .response)
            case let .chatGPTAuthTokensRefresh(_, response):
                try container.encode(response, forKey: .response)
            case let .execCommandApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .applyPatchApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .fileChangeRequestApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .commandExecutionRequestApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .toolRequestUserInput(_, response):
                try container.encode(response, forKey: .response)
            case let .dynamicToolCall(_, response):
                try container.encode(response, forKey: .response)
            case let .permissionsRequestApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .mcpServerElicitationRequest(_, response):
                try container.encode(response, forKey: .response)
            }
        }
    }

    public enum McpServerElicitationAction: String, Codable, Equatable, Sendable {
        case accept
        case decline
        case cancel
    }

    public enum McpServerElicitationRequest: Equatable, Codable, Sendable {
        case form(meta: JSONValue?, message: String, requestedSchema: McpElicitationSchema)
        case url(meta: JSONValue?, message: String, url: String, elicitationID: String)

        private enum CodingKeys: String, CodingKey {
            case mode
            case meta = "_meta"
            case message
            case requestedSchema
            case url
            case elicitationID = "elicitationId"
        }

        private enum Mode: String, Codable {
            case form
            case url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Mode.self, forKey: .mode) {
            case .form:
                self = .form(
                    meta: try container.decodeIfPresent(JSONValue.self, forKey: .meta),
                    message: try container.decode(String.self, forKey: .message),
                    requestedSchema: try container.decode(McpElicitationSchema.self, forKey: .requestedSchema)
                )
            case .url:
                self = .url(
                    meta: try container.decodeIfPresent(JSONValue.self, forKey: .meta),
                    message: try container.decode(String.self, forKey: .message),
                    url: try container.decode(String.self, forKey: .url),
                    elicitationID: try container.decode(String.self, forKey: .elicitationID)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .form(meta, message, requestedSchema):
                try container.encode(Mode.form, forKey: .mode)
                try container.encodeNilOrValue(meta, forKey: .meta)
                try container.encode(message, forKey: .message)
                try container.encode(requestedSchema, forKey: .requestedSchema)
            case let .url(meta, message, url, elicitationID):
                try container.encode(Mode.url, forKey: .mode)
                try container.encodeNilOrValue(meta, forKey: .meta)
                try container.encode(message, forKey: .message)
                try container.encode(url, forKey: .url)
                try container.encode(elicitationID, forKey: .elicitationID)
            }
        }
    }

    public struct McpServerElicitationRequestParams: Equatable, Codable, Sendable {
        public static let method = "mcpServer/elicitation/request"

        public let threadID: String
        public let turnID: String?
        public let serverName: String
        public let request: McpServerElicitationRequest

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case serverName
            case mode
            case meta = "_meta"
            case message
            case requestedSchema
            case url
            case elicitationID = "elicitationId"
        }

        private enum Mode: String, Codable {
            case form
            case url
        }

        public init(
            threadID: String,
            turnID: String?,
            serverName: String,
            request: McpServerElicitationRequest
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.serverName = serverName
            self.request = request
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            threadID = try container.decode(String.self, forKey: .threadID)
            turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
            serverName = try container.decode(String.self, forKey: .serverName)
            switch try container.decode(Mode.self, forKey: .mode) {
            case .form:
                request = .form(
                    meta: try container.decodeIfPresent(JSONValue.self, forKey: .meta),
                    message: try container.decode(String.self, forKey: .message),
                    requestedSchema: try container.decode(McpElicitationSchema.self, forKey: .requestedSchema)
                )
            case .url:
                request = .url(
                    meta: try container.decodeIfPresent(JSONValue.self, forKey: .meta),
                    message: try container.decode(String.self, forKey: .message),
                    url: try container.decode(String.self, forKey: .url),
                    elicitationID: try container.decode(String.self, forKey: .elicitationID)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(threadID, forKey: .threadID)
            try container.encodeNilOrValue(turnID, forKey: .turnID)
            try container.encode(serverName, forKey: .serverName)
            switch request {
            case let .form(meta, message, requestedSchema):
                try container.encode(Mode.form, forKey: .mode)
                try container.encodeNilOrValue(meta, forKey: .meta)
                try container.encode(message, forKey: .message)
                try container.encode(requestedSchema, forKey: .requestedSchema)
            case let .url(meta, message, url, elicitationID):
                try container.encode(Mode.url, forKey: .mode)
                try container.encodeNilOrValue(meta, forKey: .meta)
                try container.encode(message, forKey: .message)
                try container.encode(url, forKey: .url)
                try container.encode(elicitationID, forKey: .elicitationID)
            }
        }
    }

    public struct McpServerElicitationRequestResponse: Equatable, Codable, Sendable {
        public let action: McpServerElicitationAction
        public let content: JSONValue?
        public let meta: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case action
            case content
            case meta = "_meta"
        }

        public init(action: McpServerElicitationAction, content: JSONValue?, meta: JSONValue?) {
            self.action = action
            self.content = content
            self.meta = meta
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            try container.encodeNilOrValue(content, forKey: .content)
            try container.encodeNilOrValue(meta, forKey: .meta)
        }
    }

    public struct McpElicitationSchema: Equatable, Codable, Sendable {
        public let schemaURI: String?
        public let properties: [String: McpElicitationPrimitiveSchema]
        public let required: [String]?

        private enum CodingKeys: String, CodingKey {
            case schemaURI = "$schema"
            case type
            case properties
            case required
        }

        public init(
            schemaURI: String? = nil,
            properties: [String: McpElicitationPrimitiveSchema],
            required: [String]? = nil
        ) {
            self.schemaURI = schemaURI
            self.properties = properties
            self.required = required
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            guard type == "object" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "unsupported MCP elicitation schema type: \(type)"
                )
            }
            schemaURI = try container.decodeIfPresent(String.self, forKey: .schemaURI)
            properties = try container.decode([String: McpElicitationPrimitiveSchema].self, forKey: .properties)
            required = try container.decodeIfPresent([String].self, forKey: .required)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(schemaURI, forKey: .schemaURI)
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
        }
    }

    public enum McpElicitationPrimitiveSchema: Equatable, Codable, Sendable {
        case enumSchema(McpElicitationEnumSchema)
        case string(McpElicitationStringSchema)
        case number(McpElicitationNumberSchema)
        case boolean(McpElicitationBooleanSchema)

        private enum CodingKeys: String, CodingKey {
            case type
            case `enum`
            case enumNames
            case oneOf
            case anyOf
            case items
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "string":
                if container.contains(.oneOf) {
                    self = .enumSchema(.singleSelect(.titled(try McpElicitationTitledSingleSelectEnumSchema(
                        from: decoder
                    ))))
                } else if container.contains(.enumNames) {
                    self = .enumSchema(.legacy(try McpElicitationLegacyTitledEnumSchema(from: decoder)))
                } else if container.contains(.enum) {
                    self = .enumSchema(.singleSelect(.untitled(try McpElicitationUntitledSingleSelectEnumSchema(
                        from: decoder
                    ))))
                } else {
                    self = .string(try McpElicitationStringSchema(from: decoder))
                }
            case "array":
                let items = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .items)
                if items.contains(.anyOf) || items.contains(.oneOf) {
                    self = .enumSchema(.multiSelect(.titled(try McpElicitationTitledMultiSelectEnumSchema(
                        from: decoder
                    ))))
                } else {
                    self = .enumSchema(.multiSelect(.untitled(try McpElicitationUntitledMultiSelectEnumSchema(
                        from: decoder
                    ))))
                }
            case "number", "integer":
                self = .number(try McpElicitationNumberSchema(from: decoder))
            case "boolean":
                self = .boolean(try McpElicitationBooleanSchema(from: decoder))
            case let type:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "unsupported MCP elicitation primitive schema type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case let .enumSchema(schema):
                try schema.encode(to: encoder)
            case let .string(schema):
                try schema.encode(to: encoder)
            case let .number(schema):
                try schema.encode(to: encoder)
            case let .boolean(schema):
                try schema.encode(to: encoder)
            }
        }
    }

    public enum McpElicitationEnumSchema: Equatable, Codable, Sendable {
        case singleSelect(McpElicitationSingleSelectEnumSchema)
        case multiSelect(McpElicitationMultiSelectEnumSchema)
        case legacy(McpElicitationLegacyTitledEnumSchema)

        public init(from decoder: Decoder) throws {
            if let schema = try? McpElicitationLegacyTitledEnumSchema(from: decoder) {
                self = .legacy(schema)
            } else if let schema = try? McpElicitationSingleSelectEnumSchema(from: decoder) {
                self = .singleSelect(schema)
            } else {
                self = .multiSelect(try McpElicitationMultiSelectEnumSchema(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case let .singleSelect(schema):
                try schema.encode(to: encoder)
            case let .multiSelect(schema):
                try schema.encode(to: encoder)
            case let .legacy(schema):
                try schema.encode(to: encoder)
            }
        }
    }

    public enum McpElicitationSingleSelectEnumSchema: Equatable, Codable, Sendable {
        case untitled(McpElicitationUntitledSingleSelectEnumSchema)
        case titled(McpElicitationTitledSingleSelectEnumSchema)

        private enum CodingKeys: String, CodingKey {
            case oneOf
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.oneOf) {
                self = .titled(try McpElicitationTitledSingleSelectEnumSchema(from: decoder))
            } else {
                self = .untitled(try McpElicitationUntitledSingleSelectEnumSchema(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case let .untitled(schema):
                try schema.encode(to: encoder)
            case let .titled(schema):
                try schema.encode(to: encoder)
            }
        }
    }

    public enum McpElicitationMultiSelectEnumSchema: Equatable, Codable, Sendable {
        case untitled(McpElicitationUntitledMultiSelectEnumSchema)
        case titled(McpElicitationTitledMultiSelectEnumSchema)

        private enum CodingKeys: String, CodingKey {
            case items
            case anyOf
            case oneOf
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let items = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .items)
            if items.contains(.anyOf) || items.contains(.oneOf) {
                self = .titled(try McpElicitationTitledMultiSelectEnumSchema(from: decoder))
            } else {
                self = .untitled(try McpElicitationUntitledMultiSelectEnumSchema(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case let .untitled(schema):
                try schema.encode(to: encoder)
            case let .titled(schema):
                try schema.encode(to: encoder)
            }
        }
    }

    public enum McpElicitationStringFormat: String, Codable, Equatable, Sendable {
        case email
        case uri
        case date
        case dateTime = "date-time"
    }

    public enum McpElicitationNumberType: String, Codable, Equatable, Sendable {
        case number
        case integer
    }

    public struct McpElicitationStringSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let minLength: UInt32?
        public let maxLength: UInt32?
        public let format: McpElicitationStringFormat?
        public let defaultValue: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case minLength
            case maxLength
            case format
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            minLength: UInt32? = nil,
            maxLength: UInt32? = nil,
            format: McpElicitationStringFormat? = nil,
            defaultValue: String? = nil
        ) {
            self.title = title
            self.description = description
            self.minLength = minLength
            self.maxLength = maxLength
            self.format = format
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            minLength = try container.decodeIfPresent(UInt32.self, forKey: .minLength)
            maxLength = try container.decodeIfPresent(UInt32.self, forKey: .maxLength)
            format = try container.decodeIfPresent(McpElicitationStringFormat.self, forKey: .format)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(minLength, forKey: .minLength)
            try container.encodeIfPresent(maxLength, forKey: .maxLength)
            try container.encodeIfPresent(format, forKey: .format)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationNumberSchema: Equatable, Codable, Sendable {
        public let type: McpElicitationNumberType
        public let title: String?
        public let description: String?
        public let minimum: Double?
        public let maximum: Double?
        public let defaultValue: Double?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case minimum
            case maximum
            case defaultValue = "default"
        }

        public init(
            type: McpElicitationNumberType,
            title: String? = nil,
            description: String? = nil,
            minimum: Double? = nil,
            maximum: Double? = nil,
            defaultValue: Double? = nil
        ) {
            self.type = type
            self.title = title
            self.description = description
            self.minimum = minimum
            self.maximum = maximum
            self.defaultValue = defaultValue
        }
    }

    public struct McpElicitationBooleanSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let defaultValue: Bool?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case defaultValue = "default"
        }

        public init(title: String? = nil, description: String? = nil, defaultValue: Bool? = nil) {
            self.title = title
            self.description = description
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            defaultValue = try container.decodeIfPresent(Bool.self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationUntitledSingleSelectEnumSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let values: [String]
        public let defaultValue: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case values = "enum"
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            values: [String],
            defaultValue: String? = nil
        ) {
            self.title = title
            self.description = description
            self.values = values
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            values = try container.decode([String].self, forKey: .values)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(values, forKey: .values)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationTitledSingleSelectEnumSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let oneOf: [McpElicitationConstOption]
        public let defaultValue: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case oneOf
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            oneOf: [McpElicitationConstOption],
            defaultValue: String? = nil
        ) {
            self.title = title
            self.description = description
            self.oneOf = oneOf
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            oneOf = try container.decode([McpElicitationConstOption].self, forKey: .oneOf)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(oneOf, forKey: .oneOf)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationLegacyTitledEnumSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let values: [String]
        public let enumNames: [String]?
        public let defaultValue: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case values = "enum"
            case enumNames
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            values: [String],
            enumNames: [String]? = nil,
            defaultValue: String? = nil
        ) {
            self.title = title
            self.description = description
            self.values = values
            self.enumNames = enumNames
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            values = try container.decode([String].self, forKey: .values)
            enumNames = try container.decodeIfPresent([String].self, forKey: .enumNames)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(values, forKey: .values)
            try container.encodeIfPresent(enumNames, forKey: .enumNames)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationUntitledMultiSelectEnumSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let minItems: UInt64?
        public let maxItems: UInt64?
        public let items: McpElicitationUntitledEnumItems
        public let defaultValue: [String]?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case minItems
            case maxItems
            case items
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            minItems: UInt64? = nil,
            maxItems: UInt64? = nil,
            items: McpElicitationUntitledEnumItems,
            defaultValue: [String]? = nil
        ) {
            self.title = title
            self.description = description
            self.minItems = minItems
            self.maxItems = maxItems
            self.items = items
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            minItems = try container.decodeIfPresent(UInt64.self, forKey: .minItems)
            maxItems = try container.decodeIfPresent(UInt64.self, forKey: .maxItems)
            items = try container.decode(McpElicitationUntitledEnumItems.self, forKey: .items)
            defaultValue = try container.decodeIfPresent([String].self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("array", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(minItems, forKey: .minItems)
            try container.encodeIfPresent(maxItems, forKey: .maxItems)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationTitledMultiSelectEnumSchema: Equatable, Codable, Sendable {
        public let title: String?
        public let description: String?
        public let minItems: UInt64?
        public let maxItems: UInt64?
        public let items: McpElicitationTitledEnumItems
        public let defaultValue: [String]?

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case description
            case minItems
            case maxItems
            case items
            case defaultValue = "default"
        }

        public init(
            title: String? = nil,
            description: String? = nil,
            minItems: UInt64? = nil,
            maxItems: UInt64? = nil,
            items: McpElicitationTitledEnumItems,
            defaultValue: [String]? = nil
        ) {
            self.title = title
            self.description = description
            self.minItems = minItems
            self.maxItems = maxItems
            self.items = items
            self.defaultValue = defaultValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            minItems = try container.decodeIfPresent(UInt64.self, forKey: .minItems)
            maxItems = try container.decodeIfPresent(UInt64.self, forKey: .maxItems)
            items = try container.decode(McpElicitationTitledEnumItems.self, forKey: .items)
            defaultValue = try container.decodeIfPresent([String].self, forKey: .defaultValue)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("array", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(minItems, forKey: .minItems)
            try container.encodeIfPresent(maxItems, forKey: .maxItems)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        }
    }

    public struct McpElicitationUntitledEnumItems: Equatable, Codable, Sendable {
        public let values: [String]

        private enum CodingKeys: String, CodingKey {
            case type
            case values = "enum"
        }

        public init(values: [String]) {
            self.values = values
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = try container.decode([String].self, forKey: .values)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("string", forKey: .type)
            try container.encode(values, forKey: .values)
        }
    }

    public struct McpElicitationTitledEnumItems: Equatable, Codable, Sendable {
        public let anyOf: [McpElicitationConstOption]

        private enum CodingKeys: String, CodingKey {
            case anyOf
            case oneOf
        }

        public init(anyOf: [McpElicitationConstOption]) {
            self.anyOf = anyOf
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let anyOf = try container.decodeIfPresent([McpElicitationConstOption].self, forKey: .anyOf) {
                self.anyOf = anyOf
            } else {
                anyOf = try container.decode([McpElicitationConstOption].self, forKey: .oneOf)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(anyOf, forKey: .anyOf)
        }
    }

    public struct McpElicitationConstOption: Equatable, Codable, Sendable {
        public let constValue: String
        public let title: String

        private enum CodingKeys: String, CodingKey {
            case constValue = "const"
            case title
        }

        public init(constValue: String, title: String) {
            self.constValue = constValue
            self.title = title
        }
    }

    public struct PermissionsProfile: Equatable, Codable, Sendable {
        public let network: RequestPermissionNetworkPermissions?
        public let fileSystem: FileSystemPermissions?

        private enum CodingKeys: String, CodingKey {
            case network
            case fileSystem
        }

        public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
            self.network = network
            self.fileSystem = fileSystem
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(network, forKey: .network)
            try container.encodeNilOrValue(fileSystem, forKey: .fileSystem)
        }
    }

    public struct GrantedPermissionProfile: Equatable, Codable, Sendable {
        public let network: RequestPermissionNetworkPermissions?
        public let fileSystem: FileSystemPermissions?

        private enum CodingKeys: String, CodingKey {
            case network
            case fileSystem
        }

        public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
            self.network = network
            self.fileSystem = fileSystem
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(network, forKey: .network)
            try container.encodeIfPresent(fileSystem, forKey: .fileSystem)
        }
    }

    public struct PermissionsRequestApprovalParams: Equatable, Codable, Sendable {
        public static let method = "item/permissions/requestApproval"

        public let threadID: String
        public let turnID: String
        public let itemID: String
        public let startedAtMilliseconds: Int64
        public let cwd: String
        public let reason: String?
        public let permissions: PermissionsProfile

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case itemID = "itemId"
            case startedAtMilliseconds = "startedAtMs"
            case cwd
            case reason
            case permissions
        }

        public init(
            threadID: String,
            turnID: String,
            itemID: String,
            startedAtMilliseconds: Int64,
            cwd: String,
            reason: String?,
            permissions: PermissionsProfile
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.itemID = itemID
            self.startedAtMilliseconds = startedAtMilliseconds
            self.cwd = cwd
            self.reason = reason
            self.permissions = permissions
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(threadID, forKey: .threadID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(itemID, forKey: .itemID)
            try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encode(permissions, forKey: .permissions)
        }
    }

    public struct PermissionsRequestApprovalResponse: Equatable, Codable, Sendable {
        public let permissions: GrantedPermissionProfile
        public let scope: PermissionGrantScope
        public let strictAutoReview: Bool?

        private enum CodingKeys: String, CodingKey {
            case permissions
            case scope
            case strictAutoReview
        }

        public init(
            permissions: GrantedPermissionProfile,
            scope: PermissionGrantScope = .turn,
            strictAutoReview: Bool? = nil
        ) {
            self.permissions = permissions
            self.scope = scope
            self.strictAutoReview = strictAutoReview
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            permissions = try container.decode(GrantedPermissionProfile.self, forKey: .permissions)
            scope = try container.decodeIfPresent(PermissionGrantScope.self, forKey: .scope) ?? .turn
            strictAutoReview = try container.decodeIfPresent(Bool.self, forKey: .strictAutoReview)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(permissions, forKey: .permissions)
            try container.encode(scope, forKey: .scope)
            try container.encodeIfPresent(strictAutoReview, forKey: .strictAutoReview)
        }
    }

    public struct DynamicToolCallParams: Equatable, Codable, Sendable {
        public static let method = "item/tool/call"

        public let threadID: String
        public let turnID: String
        public let callID: String
        public let namespace: String?
        public let tool: String
        public let arguments: JSONValue

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case callID = "callId"
            case namespace
            case tool
            case arguments
        }

        public init(
            threadID: String,
            turnID: String,
            callID: String,
            namespace: String?,
            tool: String,
            arguments: JSONValue
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.callID = callID
            self.namespace = namespace
            self.tool = tool
            self.arguments = arguments
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(threadID, forKey: .threadID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(callID, forKey: .callID)
            try container.encodeNilOrValue(namespace, forKey: .namespace)
            try container.encode(tool, forKey: .tool)
            try container.encode(arguments, forKey: .arguments)
        }
    }

    public struct DynamicToolCallResponse: Equatable, Codable, Sendable {
        public let contentItems: [DynamicToolCallOutputContentItem]
        public let success: Bool

        public init(contentItems: [DynamicToolCallOutputContentItem], success: Bool) {
            self.contentItems = contentItems
            self.success = success
        }
    }

    public struct ToolRequestUserInputParams: Equatable, Codable, Sendable {
        public static let method = "item/tool/requestUserInput"

        public let threadID: String
        public let turnID: String
        public let itemID: String
        public let questions: [RequestUserInputQuestion]

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case itemID = "itemId"
            case questions
        }

        public init(
            threadID: String,
            turnID: String,
            itemID: String,
            questions: [RequestUserInputQuestion]
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.itemID = itemID
            self.questions = questions
        }
    }

    public struct ToolRequestUserInputResponse: Equatable, Codable, Sendable {
        public let answers: [String: RequestUserInputAnswer]

        public init(answers: [String: RequestUserInputAnswer]) {
            self.answers = answers
        }
    }

    public enum CommandExecutionApprovalDecision: Equatable, Codable, Sendable {
        case accept
        case acceptForSession
        case acceptWithExecpolicyAmendment(execpolicyAmendment: ExecPolicyAmendment)
        case applyNetworkPolicyAmendment(networkPolicyAmendment: NetworkPolicyAmendment)
        case decline
        case cancel

        private enum UnitDecision: String, Codable {
            case accept
            case acceptForSession
            case decline
            case cancel
        }

        private enum CodingKeys: String, CodingKey {
            case acceptWithExecpolicyAmendment
            case applyNetworkPolicyAmendment
        }

        private enum AmendmentKeys: String, CodingKey {
            case execpolicyAmendment = "execpolicy_amendment"
            case networkPolicyAmendment = "network_policy_amendment"
        }

        public init(from decoder: Decoder) throws {
            if let unit = try? UnitDecision(from: decoder) {
                switch unit {
                case .accept:
                    self = .accept
                case .acceptForSession:
                    self = .acceptForSession
                case .decline:
                    self = .decline
                case .cancel:
                    self = .cancel
                }
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.acceptWithExecpolicyAmendment) {
                let nested = try container.nestedContainer(
                    keyedBy: AmendmentKeys.self,
                    forKey: .acceptWithExecpolicyAmendment
                )
                self = .acceptWithExecpolicyAmendment(
                    execpolicyAmendment: try nested.decode(ExecPolicyAmendment.self, forKey: .execpolicyAmendment)
                )
                return
            }

            if container.contains(.applyNetworkPolicyAmendment) {
                let nested = try container.nestedContainer(
                    keyedBy: AmendmentKeys.self,
                    forKey: .applyNetworkPolicyAmendment
                )
                self = .applyNetworkPolicyAmendment(
                    networkPolicyAmendment: try nested.decode(
                        NetworkPolicyAmendment.self,
                        forKey: .networkPolicyAmendment
                    )
                )
                return
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported command execution approval decision"
                )
            )
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .accept:
                try UnitDecision.accept.encode(to: encoder)
            case .acceptForSession:
                try UnitDecision.acceptForSession.encode(to: encoder)
            case let .acceptWithExecpolicyAmendment(amendment):
                var container = encoder.container(keyedBy: CodingKeys.self)
                var nested = container.nestedContainer(
                    keyedBy: AmendmentKeys.self,
                    forKey: .acceptWithExecpolicyAmendment
                )
                try nested.encode(amendment, forKey: .execpolicyAmendment)
            case let .applyNetworkPolicyAmendment(amendment):
                var container = encoder.container(keyedBy: CodingKeys.self)
                var nested = container.nestedContainer(
                    keyedBy: AmendmentKeys.self,
                    forKey: .applyNetworkPolicyAmendment
                )
                try nested.encode(amendment, forKey: .networkPolicyAmendment)
            case .decline:
                try UnitDecision.decline.encode(to: encoder)
            case .cancel:
                try UnitDecision.cancel.encode(to: encoder)
            }
        }
    }

    public enum CommandAction: Equatable, Codable, Sendable {
        case read(command: String, name: String, path: String)
        case listFiles(command: String, path: String?)
        case search(command: String, query: String?, path: String?)
        case unknown(command: String)

        private enum CodingKeys: String, CodingKey {
            case type
            case command
            case name
            case path
            case query
        }

        private enum CommandType: String, Codable {
            case read
            case listFiles
            case search
            case unknown
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(CommandType.self, forKey: .type) {
            case .read:
                self = .read(
                    command: try container.decode(String.self, forKey: .command),
                    name: try container.decode(String.self, forKey: .name),
                    path: try container.decode(String.self, forKey: .path)
                )
            case .listFiles:
                self = .listFiles(
                    command: try container.decode(String.self, forKey: .command),
                    path: try container.decodeIfPresent(String.self, forKey: .path)
                )
            case .search:
                self = .search(
                    command: try container.decode(String.self, forKey: .command),
                    query: try container.decodeIfPresent(String.self, forKey: .query),
                    path: try container.decodeIfPresent(String.self, forKey: .path)
                )
            case .unknown:
                self = .unknown(command: try container.decode(String.self, forKey: .command))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .read(command, name, path):
                try container.encode(CommandType.read, forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encode(name, forKey: .name)
                try container.encode(path, forKey: .path)
            case let .listFiles(command, path):
                try container.encode(CommandType.listFiles, forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encodeIfPresent(path, forKey: .path)
            case let .search(command, query, path):
                try container.encode(CommandType.search, forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encodeIfPresent(query, forKey: .query)
                try container.encodeIfPresent(path, forKey: .path)
            case let .unknown(command):
                try container.encode(CommandType.unknown, forKey: .type)
                try container.encode(command, forKey: .command)
            }
        }
    }

    public struct AdditionalPermissionProfile: Equatable, Codable, Sendable {
        public let network: RequestPermissionNetworkPermissions?
        public let fileSystem: FileSystemPermissions?

        private enum CodingKeys: String, CodingKey {
            case network
            case fileSystem
        }

        public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
            self.network = network
            self.fileSystem = fileSystem
        }
    }

    public struct CommandExecutionRequestApprovalParams: Equatable, Codable, Sendable {
        public static let method = "item/commandExecution/requestApproval"

        public let threadID: String
        public let turnID: String
        public let itemID: String
        public let startedAtMilliseconds: Int64
        public let approvalID: String?
        public let reason: String?
        public let networkApprovalContext: NetworkApprovalContext?
        public let command: String?
        public let cwd: String?
        public let commandActions: [CommandAction]?
        public let additionalPermissions: AdditionalPermissionProfile?
        public let proposedExecPolicyAmendment: ExecPolicyAmendment?
        public let proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]?
        public let availableDecisions: [CommandExecutionApprovalDecision]?

        public init(
            threadID: String,
            turnID: String,
            itemID: String,
            startedAtMilliseconds: Int64,
            approvalID: String? = nil,
            reason: String? = nil,
            networkApprovalContext: NetworkApprovalContext? = nil,
            command: String? = nil,
            cwd: String? = nil,
            commandActions: [CommandAction]? = nil,
            additionalPermissions: AdditionalPermissionProfile? = nil,
            proposedExecPolicyAmendment: ExecPolicyAmendment? = nil,
            proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]? = nil,
            availableDecisions: [CommandExecutionApprovalDecision]? = nil
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.itemID = itemID
            self.startedAtMilliseconds = startedAtMilliseconds
            self.approvalID = approvalID
            self.reason = reason
            self.networkApprovalContext = networkApprovalContext
            self.command = command
            self.cwd = cwd
            self.commandActions = commandActions
            self.additionalPermissions = additionalPermissions
            self.proposedExecPolicyAmendment = proposedExecPolicyAmendment
            self.proposedNetworkPolicyAmendments = proposedNetworkPolicyAmendments
            self.availableDecisions = availableDecisions
        }

        public func redactingExperimentalFields(experimentalAPIEnabled: Bool) -> Self {
            guard !experimentalAPIEnabled, additionalPermissions != nil else {
                return self
            }
            return Self(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                startedAtMilliseconds: startedAtMilliseconds,
                approvalID: approvalID,
                reason: reason,
                networkApprovalContext: networkApprovalContext,
                command: command,
                cwd: cwd,
                commandActions: commandActions,
                additionalPermissions: nil,
                proposedExecPolicyAmendment: proposedExecPolicyAmendment,
                proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
                availableDecisions: availableDecisions
            )
        }

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case itemID = "itemId"
            case startedAtMilliseconds = "startedAtMs"
            case approvalID = "approvalId"
            case reason
            case networkApprovalContext
            case command
            case cwd
            case commandActions
            case additionalPermissions
            case proposedExecPolicyAmendment = "proposedExecpolicyAmendment"
            case proposedNetworkPolicyAmendments
            case availableDecisions
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(threadID, forKey: .threadID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(itemID, forKey: .itemID)
            try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
            try container.encodeIfPresent(approvalID, forKey: .approvalID)
            try container.encodeIfPresent(reason, forKey: .reason)
            try container.encodeIfPresent(networkApprovalContext, forKey: .networkApprovalContext)
            try container.encodeIfPresent(command, forKey: .command)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encodeIfPresent(commandActions, forKey: .commandActions)
            try container.encodeIfPresent(additionalPermissions, forKey: .additionalPermissions)
            try container.encodeIfPresent(proposedExecPolicyAmendment, forKey: .proposedExecPolicyAmendment)
            try container.encodeIfPresent(proposedNetworkPolicyAmendments, forKey: .proposedNetworkPolicyAmendments)
            try container.encodeIfPresent(availableDecisions, forKey: .availableDecisions)
        }
    }

    public struct CommandExecutionRequestApprovalResponse: Equatable, Codable, Sendable {
        public let decision: CommandExecutionApprovalDecision

        public init(decision: CommandExecutionApprovalDecision) {
            self.decision = decision
        }
    }

    public enum FileChangeApprovalDecision: String, Codable, Equatable, Sendable {
        case accept
        case acceptForSession
        case decline
        case cancel
    }

    public struct FileChangeRequestApprovalParams: Equatable, Codable, Sendable {
        public static let method = "item/fileChange/requestApproval"

        public let threadID: String
        public let turnID: String
        public let itemID: String
        public let startedAtMilliseconds: Int64
        public let reason: String?
        public let grantRoot: String?

        public init(
            threadID: String,
            turnID: String,
            itemID: String,
            startedAtMilliseconds: Int64,
            reason: String?,
            grantRoot: String?
        ) {
            self.threadID = threadID
            self.turnID = turnID
            self.itemID = itemID
            self.startedAtMilliseconds = startedAtMilliseconds
            self.reason = reason
            self.grantRoot = grantRoot
        }

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case turnID = "turnId"
            case itemID = "itemId"
            case startedAtMilliseconds = "startedAtMs"
            case reason
            case grantRoot
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(threadID, forKey: .threadID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(itemID, forKey: .itemID)
            try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encodeNilOrValue(grantRoot, forKey: .grantRoot)
        }
    }

    public struct FileChangeRequestApprovalResponse: Equatable, Codable, Sendable {
        public let decision: FileChangeApprovalDecision

        public init(decision: FileChangeApprovalDecision) {
            self.decision = decision
        }
    }

    public struct ApplyPatchApprovalParams: Equatable, Codable, Sendable {
        public static let method = "applyPatchApproval"

        public let conversationID: String
        public let callID: String
        public let fileChanges: [String: FileChange]
        public let reason: String?
        public let grantRoot: String?

        public init(
            conversationID: String,
            callID: String,
            fileChanges: [String: FileChange],
            reason: String? = nil,
            grantRoot: String? = nil
        ) {
            self.conversationID = conversationID
            self.callID = callID
            self.fileChanges = fileChanges
            self.reason = reason
            self.grantRoot = grantRoot
        }

        private enum CodingKeys: String, CodingKey {
            case conversationID = "conversationId"
            case callID = "callId"
            case fileChanges
            case reason
            case grantRoot
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(callID, forKey: .callID)
            try container.encode(fileChanges, forKey: .fileChanges)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encodeNilOrValue(grantRoot, forKey: .grantRoot)
        }
    }

    public struct ApplyPatchApprovalResponse: Equatable, Codable, Sendable {
        public let decision: ReviewDecision

        public init(decision: ReviewDecision) {
            self.decision = decision
        }
    }

    public struct ExecCommandApprovalParams: Equatable, Codable, Sendable {
        public static let method = "execCommandApproval"

        public let conversationID: String
        public let callID: String
        public let approvalID: String?
        public let command: [String]
        public let cwd: String
        public let reason: String?
        public let parsedCmd: [ParsedCommand]

        public init(
            conversationID: String,
            callID: String,
            approvalID: String? = nil,
            command: [String],
            cwd: String,
            reason: String? = nil,
            parsedCmd: [ParsedCommand]
        ) {
            self.conversationID = conversationID
            self.callID = callID
            self.approvalID = approvalID
            self.command = command
            self.cwd = cwd
            self.reason = reason
            self.parsedCmd = parsedCmd
        }

        private enum CodingKeys: String, CodingKey {
            case conversationID = "conversationId"
            case callID = "callId"
            case approvalID = "approvalId"
            case command
            case cwd
            case reason
            case parsedCmd
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(callID, forKey: .callID)
            try container.encodeNilOrValue(approvalID, forKey: .approvalID)
            try container.encode(command, forKey: .command)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encode(parsedCmd, forKey: .parsedCmd)
        }
    }

    public struct ExecCommandApprovalResponse: Equatable, Codable, Sendable {
        public let decision: ReviewDecision

        public init(decision: ReviewDecision) {
            self.decision = decision
        }
    }

    public enum ChatGPTAuthTokensRefreshReason: String, Codable, Equatable, Sendable {
        case unauthorized
    }

    public struct ChatGPTAuthTokensRefreshParams: Equatable, Codable, Sendable {
        public static let method = "account/chatgptAuthTokens/refresh"

        public let reason: ChatGPTAuthTokensRefreshReason
        public let previousAccountID: String?

        public init(reason: ChatGPTAuthTokensRefreshReason, previousAccountID: String?) {
            self.reason = reason
            self.previousAccountID = previousAccountID
        }

        private enum CodingKeys: String, CodingKey {
            case reason
            case previousAccountID = "previousAccountId"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reason, forKey: .reason)
            try container.encodeNilOrValue(previousAccountID, forKey: .previousAccountID)
        }
    }

    public struct ChatGPTAuthTokensRefreshResponse: Equatable, Codable, Sendable {
        public let accessToken: String
        public let chatGPTAccountID: String
        public let chatGPTPlanType: String?

        public init(accessToken: String, chatGPTAccountID: String, chatGPTPlanType: String?) {
            self.accessToken = accessToken
            self.chatGPTAccountID = chatGPTAccountID
            self.chatGPTPlanType = chatGPTPlanType
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken
            case chatGPTAccountID = "chatgptAccountId"
            case chatGPTPlanType = "chatgptPlanType"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(accessToken, forKey: .accessToken)
            try container.encode(chatGPTAccountID, forKey: .chatGPTAccountID)
            try container.encodeNilOrValue(chatGPTPlanType, forKey: .chatGPTPlanType)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
