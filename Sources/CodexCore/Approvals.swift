import Foundation

public struct ExecPolicyAmendment: Equatable, Codable, Sendable {
    public let command: [String]

    public init(command: [String]) {
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.command = try container.decode([String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(command)
    }
}

public enum CommandPrefixFormatter {
    public static let maxRenderedPrefixes = 100
    public static let maxAllowPrefixTextBytes = 5_000
    public static let truncatedMarker = "...\n[Some commands were truncated]"

    public static func formatAllowPrefixes(_ prefixes: [[String]]) -> String? {
        var truncated = prefixes.count > maxRenderedPrefixes
        let sorted = prefixes.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }

            let lhsCombinedLength = lhs.reduce(0) { $0 + $1.count }
            let rhsCombinedLength = rhs.reduce(0) { $0 + $1.count }
            if lhsCombinedLength != rhsCombinedLength {
                return lhsCombinedLength < rhsCombinedLength
            }

            return lhs.lexicographicallyPrecedes(rhs)
        }

        var output = sorted
            .prefix(maxRenderedPrefixes)
            .map { "- \(renderCommandPrefix($0))" }
            .joined(separator: "\n")

        if output.utf8.count > maxAllowPrefixTextBytes {
            truncated = true
            output = truncateToUTF8Boundary(output, maxBytes: maxAllowPrefixTextBytes)
        }

        return truncated ? output + truncatedMarker : output
    }

    private static func truncateToUTF8Boundary(_ value: String, maxBytes: Int) -> String {
        var end = value.utf8.index(value.utf8.startIndex, offsetBy: maxBytes)
        while end > value.utf8.startIndex,
              String.Index(end, within: value) == nil
        {
            end = value.utf8.index(before: end)
        }
        guard let stringEnd = String.Index(end, within: value) else {
            return ""
        }
        return String(value[..<stringEnd])
    }

    private static func renderCommandPrefix(_ prefix: [String]) -> String {
        let tokens = prefix.map(jsonString).joined(separator: ", ")
        return "[\(tokens)]"
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return String(reflecting: value)
        }
        return encoded
    }
}

public enum NetworkPolicyRuleAction: String, Codable, Equatable, Sendable {
    case allow
    case deny
}

public enum NetworkPolicyDecision: String, Codable, Equatable, Sendable {
    case deny
    case ask
}

public enum NetworkDecisionSource: String, Codable, Equatable, Sendable {
    case baselinePolicy = "baseline_policy"
    case modeGuard = "mode_guard"
    case proxyState = "proxy_state"
    case decider
}

public struct NetworkApprovalContext: Equatable, Codable, Sendable {
    public let host: String
    public let `protocol`: NetworkApprovalProtocol

    public init(host: String, protocol: NetworkApprovalProtocol) {
        self.host = host
        self.protocol = `protocol`
    }
}

public struct NetworkPolicyDecisionPayload: Equatable, Codable, Sendable {
    public let decision: NetworkPolicyDecision
    public let source: NetworkDecisionSource
    public let `protocol`: NetworkApprovalProtocol?
    public let host: String?
    public let reason: String?
    public let port: UInt16?

    public init(
        decision: NetworkPolicyDecision,
        source: NetworkDecisionSource,
        protocol: NetworkApprovalProtocol? = nil,
        host: String? = nil,
        reason: String? = nil,
        port: UInt16? = nil
    ) {
        self.decision = decision
        self.source = source
        self.protocol = `protocol`
        self.host = host
        self.reason = reason
        self.port = port
    }

    public var isAskFromDecider: Bool {
        decision == .ask && source == .decider
    }

    public var networkApprovalContext: NetworkApprovalContext? {
        guard isAskFromDecider,
              let `protocol`,
              let trimmedHost = host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedHost.isEmpty
        else {
            return nil
        }

        return NetworkApprovalContext(host: trimmedHost, protocol: `protocol`)
    }
}

public struct NetworkPolicyAmendment: Equatable, Codable, Sendable {
    public let host: String
    public let action: NetworkPolicyRuleAction

    public init(host: String, action: NetworkPolicyRuleAction) {
        self.host = host
        self.action = action
    }
}

public enum RequestID: Equatable, Codable, Sendable {
    case string(String)
    case integer(Int64)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .integer(try container.decode(Int64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        }
    }
}

