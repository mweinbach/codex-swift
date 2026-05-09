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
    case invalidFilesystemRequirement(String)
    case invalidRemoteSandboxConfig(String)
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
        case let .invalidFilesystemRequirement(value):
            return "Invalid filesystem requirement: \(value)"
        case let .invalidRemoteSandboxConfig(value):
            return "Invalid remote sandbox config: \(value)"
        case let .invalidArray(key):
            return "Invalid array for \(key)"
        }
    }
}

public struct ConfigRequirements: Equatable, Sendable {
    public var approvalPolicy: Constrained<AskForApproval>
    public var approvalsReviewer: Constrained<ApprovalsReviewer>
    public var sandboxPolicy: Constrained<SandboxPolicy>
    public var managedHooks: ManagedHooksRequirement?
    public var mcpServers: [String: McpServerRequirement]?
    public var plugins: [String: PluginRequirementsToml]?
    public var execPolicy: ExecPolicy?
    public var filesystem: FilesystemConstraints?

    public init(
        approvalPolicy: Constrained<AskForApproval> = .allowAnyFromDefault(),
        approvalsReviewer: Constrained<ApprovalsReviewer> = .allowAnyFromDefault(),
        sandboxPolicy: Constrained<SandboxPolicy> = .allowAny(.readOnly),
        managedHooks: ManagedHooksRequirement? = nil,
        mcpServers: [String: McpServerRequirement]? = nil,
        plugins: [String: PluginRequirementsToml]? = nil,
        execPolicy: ExecPolicy? = nil,
        filesystem: FilesystemConstraints? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandboxPolicy = sandboxPolicy
        self.managedHooks = managedHooks
        self.mcpServers = mcpServers
        self.plugins = plugins
        self.execPolicy = execPolicy
        self.filesystem = filesystem
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

public enum McpServerIdentityRequirement: Equatable, Sendable {
    case command(command: String)
    case url(url: String)
}

public struct McpServerRequirement: Equatable, Sendable {
    public var identity: McpServerIdentityRequirement

    public init(identity: McpServerIdentityRequirement) {
        self.identity = identity
    }
}

public struct PluginRequirementsToml: Equatable, Sendable {
    public var mcpServers: [String: McpServerRequirement]?

    public init(mcpServers: [String: McpServerRequirement]? = nil) {
        self.mcpServers = mcpServers
    }

    public var isEmpty: Bool {
        mcpServers?.isEmpty ?? true
    }
}

public struct RequirementsExecPolicyToml: Equatable, Sendable {
    public var prefixRules: [RequirementsExecPolicyPrefixRuleToml]

    public init(prefixRules: [RequirementsExecPolicyPrefixRuleToml] = []) {
        self.prefixRules = prefixRules
    }

    public func toPolicy() throws -> ExecPolicy {
        guard !prefixRules.isEmpty else {
            throw ConstraintError.invalidRequirementsExecPolicy(reason: "rules prefix_rules cannot be empty")
        }

        var rulesByProgram: [String: [PrefixRule]] = [:]
        for (ruleIndex, rule) in prefixRules.enumerated() {
            if let justification = rule.justification,
               justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw ConstraintError.invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index \(ruleIndex) has an empty justification"
                )
            }
            guard !rule.pattern.isEmpty else {
                throw ConstraintError.invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index \(ruleIndex) has an empty pattern"
                )
            }

            let patternTokens = try rule.pattern.enumerated().map { tokenIndex, token in
                try token.patternToken(ruleIndex: ruleIndex, tokenIndex: tokenIndex)
            }
            let decision: ExecPolicyDecision
            switch rule.decision {
            case .some(.allow):
                throw ConstraintError.invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index \(ruleIndex) has decision 'allow', which is not permitted in requirements.toml: Codex merges these rules with other config and uses the most restrictive result (use 'prompt' or 'forbidden')"
                )
            case .some(.prompt):
                decision = .prompt
            case .some(.forbidden):
                decision = .forbidden
            case .none:
                throw ConstraintError.invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index \(ruleIndex) is missing a decision"
                )
            }

            guard let firstToken = patternTokens.first else {
                throw ConstraintError.invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index \(ruleIndex) has an empty pattern"
                )
            }
            let rest = Array(patternTokens.dropFirst())
            for head in firstToken.alternatives {
                rulesByProgram[head, default: []].append(PrefixRule(
                    pattern: PrefixPattern(first: head, rest: rest),
                    decision: decision,
                    justification: rule.justification
                ))
            }
        }
        return ExecPolicy(rulesByProgram: rulesByProgram)
    }
}

