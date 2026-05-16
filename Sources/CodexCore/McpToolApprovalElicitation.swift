import Foundation

public enum McpToolApprovalMetaKey {
    public static let approvalKind = "codex_approval_kind"
    public static let approvalKindMcpToolCall = "mcp_tool_call"
    public static let approvalKindToolSuggestion = "tool_suggestion"
    public static let requestType = "codex_request_type"
    public static let requestTypeApprovalRequest = "approval_request"
    public static let approvalsReviewer = "approvals_reviewer"
    public static let persist = "persist"
    public static let persistSession = "session"
    public static let persistAlways = "always"
    public static let source = "source"
    public static let sourceConnector = "connector"
    public static let connectorID = "connector_id"
    public static let connectorName = "connector_name"
    public static let connectorDescription = "connector_description"
    public static let toolName = "tool_name"
    public static let toolTitle = "tool_title"
    public static let toolDescription = "tool_description"
    public static let toolParams = "tool_params"
    public static let toolParamsDisplay = "tool_params_display"
}

public enum McpToolApprovalAnswer {
    public static let questionIDPrefix = "mcp_tool_call_approval"
    public static let accept = "Allow"
    public static let acceptForSession = "Allow for this session"
    public static let acceptAndRemember = "Allow and don't ask me again"
    public static let declineSynthetic = "__codex_mcp_decline__"
    public static let cancel = "Cancel"
}

public enum McpToolApprovalDecision: Equatable, Sendable {
    case accept
    case acceptForSession
    case acceptAndRemember
    case decline(message: String?)
    case cancel
    case blockedBySafetyMonitor(String)
}

public struct McpToolApprovalKey: Equatable, Codable, Sendable {
    public let server: String
    public let connectorID: String?
    public let toolName: String

    private enum CodingKeys: String, CodingKey {
        case server
        case connectorID = "connector_id"
        case toolName = "tool_name"
    }

    public init(server: String, connectorID: String?, toolName: String) {
        self.server = server
        self.connectorID = connectorID
        self.toolName = toolName
    }
}

public struct McpToolApprovalMetadata: Equatable, Sendable {
    public let connectorID: String?
    public let connectorName: String?
    public let connectorDescription: String?
    public let toolTitle: String?
    public let toolDescription: String?

    public init(
        connectorID: String? = nil,
        connectorName: String? = nil,
        connectorDescription: String? = nil,
        toolTitle: String? = nil,
        toolDescription: String? = nil
    ) {
        self.connectorID = connectorID
        self.connectorName = connectorName
        self.connectorDescription = connectorDescription
        self.toolTitle = toolTitle
        self.toolDescription = toolDescription
    }
}

public struct McpToolApprovalPromptOptions: Equatable, Sendable {
    public let allowSessionRemember: Bool
    public let allowPersistentApproval: Bool

    public init(allowSessionRemember: Bool, allowPersistentApproval: Bool) {
        self.allowSessionRemember = allowSessionRemember
        self.allowPersistentApproval = allowPersistentApproval
    }
}

public func isMcpToolApprovalQuestionID(_ questionID: String) -> Bool {
    let prefix = McpToolApprovalAnswer.questionIDPrefix
    guard questionID.hasPrefix(prefix) else {
        return false
    }
    let suffix = questionID.dropFirst(prefix.count)
    return suffix.first == "_"
}

public func mcpToolApprovalPromptOptions(
    sessionApprovalKey: McpToolApprovalKey?,
    persistentApprovalKey: McpToolApprovalKey?,
    toolCallMcpElicitationEnabled: Bool
) -> McpToolApprovalPromptOptions {
    McpToolApprovalPromptOptions(
        allowSessionRemember: sessionApprovalKey != nil,
        allowPersistentApproval: toolCallMcpElicitationEnabled && persistentApprovalKey != nil
    )
}

public func sessionMcpToolApprovalKey(
    invocation: McpInvocation,
    metadata: McpToolApprovalMetadata?,
    approvalMode: AppToolApproval
) -> McpToolApprovalKey? {
    guard approvalMode == .auto else {
        return nil
    }

    let connectorID = metadata?.connectorID
    if invocation.server == codexAppsMCPServerName && connectorID == nil {
        return nil
    }

    return McpToolApprovalKey(
        server: invocation.server,
        connectorID: connectorID,
        toolName: invocation.tool
    )
}

public func persistentMcpToolApprovalKey(
    invocation: McpInvocation,
    metadata: McpToolApprovalMetadata?,
    approvalMode: AppToolApproval
) -> McpToolApprovalKey? {
    sessionMcpToolApprovalKey(
        invocation: invocation,
        metadata: metadata,
        approvalMode: approvalMode
    )
}