public struct ExecApprovalRequestEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let approvalID: String?
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let command: [String]
    public let cwd: String
    public let reason: String?
    public let networkApprovalContext: NetworkApprovalContext?
    public let proposedExecPolicyAmendment: ExecPolicyAmendment?
    public let proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]?
    public let additionalPermissions: RequestPermissionProfile?
    public let availableDecisions: [ReviewDecision]?
    public let parsedCmd: [ParsedCommand]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case approvalID = "approval_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case command
        case cwd
        case reason
        case networkApprovalContext = "network_approval_context"
        case proposedExecPolicyAmendment = "proposed_execpolicy_amendment"
        case proposedNetworkPolicyAmendments = "proposed_network_policy_amendments"
        case additionalPermissions = "additional_permissions"
        case availableDecisions = "available_decisions"
        case parsedCmd = "parsed_cmd"
    }

    public init(
        callID: String,
        approvalID: String? = nil,
        turnID: String = "",
        startedAtMilliseconds: Int64 = 0,
        command: [String],
        cwd: String,
        reason: String? = nil,
        networkApprovalContext: NetworkApprovalContext? = nil,
        proposedExecPolicyAmendment: ExecPolicyAmendment? = nil,
        proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]? = nil,
        additionalPermissions: RequestPermissionProfile? = nil,
        availableDecisions: [ReviewDecision]? = nil,
        parsedCmd: [ParsedCommand]
    ) {
        self.callID = callID
        self.approvalID = approvalID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.networkApprovalContext = networkApprovalContext
        self.proposedExecPolicyAmendment = proposedExecPolicyAmendment
        self.proposedNetworkPolicyAmendments = proposedNetworkPolicyAmendments
        self.additionalPermissions = additionalPermissions
        self.availableDecisions = availableDecisions
        self.parsedCmd = parsedCmd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.approvalID = try container.decodeIfPresent(String.self, forKey: .approvalID)
        self.turnID = try container.decodeRustDefaulted(String.self, forKey: .turnID, defaultValue: "")
        self.startedAtMilliseconds = try container.decode(Int64.self, forKey: .startedAtMilliseconds)
        self.command = try container.decode([String].self, forKey: .command)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.networkApprovalContext = try container.decodeIfPresent(
            NetworkApprovalContext.self,
            forKey: .networkApprovalContext
        )
        self.proposedExecPolicyAmendment = try container.decodeIfPresent(
            ExecPolicyAmendment.self,
            forKey: .proposedExecPolicyAmendment
        )
        self.proposedNetworkPolicyAmendments = try container.decodeIfPresent(
            [NetworkPolicyAmendment].self,
            forKey: .proposedNetworkPolicyAmendments
        )
        self.additionalPermissions = try container.decodeIfPresent(
            RequestPermissionProfile.self,
            forKey: .additionalPermissions
        )
        self.availableDecisions = try container.decodeIfPresent([ReviewDecision].self, forKey: .availableDecisions)
        self.parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encodeIfPresent(approvalID, forKey: .approvalID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(networkApprovalContext, forKey: .networkApprovalContext)
        try container.encodeIfPresent(proposedExecPolicyAmendment, forKey: .proposedExecPolicyAmendment)
        try container.encodeIfPresent(proposedNetworkPolicyAmendments, forKey: .proposedNetworkPolicyAmendments)
        try container.encodeIfPresent(additionalPermissions, forKey: .additionalPermissions)
        try container.encodeIfPresent(availableDecisions, forKey: .availableDecisions)
        try container.encode(parsedCmd, forKey: .parsedCmd)
    }

    public var effectiveApprovalID: String {
        approvalID ?? callID
    }

    public var effectiveAvailableDecisions: [ReviewDecision] {
        availableDecisions ?? Self.defaultAvailableDecisions(
            networkApprovalContext: networkApprovalContext,
            proposedExecPolicyAmendment: proposedExecPolicyAmendment,
            proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
            additionalPermissions: additionalPermissions
        )
    }

    public static func defaultAvailableDecisions(
        networkApprovalContext: NetworkApprovalContext?,
        proposedExecPolicyAmendment: ExecPolicyAmendment?,
        proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]?,
        additionalPermissions: RequestPermissionProfile?
    ) -> [ReviewDecision] {
        if networkApprovalContext != nil {
            var decisions: [ReviewDecision] = [.approved, .approvedForSession]
            if let amendment = proposedNetworkPolicyAmendments?.first(where: { $0.action == .allow }) {
                decisions.append(.networkPolicyAmendment(networkPolicyAmendment: amendment))
            }
            decisions.append(.abort)
            return decisions
        }

        if additionalPermissions != nil {
            return [.approved, .abort]
        }

        var decisions: [ReviewDecision] = [.approved]
        if let proposedExecPolicyAmendment {
            decisions.append(.approvedExecpolicyAmendment(
                proposedExecpolicyAmendment: proposedExecPolicyAmendment
            ))
        }
        decisions.append(.abort)
        return decisions
    }
}

