import Foundation

public struct Submission: Equatable, Codable, Sendable {
    public let id: String
    public let op: Op
    public let trace: W3CTraceContext?

    public init(id: String, op: Op, trace: W3CTraceContext? = nil) {
        self.id = id
        self.op = op
        self.trace = trace
    }
}

public struct W3CTraceContext: Equatable, Codable, Sendable {
    public let traceparent: String?
    public let tracestate: String?

    public init(traceparent: String? = nil, tracestate: String? = nil) {
        self.traceparent = traceparent
        self.tracestate = tracestate
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> W3CTraceContext? {
        guard let traceparent = environment["TRACEPARENT"],
              isValidTraceparent(traceparent)
        else {
            return nil
        }
        return W3CTraceContext(traceparent: traceparent, tracestate: environment["TRACESTATE"])
    }

    private static func isValidTraceparent(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0].count == 2,
              parts[1].count == 32,
              parts[2].count == 16,
              parts[3].count == 2,
              parts.allSatisfy(isLowercaseHex),
              parts[0] != "ff",
              parts[1].contains(where: { $0 != "0" }),
              parts[2].contains(where: { $0 != "0" })
        else {
            return false
        }
        return true
    }

    private static func isLowercaseHex(_ value: Substring) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            (UnicodeScalar("0")..."9").contains(scalar) || (UnicodeScalar("a")..."f").contains(scalar)
        }
    }
}

public enum ResponsesClientMetadata {
    public static let wsRequestHeaderTraceparentKey = "ws_request_header_traceparent"
    public static let wsRequestHeaderTracestateKey = "ws_request_header_tracestate"

