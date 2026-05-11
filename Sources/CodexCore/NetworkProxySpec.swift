import Foundation

public enum NetworkMode: String, Equatable, Sendable {
    case limited
    case full
}

public enum NetworkDomainPermission: String, Equatable, Comparable, Sendable {
    case none
    case allow
    case deny

    public static func < (lhs: NetworkDomainPermission, rhs: NetworkDomainPermission) -> Bool {
        lhs.precedence < rhs.precedence
    }

    private var precedence: Int {
        switch self {
        case .none:
            0
        case .allow:
            1
        case .deny:
            2
        }
    }
}

public struct NetworkDomainPermissionEntry: Equatable, Sendable {
    public var pattern: String
    public var permission: NetworkDomainPermission

    public init(pattern: String, permission: NetworkDomainPermission) {
        self.pattern = pattern
        self.permission = permission
    }
}

public struct NetworkDomainPermissions: Equatable, Sendable {
    public var entries: [NetworkDomainPermissionEntry]

    public init(entries: [NetworkDomainPermissionEntry] = []) {
        self.entries = entries
    }

    public func entries(with permission: NetworkDomainPermission) -> [String]? {
        let values = effectiveEntries()
            .filter { $0.permission == permission }
            .map(\.pattern)
        return values.isEmpty ? nil : values
    }

    public func effectiveEntries() -> [NetworkDomainPermissionEntry] {
        var order: [String] = []
        var effective: [String: NetworkDomainPermission] = [:]
        for entry in entries {
            if effective[entry.pattern] == nil {
                order.append(entry.pattern)
            }
            if let existing = effective[entry.pattern] {
                effective[entry.pattern] = max(existing, entry.permission)
            } else {
                effective[entry.pattern] = entry.permission
            }
        }
        return order.compactMap { pattern in
            effective[pattern].map { NetworkDomainPermissionEntry(pattern: pattern, permission: $0) }
        }
    }
}

public enum NetworkUnixSocketPermission: String, Equatable, Sendable {
    case allow
    case none
}

public struct NetworkProxySettings: Equatable, Sendable {
    public var enabled: Bool
    public var proxyURL: String
    public var enableSocks5: Bool
    public var socksURL: String
    public var enableSocks5UDP: Bool
    public var allowUpstreamProxy: Bool
    public var dangerouslyAllowNonLoopbackProxy: Bool
    public var dangerouslyAllowAllUnixSockets: Bool
    public var mode: NetworkMode
    public var domains: NetworkDomainPermissions?
    public var unixSockets: [String: NetworkUnixSocketPermission]?
    public var allowLocalBinding: Bool

    public init(
        enabled: Bool = false,
        proxyURL: String = "http://127.0.0.1:3128",
        enableSocks5: Bool = true,
        socksURL: String = "http://127.0.0.1:8081",
        enableSocks5UDP: Bool = true,
        allowUpstreamProxy: Bool = true,
        dangerouslyAllowNonLoopbackProxy: Bool = false,
        dangerouslyAllowAllUnixSockets: Bool = false,
        mode: NetworkMode = .full,
        domains: NetworkDomainPermissions? = nil,
        unixSockets: [String: NetworkUnixSocketPermission]? = nil,
        allowLocalBinding: Bool = false
    ) {
        self.enabled = enabled
        self.proxyURL = proxyURL
        self.enableSocks5 = enableSocks5
        self.socksURL = socksURL
        self.enableSocks5UDP = enableSocks5UDP
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.mode = mode
        self.domains = domains
        self.unixSockets = unixSockets
        self.allowLocalBinding = allowLocalBinding
    }

    public func allowedDomains() -> [String]? {
        domains?.entries(with: .allow)
    }

    public func deniedDomains() -> [String]? {
        domains?.entries(with: .deny)
    }

    public func allowedUnixSockets() -> [String] {
        unixSockets?
            .filter { $0.value == .allow }
            .map(\.key)
            .sorted() ?? []
    }

    public mutating func setAllowedDomains(_ allowedDomains: [String]) {
        setDomainEntries(allowedDomains, permission: .allow)
    }

    public mutating func setDeniedDomains(_ deniedDomains: [String]) {
        setDomainEntries(deniedDomains, permission: .deny)
    }

