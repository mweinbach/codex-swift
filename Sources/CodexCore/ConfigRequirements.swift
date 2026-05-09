import Foundation

public enum ConfigRequirementsParseError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLine(String)
    case invalidApprovalPolicy(String)
    case invalidSandboxMode(String)
    case invalidArray(String)

    public var description: String {
        switch self {
        case let .invalidLine(line):
            return "Invalid requirements line: \(line)"
        case let .invalidApprovalPolicy(value):
            return "Invalid approval policy requirement: \(value)"
        case let .invalidSandboxMode(value):
            return "Invalid sandbox mode requirement: \(value)"
        case let .invalidArray(key):
            return "Invalid array for \(key)"
        }
    }
}

public struct ConfigRequirements: Equatable, Sendable {
    public var approvalPolicy: Constrained<AskForApproval>
    public var sandboxPolicy: Constrained<SandboxPolicy>
    public var managedHooks: ManagedHooksRequirement?

    public init(
        approvalPolicy: Constrained<AskForApproval> = .allowAnyFromDefault(),
        sandboxPolicy: Constrained<SandboxPolicy> = .allowAny(.readOnly),
        managedHooks: ManagedHooksRequirement? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.managedHooks = managedHooks
    }

    public static let `default` = ConfigRequirements()
}

public struct ManagedHooksRequirement: Equatable, Sendable {
    public var value: ManagedHooksRequirementsToml
    public var source: HookSource
    public var sourceDescription: String

    public init(
        value: ManagedHooksRequirementsToml,
        source: HookSource = .unknown,
        sourceDescription: String = "managed requirements"
    ) {
        self.value = value
        self.source = source
        self.sourceDescription = sourceDescription
    }
}

public struct ManagedHooksRequirementsToml: Equatable, Sendable {
    public var managedDir: String?
    public var windowsManagedDir: String?
    public var hooks: ConfigValue

    public init(
        managedDir: String? = nil,
        windowsManagedDir: String? = nil,
        hooks: ConfigValue = .table([:])
    ) {
        self.managedDir = managedDir
        self.windowsManagedDir = windowsManagedDir
        self.hooks = hooks
    }

    public var isEmpty: Bool {
        managedDir == nil &&
            windowsManagedDir == nil &&
            hookHandlerCount == 0
    }

    public var hookHandlerCount: Int {
        guard case let .table(table) = hooks else {
            return 0
        }
        return HookEventName.allCases.reduce(0) { count, eventName in
            guard case let .array(groups)? = table[eventName.configLabel] else {
                return count
            }
            return count + groups.reduce(0) { groupCount, group in
                guard case let .table(groupTable) = group,
                      case let .array(handlers)? = groupTable["hooks"]
                else {
                    return groupCount
                }
                return groupCount + handlers.count
            }
        }
    }

    public var managedDirForCurrentPlatform: String? {
        #if os(Windows)
        return windowsManagedDir
        #else
        return managedDir
        #endif
    }
}

public struct ConfigRequirementsToml: Equatable, Sendable {
    public var allowedApprovalPolicies: [AskForApproval]?
    public var allowedSandboxModes: [SandboxModeRequirement]?
    public var hooks: ManagedHooksRequirementsToml?
    public var hooksSource: HookSource
    public var hooksSourceDescription: String

    public init(
        allowedApprovalPolicies: [AskForApproval]? = nil,
        allowedSandboxModes: [SandboxModeRequirement]? = nil,
        hooks: ManagedHooksRequirementsToml? = nil,
        hooksSource: HookSource = .unknown,
        hooksSourceDescription: String = "managed requirements"
    ) {
        self.allowedApprovalPolicies = allowedApprovalPolicies
        self.allowedSandboxModes = allowedSandboxModes
        self.hooks = hooks
        self.hooksSource = hooksSource
        self.hooksSourceDescription = hooksSourceDescription
    }

    public var isEmpty: Bool {
        allowedApprovalPolicies == nil &&
            allowedSandboxModes == nil &&
            hooks == nil
    }

    public mutating func mergeUnsetFields(from other: ConfigRequirementsToml) {
        if allowedApprovalPolicies == nil, let value = other.allowedApprovalPolicies {
            allowedApprovalPolicies = value
        }
        if allowedSandboxModes == nil, let value = other.allowedSandboxModes {
            allowedSandboxModes = value
        }
        if hooks == nil, let value = other.hooks {
            hooks = value
            hooksSource = other.hooksSource
            hooksSourceDescription = other.hooksSourceDescription
        }
    }