public struct RequirementsExecPolicyPrefixRuleToml: Equatable, Sendable {
    public var pattern: [RequirementsExecPolicyPatternTokenToml]
    public var decision: ExecPolicyDecision?
    public var justification: String?

    public init(
        pattern: [RequirementsExecPolicyPatternTokenToml] = [],
        decision: ExecPolicyDecision? = nil,
        justification: String? = nil
    ) {
        self.pattern = pattern
        self.decision = decision
        self.justification = justification
    }
}

public struct RequirementsExecPolicyPatternTokenToml: Equatable, Sendable {
    public var token: String?
    public var anyOf: [String]?

    public init(token: String? = nil, anyOf: [String]? = nil) {
        self.token = token
        self.anyOf = anyOf
    }

    fileprivate func patternToken(ruleIndex: Int, tokenIndex: Int) throws -> PatternToken {
        switch (token, anyOf) {
        case let (single?, nil):
            guard !single.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalidPatternToken(ruleIndex: ruleIndex, tokenIndex: tokenIndex, reason: "token cannot be empty")
            }
            return .single(single)
        case let (nil, alternatives?):
            guard !alternatives.isEmpty else {
                throw invalidPatternToken(ruleIndex: ruleIndex, tokenIndex: tokenIndex, reason: "any_of cannot be empty")
            }
            guard !alternatives.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw invalidPatternToken(
                    ruleIndex: ruleIndex,
                    tokenIndex: tokenIndex,
                    reason: "any_of cannot include empty tokens"
                )
            }
            return .alts(alternatives)
        case (.some, .some):
            throw invalidPatternToken(ruleIndex: ruleIndex, tokenIndex: tokenIndex, reason: "set either token or any_of, not both")
        case (nil, nil):
            throw invalidPatternToken(ruleIndex: ruleIndex, tokenIndex: tokenIndex, reason: "set either token or any_of")
        }
    }

    private func invalidPatternToken(ruleIndex: Int, tokenIndex: Int, reason: String) -> ConstraintError {
        .invalidRequirementsExecPolicy(
            reason: "rules prefix_rule at index \(ruleIndex) has an invalid pattern token at index \(tokenIndex): \(reason)"
        )
    }
}

public struct AppRequirementToml: Equatable, Sendable {
    public var enabled: Bool?

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }

    public var isEmpty: Bool {
        enabled == nil
    }
}

public struct AppsRequirementsToml: Equatable, Sendable {
    public var apps: [String: AppRequirementToml]

    public init(apps: [String: AppRequirementToml] = [:]) {
        self.apps = apps
    }

    public var isEmpty: Bool {
        apps.values.allSatisfy(\.isEmpty)
    }