public struct ElicitationRequestEvent: Equatable, Codable, Sendable {
    public let serverName: String
    public let id: RequestID
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case id
        case message
    }

    public init(serverName: String, id: RequestID, message: String) {
        self.serverName = serverName
        self.id = id
        self.message = message
    }
}

public enum ElicitationAction: String, Codable, Equatable, Sendable {
    case accept
    case decline
    case cancel
}

public struct ApplyPatchApprovalRequestEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let changes: [String: FileChange]
    public let reason: String?
    public let grantRoot: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case changes
        case reason
        case grantRoot = "grant_root"
    }

    public init(
        callID: String,
        turnID: String = "",
        startedAtMilliseconds: Int64 = 0,
        changes: [String: FileChange],
        reason: String? = nil,
        grantRoot: String? = nil
    ) {
        self.callID = callID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.changes = changes
        self.reason = reason
        self.grantRoot = grantRoot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.turnID = try container.decodeRustDefaulted(String.self, forKey: .turnID, defaultValue: "")
        self.startedAtMilliseconds = try container.decode(Int64.self, forKey: .startedAtMilliseconds)
        self.changes = try container.decode([String: FileChange].self, forKey: .changes)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.grantRoot = try container.decodeIfPresent(String.self, forKey: .grantRoot)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(changes, forKey: .changes)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(grantRoot, forKey: .grantRoot)
    }
}

public enum ReviewDecision: Equatable, Codable, Sendable {
    case approved
    case approvedExecpolicyAmendment(proposedExecpolicyAmendment: ExecPolicyAmendment)
    case approvedForSession
    case networkPolicyAmendment(networkPolicyAmendment: NetworkPolicyAmendment)
    case denied
    case timedOut
    case abort

    public static let `default`: ReviewDecision = .denied

    private enum UnitDecision: String, Codable {
        case approved
        case approvedForSession = "approved_for_session"
        case denied
        case timedOut = "timed_out"
        case abort
    }

    private enum CodingKeys: String, CodingKey {
        case approvedExecpolicyAmendment = "approved_execpolicy_amendment"
        case networkPolicyAmendment = "network_policy_amendment"
    }

    private enum AmendmentKeys: String, CodingKey {
        case proposedExecpolicyAmendment = "proposed_execpolicy_amendment"
        case networkPolicyAmendment = "network_policy_amendment"
    }

    public init(from decoder: Decoder) throws {
        if let unit = try? UnitDecision(from: decoder) {
            switch unit {
            case .approved:
                self = .approved
            case .approvedForSession:
                self = .approvedForSession
            case .denied:
                self = .denied
            case .timedOut:
                self = .timedOut
            case .abort:
                self = .abort
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.approvedExecpolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            self = .approvedExecpolicyAmendment(
                proposedExecpolicyAmendment: try nested.decode(
                    ExecPolicyAmendment.self,
                    forKey: .proposedExecpolicyAmendment
                )
            )
            return
        }

        if container.contains(.networkPolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .networkPolicyAmendment
            )
            self = .networkPolicyAmendment(
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
                debugDescription: "Unsupported review decision"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .approved:
            try UnitDecision.approved.encode(to: encoder)
        case let .approvedExecpolicyAmendment(amendment):
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            try nested.encode(amendment, forKey: .proposedExecpolicyAmendment)
        case .approvedForSession:
            try UnitDecision.approvedForSession.encode(to: encoder)
        case let .networkPolicyAmendment(amendment):
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .networkPolicyAmendment
            )
            try nested.encode(amendment, forKey: .networkPolicyAmendment)
        case .denied:
            try UnitDecision.denied.encode(to: encoder)
        case .timedOut:
            try UnitDecision.timedOut.encode(to: encoder)
        case .abort:
            try UnitDecision.abort.encode(to: encoder)
        }
    }
}
