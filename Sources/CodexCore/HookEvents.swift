import Foundation

public enum HookEventName: String, Codable, CaseIterable, Equatable, Sendable {
    case preToolUse = "pre_tool_use"
    case permissionRequest = "permission_request"
    case postToolUse = "post_tool_use"
    case preCompact = "pre_compact"
    case postCompact = "post_compact"
    case sessionStart = "session_start"
    case userPromptSubmit = "user_prompt_submit"
    case stop

    public var configLabel: String {
        switch self {
        case .preToolUse: return "PreToolUse"
        case .permissionRequest: return "PermissionRequest"
        case .postToolUse: return "PostToolUse"
        case .preCompact: return "PreCompact"
        case .postCompact: return "PostCompact"
        case .sessionStart: return "SessionStart"
        case .userPromptSubmit: return "UserPromptSubmit"
        case .stop: return "Stop"
        }
    }
}

public enum HookHandlerType: String, Codable, Equatable, Sendable {
    case command
    case prompt
    case agent
}

public enum HookExecutionMode: String, Codable, Equatable, Sendable {
    case sync
    case `async`
}

public enum HookScope: String, Codable, Equatable, Sendable {
    case thread
    case turn
}

public enum HookSource: String, Codable, Equatable, Sendable {
    case system
    case user
    case project
    case mdm
    case sessionFlags = "session_flags"
    case plugin
    case cloudRequirements = "cloud_requirements"
    case legacyManagedConfigFile = "legacy_managed_config_file"
    case legacyManagedConfigMdm = "legacy_managed_config_mdm"
    case unknown
}

public enum HookTrustStatus: String, Codable, Equatable, Sendable {
    case managed
    case untrusted
    case trusted
    case modified
}

public enum HookRunStatus: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case blocked
    case stopped
}

public enum HookOutputEntryKind: String, Codable, Equatable, Sendable {
    case warning
    case stop
    case feedback
    case context
    case error
}

public struct HookOutputEntry: Codable, Equatable, Sendable {
    public let kind: HookOutputEntryKind
    public let text: String

    public init(kind: HookOutputEntryKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct HookRunSummary: Codable, Equatable, Sendable {
    public let id: String
    public let eventName: HookEventName
    public let handlerType: HookHandlerType
    public let executionMode: HookExecutionMode
    public let scope: HookScope
    public let sourcePath: AbsolutePath
    public let source: HookSource
    public let displayOrder: Int64
    public let status: HookRunStatus
    public let statusMessage: String?
    public let startedAt: Int64
    public let completedAt: Int64?
    public let durationMs: Int64?
    public let entries: [HookOutputEntry]

    public init(
        id: String,
        eventName: HookEventName,
        handlerType: HookHandlerType,
        executionMode: HookExecutionMode,
        scope: HookScope,
        sourcePath: AbsolutePath,
        source: HookSource = .unknown,
        displayOrder: Int64,
        status: HookRunStatus,
        statusMessage: String?,
        startedAt: Int64,
        completedAt: Int64?,
        durationMs: Int64?,
        entries: [HookOutputEntry]
    ) {
        self.id = id
        self.eventName = eventName
        self.handlerType = handlerType
        self.executionMode = executionMode
        self.scope = scope
        self.sourcePath = sourcePath
        self.source = source
        self.displayOrder = displayOrder
        self.status = status
        self.statusMessage = statusMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventName = "event_name"
        case handlerType = "handler_type"
        case executionMode = "execution_mode"
        case scope
        case sourcePath = "source_path"
        case source
        case displayOrder = "display_order"
        case status
        case statusMessage = "status_message"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMs = "duration_ms"
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.eventName = try container.decode(HookEventName.self, forKey: .eventName)
        self.handlerType = try container.decode(HookHandlerType.self, forKey: .handlerType)
        self.executionMode = try container.decode(HookExecutionMode.self, forKey: .executionMode)
        self.scope = try container.decode(HookScope.self, forKey: .scope)
        self.sourcePath = try container.decode(AbsolutePath.self, forKey: .sourcePath)
        self.source = try container.decodeRustDefaulted(HookSource.self, forKey: .source, defaultValue: .unknown)
        self.displayOrder = try container.decode(Int64.self, forKey: .displayOrder)
        self.status = try container.decode(HookRunStatus.self, forKey: .status)
        self.statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        self.startedAt = try container.decode(Int64.self, forKey: .startedAt)
        self.completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        self.durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
        self.entries = try container.decode([HookOutputEntry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(handlerType, forKey: .handlerType)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(scope, forKey: .scope)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(source, forKey: .source)
        try container.encode(displayOrder, forKey: .displayOrder)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(statusMessage, forKey: .statusMessage)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeNilOrValue(completedAt, forKey: .completedAt)
        try container.encodeNilOrValue(durationMs, forKey: .durationMs)
        try container.encode(entries, forKey: .entries)
    }
}

public struct HookStartedEvent: Codable, Equatable, Sendable {
    public let turnID: String?
    public let run: HookRunSummary

    public init(turnID: String?, run: HookRunSummary) {
        self.turnID = turnID
        self.run = run
    }

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case run
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
    }
}

public struct HookCompletedEvent: Codable, Equatable, Sendable {
    public let turnID: String?
    public let run: HookRunSummary

    public init(turnID: String?, run: HookRunSummary) {
        self.turnID = turnID
        self.run = run
    }

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case run
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
    }
}

public struct HookUniversalOutput: Equatable, Sendable {
    public let continueProcessing: Bool
    public let stopReason: String?
    public let suppressOutput: Bool
    public let systemMessage: String?

    public init(
        continueProcessing: Bool = true,
        stopReason: String? = nil,
        suppressOutput: Bool = false,
        systemMessage: String? = nil
    ) {
        self.continueProcessing = continueProcessing
        self.stopReason = stopReason
        self.suppressOutput = suppressOutput
        self.systemMessage = systemMessage
    }
}

public struct HookStatelessOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let invalidReason: String?

    public init(universal: HookUniversalOutput, invalidReason: String? = nil) {
        self.universal = universal
        self.invalidReason = invalidReason
    }
}

public enum HookPermissionRequestDecision: Equatable, Sendable {
    case allow
    case deny(message: String)
}

public struct HookPermissionRequestOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let decision: HookPermissionRequestDecision?
    public let invalidReason: String?