    public static func create(
        clientMetadata: [String: String]? = nil,
        trace: W3CTraceContext? = nil
    ) -> [String: String]? {
        var metadata = clientMetadata ?? [:]
        if let traceparent = trace?.traceparent {
            metadata[wsRequestHeaderTraceparentKey] = traceparent
        }
        if let tracestate = trace?.tracestate {
            metadata[wsRequestHeaderTracestateKey] = tracestate
        }
        return metadata.isEmpty ? nil : metadata
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
    case userInputWithTurnContext(UserInputWithTurnContextParams)
    case userTurn(
        items: [UserInput],
        cwd: String,
        approvalPolicy: AskForApproval,
        approvalsReviewer: JSONValue? = nil,
        sandboxPolicy: SandboxPolicy,
        permissionProfile: PermissionProfile? = nil,
        model: String,
        effort: ReasoningEffort?,
        summary: ReasoningSummary?,
        serviceTier: JSONValue? = nil,
        finalOutputJSONSchema: JSONValue?,
        collaborationMode: JSONValue? = nil,
        personality: JSONValue? = nil,
        environments: [TurnEnvironmentSelection]? = nil
    )
    case interAgentCommunication(communication: InterAgentCommunication)
    case overrideTurnContext(
        cwd: String?,
        approvalPolicy: AskForApproval?,
        approvalsReviewer: JSONValue? = nil,
        sandboxPolicy: SandboxPolicy?,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        windowsSandboxLevel: JSONValue? = nil,
        model: String?,
        effort: ReasoningEffortOverride?,
        summary: ReasoningSummary?,
        serviceTier: JSONValue? = nil,
        collaborationMode: JSONValue? = nil,
        personality: JSONValue? = nil
    )
    case execApproval(id: String, turnID: String? = nil, decision: ReviewDecision)
    case patchApproval(id: String, decision: ReviewDecision)
    case resolveElicitation(
        serverName: String,
        requestID: RequestID,
        decision: ElicitationAction,
        content: JSONValue? = nil,
        meta: JSONValue? = nil
    )
    case userInputAnswer(id: String, response: RequestUserInputResponse)
    case requestPermissionsResponse(id: String, response: RequestPermissionsResponse)
    case dynamicToolResponse(id: String, response: DynamicToolResponse)
    case refreshMcpServers(config: McpServerRefreshConfig)
    case addToHistory(text: String)
    case getHistoryEntryRequest(offset: Int, logID: UInt64)
    case listCustomPrompts
    case reloadUserConfig
    case refreshRuntimeConfig(config: ConfigValue)
    case compact
    case setThreadMemoryMode(mode: ThreadMemoryMode)
    case threadRollback(numTurns: UInt32)
    case undo
    case review(reviewRequest: ReviewRequest)
    case approveGuardianDeniedAction(event: GuardianAssessmentEvent)
    case shutdown
    case runUserShellCommand(command: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case items
        case cwd
        case approvalPolicy = "approval_policy"
        case approvalsReviewer = "approvals_reviewer"
        case sandboxPolicy = "sandbox_policy"
        case permissionProfile = "permission_profile"
        case activePermissionProfile = "active_permission_profile"
        case windowsSandboxLevel = "windows_sandbox_level"
        case model
        case effort
        case summary
        case serviceTier = "service_tier"
        case finalOutputJSONSchema = "final_output_json_schema"
        case collaborationMode = "collaboration_mode"
        case personality
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
        case turnID = "turn_id"
        case decision
        case serverName = "server_name"
        case requestID = "request_id"
        case content
        case meta
        case text
        case offset
        case logID = "log_id"
        case mode
        case numTurns = "num_turns"
        case reviewRequest = "review_request"
        case event
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
        case userInputWithTurnContext = "user_input_with_turn_context"
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
        case listCustomPrompts = "list_custom_prompts"
        case reloadUserConfig = "reload_user_config"
        case refreshRuntimeConfig = "refresh_runtime_config"
        case compact
        case setThreadMemoryMode = "set_thread_memory_mode"
        case threadRollback = "thread_rollback"
        case undo
        case review
        case approveGuardianDeniedAction = "approve_guardian_denied_action"
        case shutdown
        case runUserShellCommand = "run_user_shell_command"
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
        case .userInputWithTurnContext:
            self = .userInputWithTurnContext(try UserInputWithTurnContextParams(from: decoder))
        case .userTurn:
            self = .userTurn(
                items: try container.decode([UserInput].self, forKey: .items),
                cwd: try container.decode(String.self, forKey: .cwd),
                approvalPolicy: try container.decode(AskForApproval.self, forKey: .approvalPolicy),
                approvalsReviewer: try Self.decodeNullableJSON(from: container, forKey: .approvalsReviewer),
                sandboxPolicy: try container.decode(SandboxPolicy.self, forKey: .sandboxPolicy),
                permissionProfile: try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile),
                model: try container.decode(String.self, forKey: .model),
                effort: try container.decodeIfPresent(ReasoningEffort.self, forKey: .effort),
                summary: try container.decodeIfPresent(ReasoningSummary.self, forKey: .summary),
                serviceTier: try Self.decodeNullableJSON(from: container, forKey: .serviceTier),
                finalOutputJSONSchema: try container.decodeIfPresent(JSONValue.self, forKey: .finalOutputJSONSchema),
                collaborationMode: try Self.decodeNullableJSON(from: container, forKey: .collaborationMode),
                personality: try Self.decodeNullableJSON(from: container, forKey: .personality),
                environments: try container.decodeIfPresent([TurnEnvironmentSelection].self, forKey: .environments)
            )
        case .interAgentCommunication:
            self = .interAgentCommunication(
                communication: try container.decode(InterAgentCommunication.self, forKey: .communication)
            )
        case .overrideTurnContext:
            let activePermissionProfile = try container.decodeIfPresent(
                ActivePermissionProfile.self,
                forKey: .activePermissionProfile
            )
            self = .overrideTurnContext(
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
                approvalPolicy: try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy),
                approvalsReviewer: try Self.decodeNullableJSON(from: container, forKey: .approvalsReviewer),
                sandboxPolicy: try container.decodeIfPresent(SandboxPolicy.self, forKey: .sandboxPolicy),
                permissionProfile: try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile),
                activePermissionProfile: activePermissionProfile,
                windowsSandboxLevel: try Self.decodeNullableJSON(from: container, forKey: .windowsSandboxLevel),
                model: try container.decodeIfPresent(String.self, forKey: .model),
                effort: try Self.decodeEffortOverride(from: container),
                summary: try container.decodeIfPresent(ReasoningSummary.self, forKey: .summary),
                serviceTier: try Self.decodeNullableJSON(from: container, forKey: .serviceTier),
                collaborationMode: try Self.decodeNullableJSON(from: container, forKey: .collaborationMode),
                personality: try Self.decodeNullableJSON(from: container, forKey: .personality)
            )
        case .execApproval:
            self = .execApproval(
                id: try container.decode(String.self, forKey: .id),
                turnID: try container.decodeIfPresent(String.self, forKey: .turnID),
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
                decision: try container.decode(ElicitationAction.self, forKey: .decision),
                content: try Self.decodeNullableJSON(from: container, forKey: .content),
                meta: try Self.decodeNullableJSON(from: container, forKey: .meta)
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
        case .listCustomPrompts:
            self = .listCustomPrompts
        case .reloadUserConfig:
            self = .reloadUserConfig
        case .refreshRuntimeConfig:
            self = .refreshRuntimeConfig(config: try container.decode(ConfigValue.self, forKey: .config))
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
        case .approveGuardianDeniedAction:
            self = .approveGuardianDeniedAction(event: try container.decode(GuardianAssessmentEvent.self, forKey: .event))
        case .shutdown:
            self = .shutdown
        case .runUserShellCommand:
            self = .runUserShellCommand(command: try container.decode(String.self, forKey: .command))
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
        case let .userInputWithTurnContext(params):
            try container.encode(OperationType.userInputWithTurnContext, forKey: .type)
            try params.encode(to: encoder)
        case let .userTurn(
            items,
            cwd,
            approvalPolicy,
            approvalsReviewer,
            sandboxPolicy,
            permissionProfile,
            model,
            effort,
            summary,
            serviceTier,
            finalOutputJSONSchema,
            collaborationMode,
            personality,
            environments
        ):
            try container.encode(OperationType.userTurn, forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encode(cwd, forKey: .cwd)
            try container.encode(approvalPolicy, forKey: .approvalPolicy)
            try Self.encodeNullableJSON(approvalsReviewer, into: &container, forKey: .approvalsReviewer)
            try container.encode(sandboxPolicy, forKey: .sandboxPolicy)
            try container.encodeIfPresent(permissionProfile, forKey: .permissionProfile)
            try container.encode(model, forKey: .model)
            try container.encodeIfPresent(effort, forKey: .effort)
            try container.encodeIfPresent(summary, forKey: .summary)
            try Self.encodeNullableJSON(serviceTier, into: &container, forKey: .serviceTier)
            try container.encode(finalOutputJSONSchema, forKey: .finalOutputJSONSchema)
            try Self.encodeNullableJSON(collaborationMode, into: &container, forKey: .collaborationMode)
            try Self.encodeNullableJSON(personality, into: &container, forKey: .personality)
            try container.encodeIfPresent(environments, forKey: .environments)
        case let .interAgentCommunication(communication):
            try container.encode(OperationType.interAgentCommunication, forKey: .type)
            try container.encode(communication, forKey: .communication)
        case let .overrideTurnContext(
            cwd,
            approvalPolicy,
            approvalsReviewer,
            sandboxPolicy,
            permissionProfile,
            activePermissionProfile,
            windowsSandboxLevel,
            model,
            effort,
            summary,
            serviceTier,
            collaborationMode,
            personality
        ):
            try container.encode(OperationType.overrideTurnContext, forKey: .type)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encodeIfPresent(approvalPolicy, forKey: .approvalPolicy)
            try Self.encodeNullableJSON(approvalsReviewer, into: &container, forKey: .approvalsReviewer)
            try container.encodeIfPresent(sandboxPolicy, forKey: .sandboxPolicy)
            try container.encodeIfPresent(permissionProfile, forKey: .permissionProfile)
            try container.encodeIfPresent(activePermissionProfile, forKey: .activePermissionProfile)
            try Self.encodeNullableJSON(windowsSandboxLevel, into: &container, forKey: .windowsSandboxLevel)
            try container.encodeIfPresent(model, forKey: .model)
            try Self.encode(effortOverride: effort, into: &container)
            try container.encodeIfPresent(summary, forKey: .summary)
            try Self.encodeNullableJSON(serviceTier, into: &container, forKey: .serviceTier)
            try Self.encodeNullableJSON(collaborationMode, into: &container, forKey: .collaborationMode)
            try Self.encodeNullableJSON(personality, into: &container, forKey: .personality)
        case let .execApproval(id, turnID, decision):
            try container.encode(OperationType.execApproval, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(turnID, forKey: .turnID)
            try container.encode(decision, forKey: .decision)
        case let .patchApproval(id, decision):
            try container.encode(OperationType.patchApproval, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(decision, forKey: .decision)
        case let .resolveElicitation(serverName, requestID, decision, content, meta):
            try container.encode(OperationType.resolveElicitation, forKey: .type)
            try container.encode(serverName, forKey: .serverName)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(decision, forKey: .decision)
            try Self.encodeNullableJSON(content, into: &container, forKey: .content)
            try Self.encodeNullableJSON(meta, into: &container, forKey: .meta)
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
        case .listCustomPrompts:
            try container.encode(OperationType.listCustomPrompts, forKey: .type)
        case .reloadUserConfig:
            try container.encode(OperationType.reloadUserConfig, forKey: .type)
        case let .refreshRuntimeConfig(config):
            try container.encode(OperationType.refreshRuntimeConfig, forKey: .type)
            try container.encode(config, forKey: .config)
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
        case let .approveGuardianDeniedAction(event):
            try container.encode(OperationType.approveGuardianDeniedAction, forKey: .type)
            try container.encode(event, forKey: .event)
        case .shutdown:
            try container.encode(OperationType.shutdown, forKey: .type)
        case let .runUserShellCommand(command):
            try container.encode(OperationType.runUserShellCommand, forKey: .type)
            try container.encode(command, forKey: .command)
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

    private static func decodeNullableJSON(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> JSONValue? {
        guard container.contains(key) else {
            return nil
        }
        if try container.decodeNil(forKey: key) {
            return .null
        }
        return try container.decode(JSONValue.self, forKey: key)
    }

    private static func encodeNullableJSON(
        _ value: JSONValue?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        guard let value else {
            return
        }
        if value == .null {
            try container.encodeNil(forKey: key)
        } else {
            try container.encode(value, forKey: key)
        }
    }
}
