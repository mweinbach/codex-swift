import Foundation

public struct Submission: Equatable, Codable, Sendable {
    public let id: String
    public let op: Op

    public init(id: String, op: Op) {
        self.id = id
        self.op = op
    }
}

public enum ReasoningEffortOverride: Equatable, Sendable {
    case clear
    case set(ReasoningEffort)
}

public enum ThreadMemoryMode: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
}

public enum Op: Equatable, Sendable {
    case interrupt
    case cleanBackgroundTerminals
    case realtimeConversationStart(ConversationStartParams)
    case realtimeConversationAudio(ConversationAudioParams)
    case realtimeConversationText(ConversationTextParams)
    case realtimeConversationClose
    case realtimeConversationListVoices
    case userInput(
        items: [UserInput],
        environments: [TurnEnvironmentSelection]? = nil,
        finalOutputJSONSchema: JSONValue? = nil,
        responsesAPIClientMetadata: [String: String]? = nil
    )
    case userTurn(
        items: [UserInput],
        cwd: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        model: String,
        effort: ReasoningEffort?,
        summary: ReasoningSummary,
        finalOutputJSONSchema: JSONValue?
    )
    case interAgentCommunication(communication: InterAgentCommunication)
    case overrideTurnContext(
        cwd: String?,
        approvalPolicy: AskForApproval?,
        sandboxPolicy: SandboxPolicy?,
        model: String?,
        effort: ReasoningEffortOverride?,
        summary: ReasoningSummary?
    )
    case execApproval(id: String, decision: ReviewDecision)
    case patchApproval(id: String, decision: ReviewDecision)
    case resolveElicitation(serverName: String, requestID: RequestID, decision: ElicitationAction)
    case userInputAnswer(id: String, response: RequestUserInputResponse)
    case requestPermissionsResponse(id: String, response: RequestPermissionsResponse)
    case dynamicToolResponse(id: String, response: DynamicToolResponse)
    case refreshMcpServers(config: McpServerRefreshConfig)
    case addToHistory(text: String)
    case getHistoryEntryRequest(offset: Int, logID: UInt64)
    case listMcpTools
    case listCustomPrompts
    case listSkills(cwds: [String], forceReload: Bool)
    case reloadUserConfig
    case compact
    case setThreadMemoryMode(mode: ThreadMemoryMode)
    case threadRollback(numTurns: UInt32)
    case undo
    case review(reviewRequest: ReviewRequest)
    case shutdown
    case runUserShellCommand(command: String)
    case listModels

    private enum CodingKeys: String, CodingKey {
        case type
        case items
        case cwd
        case approvalPolicy = "approval_policy"
        case sandboxPolicy = "sandbox_policy"
        case model
        case effort
        case summary
        case finalOutputJSONSchema = "final_output_json_schema"
        case environments
        case responsesAPIClientMetadata = "responsesapi_client_metadata"
        case outputModality = "output_modality"
        case prompt
        case realtimeSessionID = "realtime_session_id"
        case transport
        case voice
        case frame
        case communication
        case id
        case decision
        case serverName = "server_name"
        case requestID = "request_id"
        case text
        case offset
        case logID = "log_id"
        case cwds
        case forceReload = "force_reload"
        case mode
        case numTurns = "num_turns"
        case reviewRequest = "review_request"
        case command
        case response
        case config
    }