    public init(
        universal: HookUniversalOutput,
        decision: HookPermissionRequestDecision?,
        invalidReason: String? = nil
    ) {
        self.universal = universal
        self.decision = decision
        self.invalidReason = invalidReason
    }
}

public struct HookPreToolUseOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let blockReason: String?
    public let additionalContext: String?
    public let updatedInput: JSONValue?
    public let invalidReason: String?

    public init(
        universal: HookUniversalOutput,
        blockReason: String?,
        additionalContext: String?,
        updatedInput: JSONValue? = nil,
        invalidReason: String? = nil
    ) {
        self.universal = universal
        self.blockReason = blockReason
        self.additionalContext = additionalContext
        self.updatedInput = updatedInput
        self.invalidReason = invalidReason
    }
}

public struct HookPostToolUseOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let shouldBlock: Bool
    public let reason: String?
    public let invalidBlockReason: String?
    public let additionalContext: String?
    public let invalidReason: String?

    public init(
        universal: HookUniversalOutput,
        shouldBlock: Bool,
        reason: String?,
        invalidBlockReason: String? = nil,
        additionalContext: String?,
        invalidReason: String? = nil
    ) {
        self.universal = universal
        self.shouldBlock = shouldBlock
        self.reason = reason
        self.invalidBlockReason = invalidBlockReason
        self.additionalContext = additionalContext
        self.invalidReason = invalidReason
    }
}

public struct HookUserPromptSubmitOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let shouldBlock: Bool
    public let reason: String?
    public let invalidBlockReason: String?
    public let additionalContext: String?

    public init(
        universal: HookUniversalOutput,
        shouldBlock: Bool,
        reason: String?,
        invalidBlockReason: String? = nil,
        additionalContext: String?
    ) {
        self.universal = universal
        self.shouldBlock = shouldBlock
        self.reason = reason
        self.invalidBlockReason = invalidBlockReason
        self.additionalContext = additionalContext
    }
}

public struct HookStopOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let shouldBlock: Bool
    public let reason: String?
    public let invalidBlockReason: String?

    public init(
        universal: HookUniversalOutput,
        shouldBlock: Bool,
        reason: String?,
        invalidBlockReason: String? = nil
    ) {
        self.universal = universal
        self.shouldBlock = shouldBlock
        self.reason = reason
        self.invalidBlockReason = invalidBlockReason
    }
}

public struct HookSessionStartOutput: Equatable, Sendable {
    public let universal: HookUniversalOutput
    public let additionalContext: String?