    public mutating func upsertDomainPermission(_ pattern: String, permission: NetworkDomainPermission) {
        var entries = domains?.entries ?? []
        let normalized = Self.normalizeHost(pattern)
        entries.removeAll { Self.normalizeHost($0.pattern) == normalized }
        entries.append(NetworkDomainPermissionEntry(pattern: pattern, permission: permission))
        domains = entries.isEmpty ? nil : NetworkDomainPermissions(entries: entries)
    }

    public mutating func setAllowedUnixSockets(_ sockets: [String]) {
        var entries = unixSockets ?? [:]
        entries = entries.filter { $0.value != .allow }
        for socket in sockets {
            entries[socket] = .allow
        }
        unixSockets = entries.isEmpty ? nil : entries
    }

    private mutating func setDomainEntries(_ values: [String], permission: NetworkDomainPermission) {
        var entries = domains?.entries ?? []
        entries.removeAll { $0.permission == permission }
        for value in values where !entries.contains(where: { $0.pattern == value && $0.permission == permission }) {
            entries.append(NetworkDomainPermissionEntry(pattern: value, permission: permission))
        }
        domains = entries.isEmpty ? nil : NetworkDomainPermissions(entries: entries)
    }

    private static func normalizeHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["),
           let end = value.firstIndex(of: "]")
        {
            value = String(value[value.index(after: value.startIndex)..<end])
        } else if value.filter({ $0 == ":" }).count == 1 {
            value = String(value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        }
        return value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public struct NetworkProxyConfig: Equatable, Sendable {
    public var network: NetworkProxySettings

    public init(network: NetworkProxySettings = NetworkProxySettings()) {
        self.network = network
    }
}

public struct NetworkProxyConstraints: Equatable, Sendable {
    public var enabled: Bool?
    public var mode: NetworkMode?
    public var allowUpstreamProxy: Bool?
    public var dangerouslyAllowNonLoopbackProxy: Bool?
    public var dangerouslyAllowAllUnixSockets: Bool?
    public var allowedDomains: [String]?
    public var deniedDomains: [String]?
    public var allowlistExpansionEnabled: Bool?
    public var denylistExpansionEnabled: Bool?
    public var allowUnixSockets: [String]?
    public var allowLocalBinding: Bool?

    public init(
        enabled: Bool? = nil,
        mode: NetworkMode? = nil,
        allowUpstreamProxy: Bool? = nil,
        dangerouslyAllowNonLoopbackProxy: Bool? = nil,
        dangerouslyAllowAllUnixSockets: Bool? = nil,
        allowedDomains: [String]? = nil,
        deniedDomains: [String]? = nil,
        allowlistExpansionEnabled: Bool? = nil,
        denylistExpansionEnabled: Bool? = nil,
        allowUnixSockets: [String]? = nil,
        allowLocalBinding: Bool? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.allowedDomains = allowedDomains
        self.deniedDomains = deniedDomains
        self.allowlistExpansionEnabled = allowlistExpansionEnabled
        self.denylistExpansionEnabled = denylistExpansionEnabled
        self.allowUnixSockets = allowUnixSockets
        self.allowLocalBinding = allowLocalBinding
    }
}

public struct NetworkProxySpec: Equatable, Sendable {
    public var baseConfig: NetworkProxyConfig
    public var requirements: NetworkRequirementsToml?
    public var config: NetworkProxyConfig
    public var constraints: NetworkProxyConstraints
    public var hardDenyAllowlistMisses: Bool

    public init(
        baseConfig: NetworkProxyConfig,
        requirements: NetworkRequirementsToml?,
        config: NetworkProxyConfig,
        constraints: NetworkProxyConstraints,
        hardDenyAllowlistMisses: Bool
    ) {
        self.baseConfig = baseConfig
        self.requirements = requirements
        self.config = config
        self.constraints = constraints
        self.hardDenyAllowlistMisses = hardDenyAllowlistMisses
    }

    public var enabled: Bool {
        config.network.enabled
    }

    public static func fromConfigAndRequirements(
        _ config: NetworkProxyConfig = NetworkProxyConfig(),
        requirements: NetworkRequirementsToml?,
        permissionProfile: PermissionProfile
    ) -> NetworkProxySpec {
        let baseConfig = config
        let hardDenyAllowlistMisses = requirements?.managedAllowedDomainsOnly ?? false
        let (effectiveConfig, constraints) = requirements.map {
            applyRequirements(
                $0,
                to: config,
                permissionProfile: permissionProfile,
                hardDenyAllowlistMisses: hardDenyAllowlistMisses
            )
        } ?? (config, NetworkProxyConstraints())
        return NetworkProxySpec(
            baseConfig: baseConfig,
            requirements: requirements,
            config: effectiveConfig,
            constraints: constraints,
            hardDenyAllowlistMisses: hardDenyAllowlistMisses
        )
    }

    private static func applyRequirements(
        _ requirements: NetworkRequirementsToml,
        to config: NetworkProxyConfig,
        permissionProfile: PermissionProfile,
        hardDenyAllowlistMisses: Bool
    ) -> (NetworkProxyConfig, NetworkProxyConstraints) {
        var config = config
        var constraints = NetworkProxyConstraints()
        let allowlistExpansionEnabled = permissionProfile.isManaged && !hardDenyAllowlistMisses
        let denylistExpansionEnabled = permissionProfile.isManaged

        if let enabled = requirements.enabled {
            config.network.enabled = enabled
            constraints.enabled = enabled
        }
        if let httpPort = requirements.httpPort {
            config.network.proxyURL = "http://127.0.0.1:\(httpPort)"
        }
        if let socksPort = requirements.socksPort {
            config.network.socksURL = "http://127.0.0.1:\(socksPort)"
        }
        if let allowUpstreamProxy = requirements.allowUpstreamProxy {
            config.network.allowUpstreamProxy = allowUpstreamProxy
            constraints.allowUpstreamProxy = allowUpstreamProxy
        }
        if let dangerouslyAllowNonLoopbackProxy = requirements.dangerouslyAllowNonLoopbackProxy {
            config.network.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
            constraints.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        }
        if let dangerouslyAllowAllUnixSockets = requirements.dangerouslyAllowAllUnixSockets {
            config.network.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
            constraints.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        }

        let managedAllowedDomains: [String]?
        if hardDenyAllowlistMisses {
            managedAllowedDomains = allowedDomains(from: requirements.domains) ?? []
        } else {
            managedAllowedDomains = allowedDomains(from: requirements.domains)
        }
        if let managedAllowedDomains {
            let effectiveAllowedDomains = allowlistExpansionEnabled
                ? mergeDomainLists(managedAllowedDomains, config.network.allowedDomains() ?? [])
                : managedAllowedDomains
            config.network.setAllowedDomains(effectiveAllowedDomains)
            constraints.allowedDomains = managedAllowedDomains
            constraints.allowlistExpansionEnabled = allowlistExpansionEnabled
        }

        if let managedDeniedDomains = deniedDomains(from: requirements.domains) {
            let effectiveDeniedDomains = denylistExpansionEnabled
                ? mergeDomainLists(managedDeniedDomains, config.network.deniedDomains() ?? [])
                : managedDeniedDomains
            config.network.setDeniedDomains(effectiveDeniedDomains)
            constraints.deniedDomains = managedDeniedDomains
            constraints.denylistExpansionEnabled = denylistExpansionEnabled
        }

        if let unixSockets = requirements.unixSockets {
            let allowedSockets = unixSockets
                .filter { $0.value == .allow }
                .map(\.key)
                .sorted()
            config.network.setAllowedUnixSockets(allowedSockets)
            constraints.allowUnixSockets = allowedSockets
        }
        if let allowLocalBinding = requirements.allowLocalBinding {
            config.network.allowLocalBinding = allowLocalBinding
            constraints.allowLocalBinding = allowLocalBinding
        }

        return (config, constraints)
    }

    private static func allowedDomains(from domains: [String: NetworkDomainPermissionRequirement]?) -> [String]? {
        domainList(from: domains, matching: .allow)
    }

    private static func deniedDomains(from domains: [String: NetworkDomainPermissionRequirement]?) -> [String]? {
        domainList(from: domains, matching: .deny)
    }

    private static func domainList(
        from domains: [String: NetworkDomainPermissionRequirement]?,
        matching permission: NetworkDomainPermissionRequirement
    ) -> [String]? {
        guard let domains else {
            return nil
        }
        let values = domains
            .filter { $0.value == permission }
            .map(\.key)
            .sorted()
        return values.isEmpty ? nil : values
    }

    private static func mergeDomainLists(_ managed: [String], _ userEntries: [String]) -> [String] {
        var merged = managed
        for entry in userEntries where !merged.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
            merged.append(entry)
        }
        return merged
    }
}

private extension PermissionProfile {
    var isManaged: Bool {
        if case .managed = self {
            return true
        }
        return false
    }
}