    private enum OperationType: String, Codable {
        case interrupt
        case cleanBackgroundTerminals = "clean_background_terminals"
        case realtimeConversationStart = "realtime_conversation_start"
        case realtimeConversationAudio = "realtime_conversation_audio"
        case realtimeConversationText = "realtime_conversation_text"
        case realtimeConversationClose = "realtime_conversation_close"
        case realtimeConversationListVoices = "realtime_conversation_list_voices"
        case userInput = "user_input"
        case userTurn = "user_turn"
        case interAgentCommunication = "inter_agent_communication"
        case overrideTurnContext = "override_turn_context"
        case execApproval = "exec_approval"
        case patchApproval = "patch_approval"
        case resolveElicitation = "resolve_elicitation"
        case userInputAnswer = "user_input_answer"
        case requestUserInputResponse = "request_user_input_response"
        case requestPermissionsResponse = "request_permissions_response"
        case dynamicToolResponse = "dynamic_tool_response"
        case refreshMcpServers = "refresh_mcp_servers"
        case addToHistory = "add_to_history"
        case getHistoryEntryRequest = "get_history_entry_request"
        case listMcpTools = "list_mcp_tools"
        case listCustomPrompts = "list_custom_prompts"
        case listSkills = "list_skills"
        case reloadUserConfig = "reload_user_config"
        case compact
        case setThreadMemoryMode = "set_thread_memory_mode"
        case threadRollback = "thread_rollback"
        case undo
        case review
        case shutdown
        case runUserShellCommand = "run_user_shell_command"
        case listModels = "list_models"
    }
}

