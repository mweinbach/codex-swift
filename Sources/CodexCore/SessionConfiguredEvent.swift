import Foundation

public struct SessionNetworkProxyRuntime: Equatable, Codable, Sendable {
    public let httpAddr: String
    public let socksAddr: String

    private enum CodingKeys: String, CodingKey {
        case httpAddr = "http_addr"
        case socksAddr = "socks_addr"
    }

    public init(httpAddr: String, socksAddr: String) {
        self.httpAddr = httpAddr
        self.socksAddr = socksAddr
    }
}

public struct SessionConfiguredEvent: Equatable, Codable, Sendable {
    public let sessionID: SessionId
    public let threadID: ThreadId
    public let forkedFromID: ThreadId?
    public let threadSource: ThreadSource?
    public let threadName: String?
    public let model: String
    public let modelProviderID: String
    public let serviceTier: String?
    public let approvalPolicy: AskForApproval
    public let approvalsReviewer: ApprovalsReviewer
    public let permissionProfile: PermissionProfile
    public let activePermissionProfile: ActivePermissionProfile?
    public let sandboxPolicy: SandboxPolicy
    public let cwd: String
    public let reasoningEffort: ReasoningEffort?
    public let historyLogID: UInt64
    public let historyEntryCount: Int
    public let initialMessages: [EventMessage]?
    public let networkProxy: SessionNetworkProxyRuntime?
    public let rolloutPath: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case threadID = "thread_id"
        case forkedFromID = "forked_from_id"
        case threadSource = "thread_source"
        case threadName = "thread_name"
        case model
        case modelProviderID = "model_provider_id"
        case serviceTier = "service_tier"
        case approvalPolicy = "approval_policy"
        case approvalsReviewer = "approvals_reviewer"
        case permissionProfile = "permission_profile"
        case activePermissionProfile = "active_permission_profile"
        case sandboxPolicy = "sandbox_policy"
        case cwd
        case reasoningEffort = "reasoning_effort"
        case initialMessages = "initial_messages"
        case networkProxy = "network_proxy"
        case rolloutPath = "rollout_path"
    }

    public init(
        sessionID: ConversationId,
        threadID: ThreadId? = nil,
        forkedFromID: ThreadId? = nil,
        threadSource: ThreadSource? = nil,
        threadName: String? = nil,
        model: String,
        modelProviderID: String,
        serviceTier: String? = nil,
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer = .user,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        sandboxPolicy: SandboxPolicy,
        cwd: String,
        reasoningEffort: ReasoningEffort? = nil,
        historyLogID: UInt64,
        historyEntryCount: Int,
        initialMessages: [EventMessage]? = nil,
        networkProxy: SessionNetworkProxyRuntime? = nil,
        rolloutPath: String?
    ) {
        self.init(
            sessionID: SessionId(uuid: sessionID.uuid),
            threadID: threadID,
            forkedFromID: forkedFromID,
            threadSource: threadSource,
            threadName: threadName,
            model: model,
            modelProviderID: modelProviderID,
            serviceTier: serviceTier,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: approvalsReviewer,
            permissionProfile: permissionProfile,
            activePermissionProfile: activePermissionProfile,
            sandboxPolicy: sandboxPolicy,
            cwd: cwd,
            reasoningEffort: reasoningEffort,
            historyLogID: historyLogID,
            historyEntryCount: historyEntryCount,
            initialMessages: initialMessages,
            networkProxy: networkProxy,
            rolloutPath: rolloutPath
        )
    }

    public init(
        sessionID: SessionId,
        threadID: ThreadId? = nil,
        forkedFromID: ThreadId? = nil,
        threadSource: ThreadSource? = nil,
        threadName: String? = nil,
        model: String,
        modelProviderID: String,
        serviceTier: String? = nil,
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer = .user,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        sandboxPolicy: SandboxPolicy,
        cwd: String,
        reasoningEffort: ReasoningEffort? = nil,
        historyLogID: UInt64,
        historyEntryCount: Int,
        initialMessages: [EventMessage]? = nil,
        networkProxy: SessionNetworkProxyRuntime? = nil,
        rolloutPath: String?
    ) {
        self.sessionID = sessionID
        self.threadID = threadID ?? ThreadId(sessionID: sessionID)
        self.forkedFromID = forkedFromID
        self.threadSource = threadSource
        self.threadName = threadName
        self.model = model
        self.modelProviderID = modelProviderID
        self.serviceTier = serviceTier
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.permissionProfile = permissionProfile ?? PermissionProfile.fromLegacySandboxPolicy(sandboxPolicy)
        self.activePermissionProfile = activePermissionProfile
        self.sandboxPolicy = sandboxPolicy
        self.cwd = cwd
        self.reasoningEffort = reasoningEffort
        self.historyLogID = historyLogID
        self.historyEntryCount = historyEntryCount
        self.initialMessages = initialMessages
        self.networkProxy = networkProxy
        self.rolloutPath = rolloutPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(SessionId.self, forKey: .sessionID)
        threadID = try container.decodeIfPresent(ThreadId.self, forKey: .threadID) ?? ThreadId(sessionID: sessionID)
        forkedFromID = try container.decodeIfPresent(ThreadId.self, forKey: .forkedFromID)
        threadSource = try container.decodeIfPresent(ThreadSource.self, forKey: .threadSource)
        threadName = try container.decodeIfPresent(String.self, forKey: .threadName)
        model = try container.decode(String.self, forKey: .model)
        modelProviderID = try container.decode(String.self, forKey: .modelProviderID)
        serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        approvalPolicy = try container.decode(AskForApproval.self, forKey: .approvalPolicy)
        approvalsReviewer = try container.decodeIfPresent(ApprovalsReviewer.self, forKey: .approvalsReviewer) ?? .user
        activePermissionProfile = try container.decodeIfPresent(
            ActivePermissionProfile.self,
            forKey: .activePermissionProfile
        )
        cwd = try container.decode(String.self, forKey: .cwd)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        initialMessages = try container.decodeIfPresent([EventMessage].self, forKey: .initialMessages)
        networkProxy = try container.decodeIfPresent(SessionNetworkProxyRuntime.self, forKey: .networkProxy)
        rolloutPath = try container.decodeIfPresent(String.self, forKey: .rolloutPath)
        historyLogID = 0
        historyEntryCount = 0

        let legacySandboxPolicy = try container.decodeIfPresent(SandboxPolicy.self, forKey: .sandboxPolicy)
        if let decodedPermissionProfile = try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile) {
            permissionProfile = decodedPermissionProfile
            sandboxPolicy = legacySandboxPolicy ?? Self.legacySandboxPolicy(from: decodedPermissionProfile)
        } else if let legacySandboxPolicy {
            sandboxPolicy = legacySandboxPolicy
            permissionProfile = PermissionProfile.fromLegacySandboxPolicy(legacySandboxPolicy)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.permissionProfile,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "No value associated with key \(CodingKeys.permissionProfile.stringValue)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(forkedFromID, forKey: .forkedFromID)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(threadName, forKey: .threadName)
        try container.encode(model, forKey: .model)
        try container.encode(modelProviderID, forKey: .modelProviderID)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encode(approvalPolicy, forKey: .approvalPolicy)
        try container.encode(approvalsReviewer, forKey: .approvalsReviewer)
        try container.encode(permissionProfile, forKey: .permissionProfile)
        try container.encodeIfPresent(activePermissionProfile, forKey: .activePermissionProfile)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(initialMessages, forKey: .initialMessages)
        try container.encodeIfPresent(networkProxy, forKey: .networkProxy)
        try container.encodeIfPresent(rolloutPath, forKey: .rolloutPath)
    }

    private static func legacySandboxPolicy(from permissionProfile: PermissionProfile) -> SandboxPolicy {
        switch permissionProfile {
        case .disabled:
            return .dangerFullAccess
        case let .external(network):
            return .externalSandbox(networkAccess: network.isEnabled ? .enabled : .restricted)
        case let .managed(fileSystem, network):
            if fileSystem == .readOnly(), network == .restricted {
                return .readOnly
            }
            return .workspaceWrite(
                writableRoots: [],
                networkAccess: network.isEnabled,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false
            )
        }
    }

    public static func == (lhs: SessionConfiguredEvent, rhs: SessionConfiguredEvent) -> Bool {
        lhs.sessionID == rhs.sessionID &&
            lhs.threadID == rhs.threadID &&
            lhs.forkedFromID == rhs.forkedFromID &&
            lhs.threadSource == rhs.threadSource &&
            lhs.threadName == rhs.threadName &&
            lhs.model == rhs.model &&
            lhs.modelProviderID == rhs.modelProviderID &&
            lhs.serviceTier == rhs.serviceTier &&
            lhs.approvalPolicy == rhs.approvalPolicy &&
            lhs.approvalsReviewer == rhs.approvalsReviewer &&
            lhs.permissionProfile == rhs.permissionProfile &&
            lhs.activePermissionProfile == rhs.activePermissionProfile &&
            lhs.cwd == rhs.cwd &&
            lhs.reasoningEffort == rhs.reasoningEffort &&
            lhs.initialMessages == rhs.initialMessages &&
            lhs.networkProxy == rhs.networkProxy &&
            lhs.rolloutPath == rhs.rolloutPath
    }
}