    public init(universal: HookUniversalOutput, additionalContext: String?) {
        self.universal = universal
        self.additionalContext = additionalContext
    }
}

public enum HooksProtocol {
    public static let eventNames: [String] = HookEventName.allCases.map(\.configLabel)

    public static let eventNamesWithMatchers: [String] = [
        HookEventName.preToolUse.configLabel,
        HookEventName.permissionRequest.configLabel,
        HookEventName.postToolUse.configLabel,
        HookEventName.preCompact.configLabel,
        HookEventName.postCompact.configLabel,
        HookEventName.sessionStart.configLabel,
    ]

    public static func hookEventKeyLabel(_ eventName: HookEventName) -> String {
        eventName.rawValue
    }

    public static func hookKey(
        keySource: String,
        eventName: HookEventName,
        groupIndex: Int,
        handlerIndex: Int
    ) -> String {
        "\(keySource):\(hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
    }

    public static func parsePreCompactOutput(_ stdout: String) -> HookStatelessOutput? {
        parseCompactOutput(stdout)
    }

    public static func parsePostCompactOutput(_ stdout: String) -> HookStatelessOutput? {
        parseCompactOutput(stdout)
    }

    public static func parsePreToolUseOutput(_ stdout: String) -> HookPreToolUseOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(
                object,
                extraAllowedKeys: ["decision", "reason", "hookSpecificOutput"]
              ),
              let legacyDecision = optionalStringEnumValue(object["decision"], allowedValues: ["approve", "block"]),
              let reason = optionalStringValue(object["reason"])
        else {
            return nil
        }

        let hookSpecific = parsePreToolUseHookSpecificOutput(object["hookSpecificOutput"])
        guard hookSpecific.valid else {
            return nil
        }

        let useHookSpecificDecision = hookSpecific.permissionDecision != nil
            || hookSpecific.permissionDecisionReason != nil
            || hookSpecific.updatedInput != nil
        let invalidReason = unsupportedPreToolUseUniversal(universal) ?? (
            useHookSpecificDecision
                ? unsupportedPreToolUseHookSpecificOutput(hookSpecific)
                : unsupportedPreToolUseLegacyDecision(decision: legacyDecision, reason: reason)
        )
        let blockReason: String?
        if invalidReason == nil {
            if useHookSpecificDecision {
                blockReason = hookSpecific.permissionDecision == "deny"
                    ? trimmedReason(hookSpecific.permissionDecisionReason)
                    : nil
            } else {
                blockReason = legacyDecision == "block" ? trimmedReason(reason) : nil
            }
        } else {
            blockReason = nil
        }
        let updatedInput = invalidReason == nil && hookSpecific.permissionDecision == "allow"
            ? hookSpecific.updatedInput
            : nil

