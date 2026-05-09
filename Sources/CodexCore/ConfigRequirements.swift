import Foundation

public enum ConfigRequirementsParseError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLine(String)
    case invalidApprovalPolicy(String)
    case invalidApprovalsReviewer(String)
    case invalidSandboxMode(String)
    case invalidWebSearchMode(String)
    case invalidFeatureRequirements(String)
    case invalidResidencyRequirement(String)
    case invalidNetworkRequirements(String)
    case invalidNetworkDomainPermission(String)
    case invalidNetworkUnixSocketPermission(String)
    case invalidArray(String)

    public var description: String {
        switch self {
        case let .invalidLine(line):
            return "Invalid requirements line: \(line)"
        case let .invalidApprovalPolicy(value):
            return "Invalid approval policy requirement: \(value)"
        case let .invalidApprovalsReviewer(value):
            return "Invalid approvals reviewer requirement: \(value)"
        case let .invalidSandboxMode(value):
            return "Invalid sandbox mode requirement: \(value)"
        case let .invalidWebSearchMode(value):
            return "Invalid web search mode requirement: \(value)"
        case let .invalidFeatureRequirements(value):
            return "Invalid feature requirements: \(value)"
        case let .invalidResidencyRequirement(value):
            return "Invalid residency requirement: \(value)"
        case let .invalidNetworkRequirements(value):
            return "Invalid network requirements: \(value)"
        case let .invalidNetworkDomainPermission(value):
            return "Invalid network domain permission: \(value)"
        case let .invalidNetworkUnixSocketPermission(value):
            return "Invalid network unix socket permission: \(value)"
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

public enum WebSearchModeRequirement: String, Equatable, Sendable, CaseIterable {
    case disabled
    case cached
    case live
}

public enum ResidencyRequirement: String, Equatable, Sendable {
    case us
}

public enum NetworkDomainPermissionRequirement: String, Equatable, Sendable {
    case allow
    case deny
}

public enum NetworkUnixSocketPermissionRequirement: String, Equatable, Sendable {
    case allow
    case none
}

public struct NetworkRequirementsToml: Equatable, Sendable {
    public var enabled: Bool?
    public var httpPort: UInt16?
    public var socksPort: UInt16?
    public var allowUpstreamProxy: Bool?
    public var dangerouslyAllowNonLoopbackProxy: Bool?
    public var dangerouslyAllowAllUnixSockets: Bool?
    public var domains: [String: NetworkDomainPermissionRequirement]?
    public var managedAllowedDomainsOnly: Bool?
    public var unixSockets: [String: NetworkUnixSocketPermissionRequirement]?
    public var allowLocalBinding: Bool?

    public init(
        enabled: Bool? = nil,
        httpPort: UInt16? = nil,
        socksPort: UInt16? = nil,
        allowUpstreamProxy: Bool? = nil,
        dangerouslyAllowNonLoopbackProxy: Bool? = nil,
        dangerouslyAllowAllUnixSockets: Bool? = nil,
        domains: [String: NetworkDomainPermissionRequirement]? = nil,
        managedAllowedDomainsOnly: Bool? = nil,
        unixSockets: [String: NetworkUnixSocketPermissionRequirement]? = nil,
        allowLocalBinding: Bool? = nil
    ) {
        self.enabled = enabled
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.domains = domains
        self.managedAllowedDomainsOnly = managedAllowedDomainsOnly
        self.unixSockets = unixSockets
        self.allowLocalBinding = allowLocalBinding
    }
}

public struct ConfigRequirementsToml: Equatable, Sendable {
    public var allowedApprovalPolicies: [AskForApproval]?
    public var allowedApprovalsReviewers: [ApprovalsReviewer]?
    public var allowedSandboxModes: [SandboxModeRequirement]?
    public var allowedWebSearchModes: [WebSearchModeRequirement]?
    public var featureRequirements: [String: Bool]?
    public var hooks: ManagedHooksRequirementsToml?
    public var hooksSource: HookSource
    public var hooksSourceDescription: String
    public var enforceResidency: ResidencyRequirement?
    public var network: NetworkRequirementsToml?

    public init(
        allowedApprovalPolicies: [AskForApproval]? = nil,
        allowedApprovalsReviewers: [ApprovalsReviewer]? = nil,
        allowedSandboxModes: [SandboxModeRequirement]? = nil,
        allowedWebSearchModes: [WebSearchModeRequirement]? = nil,
        featureRequirements: [String: Bool]? = nil,
        hooks: ManagedHooksRequirementsToml? = nil,
        hooksSource: HookSource = .unknown,
        hooksSourceDescription: String = "managed requirements",
        enforceResidency: ResidencyRequirement? = nil,
        network: NetworkRequirementsToml? = nil
    ) {
        self.allowedApprovalPolicies = allowedApprovalPolicies
        self.allowedApprovalsReviewers = allowedApprovalsReviewers
        self.allowedSandboxModes = allowedSandboxModes
        self.allowedWebSearchModes = allowedWebSearchModes
        self.featureRequirements = featureRequirements
        self.hooks = hooks
        self.hooksSource = hooksSource
        self.hooksSourceDescription = hooksSourceDescription
        self.enforceResidency = enforceResidency
        self.network = network
    }

    public var isEmpty: Bool {
        allowedApprovalPolicies == nil &&
            allowedApprovalsReviewers == nil &&
            allowedSandboxModes == nil &&
            allowedWebSearchModes == nil &&
            featureRequirements == nil &&
            hooks == nil &&
            enforceResidency == nil &&
            network == nil
    }

    public mutating func mergeUnsetFields(from other: ConfigRequirementsToml) {
        if allowedApprovalPolicies == nil, let value = other.allowedApprovalPolicies {
            allowedApprovalPolicies = value
        }
        if allowedApprovalsReviewers == nil, let value = other.allowedApprovalsReviewers {
            allowedApprovalsReviewers = value
        }
        if allowedSandboxModes == nil, let value = other.allowedSandboxModes {
            allowedSandboxModes = value
        }
        if allowedWebSearchModes == nil, let value = other.allowedWebSearchModes {
            allowedWebSearchModes = value
        }
        if featureRequirements == nil, let value = other.featureRequirements {
            featureRequirements = value
        }
        if hooks == nil, let value = other.hooks {
            hooks = value
            hooksSource = other.hooksSource
            hooksSourceDescription = other.hooksSourceDescription
        }
        if enforceResidency == nil, let value = other.enforceResidency {
            enforceResidency = value
        }
        if network == nil, let value = other.network {
            network = value
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
        if let reviewerValue = table["allowed_approvals_reviewers"] {
            result.allowedApprovalsReviewers = try parseApprovalsReviewers(reviewerValue)
        }
        if let sandboxValue = table["allowed_sandbox_modes"] {
            result.allowedSandboxModes = try parseSandboxModes(sandboxValue)
        }
        if let webSearchValue = table["allowed_web_search_modes"] {
            result.allowedWebSearchModes = try parseWebSearchModes(webSearchValue)
        }
        if let featureValue = table["features"] ?? table["feature_requirements"] {
            result.featureRequirements = try parseFeatureRequirements(featureValue)
        }
        if let hooksValue = table["hooks"] {
            result.hooks = try parseManagedHooks(hooksValue)
        }
        if let residencyValue = table["enforce_residency"] {
            result.enforceResidency = try parseResidencyRequirement(residencyValue)
        }
        if let networkValue = table["experimental_network"] {
            result.network = try parseNetworkRequirements(networkValue)
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

    private static func parseApprovalsReviewers(_ value: ConfigValue) throws -> [ApprovalsReviewer] {
        try stringArray(value, key: "allowed_approvals_reviewers").map { value in
            switch value {
            case "user":
                return .user
            case "guardian_subagent", "auto_review":
                return .autoReview
            default:
                throw ConfigRequirementsParseError.invalidApprovalsReviewer(value)
            }
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

    private static func parseWebSearchModes(_ value: ConfigValue) throws -> [WebSearchModeRequirement] {
        try stringArray(value, key: "allowed_web_search_modes").map { value in
            guard let mode = WebSearchModeRequirement(rawValue: value) else {
                throw ConfigRequirementsParseError.invalidWebSearchMode(value)
            }
            return mode
        }
    }

    private static func parseFeatureRequirements(_ value: ConfigValue) throws -> [String: Bool] {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidFeatureRequirements("features")
        }
        var requirements: [String: Bool] = [:]
        for (key, value) in table {
            guard case let .bool(enabled) = value else {
                throw ConfigRequirementsParseError.invalidFeatureRequirements(key)
            }
            requirements[key] = enabled
        }
        return requirements
    }

    private static func parseResidencyRequirement(_ value: ConfigValue) throws -> ResidencyRequirement {
        guard case let .string(rawValue) = value,
              let requirement = ResidencyRequirement(rawValue: rawValue)
        else {
            throw ConfigRequirementsParseError.invalidResidencyRequirement(String(describing: value))
        }
        return requirement
    }

    private static func parseNetworkRequirements(_ value: ConfigValue) throws -> NetworkRequirementsToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidNetworkRequirements("experimental_network")
        }

        if table["domains"] != nil && (table["allowed_domains"] != nil || table["denied_domains"] != nil) {
            throw ConfigRequirementsParseError.invalidNetworkRequirements(
                "`experimental_network.domains` cannot be combined with legacy `allowed_domains` or `denied_domains`"
            )
        }
        if table["unix_sockets"] != nil && table["allow_unix_sockets"] != nil {
            throw ConfigRequirementsParseError.invalidNetworkRequirements(
                "`experimental_network.unix_sockets` cannot be combined with legacy `allow_unix_sockets`"
            )
        }

        return NetworkRequirementsToml(
            enabled: try optionalBool(table["enabled"], key: "experimental_network.enabled"),
            httpPort: try optionalPort(table["http_port"], key: "experimental_network.http_port"),
            socksPort: try optionalPort(table["socks_port"], key: "experimental_network.socks_port"),
            allowUpstreamProxy: try optionalBool(
                table["allow_upstream_proxy"],
                key: "experimental_network.allow_upstream_proxy"
            ),
            dangerouslyAllowNonLoopbackProxy: try optionalBool(
                table["dangerously_allow_non_loopback_proxy"],
                key: "experimental_network.dangerously_allow_non_loopback_proxy"
            ),
            dangerouslyAllowAllUnixSockets: try optionalBool(
                table["dangerously_allow_all_unix_sockets"],
                key: "experimental_network.dangerously_allow_all_unix_sockets"
            ),
            domains: try parseNetworkDomains(table),
            managedAllowedDomainsOnly: try optionalBool(
                table["managed_allowed_domains_only"],
                key: "experimental_network.managed_allowed_domains_only"
            ),
            unixSockets: try parseNetworkUnixSockets(table),
            allowLocalBinding: try optionalBool(
                table["allow_local_binding"],
                key: "experimental_network.allow_local_binding"
            )
        )
    }

    private static func parseNetworkDomains(_ table: [String: ConfigValue]) throws
        -> [String: NetworkDomainPermissionRequirement]?
    {
        if let domainsValue = table["domains"] {
            guard case let .table(domainsTable) = domainsValue else {
                throw ConfigRequirementsParseError.invalidNetworkRequirements("experimental_network.domains")
            }
            var domains: [String: NetworkDomainPermissionRequirement] = [:]
            for (pattern, value) in domainsTable {
                guard case let .string(rawValue) = value,
                      let permission = NetworkDomainPermissionRequirement(rawValue: rawValue)
                else {
                    throw ConfigRequirementsParseError.invalidNetworkDomainPermission(pattern)
                }
                domains[pattern] = permission
            }
            return domains
        }

        var domains: [String: NetworkDomainPermissionRequirement] = [:]
        for pattern in try stringArray(table["allowed_domains"] ?? .array([]), key: "allowed_domains") {
            domains[pattern] = .allow
        }
        for pattern in try stringArray(table["denied_domains"] ?? .array([]), key: "denied_domains") {
            domains[pattern] = .deny
        }
        return domains.isEmpty ? nil : domains
    }

    private static func parseNetworkUnixSockets(_ table: [String: ConfigValue]) throws
        -> [String: NetworkUnixSocketPermissionRequirement]?
    {
        if let socketsValue = table["unix_sockets"] {
            guard case let .table(socketsTable) = socketsValue else {
                throw ConfigRequirementsParseError.invalidNetworkRequirements("experimental_network.unix_sockets")
            }
            var sockets: [String: NetworkUnixSocketPermissionRequirement] = [:]
            for (path, value) in socketsTable {
                guard case let .string(rawValue) = value,
                      let permission = NetworkUnixSocketPermissionRequirement(rawValue: rawValue)
                else {
                    throw ConfigRequirementsParseError.invalidNetworkUnixSocketPermission(path)
                }
                sockets[path] = permission
            }
            return sockets
        }

        let sockets = try stringArray(
            table["allow_unix_sockets"] ?? .array([]),
            key: "allow_unix_sockets"
        ).reduce(into: [String: NetworkUnixSocketPermissionRequirement]()) { result, path in
            result[path] = .allow
        }
        return sockets.isEmpty ? nil : sockets
    }

    private static func optionalBool(_ value: ConfigValue?, key: String) throws -> Bool? {
        guard let value else {
            return nil
        }
        guard case let .bool(boolValue) = value else {
            throw ConfigRequirementsParseError.invalidNetworkRequirements(key)
        }
        return boolValue
    }

    private static func optionalPort(_ value: ConfigValue?, key: String) throws -> UInt16? {
        guard let value else {
            return nil
        }
        guard case let .integer(port) = value,
              port >= 0,
              port <= Int64(UInt16.max)
        else {
            throw ConfigRequirementsParseError.invalidNetworkRequirements(key)
        }
        return UInt16(port)
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
            "allowedApprovalsReviewers": allowedApprovalsReviewers.map {
                $0.map(\.appServerRawValue)
            } as Any? ?? NSNull(),
            "allowedSandboxModes": allowedSandboxModes.map { modes in
                modes.compactMap(\.appServerSandboxModeValue)
            } as Any? ?? NSNull(),
            "allowedWebSearchModes": allowedWebSearchModes.map { modes in
                var normalized = modes.map(\.rawValue)
                if !normalized.contains(WebSearchModeRequirement.disabled.rawValue) {
                    normalized.append(WebSearchModeRequirement.disabled.rawValue)
                }
                return normalized
            } as Any? ?? NSNull(),
            "featureRequirements": featureRequirements as Any? ?? NSNull(),
            "hooks": hooks.map { $0.appServerObject() } as Any? ?? NSNull(),
            "enforceResidency": enforceResidency?.rawValue as Any? ?? NSNull(),
            "network": network.map { $0.appServerObject() } as Any? ?? NSNull()
        ]
    }
}

extension NetworkRequirementsToml {
    public func appServerObject() -> [String: Any] {
        [
            "enabled": enabled as Any? ?? NSNull(),
            "httpPort": httpPort.map { Int($0) } as Any? ?? NSNull(),
            "socksPort": socksPort.map { Int($0) } as Any? ?? NSNull(),
            "allowUpstreamProxy": allowUpstreamProxy as Any? ?? NSNull(),
            "dangerouslyAllowNonLoopbackProxy": dangerouslyAllowNonLoopbackProxy as Any? ?? NSNull(),
            "dangerouslyAllowAllUnixSockets": dangerouslyAllowAllUnixSockets as Any? ?? NSNull(),
            "domains": domains.map { domainObject($0) } as Any? ?? NSNull(),
            "managedAllowedDomainsOnly": managedAllowedDomainsOnly as Any? ?? NSNull(),
            "allowedDomains": allowedDomains as Any? ?? NSNull(),
            "deniedDomains": deniedDomains as Any? ?? NSNull(),
            "unixSockets": unixSockets.map { unixSocketObject($0) } as Any? ?? NSNull(),
            "allowUnixSockets": allowUnixSockets as Any? ?? NSNull(),
            "allowLocalBinding": allowLocalBinding as Any? ?? NSNull()
        ]
    }

    private var allowedDomains: [String]? {
        guard let domains else {
            return nil
        }
        let values = domains
            .filter { $0.value == .allow }
            .map(\.key)
            .sorted()
        return values.isEmpty ? nil : values
    }

    private var deniedDomains: [String]? {
        guard let domains else {
            return nil
        }
        let values = domains
            .filter { $0.value == .deny }
            .map(\.key)
            .sorted()
        return values.isEmpty ? nil : values
    }

    private var allowUnixSockets: [String]? {
        guard let unixSockets else {
            return nil
        }
        let values = unixSockets
            .filter { $0.value == .allow }
            .map(\.key)
            .sorted()
        return values.isEmpty ? nil : values
    }

    private func domainObject(_ domains: [String: NetworkDomainPermissionRequirement]) -> [String: Any] {
        domains.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = entry.value.rawValue
        }
    }

    private func unixSocketObject(_ sockets: [String: NetworkUnixSocketPermissionRequirement]) -> [String: Any] {
        sockets.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = entry.value.rawValue
        }
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
        case let .granular(config):
            return "Granular(\(config.rustDebugDescription))"
        case .never:
            return "Never"
        }
    }
}

extension GranularApprovalConfig {
    public var rustDebugDescription: String {
        "GranularApprovalConfig { sandbox_approval: \(sandboxApproval), rules: \(rules), skill_approval: \(skillApproval), request_permissions: \(requestPermissions), mcp_elicitations: \(mcpElicitations) }"
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