    public mutating func mergeEnablementSettingsDescending(from lowerPrecedence: AppsRequirementsToml) {
        for (appID, incomingRequirement) in lowerPrecedence.apps {
            let higherRequirement = apps[appID, default: AppRequirementToml()]
            let mergedEnabled: Bool?
            if higherRequirement.enabled == false || incomingRequirement.enabled == false {
                mergedEnabled = false
            } else {
                mergedEnabled = higherRequirement.enabled ?? incomingRequirement.enabled
            }
            apps[appID] = AppRequirementToml(enabled: mergedEnabled)
        }
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

public struct FilesystemDenyReadPattern: Equatable, Hashable, Sendable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public static func fromInput(_ input: String, basePath: String = FileManager.default.currentDirectoryPath) throws -> Self {
        guard input.contains(where: Self.isGlobMetacharacter) else {
            return try Self(AbsolutePath.resolve(input, against: basePath).path)
        }

        let (directoryPrefix, suffix) = splitGlobPattern(input)
        let normalizedPrefix = try AbsolutePath.resolve(
            directoryPrefix.isEmpty ? "." : directoryPrefix,
            against: basePath
        ).path
        if suffix.isEmpty {
            return Self(normalizedPrefix)
        }
        return Self(normalizedPrefix == "/" ? "/\(suffix)" : "\(normalizedPrefix)/\(suffix)")
    }

    private static func splitGlobPattern(_ input: String) -> (String, String) {
        guard let globIndex = input.firstIndex(where: isGlobMetacharacter) else {
            return ("", input)
        }
        let prefix = input[..<globIndex]
        if let separatorIndex = prefix.indices.reversed().first(where: { prefix[$0] == "/" }) {
            if separatorIndex == prefix.startIndex {
                return ("/", String(input[input.index(after: separatorIndex)...]))
            }
            return (String(input[..<separatorIndex]), String(input[input.index(after: separatorIndex)...]))
        }
        return ("", input)
    }

    private static func isGlobMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }
}

public struct FilesystemRequirementsToml: Equatable, Sendable {
    public var denyRead: [FilesystemDenyReadPattern]?

    public init(denyRead: [FilesystemDenyReadPattern]? = nil) {
        self.denyRead = denyRead
    }

    public var isEmpty: Bool {
        denyRead?.isEmpty ?? true
    }
}

public struct PermissionsRequirementsToml: Equatable, Sendable {
    public var filesystem: FilesystemRequirementsToml?

    public init(filesystem: FilesystemRequirementsToml? = nil) {
        self.filesystem = filesystem
    }

    public var isEmpty: Bool {
        filesystem?.isEmpty ?? true
    }
}

public struct RemoteSandboxConfigToml: Equatable, Sendable {
    public var hostnamePatterns: [String]
    public var allowedSandboxModes: [SandboxModeRequirement]

    public init(hostnamePatterns: [String], allowedSandboxModes: [SandboxModeRequirement]) {
        self.hostnamePatterns = hostnamePatterns
        self.allowedSandboxModes = allowedSandboxModes
    }
}

public struct FilesystemConstraints: Equatable, Sendable {
    public var denyRead: [FilesystemDenyReadPattern]

    public init(denyRead: [FilesystemDenyReadPattern] = []) {
        self.denyRead = denyRead
    }
}

public struct ConfigRequirementsToml: Equatable, Sendable {
    public var allowedApprovalPolicies: [AskForApproval]?
    public var allowedApprovalsReviewers: [ApprovalsReviewer]?
    public var allowedSandboxModes: [SandboxModeRequirement]?
    public var remoteSandboxConfig: [RemoteSandboxConfigToml]?
    public var allowedWebSearchModes: [WebSearchModeRequirement]?
    public var featureRequirements: [String: Bool]?
    public var hooks: ManagedHooksRequirementsToml?
    public var hooksSource: HookSource
    public var hooksSourceDescription: String
    public var mcpServers: [String: McpServerRequirement]?
    public var plugins: [String: PluginRequirementsToml]?
    public var apps: AppsRequirementsToml?
    public var rules: RequirementsExecPolicyToml?
    public var enforceResidency: ResidencyRequirement?
    public var network: NetworkRequirementsToml?
    public var permissions: PermissionsRequirementsToml?
    public var guardianPolicyConfig: String?

