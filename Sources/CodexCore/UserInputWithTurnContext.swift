import Foundation

public struct UserInputWithTurnContextParams: Codable, Equatable, Sendable {
    public let items: [UserInput]
    public let environments: [TurnEnvironmentSelection]?
    public let finalOutputJSONSchema: JSONValue?
    public let responsesAPIClientMetadata: [String: String]?
    public let cwd: String?
    public let workspaceRoots: [AbsolutePath]?
    public let profileWorkspaceRoots: [AbsolutePath]?
    public let approvalPolicy: AskForApproval?
    public let approvalsReviewer: JSONValue?
    public let sandboxPolicy: SandboxPolicy?
    public let permissionProfile: PermissionProfile?
    public let activePermissionProfile: ActivePermissionProfile?
    public let windowsSandboxLevel: JSONValue?
    public let model: String?
    public let effort: JSONValue?
    public let summary: ReasoningSummary?
    public let serviceTier: JSONValue?
    public let collaborationMode: JSONValue?
    public let personality: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case items
        case environments
        case finalOutputJSONSchema = "final_output_json_schema"
        case responsesAPIClientMetadata = "responsesapi_client_metadata"
        case cwd
        case workspaceRoots = "workspace_roots"
        case profileWorkspaceRoots = "profile_workspace_roots"
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
        case collaborationMode = "collaboration_mode"
        case personality
    }

    public init(
        items: [UserInput],
        environments: [TurnEnvironmentSelection]? = nil,
        finalOutputJSONSchema: JSONValue? = nil,
        responsesAPIClientMetadata: [String: String]? = nil,
        cwd: String? = nil,
        workspaceRoots: [AbsolutePath]? = nil,
        profileWorkspaceRoots: [AbsolutePath]? = nil,
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: JSONValue? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        windowsSandboxLevel: JSONValue? = nil,
        model: String? = nil,
        effort: JSONValue? = nil,
        summary: ReasoningSummary? = nil,
        serviceTier: JSONValue? = nil,
        collaborationMode: JSONValue? = nil,
        personality: JSONValue? = nil
    ) {
        self.items = items
        self.environments = environments
        self.finalOutputJSONSchema = finalOutputJSONSchema
        self.responsesAPIClientMetadata = responsesAPIClientMetadata
        self.cwd = cwd
        self.workspaceRoots = workspaceRoots
        self.profileWorkspaceRoots = profileWorkspaceRoots
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.windowsSandboxLevel = windowsSandboxLevel
        self.model = model
        self.effort = effort
        self.summary = summary
        self.serviceTier = serviceTier
        self.collaborationMode = collaborationMode
        self.personality = personality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([UserInput].self, forKey: .items)
        environments = try container.decodeIfPresent([TurnEnvironmentSelection].self, forKey: .environments)
        finalOutputJSONSchema = try container.decodeIfPresent(JSONValue.self, forKey: .finalOutputJSONSchema)
        responsesAPIClientMetadata = try container.decodeIfPresent(
            [String: String].self,
            forKey: .responsesAPIClientMetadata
        )
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        workspaceRoots = try container.decodeIfPresent([AbsolutePath].self, forKey: .workspaceRoots)
        profileWorkspaceRoots = try container.decodeIfPresent([AbsolutePath].self, forKey: .profileWorkspaceRoots)
        approvalPolicy = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy)
        approvalsReviewer = try Self.decodeNullableJSON(from: container, forKey: .approvalsReviewer)
        sandboxPolicy = try container.decodeIfPresent(SandboxPolicy.self, forKey: .sandboxPolicy)
        permissionProfile = try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile)
        activePermissionProfile = try container.decodeIfPresent(
            ActivePermissionProfile.self,
            forKey: .activePermissionProfile
        )
        windowsSandboxLevel = try Self.decodeNullableJSON(from: container, forKey: .windowsSandboxLevel)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        effort = try Self.decodeNullableJSON(from: container, forKey: .effort)
        summary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .summary)
        serviceTier = try Self.decodeNullableJSON(from: container, forKey: .serviceTier)
        collaborationMode = try Self.decodeNullableJSON(from: container, forKey: .collaborationMode)
        personality = try Self.decodeNullableJSON(from: container, forKey: .personality)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(environments, forKey: .environments)
        try container.encodeIfPresent(finalOutputJSONSchema, forKey: .finalOutputJSONSchema)
        try container.encodeIfPresent(responsesAPIClientMetadata, forKey: .responsesAPIClientMetadata)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(workspaceRoots, forKey: .workspaceRoots)
        try container.encodeIfPresent(profileWorkspaceRoots, forKey: .profileWorkspaceRoots)
        try container.encodeIfPresent(approvalPolicy, forKey: .approvalPolicy)
        try Self.encodeNullableJSON(approvalsReviewer, into: &container, forKey: .approvalsReviewer)
        try container.encodeIfPresent(sandboxPolicy, forKey: .sandboxPolicy)
        try container.encodeIfPresent(permissionProfile, forKey: .permissionProfile)
        try container.encodeIfPresent(activePermissionProfile, forKey: .activePermissionProfile)
        try Self.encodeNullableJSON(windowsSandboxLevel, into: &container, forKey: .windowsSandboxLevel)
        try container.encodeIfPresent(model, forKey: .model)
        try Self.encodeNullableJSON(effort, into: &container, forKey: .effort)
        try container.encodeIfPresent(summary, forKey: .summary)
        try Self.encodeNullableJSON(serviceTier, into: &container, forKey: .serviceTier)
        try Self.encodeNullableJSON(collaborationMode, into: &container, forKey: .collaborationMode)
        try Self.encodeNullableJSON(personality, into: &container, forKey: .personality)
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