public func buildMcpToolApprovalElicitationRequest(
    threadID: String,
    turnID: String?,
    serverName: String,
    metadata: McpToolApprovalMetadata?,
    toolParams: JSONValue?,
    toolParamsDisplay: [RenderedMcpToolApprovalParam]?,
    message: String,
    promptOptions: McpToolApprovalPromptOptions
) -> AppServerProtocol.McpServerElicitationRequestParams {
    AppServerProtocol.McpServerElicitationRequestParams(
        threadID: threadID,
        turnID: turnID,
        serverName: serverName,
        request: .form(
            meta: buildMcpToolApprovalElicitationMeta(
                serverName: serverName,
                metadata: metadata,
                toolParams: toolParams,
                toolParamsDisplay: toolParamsDisplay,
                promptOptions: promptOptions
            ),
            message: message,
            requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
        )
    )
}

public func buildMcpToolApprovalElicitationMeta(
    serverName: String,
    metadata: McpToolApprovalMetadata?,
    toolParams: JSONValue?,
    toolParamsDisplay: [RenderedMcpToolApprovalParam]?,
    promptOptions: McpToolApprovalPromptOptions
) -> JSONValue {
    var meta: [String: JSONValue] = [
        McpToolApprovalMetaKey.approvalKind: .string(McpToolApprovalMetaKey.approvalKindMcpToolCall),
    ]

    switch (promptOptions.allowSessionRemember, promptOptions.allowPersistentApproval) {
    case (true, true):
        meta[McpToolApprovalMetaKey.persist] = .array([
            .string(McpToolApprovalMetaKey.persistSession),
            .string(McpToolApprovalMetaKey.persistAlways),
        ])
    case (true, false):
        meta[McpToolApprovalMetaKey.persist] = .string(McpToolApprovalMetaKey.persistSession)
    case (false, true):
        meta[McpToolApprovalMetaKey.persist] = .string(McpToolApprovalMetaKey.persistAlways)
    case (false, false):
        break
    }

    if let metadata {
        if let toolTitle = metadata.toolTitle {
            meta[McpToolApprovalMetaKey.toolTitle] = .string(toolTitle)
        }
        if let toolDescription = metadata.toolDescription {
            meta[McpToolApprovalMetaKey.toolDescription] = .string(toolDescription)
        }
        let hasConnectorMetadata = metadata.connectorID != nil
            || metadata.connectorName != nil
            || metadata.connectorDescription != nil
        if serverName == codexAppsMCPServerName, hasConnectorMetadata {
            meta[McpToolApprovalMetaKey.source] = .string(McpToolApprovalMetaKey.sourceConnector)
            if let connectorID = metadata.connectorID {
                meta[McpToolApprovalMetaKey.connectorID] = .string(connectorID)
            }
            if let connectorName = metadata.connectorName {
                meta[McpToolApprovalMetaKey.connectorName] = .string(connectorName)
            }
            if let connectorDescription = metadata.connectorDescription {
                meta[McpToolApprovalMetaKey.connectorDescription] = .string(connectorDescription)
            }
        }
    }

    if let toolParams {
        meta[McpToolApprovalMetaKey.toolParams] = toolParams
    }
    if let toolParamsDisplay {
        meta[McpToolApprovalMetaKey.toolParamsDisplay] = .array(
            toolParamsDisplay.map { param in
                .object([
                    "name": .string(param.name),
                    "value": param.value,
                    "display_name": .string(param.displayName),
                ])
            }
        )
    }

    return .object(meta)
}

public func buildMcpToolApprovalQuestion(
    id questionID: String,
    serverName: String,
    toolName: String,
    connectorName: String?,
    promptOptions: McpToolApprovalPromptOptions,
    questionOverride: String? = nil
) -> RequestUserInputQuestion {
    let baseQuestion = questionOverride
        ?? buildMcpToolApprovalFallbackMessage(
            serverName: serverName,
            toolName: toolName,
            connectorName: connectorName
        )
    let question = "\(baseQuestion.trimmingTrailingQuestionMarks())?"

    var options = [
        RequestUserInputQuestionOption(
            label: McpToolApprovalAnswer.accept,
            description: "Run the tool and continue."
        ),
    ]
    if promptOptions.allowSessionRemember {
        options.append(RequestUserInputQuestionOption(
            label: McpToolApprovalAnswer.acceptForSession,
            description: "Run the tool and remember this choice for this session."
        ))
    }
    if promptOptions.allowPersistentApproval {
        options.append(RequestUserInputQuestionOption(
            label: McpToolApprovalAnswer.acceptAndRemember,
            description: "Run the tool and remember this choice for future tool calls."
        ))
    }
    options.append(RequestUserInputQuestionOption(
        label: McpToolApprovalAnswer.cancel,
        description: "Cancel this tool call."
    ))

    return RequestUserInputQuestion(
        id: questionID,
        header: "Approve app tool call?",
        question: question,
        isOther: false,
        isSecret: false,
        options: options
    )
}