    public init(
        allowedApprovalPolicies: [AskForApproval]? = nil,
        allowedApprovalsReviewers: [ApprovalsReviewer]? = nil,
        allowedSandboxModes: [SandboxModeRequirement]? = nil,
        remoteSandboxConfig: [RemoteSandboxConfigToml]? = nil,
        allowedWebSearchModes: [WebSearchModeRequirement]? = nil,
        featureRequirements: [String: Bool]? = nil,
        hooks: ManagedHooksRequirementsToml? = nil,
        hooksSource: HookSource = .unknown,
        hooksSourceDescription: String = "managed requirements",
        mcpServers: [String: McpServerRequirement]? = nil,
        plugins: [String: PluginRequirementsToml]? = nil,
        apps: AppsRequirementsToml? = nil,
        rules: RequirementsExecPolicyToml? = nil,
        enforceResidency: ResidencyRequirement? = nil,
        network: NetworkRequirementsToml? = nil,
        permissions: PermissionsRequirementsToml? = nil,
        guardianPolicyConfig: String? = nil
    ) {
        self.allowedApprovalPolicies = allowedApprovalPolicies
        self.allowedApprovalsReviewers = allowedApprovalsReviewers
        self.allowedSandboxModes = allowedSandboxModes
        self.remoteSandboxConfig = remoteSandboxConfig
        self.allowedWebSearchModes = allowedWebSearchModes
        self.featureRequirements = featureRequirements
        self.hooks = hooks
        self.hooksSource = hooksSource
        self.hooksSourceDescription = hooksSourceDescription
        self.mcpServers = mcpServers
        self.plugins = plugins
        self.apps = apps
        self.rules = rules
        self.enforceResidency = enforceResidency
        self.network = network
        self.permissions = permissions
        self.guardianPolicyConfig = guardianPolicyConfig
    }