    public func requirements() throws -> ConfigRequirements {
        let approvalPolicy: Constrained<AskForApproval>
        if let policies = allowedApprovalPolicies {
            guard let first = policies.first else {
                throw ConstraintError.emptyField("allowed_approval_policies")
            }
            approvalPolicy = try Constrained.allowValues(
                first,
                allowed: policies,
                debugDescription: { $0.rustDebugDescription }
            )
        } else {
            approvalPolicy = .allowAnyFromDefault()
        }

        let defaultSandboxPolicy = SandboxPolicy.readOnly
        let sandboxPolicy: Constrained<SandboxPolicy>
        if let modes = allowedSandboxModes {
            guard modes.contains(.readOnly) else {
                throw ConstraintError.invalidValue(
                    "allowed_sandbox_modes",
                    "must include 'read-only' to allow any SandboxPolicy"
                )
            }

            sandboxPolicy = try Constrained(defaultSandboxPolicy) { candidate in
                let mode = SandboxModeRequirement(sandboxPolicy: candidate)
                if modes.contains(mode) {
                    return .success(())
                }
                return .failure(.invalidValue(
                    candidate.rustDebugDescription,
                    SandboxModeRequirement.rustDebugDescription(for: modes)
                ))
            }
        } else {
            sandboxPolicy = .allowAny(defaultSandboxPolicy)
        }

        let managedHooks = hooks.flatMap { hooks -> ManagedHooksRequirement? in
            guard hooks.hookHandlerCount > 0 else {
                return nil
            }
            return ManagedHooksRequirement(
                value: hooks,
                source: hooksSource,
                sourceDescription: hooksSourceDescription
            )
        }

        return ConfigRequirements(
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            managedHooks: managedHooks
        )
    }

    public static func parse(_ contents: String) throws -> ConfigRequirementsToml {
        var result = ConfigRequirementsToml()
        guard case let .table(table) = try ConfigTomlParser.parse(contents) else {
            return result
        }

        if let approvalValue = table["allowed_approval_policies"] {
            result.allowedApprovalPolicies = try parseApprovalPolicies(approvalValue)
        }
        if let sandboxValue = table["allowed_sandbox_modes"] {
            result.allowedSandboxModes = try parseSandboxModes(sandboxValue)
        }
        if let hooksValue = table["hooks"] {
            result.hooks = try parseManagedHooks(hooksValue)
        }

        return result
    }

    private static func parseApprovalPolicies(_ value: ConfigValue) throws -> [AskForApproval] {
        try stringArray(value, key: "allowed_approval_policies").map { value in
            guard let policy = AskForApproval(rawValue: value) else {
                throw ConfigRequirementsParseError.invalidApprovalPolicy(value)
            }
            return policy
        }
    }

    private static func parseSandboxModes(_ value: ConfigValue) throws -> [SandboxModeRequirement] {
        try stringArray(value, key: "allowed_sandbox_modes").map { value in
            guard let mode = SandboxModeRequirement(rawValue: value) else {
                throw ConfigRequirementsParseError.invalidSandboxMode(value)
            }
            return mode
        }
    }

    private static func stringArray(_ value: ConfigValue, key: String) throws -> [String] {
        guard case let .array(values) = value else {
            throw ConfigRequirementsParseError.invalidArray(key)
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw ConfigRequirementsParseError.invalidArray(key)
            }
            return string
        }
    }

    private static func parseManagedHooks(_ value: ConfigValue) throws -> ManagedHooksRequirementsToml {
        guard case var .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine("hooks")
        }
        let managedDir = stringValue(table.removeValue(forKey: "managed_dir"))
        let windowsManagedDir = stringValue(table.removeValue(forKey: "windows_managed_dir"))
        return ManagedHooksRequirementsToml(
            managedDir: managedDir,
            windowsManagedDir: windowsManagedDir,
            hooks: .table(table)
        )
    }

    private static func stringValue(_ value: ConfigValue?) -> String? {
        guard let value else {
            return nil
        }
        guard case let .string(string) = value else {
            return nil
        }
        return string
    }

}

extension ConfigRequirementsToml {
    public func appServerRequirementsObject() -> [String: Any] {
        [
            "allowedApprovalPolicies": allowedApprovalPolicies.map { $0.map(\.rawValue) } as Any? ?? NSNull(),
            "allowedApprovalsReviewers": NSNull(),
            "allowedSandboxModes": allowedSandboxModes.map { modes in
                modes.compactMap(\.appServerSandboxModeValue)
            } as Any? ?? NSNull(),
            "allowedWebSearchModes": NSNull(),
            "featureRequirements": NSNull(),
            "hooks": hooks.map { $0.appServerObject() } as Any? ?? NSNull(),
            "enforceResidency": NSNull(),
            "network": NSNull()
        ]
    }
}

