import Foundation

public enum AppServerRpcTransport: String, Codable, Equatable, Sendable {
    case stdio
    case websocket
    case inProcess = "in_process"
}

public struct CodexAppServerClientMetadata: Equatable, Codable, Sendable {
    public let productClientID: String
    public let clientName: String?
    public let clientVersion: String?
    public let rpcTransport: AppServerRpcTransport
    public let experimentalAPIEnabled: Bool?

    public init(
        productClientID: String,
        clientName: String? = nil,
        clientVersion: String? = nil,
        rpcTransport: AppServerRpcTransport,
        experimentalAPIEnabled: Bool? = nil
    ) {
        self.productClientID = productClientID
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.rpcTransport = rpcTransport
        self.experimentalAPIEnabled = experimentalAPIEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case productClientID = "product_client_id"
        case clientName = "client_name"
        case clientVersion = "client_version"
        case rpcTransport = "rpc_transport"
        case experimentalAPIEnabled = "experimental_api_enabled"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(productClientID, forKey: .productClientID)
        try container.encodeNilOrValue(clientName, forKey: .clientName)
        try container.encodeNilOrValue(clientVersion, forKey: .clientVersion)
        try container.encode(rpcTransport, forKey: .rpcTransport)
        try container.encodeNilOrValue(experimentalAPIEnabled, forKey: .experimentalAPIEnabled)
    }
}

public struct CodexRuntimeMetadata: Equatable, Codable, Sendable {
    public let codexRSVersion: String
    public let runtimeOS: String
    public let runtimeOSVersion: String
    public let runtimeArch: String

    public init(
        codexRSVersion: String,
        runtimeOS: String,
        runtimeOSVersion: String,
        runtimeArch: String
    ) {
        self.codexRSVersion = codexRSVersion
        self.runtimeOS = runtimeOS
        self.runtimeOSVersion = runtimeOSVersion
        self.runtimeArch = runtimeArch
    }

    private enum CodingKeys: String, CodingKey {
        case codexRSVersion = "codex_rs_version"
        case runtimeOS = "runtime_os"
        case runtimeOSVersion = "runtime_os_version"
        case runtimeArch = "runtime_arch"
    }
}

public enum ReviewSubjectKind: String, Codable, Equatable, Sendable {
    case commandExecution = "command_execution"
    case fileChange = "file_change"
    case mcpToolCall = "mcp_tool_call"
    case permissions
    case networkAccess = "network_access"
}

public enum ReviewAnalyticsReviewer: String, Codable, Equatable, Sendable {
    case guardian
    case user
}

public enum ReviewTrigger: String, Codable, Equatable, Sendable {
    case initial
    case sandboxDenial = "sandbox_denial"
    case networkPolicyDenial = "network_policy_denial"
    case execveIntercept = "execve_intercept"
}

public enum ReviewStatus: String, Codable, Equatable, Sendable {
    case approved
    case denied
    case aborted
    case timedOut = "timed_out"
}

public enum ReviewResolution: String, Codable, Equatable, Sendable {
    case none
    case sessionApproval = "session_approval"
    case execPolicyAmendment = "exec_policy_amendment"
    case networkPolicyAmendment = "network_policy_amendment"
}

public struct CodexReviewEventParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String?
    public let reviewID: String
    public let appServerClient: CodexAppServerClientMetadata
    public let runtime: CodexRuntimeMetadata
    public let threadSource: ThreadSource?
    public let subagentSource: String?
    public let parentThreadID: String?
    public let toolKind: ReviewSubjectKind
    public let toolName: String
    public let reviewer: ReviewAnalyticsReviewer
    public let trigger: ReviewTrigger
    public let status: ReviewStatus
    public let resolution: ReviewResolution
    public let startedAtMilliseconds: UInt64
    public let completedAtMilliseconds: UInt64
    public let durationMilliseconds: UInt64?

    public init(
        threadID: String,
        turnID: String,
        itemID: String? = nil,
        reviewID: String,
        appServerClient: CodexAppServerClientMetadata,
        runtime: CodexRuntimeMetadata,
        threadSource: ThreadSource? = nil,
        subagentSource: String? = nil,
        parentThreadID: String? = nil,
        toolKind: ReviewSubjectKind,
        toolName: String,
        reviewer: ReviewAnalyticsReviewer,
        trigger: ReviewTrigger,
        status: ReviewStatus,
        resolution: ReviewResolution,
        startedAtMilliseconds: UInt64,
        completedAtMilliseconds: UInt64,
        durationMilliseconds: UInt64? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reviewID = reviewID
        self.appServerClient = appServerClient
        self.runtime = runtime
        self.threadSource = threadSource
        self.subagentSource = subagentSource
        self.parentThreadID = parentThreadID
        self.toolKind = toolKind
        self.toolName = toolName
        self.reviewer = reviewer
        self.trigger = trigger
        self.status = status
        self.resolution = resolution
        self.startedAtMilliseconds = startedAtMilliseconds
        self.completedAtMilliseconds = completedAtMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case reviewID = "review_id"
        case appServerClient = "app_server_client"
        case runtime
        case threadSource = "thread_source"
        case subagentSource = "subagent_source"
        case parentThreadID = "parent_thread_id"
        case toolKind = "tool_kind"
        case toolName = "tool_name"
        case reviewer
        case trigger
        case status
        case resolution
        case startedAtMilliseconds = "started_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
        case durationMilliseconds = "duration_ms"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeNilOrValue(itemID, forKey: .itemID)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encode(appServerClient, forKey: .appServerClient)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeNilOrValue(threadSource, forKey: .threadSource)
        try container.encodeNilOrValue(subagentSource, forKey: .subagentSource)
        try container.encodeNilOrValue(parentThreadID, forKey: .parentThreadID)
        try container.encode(toolKind, forKey: .toolKind)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(reviewer, forKey: .reviewer)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(status, forKey: .status)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encodeNilOrValue(durationMilliseconds, forKey: .durationMilliseconds)
    }
}

public struct CodexReviewEventRequest: Equatable, Codable, Sendable {
    public let eventType: String
    public let eventParams: CodexReviewEventParams

    public init(eventType: String, eventParams: CodexReviewEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
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