    public var isEmpty: Bool {
        allowedApprovalPolicies == nil &&
            allowedApprovalsReviewers == nil &&
            allowedSandboxModes == nil &&
            remoteSandboxConfig == nil &&
            allowedWebSearchModes == nil &&
            featureRequirements == nil &&
            hooks == nil &&
            mcpServers == nil &&
            (plugins?.values.allSatisfy(\.isEmpty) ?? true) &&
            (apps?.isEmpty ?? true) &&
            rules == nil &&
            enforceResidency == nil &&
            network == nil &&
            (permissions?.isEmpty ?? true) &&
            (guardianPolicyConfig?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
        if remoteSandboxConfig == nil, let value = other.remoteSandboxConfig {
            remoteSandboxConfig = value
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
        if mcpServers == nil, let value = other.mcpServers {
            mcpServers = value
        }
        if plugins == nil, let value = other.plugins {
            plugins = value
        }
        if var mergedApps = apps {
            if let lowerPrecedenceApps = other.apps {
                if mergedApps.isEmpty {
                    apps = lowerPrecedenceApps.isEmpty ? nil : lowerPrecedenceApps
                } else {
                    mergedApps.mergeEnablementSettingsDescending(from: lowerPrecedenceApps)
                    apps = mergedApps.isEmpty ? nil : mergedApps
                }
            }
        } else if let lowerPrecedenceApps = other.apps {
            apps = lowerPrecedenceApps.isEmpty ? nil : lowerPrecedenceApps
        }
        if rules == nil, let value = other.rules {
            rules = value
        }
        if enforceResidency == nil, let value = other.enforceResidency {
            enforceResidency = value
        }
        if network == nil, let value = other.network {
            network = value
        }
        if permissions == nil, let value = other.permissions {
            permissions = value
        }
        if guardianPolicyConfig?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let value = other.guardianPolicyConfig,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guardianPolicyConfig = value
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

        let approvalsReviewer: Constrained<ApprovalsReviewer>
        if let reviewers = allowedApprovalsReviewers {
            guard let first = reviewers.first else {
                throw ConstraintError.emptyField("allowed_approvals_reviewers")
            }
            approvalsReviewer = try Constrained.allowValues(
                first,
                allowed: reviewers,
                debugDescription: { $0.rustDebugDescription }
            )
        } else {
            approvalsReviewer = .allowAnyFromDefault()
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

        let execPolicy = try rules?.toPolicy()
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
            approvalsReviewer: approvalsReviewer,
            sandboxPolicy: sandboxPolicy,
            managedHooks: managedHooks,
            mcpServers: mcpServers,
            plugins: plugins,
            execPolicy: execPolicy,
            filesystem: permissions?.filesystem.map { FilesystemConstraints(denyRead: $0.denyRead ?? []) }
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
        if let remoteSandboxValue = table["remote_sandbox_config"] {
            result.remoteSandboxConfig = try parseRemoteSandboxConfig(remoteSandboxValue)
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
        if let mcpServersValue = table["mcp_servers"] {
            result.mcpServers = try parseMcpServerRequirements(mcpServersValue, key: "mcp_servers")
        }
        if let pluginsValue = table["plugins"] {
            result.plugins = try parsePluginRequirements(pluginsValue)
        }
        if let appsValue = table["apps"] {
            result.apps = try parseAppsRequirements(appsValue)
        }
        if let rulesValue = table["rules"] {
            result.rules = try parseRequirementsExecPolicy(rulesValue)
        }
        if let residencyValue = table["enforce_residency"] {
            result.enforceResidency = try parseResidencyRequirement(residencyValue)
        }
        if let networkValue = table["experimental_network"] {
            result.network = try parseNetworkRequirements(networkValue)
        }
        if let permissionsValue = table["permissions"] {
            result.permissions = try parsePermissionsRequirements(permissionsValue)
        }
        if let guardianPolicyConfigValue = table["guardian_policy_config"] {
            result.guardianPolicyConfig = try stringValue(
                guardianPolicyConfigValue,
                key: "guardian_policy_config"
            )
        }

        return result
    }

    public mutating func applyRemoteSandboxConfig(hostname: String?) {
        guard let remoteSandboxConfig,
              let hostname = Self.normalizedHostname(hostname),
              let matchedConfig = remoteSandboxConfig.first(where: { config in
                  config.hostnamePatterns.contains { pattern in
                      guard let pattern = Self.normalizedHostname(pattern) else {
                          return false
                      }
                      return Self.wildcardMatch(pattern: pattern, text: hostname)
                  }
              })
        else {
            return
        }

        allowedSandboxModes = matchedConfig.allowedSandboxModes
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

    private static func parseRemoteSandboxConfig(_ value: ConfigValue) throws -> [RemoteSandboxConfigToml] {
        guard case let .array(entries) = value else {
            throw ConfigRequirementsParseError.invalidRemoteSandboxConfig("remote_sandbox_config")
        }
        return try entries.enumerated().map { index, entry in
            guard case let .table(table) = entry else {
                throw ConfigRequirementsParseError.invalidRemoteSandboxConfig("remote_sandbox_config[\(index)]")
            }
            guard let hostnamePatternsValue = table["hostname_patterns"] else {
                throw ConfigRequirementsParseError.invalidRemoteSandboxConfig("remote_sandbox_config.hostname_patterns")
            }
            guard let allowedSandboxModesValue = table["allowed_sandbox_modes"] else {
                throw ConfigRequirementsParseError.invalidRemoteSandboxConfig("remote_sandbox_config.allowed_sandbox_modes")
            }
            return RemoteSandboxConfigToml(
                hostnamePatterns: try stringArray(hostnamePatternsValue, key: "remote_sandbox_config.hostname_patterns"),
                allowedSandboxModes: try parseSandboxModes(allowedSandboxModesValue)
            )
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

    private static func parsePermissionsRequirements(_ value: ConfigValue) throws -> PermissionsRequirementsToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidFilesystemRequirement("permissions")
        }
        let filesystem = try table["filesystem"].map(parseFilesystemRequirements)
        return PermissionsRequirementsToml(filesystem: filesystem)
    }

    private static func parseAppsRequirements(_ value: ConfigValue) throws -> AppsRequirementsToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine("apps")
        }
        var apps: [String: AppRequirementToml] = [:]
        for appID in table.keys.sorted() {
            guard case let .table(appTable) = table[appID] else {
                throw ConfigRequirementsParseError.invalidLine("apps.\(appID)")
            }
            apps[appID] = AppRequirementToml(
                enabled: try optionalBool(appTable["enabled"], key: "apps.\(appID).enabled")
            )
        }
        return AppsRequirementsToml(apps: apps)
    }

    private static func parsePluginRequirements(_ value: ConfigValue) throws -> [String: PluginRequirementsToml] {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine("plugins")
        }
        var plugins: [String: PluginRequirementsToml] = [:]
        for pluginID in table.keys.sorted() {
            guard case let .table(pluginTable) = table[pluginID] else {
                throw ConfigRequirementsParseError.invalidLine("plugins.\(pluginID)")
            }
            let mcpServers = try pluginTable["mcp_servers"].map {
                try parseMcpServerRequirements($0, key: "plugins.\(pluginID).mcp_servers")
            }
            plugins[pluginID] = PluginRequirementsToml(mcpServers: mcpServers)
        }
        return plugins
    }

    private static func parseRequirementsExecPolicy(_ value: ConfigValue) throws -> RequirementsExecPolicyToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine("rules")
        }
        guard let prefixRulesValue = table["prefix_rules"] else {
            return RequirementsExecPolicyToml()
        }
        guard case let .array(ruleValues) = prefixRulesValue else {
            throw ConfigRequirementsParseError.invalidLine("rules.prefix_rules")
        }
        let prefixRules = try ruleValues.enumerated().map { ruleIndex, ruleValue in
            try parseRequirementsPrefixRule(ruleValue, ruleIndex: ruleIndex)
        }
        return RequirementsExecPolicyToml(prefixRules: prefixRules)
    }