extension Op: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OperationType.self, forKey: .type) {
        case .interrupt:
            self = .interrupt
        case .cleanBackgroundTerminals:
            self = .cleanBackgroundTerminals
        case .realtimeConversationStart:
            self = .realtimeConversationStart(try ConversationStartParams(from: decoder))
        case .realtimeConversationAudio:
            self = .realtimeConversationAudio(try ConversationAudioParams(from: decoder))
        case .realtimeConversationText:
            self = .realtimeConversationText(try ConversationTextParams(from: decoder))
        case .realtimeConversationClose:
            self = .realtimeConversationClose
        case .realtimeConversationListVoices:
            self = .realtimeConversationListVoices
        case .userInput:
            self = .userInput(
                items: try container.decode([UserInput].self, forKey: .items),
                environments: try container.decodeIfPresent([TurnEnvironmentSelection].self, forKey: .environments),
                finalOutputJSONSchema: try container.decodeIfPresent(JSONValue.self, forKey: .finalOutputJSONSchema),
                responsesAPIClientMetadata: try container.decodeIfPresent(
                    [String: String].self,
                    forKey: .responsesAPIClientMetadata
                )
            )
        case .userTurn:
            self = .userTurn(
                items: try container.decode([UserInput].self, forKey: .items),
                cwd: try container.decode(String.self, forKey: .cwd),
                approvalPolicy: try container.decode(AskForApproval.self, forKey: .approvalPolicy),
                sandboxPolicy: try container.decode(SandboxPolicy.self, forKey: .sandboxPolicy),
                model: try container.decode(String.self, forKey: .model),
                effort: try container.decodeIfPresent(ReasoningEffort.self, forKey: .effort),
                summary: try container.decode(ReasoningSummary.self, forKey: .summary),
                finalOutputJSONSchema: try container.decodeIfPresent(JSONValue.self, forKey: .finalOutputJSONSchema)
            )
        case .interAgentCommunication:
            self = .interAgentCommunication(
                communication: try container.decode(InterAgentCommunication.self, forKey: .communication)
            )
        case .overrideTurnContext:
            self = .overrideTurnContext(
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
                approvalPolicy: try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy),
                sandboxPolicy: try container.decodeIfPresent(SandboxPolicy.self, forKey: .sandboxPolicy),
                model: try container.decodeIfPresent(String.self, forKey: .model),
                effort: try Self.decodeEffortOverride(from: container),
                summary: try container.decodeIfPresent(ReasoningSummary.self, forKey: .summary)
            )
        case .execApproval:
            self = .execApproval(
                id: try container.decode(String.self, forKey: .id),
                decision: try container.decode(ReviewDecision.self, forKey: .decision)
            )
        case .patchApproval:
            self = .patchApproval(
                id: try container.decode(String.self, forKey: .id),
                decision: try container.decode(ReviewDecision.self, forKey: .decision)
            )
        case .resolveElicitation:
            self = .resolveElicitation(
                serverName: try container.decode(String.self, forKey: .serverName),
                requestID: try container.decode(RequestID.self, forKey: .requestID),
                decision: try container.decode(ElicitationAction.self, forKey: .decision)
            )
        case .userInputAnswer, .requestUserInputResponse:
            self = .userInputAnswer(
                id: try container.decode(String.self, forKey: .id),
                response: try container.decode(RequestUserInputResponse.self, forKey: .response)
            )
        case .requestPermissionsResponse:
            self = .requestPermissionsResponse(
                id: try container.decode(String.self, forKey: .id),
                response: try container.decode(RequestPermissionsResponse.self, forKey: .response)
            )
        case .dynamicToolResponse:
            self = .dynamicToolResponse(
                id: try container.decode(String.self, forKey: .id),
                response: try container.decode(DynamicToolResponse.self, forKey: .response)
            )
        case .refreshMcpServers:
            self = .refreshMcpServers(config: try container.decode(McpServerRefreshConfig.self, forKey: .config))
        case .addToHistory:
            self = .addToHistory(text: try container.decode(String.self, forKey: .text))
        case .getHistoryEntryRequest:
            self = .getHistoryEntryRequest(
                offset: try container.decode(Int.self, forKey: .offset),
                logID: try container.decode(UInt64.self, forKey: .logID)
            )
        case .listMcpTools:
            self = .listMcpTools
        case .listCustomPrompts:
            self = .listCustomPrompts
        case .listSkills:
            self = .listSkills(
                cwds: try container.decodeIfPresent([String].self, forKey: .cwds) ?? [],
                forceReload: try container.decodeIfPresent(Bool.self, forKey: .forceReload) ?? false
            )
        case .reloadUserConfig:
            self = .reloadUserConfig
        case .compact:
            self = .compact
        case .setThreadMemoryMode:
            self = .setThreadMemoryMode(mode: try container.decode(ThreadMemoryMode.self, forKey: .mode))
        case .threadRollback:
            self = .threadRollback(numTurns: try container.decode(UInt32.self, forKey: .numTurns))
        case .undo:
            self = .undo
        case .review:
            self = .review(reviewRequest: try container.decode(ReviewRequest.self, forKey: .reviewRequest))
        case .shutdown:
            self = .shutdown
        case .runUserShellCommand:
            self = .runUserShellCommand(command: try container.decode(String.self, forKey: .command))
        case .listModels:
            self = .listModels
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .interrupt:
            try container.encode(OperationType.interrupt, forKey: .type)
        case .cleanBackgroundTerminals:
            try container.encode(OperationType.cleanBackgroundTerminals, forKey: .type)
        case let .realtimeConversationStart(params):
            try container.encode(OperationType.realtimeConversationStart, forKey: .type)
            try params.encode(to: encoder)
        case let .realtimeConversationAudio(params):
            try container.encode(OperationType.realtimeConversationAudio, forKey: .type)
            try params.encode(to: encoder)
        case let .realtimeConversationText(params):
            try container.encode(OperationType.realtimeConversationText, forKey: .type)
            try params.encode(to: encoder)
        case .realtimeConversationClose:
            try container.encode(OperationType.realtimeConversationClose, forKey: .type)
        case .realtimeConversationListVoices:
            try container.encode(OperationType.realtimeConversationListVoices, forKey: .type)
        case let .userInput(items, environments, finalOutputJSONSchema, responsesAPIClientMetadata):
            try container.encode(OperationType.userInput, forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(environments, forKey: .environments)
            try container.encodeIfPresent(finalOutputJSONSchema, forKey: .finalOutputJSONSchema)
            try container.encodeIfPresent(responsesAPIClientMetadata, forKey: .responsesAPIClientMetadata)
        case let .userTurn(items, cwd, approvalPolicy, sandboxPolicy, model, effort, summary, finalOutputJSONSchema):
            try container.encode(OperationType.userTurn, forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encode(cwd, forKey: .cwd)
            try container.encode(approvalPolicy, forKey: .approvalPolicy)
            try container.encode(sandboxPolicy, forKey: .sandboxPolicy)
            try container.encode(model, forKey: .model)
            try container.encodeIfPresent(effort, forKey: .effort)
            try container.encode(summary, forKey: .summary)
            try container.encode(finalOutputJSONSchema, forKey: .finalOutputJSONSchema)
        case let .interAgentCommunication(communication):
            try container.encode(OperationType.interAgentCommunication, forKey: .type)
            try container.encode(communication, forKey: .communication)
        case let .overrideTurnContext(cwd, approvalPolicy, sandboxPolicy, model, effort, summary):
            try container.encode(OperationType.overrideTurnContext, forKey: .type)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encodeIfPresent(approvalPolicy, forKey: .approvalPolicy)
            try container.encodeIfPresent(sandboxPolicy, forKey: .sandboxPolicy)
            try container.encodeIfPresent(model, forKey: .model)
            try Self.encode(effortOverride: effort, into: &container)
            try container.encodeIfPresent(summary, forKey: .summary)
        case let .execApproval(id, decision):
            try container.encode(OperationType.execApproval, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(decision, forKey: .decision)
        case let .patchApproval(id, decision):
            try container.encode(OperationType.patchApproval, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(decision, forKey: .decision)
        case let .resolveElicitation(serverName, requestID, decision):
            try container.encode(OperationType.resolveElicitation, forKey: .type)
            try container.encode(serverName, forKey: .serverName)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(decision, forKey: .decision)
        case let .userInputAnswer(id, response):
            try container.encode(OperationType.userInputAnswer, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(response, forKey: .response)
        case let .requestPermissionsResponse(id, response):
            try container.encode(OperationType.requestPermissionsResponse, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(response, forKey: .response)
        case let .dynamicToolResponse(id, response):
            try container.encode(OperationType.dynamicToolResponse, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(response, forKey: .response)
        case let .refreshMcpServers(config):
            try container.encode(OperationType.refreshMcpServers, forKey: .type)
            try container.encode(config, forKey: .config)
        case let .addToHistory(text):
            try container.encode(OperationType.addToHistory, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .getHistoryEntryRequest(offset, logID):
            try container.encode(OperationType.getHistoryEntryRequest, forKey: .type)
            try container.encode(offset, forKey: .offset)
            try container.encode(logID, forKey: .logID)
        case .listMcpTools:
            try container.encode(OperationType.listMcpTools, forKey: .type)
        case .listCustomPrompts:
            try container.encode(OperationType.listCustomPrompts, forKey: .type)
        case let .listSkills(cwds, forceReload):
            try container.encode(OperationType.listSkills, forKey: .type)
            if !cwds.isEmpty {
                try container.encode(cwds, forKey: .cwds)
            }
            if forceReload {
                try container.encode(forceReload, forKey: .forceReload)
            }
        case .reloadUserConfig:
            try container.encode(OperationType.reloadUserConfig, forKey: .type)
        case .compact:
            try container.encode(OperationType.compact, forKey: .type)
        case let .setThreadMemoryMode(mode):
            try container.encode(OperationType.setThreadMemoryMode, forKey: .type)
            try container.encode(mode, forKey: .mode)
        case let .threadRollback(numTurns):
            try container.encode(OperationType.threadRollback, forKey: .type)
            try container.encode(numTurns, forKey: .numTurns)
        case .undo:
            try container.encode(OperationType.undo, forKey: .type)
        case let .review(reviewRequest):
            try container.encode(OperationType.review, forKey: .type)
            try container.encode(reviewRequest, forKey: .reviewRequest)
        case .shutdown:
            try container.encode(OperationType.shutdown, forKey: .type)
        case let .runUserShellCommand(command):
            try container.encode(OperationType.runUserShellCommand, forKey: .type)
            try container.encode(command, forKey: .command)
        case .listModels:
            try container.encode(OperationType.listModels, forKey: .type)
        }
    }

    private static func decodeEffortOverride(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ReasoningEffortOverride? {
        guard container.contains(.effort) else {
            return nil
        }
        if try container.decodeNil(forKey: .effort) {
            return .clear
        }
        return .set(try container.decode(ReasoningEffort.self, forKey: .effort))
    }

    private static func encode(
        effortOverride: ReasoningEffortOverride?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let effortOverride else {
            return
        }
        switch effortOverride {
        case .clear:
            try container.encodeNil(forKey: .effort)
        case let .set(effort):
            try container.encode(effort, forKey: .effort)
        }
    }
}
