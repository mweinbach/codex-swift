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
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "unknown app-server request method: \(method)"
                )
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
            }
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
        public let fileSystem: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case network
            case fileSystem
        }

        public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: JSONValue? = nil) {
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