    private static func parseRequirementsPrefixRule(
        _ value: ConfigValue,
        ruleIndex: Int
    ) throws -> RequirementsExecPolicyPrefixRuleToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine("rules.prefix_rules[\(ruleIndex)]")
        }
        let pattern = try table["pattern"].map { value in
            try parseRequirementsPattern(value, ruleIndex: ruleIndex)
        } ?? []
        let decision = try table["decision"].map(parseRequirementsDecision)
        let justification = try table["justification"].map {
            try stringValue($0, key: "rules.prefix_rules[\(ruleIndex)].justification")
        }
        return RequirementsExecPolicyPrefixRuleToml(
            pattern: pattern,
            decision: decision,
            justification: justification
        )
    }

    private static func parseRequirementsPattern(
        _ value: ConfigValue,
        ruleIndex: Int
    ) throws -> [RequirementsExecPolicyPatternTokenToml] {
        guard case let .array(tokenValues) = value else {
            throw ConfigRequirementsParseError.invalidLine("rules.prefix_rules[\(ruleIndex)].pattern")
        }
        return try tokenValues.enumerated().map { tokenIndex, tokenValue in
            try parseRequirementsPatternToken(tokenValue, ruleIndex: ruleIndex, tokenIndex: tokenIndex)
        }
    }

    private static func parseRequirementsPatternToken(
        _ value: ConfigValue,
        ruleIndex: Int,
        tokenIndex: Int
    ) throws -> RequirementsExecPolicyPatternTokenToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine(
                "rules.prefix_rules[\(ruleIndex)].pattern[\(tokenIndex)]"
            )
        }
        let token = try table["token"].map {
            try stringValue($0, key: "rules.prefix_rules[\(ruleIndex)].pattern[\(tokenIndex)].token")
        }
        let anyOf = try table["any_of"].map {
            try stringArray($0, key: "rules.prefix_rules[\(ruleIndex)].pattern[\(tokenIndex)].any_of")
        }
        return RequirementsExecPolicyPatternTokenToml(token: token, anyOf: anyOf)
    }

    private static func parseRequirementsDecision(_ value: ConfigValue) throws -> ExecPolicyDecision {
        guard case let .string(rawValue) = value,
              let decision = ExecPolicyDecision(rawValue: rawValue)
        else {
            throw ConfigRequirementsParseError.invalidLine("rules.prefix_rules.decision")
        }
        return decision
    }

    private static func parseMcpServerRequirements(
        _ value: ConfigValue,
        key: String
    ) throws -> [String: McpServerRequirement] {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidLine(key)
        }
        var servers: [String: McpServerRequirement] = [:]
        for serverName in table.keys.sorted() {
            guard case let .table(serverTable) = table[serverName] else {
                throw ConfigRequirementsParseError.invalidLine("\(key).\(serverName)")
            }
            guard case let .table(identityTable)? = serverTable["identity"] else {
                throw ConfigRequirementsParseError.invalidLine("\(key).\(serverName).identity")
            }
            servers[serverName] = McpServerRequirement(
                identity: try parseMcpServerIdentity(identityTable, key: "\(key).\(serverName).identity")
            )
        }
        return servers
    }

    private static func parseMcpServerIdentity(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> McpServerIdentityRequirement {
        if let commandValue = table["command"] {
            guard case let .string(command) = commandValue else {
                throw ConfigRequirementsParseError.invalidLine("\(key).command")
            }
            return .command(command: command)
        }
        if let urlValue = table["url"] {
            guard case let .string(url) = urlValue else {
                throw ConfigRequirementsParseError.invalidLine("\(key).url")
            }
            return .url(url: url)
        }
        throw ConfigRequirementsParseError.invalidLine(key)
    }

    private static func parseFilesystemRequirements(_ value: ConfigValue) throws -> FilesystemRequirementsToml {
        guard case let .table(table) = value else {
            throw ConfigRequirementsParseError.invalidFilesystemRequirement("permissions.filesystem")
        }
        let denyRead = try table["deny_read"].map { value in
            try stringArray(value, key: "permissions.filesystem.deny_read").map {
                try FilesystemDenyReadPattern.fromInput($0)
            }
        }
        return FilesystemRequirementsToml(denyRead: denyRead)
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

    private static func stringValue(_ value: ConfigValue, key: String) throws -> String {
        guard case let .string(string) = value else {
            throw ConfigRequirementsParseError.invalidLine(key)
        }
        return string
    }

    private static func normalizedHostname(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingSuffix(".")
            .lowercased(),
              !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }

    private static func wildcardMatch(pattern: String, text: String) -> Bool {
        let pattern = Array(pattern)
        let text = Array(text)
        var memo: [WildcardMemoKey: Bool] = [:]

        func matches(_ patternIndex: Int, _ textIndex: Int) -> Bool {
            let key = WildcardMemoKey(patternIndex: patternIndex, textIndex: textIndex)
            if let cached = memo[key] {
                return cached
            }

            let result: Bool
            if patternIndex == pattern.count {
                result = textIndex == text.count
            } else {
                switch pattern[patternIndex] {
                case "*":
                    result = matches(patternIndex + 1, textIndex) ||
                        (textIndex < text.count && matches(patternIndex, textIndex + 1))
                case "?":
                    result = textIndex < text.count && matches(patternIndex + 1, textIndex + 1)
                default:
                    result = textIndex < text.count &&
                        pattern[patternIndex] == text[textIndex] &&
                        matches(patternIndex + 1, textIndex + 1)
                }
            }

            memo[key] = result
            return result
        }

        return matches(0, 0)
    }

}

private struct WildcardMemoKey: Hashable {
    var patternIndex: Int
    var textIndex: Int
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var result = self
        while result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
        }
        return result
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