        return HookPreToolUseOutput(
            universal: universal,
            blockReason: blockReason,
            additionalContext: hookSpecific.additionalContext,
            updatedInput: updatedInput,
            invalidReason: invalidReason
        )
    }

    public static func parsePostToolUseOutput(_ stdout: String) -> HookPostToolUseOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(
                object,
                extraAllowedKeys: ["decision", "reason", "hookSpecificOutput"]
              ),
              let decision = optionalStringEnumValue(object["decision"], allowedValues: ["block"]),
              let reason = optionalStringValue(object["reason"])
        else {
            return nil
        }

        let hookSpecific = parsePostToolUseHookSpecificOutput(object["hookSpecificOutput"])
        guard hookSpecific.valid else {
            return nil
        }

        let invalidReason = unsupportedPostToolUseUniversal(universal)
            ?? hookSpecific.invalidReason
        let shouldBlock = decision == "block"
        let invalidBlockReason: String?
        if shouldBlock && trimmedReason(reason) == nil {
            invalidBlockReason = invalidBlockMessage("PostToolUse")
        } else if !shouldBlock && universal.continueProcessing && reason != nil {
            invalidBlockReason = "PostToolUse hook returned reason without decision"
        } else {
            invalidBlockReason = nil
        }

        return HookPostToolUseOutput(
            universal: universal,
            shouldBlock: shouldBlock && invalidReason == nil && invalidBlockReason == nil,
            reason: reason,
            invalidBlockReason: invalidBlockReason,
            additionalContext: hookSpecific.additionalContext,
            invalidReason: invalidReason
        )
    }

    public static func parsePermissionRequestOutput(_ stdout: String) -> HookPermissionRequestOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(object, extraAllowedKeys: ["hookSpecificOutput"])
        else {
            return nil
        }

        let hookSpecific = parsePermissionRequestHookSpecificOutput(object["hookSpecificOutput"])
        guard hookSpecific.valid else {
            return nil
        }

        let invalidReason = unsupportedPermissionRequestUniversal(universal)
            ?? hookSpecific.invalidReason
        let decision = invalidReason == nil ? hookSpecific.decision : nil
        return HookPermissionRequestOutput(
            universal: universal,
            decision: decision,
            invalidReason: invalidReason
        )
    }

    public static func parseUserPromptSubmitOutput(_ stdout: String) -> HookUserPromptSubmitOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(
                object,
                extraAllowedKeys: ["decision", "reason", "hookSpecificOutput"]
              ),
              let decision = optionalStringEnumValue(object["decision"], allowedValues: ["block"]),
              let reason = optionalStringValue(object["reason"])
        else {
            return nil
        }

        let hookSpecific = parseAdditionalContextHookSpecificOutput(
            object["hookSpecificOutput"],
            allowedKeys: ["hookEventName", "additionalContext"]
        )
        guard hookSpecific.valid else {
            return nil
        }

        let shouldBlock = decision == "block"
        let invalidBlockReason = shouldBlock && trimmedReason(reason) == nil
            ? invalidBlockMessage("UserPromptSubmit")
            : nil
        return HookUserPromptSubmitOutput(
            universal: universal,
            shouldBlock: shouldBlock && invalidBlockReason == nil,
            reason: reason,
            invalidBlockReason: invalidBlockReason,
            additionalContext: hookSpecific.additionalContext
        )
    }

    public static func parseStopOutput(_ stdout: String) -> HookStopOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(object, extraAllowedKeys: ["decision", "reason"]),
              let decision = optionalStringEnumValue(object["decision"], allowedValues: ["block"]),
              let reason = optionalStringValue(object["reason"])
        else {
            return nil
        }

        let shouldBlock = decision == "block"
        let invalidBlockReason = shouldBlock && trimmedReason(reason) == nil
            ? invalidBlockMessage("Stop")
            : nil
        return HookStopOutput(
            universal: universal,
            shouldBlock: shouldBlock && invalidBlockReason == nil,
            reason: reason,
            invalidBlockReason: invalidBlockReason
        )
    }

    public static func parseSessionStartOutput(_ stdout: String) -> HookSessionStartOutput? {
        guard let object = parseJSONObject(stdout),
              let universal = parseUniversalOutput(object, extraAllowedKeys: ["hookSpecificOutput"])
        else {
            return nil
        }

        let hookSpecific = parseAdditionalContextHookSpecificOutput(
            object["hookSpecificOutput"],
            allowedKeys: ["hookEventName", "additionalContext"]
        )
        guard hookSpecific.valid else {
            return nil
        }

        return HookSessionStartOutput(
            universal: universal,
            additionalContext: hookSpecific.additionalContext
        )
    }

    public static func looksLikeJSON(_ stdout: String) -> Bool {
        guard let first = stdout.first(where: { !$0.isWhitespace }) else {
            return false
        }
        return first == "{" || first == "["
    }

    private static func parseCompactOutput(_ stdout: String) -> HookStatelessOutput? {
        guard let object = parseJSONObject(stdout) else {
            return nil
        }
        return parseUniversalOutput(object).map { HookStatelessOutput(universal: $0) }
    }

    private static func parseJSONObject(_ stdout: String) -> [String: Any]? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func parseUniversalOutput(
        _ object: [String: Any],
        extraAllowedKeys: Set<String> = []
    ) -> HookUniversalOutput? {
        let universalKeys: Set<String> = [
            "continue",
            "stopReason",
            "suppressOutput",
            "systemMessage",
        ]
        let allowedKeys = universalKeys.union(extraAllowedKeys)
        guard Set(object.keys).isSubset(of: allowedKeys),
              let continueProcessing = boolValue(object["continue"], defaultValue: true),
              let suppressOutput = boolValue(object["suppressOutput"], defaultValue: false),
              let stopReason = optionalStringValue(object["stopReason"]),
              let systemMessage = optionalStringValue(object["systemMessage"])
        else {
            return nil
        }

        return HookUniversalOutput(
            continueProcessing: continueProcessing,
            stopReason: stopReason,
            suppressOutput: suppressOutput,
            systemMessage: systemMessage
        )
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool) -> Bool? {
        guard let value else {
            return defaultValue
        }
        return value as? Bool
    }

    private static func parsePreToolUseHookSpecificOutput(_ value: Any?) -> (
        valid: Bool,
        permissionDecision: String?,
        permissionDecisionReason: String?,
        updatedInput: JSONValue?,
        additionalContext: String?
    ) {
        guard let value else {
            return (true, nil, nil, nil, nil)
        }
        if value is NSNull {
            return (true, nil, nil, nil, nil)
        }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: [
                "hookEventName",
                "permissionDecision",
                "permissionDecisionReason",
                "updatedInput",
                "additionalContext",
              ]),
              let eventName = object["hookEventName"] as? String,
              allHookEventWireNames.contains(eventName),
              let permissionDecision = optionalStringEnumValue(
                object["permissionDecision"],
                allowedValues: ["allow", "deny", "ask"]
              ),
              let permissionDecisionReason = optionalStringValue(object["permissionDecisionReason"]),
              let additionalContext = optionalStringValue(object["additionalContext"])
        else {
            return (false, nil, nil, nil, nil)
        }

        return (
            true,
            permissionDecision,
            permissionDecisionReason,
            jsonValue(from: object["updatedInput"]),
            additionalContext
        )
    }

    private static func unsupportedPreToolUseUniversal(_ universal: HookUniversalOutput) -> String? {
        if !universal.continueProcessing {
            return "PreToolUse hook returned unsupported continue:false"
        }
        if universal.stopReason != nil {
            return "PreToolUse hook returned unsupported stopReason"
        }
        if universal.suppressOutput {
            return "PreToolUse hook returned unsupported suppressOutput"
        }
        return nil
    }

    private static func unsupportedPreToolUseHookSpecificOutput(
        _ output: (
            valid: Bool,
            permissionDecision: String?,
            permissionDecisionReason: String?,
            updatedInput: JSONValue?,
            additionalContext: String?
        )
    ) -> String? {
        if output.updatedInput != nil, output.permissionDecision != "allow" {
            return "PreToolUse hook returned updatedInput without permissionDecision:allow"
        }
        switch output.permissionDecision {
        case "allow":
            return output.updatedInput == nil
                ? "PreToolUse hook returned unsupported permissionDecision:allow"
                : nil
        case "ask":
            return "PreToolUse hook returned unsupported permissionDecision:ask"
        case "deny":
            return trimmedReason(output.permissionDecisionReason) == nil
                ? invalidPreToolUseReasonMessage
                : nil
        case nil:
            return output.permissionDecisionReason != nil
                ? "PreToolUse hook returned permissionDecisionReason without permissionDecision"
                : nil
        default:
            return nil
        }
    }

    private static func unsupportedPreToolUseLegacyDecision(decision: String?, reason: String?) -> String? {
        switch decision {
        case "approve":
            return "PreToolUse hook returned unsupported decision:approve"
        case "block":
            return trimmedReason(reason) == nil ? invalidBlockMessage("PreToolUse") : nil
        case nil:
            return reason != nil ? "PreToolUse hook returned reason without decision" : nil
        default:
            return nil
        }
    }

    private static func parsePostToolUseHookSpecificOutput(_ value: Any?) -> (
        valid: Bool,
        additionalContext: String?,
        invalidReason: String?
    ) {
        let parsed = parseAdditionalContextHookSpecificOutput(
            value,
            allowedKeys: ["hookEventName", "additionalContext", "updatedMCPToolOutput"]
        )
        guard parsed.valid else {
            return (false, nil, nil)
        }

        return (
            true,
            parsed.additionalContext,
            isNonNullJSONValue(parsed.object?["updatedMCPToolOutput"])
                ? "PostToolUse hook returned unsupported updatedMCPToolOutput"
                : nil
        )
    }

    private static func unsupportedPostToolUseUniversal(_ universal: HookUniversalOutput) -> String? {
        if universal.suppressOutput {
            return "PostToolUse hook returned unsupported suppressOutput"
        }
        return nil
    }

    private static func parseAdditionalContextHookSpecificOutput(
        _ value: Any?,
        allowedKeys: Set<String>
    ) -> (valid: Bool, object: [String: Any]?, additionalContext: String?) {
        guard let value else {
            return (true, nil, nil)
        }
        if value is NSNull {
            return (true, nil, nil)
        }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: allowedKeys),
              let eventName = object["hookEventName"] as? String,
              allHookEventWireNames.contains(eventName),
              let additionalContext = optionalStringValue(object["additionalContext"])
        else {
            return (false, nil, nil)
        }
        return (true, object, additionalContext)
    }

    private static func parsePermissionRequestHookSpecificOutput(_ value: Any?) -> (
        valid: Bool,
        decision: HookPermissionRequestDecision?,
        invalidReason: String?
    ) {
        guard let value else {
            return (true, nil, nil)
        }
        if value is NSNull {
            return (true, nil, nil)
        }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: ["hookEventName", "decision"]),
              let eventName = object["hookEventName"] as? String,
              allHookEventWireNames.contains(eventName)
        else {
            return (false, nil, nil)
        }

        return parsePermissionRequestDecision(object["decision"])
    }

    private static func parsePermissionRequestDecision(_ value: Any?) -> (
        valid: Bool,
        decision: HookPermissionRequestDecision?,
        invalidReason: String?
    ) {
        guard let value else {
            return (true, nil, nil)
        }
        if value is NSNull {
            return (true, nil, nil)
        }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: [
                "behavior",
                "updatedInput",
                "updatedPermissions",
                "message",
                "interrupt",
              ]),
              let behavior = object["behavior"] as? String,
              ["allow", "deny"].contains(behavior),
              let interrupt = boolValue(object["interrupt"], defaultValue: false),
              let message = optionalStringValue(object["message"])
        else {
            return (false, nil, nil)
        }

        let invalidReason = unsupportedPermissionRequestDecision(
            updatedInput: object["updatedInput"],
            updatedPermissions: object["updatedPermissions"],
            interrupt: interrupt
        )
        guard invalidReason == nil else {
            return (true, nil, invalidReason)
        }

        if behavior == "allow" {
            return (true, .allow, nil)
        }

        return (true, .deny(message: trimmedReason(message) ?? "PermissionRequest hook denied approval"), nil)
    }

    private static func unsupportedPermissionRequestUniversal(_ universal: HookUniversalOutput) -> String? {
        if !universal.continueProcessing {
            return "PermissionRequest hook returned unsupported continue:false"
        }
        if universal.stopReason != nil {
            return "PermissionRequest hook returned unsupported stopReason"
        }
        if universal.suppressOutput {
            return "PermissionRequest hook returned unsupported suppressOutput"
        }
        return nil
    }

    private static func unsupportedPermissionRequestDecision(
        updatedInput: Any?,
        updatedPermissions: Any?,
        interrupt: Bool
    ) -> String? {
        if isNonNullJSONValue(updatedInput) {
            return "PermissionRequest hook returned unsupported updatedInput"
        }
        if isNonNullJSONValue(updatedPermissions) {
            return "PermissionRequest hook returned unsupported updatedPermissions"
        }
        if interrupt {
            return "PermissionRequest hook returned unsupported interrupt:true"
        }
        return nil
    }

    private static func trimmedReason(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func invalidBlockMessage(_ eventName: String) -> String {
        "\(eventName) hook returned decision:block without a non-empty reason"
    }

    private static let invalidPreToolUseReasonMessage =
        "PreToolUse hook returned permissionDecision:deny without a non-empty permissionDecisionReason"

    private static func isNonNullJSONValue(_ value: Any?) -> Bool {
        guard let value else {
            return false
        }
        return !(value is NSNull)
    }

    private static func jsonValue(from value: Any?) -> JSONValue? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        switch value {
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
            return .array(values.map { jsonValue(from: $0) ?? .null })
        case let object as [String: Any]:
            return .object(object.mapValues { jsonValue(from: $0) ?? .null })
        default:
            return nil
        }
    }

    private static func optionalStringEnumValue(_ value: Any?, allowedValues: Set<String>) -> String?? {
        guard let value else {
            return .some(nil)
        }
        if value is NSNull {
            return .some(nil)
        }
        guard let string = value as? String, allowedValues.contains(string) else {
            return nil
        }
        return .some(string)
    }

    private static let allHookEventWireNames: Set<String> = [
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PreCompact",
        "PostCompact",
        "SessionStart",
        "UserPromptSubmit",
        "Stop",
    ]

    private static func optionalStringValue(_ value: Any?) -> String?? {
        guard let value else {
            return .some(nil)
        }
        if value is NSNull {
            return .some(nil)
        }
        guard let string = value as? String else {
            return nil
        }
        return .some(string)
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