extension ManagedHooksRequirementsToml {
    public func appServerObject() -> [String: Any] {
        var object: [String: Any] = [
            "managedDir": managedDir as Any? ?? NSNull(),
            "windowsManagedDir": windowsManagedDir as Any? ?? NSNull()
        ]
        for eventName in HookEventName.allCases {
            object[eventName.configLabel] = appServerGroups(for: eventName)
        }
        return object
    }

    private func appServerGroups(for eventName: HookEventName) -> [[String: Any]] {
        guard case let .table(table) = hooks,
              case let .array(groups)? = table[eventName.configLabel]
        else {
            return []
        }
        return groups.compactMap { groupValue in
            guard case let .table(group) = groupValue else {
                return nil
            }
            let matcher: Any = {
                guard case let .string(value)? = group["matcher"] else {
                    return NSNull()
                }
                return value
            }()
            let handlers = appServerHandlers(from: group["hooks"])
            return [
                "matcher": matcher,
                "hooks": handlers
            ]
        }
    }

    private func appServerHandlers(from value: ConfigValue?) -> [[String: Any]] {
        guard case let .array(values)? = value else {
            return []
        }
        return values.compactMap { value in
            guard case let .table(handler) = value,
                  case let .string(type)? = handler["type"]
            else {
                return nil
            }
            switch type {
            case "command":
                guard case let .string(command)? = handler["command"] else {
                    return nil
                }
                return [
                    "type": "command",
                    "command": command,
                    "timeoutSec": intValue(handler["timeout_sec"] ?? handler["timeout"]) as Any? ?? NSNull(),
                    "async": boolValue(handler["async"]) ?? false,
                    "statusMessage": stringValue(handler["status_message"] ?? handler["statusMessage"]) as Any? ?? NSNull()
                ]
            case "prompt", "agent":
                return ["type": type]
            default:
                return nil
            }
        }
    }

    private func stringValue(_ value: ConfigValue?) -> String? {
        guard case let .string(string)? = value else {
            return nil
        }
        return string
    }

    private func boolValue(_ value: ConfigValue?) -> Bool? {
        guard case let .bool(bool)? = value else {
            return nil
        }
        return bool
    }

    private func intValue(_ value: ConfigValue?) -> Int? {
        switch value {
        case let .integer(integer)?:
            return Int(integer)
        case let .double(double)? where double.rounded() == double:
            return Int(double)
        default:
            return nil
        }
    }
}

public enum SandboxModeRequirement: String, Codable, CaseIterable, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
    case externalSandbox = "external-sandbox"

    public init(sandboxMode: SandboxMode) {
        switch sandboxMode {
        case .readOnly:
            self = .readOnly
        case .workspaceWrite:
            self = .workspaceWrite
        case .dangerFullAccess:
            self = .dangerFullAccess
        }
    }

    public init(sandboxPolicy: SandboxPolicy) {
        switch sandboxPolicy {
        case .readOnly:
            self = .readOnly
        case .workspaceWrite:
            self = .workspaceWrite
        case .dangerFullAccess:
            self = .dangerFullAccess
        case .externalSandbox:
            self = .externalSandbox
        }
    }

    public var rustDebugDescription: String {
        switch self {
        case .readOnly:
            return "ReadOnly"
        case .workspaceWrite:
            return "WorkspaceWrite"
        case .dangerFullAccess:
            return "DangerFullAccess"
        case .externalSandbox:
            return "ExternalSandbox"
        }
    }

    public var appServerSandboxModeValue: String? {
        switch self {
        case .readOnly, .workspaceWrite, .dangerFullAccess:
            return rawValue
        case .externalSandbox:
            return nil
        }
    }

    public static func rustDebugDescription(for modes: [SandboxModeRequirement]) -> String {
        "[" + modes.map(\.rustDebugDescription).joined(separator: ", ") + "]"
    }
}

extension AskForApproval {
    public var rustDebugDescription: String {
        switch self {
        case .unlessTrusted:
            return "UnlessTrusted"
        case .onFailure:
            return "OnFailure"
        case .onRequest:
            return "OnRequest"
        case .never:
            return "Never"
        }
    }
}

extension SandboxPolicy {
    public var rustDebugDescription: String {
        switch self {
        case .dangerFullAccess:
            return "DangerFullAccess"
        case .readOnly:
            return "ReadOnly"
        case let .externalSandbox(networkAccess):
            return "ExternalSandbox { network_access: \(networkAccess.rustDebugDescription) }"
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            return "WorkspaceWrite { writable_roots: \(writableRoots), network_access: \(networkAccess), exclude_tmpdir_env_var: \(excludeTmpdirEnvVar), exclude_slash_tmp: \(excludeSlashTmp) }"
        }
    }
}

extension NetworkAccess {
    public var rustDebugDescription: String {
        switch self {
        case .restricted:
            return "Restricted"
        case .enabled:
            return "Enabled"
        }
    }
}