public func buildMcpToolApprovalFallbackMessage(
    serverName: String,
    toolName: String,
    connectorName: String?
) -> String {
    let trimmedConnectorName = connectorName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let actor: String
    if let trimmedConnectorName, !trimmedConnectorName.isEmpty {
        actor = trimmedConnectorName
    } else if serverName == codexAppsMCPServerName {
        actor = "this app"
    } else {
        actor = "the \(serverName) MCP server"
    }
    return "Allow \(actor) to run tool \"\(toolName)\"?"
}

public func mcpToolApprovalQuestionText(
    question: String,
    monitorReason: String?
) -> String {
    if let reason = monitorReason?.trimmingCharacters(in: .whitespacesAndNewlines),
       !reason.isEmpty
    {
        return "Tool call needs your approval. Reason: \(reason)"
    }
    return question
}

public func parseMcpToolApprovalElicitationResponse(
    _ response: AppServerProtocol.McpServerElicitationRequestResponse?,
    questionID: String
) -> McpToolApprovalDecision {
    guard let response else {
        return .cancel
    }

    switch response.action {
    case .accept:
        if case let .object(meta)? = response.meta,
           case .string(McpToolApprovalMetaKey.persistSession)? = meta[McpToolApprovalMetaKey.persist]
        {
            return .acceptForSession
        }
        if case let .object(meta)? = response.meta,
           case .string(McpToolApprovalMetaKey.persistAlways)? = meta[McpToolApprovalMetaKey.persist]
        {
            return .acceptAndRemember
        }

        let decision = parseMcpToolApprovalResponse(
            requestUserInputResponseFromMcpElicitationContent(response.content),
            questionID: questionID
        )
        if decision == .cancel {
            return .accept
        }
        return decision
    case .decline:
        return .decline(message: nil)
    case .cancel:
        return .cancel
    }
}

public func parseMcpToolApprovalResponse(
    _ response: RequestUserInputResponse?,
    questionID: String
) -> McpToolApprovalDecision {
    guard let answers = response?.answers[questionID]?.answers else {
        return .cancel
    }

    if answers.contains(McpToolApprovalAnswer.declineSynthetic) {
        return .decline(message: nil)
    }
    if answers.contains(McpToolApprovalAnswer.acceptForSession) {
        return .acceptForSession
    }
    if answers.contains(McpToolApprovalAnswer.acceptAndRemember) {
        return .acceptAndRemember
    }
    if answers.contains(McpToolApprovalAnswer.accept) {
        return .accept
    }
    return .cancel
}

public func requestUserInputResponseFromMcpElicitationContent(
    _ content: JSONValue?
) -> RequestUserInputResponse? {
    guard let content else {
        return RequestUserInputResponse(answers: [:])
    }
    guard case let .object(contentObject) = content else {
        return nil
    }

    var answers: [String: RequestUserInputAnswer] = [:]
    for (questionID, value) in contentObject {
        switch value {
        case let .string(answer):
            answers[questionID] = RequestUserInputAnswer(answers: [answer])
        case let .array(values):
            answers[questionID] = RequestUserInputAnswer(
                answers: values.compactMap { value in
                    if case let .string(answer) = value {
                        return answer
                    }
                    return nil
                }
            )
        default:
            continue
        }
    }
    return RequestUserInputResponse(answers: answers)
}

public func normalizeMcpToolApprovalDecision(
    _ decision: McpToolApprovalDecision,
    for approvalMode: AppToolApproval
) -> McpToolApprovalDecision {
    if approvalMode == .prompt {
        switch decision {
        case .acceptForSession, .acceptAndRemember:
            return .accept
        case .accept, .decline, .cancel, .blockedBySafetyMonitor:
            return decision
        }
    }
    return decision
}

private extension String {
    func trimmingTrailingQuestionMarks() -> String {
        var result = self
        while result.last == "?" {
            result.removeLast()
        }
        return result
    }
}
