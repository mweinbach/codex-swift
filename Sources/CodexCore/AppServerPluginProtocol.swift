import Foundation

public struct MarketplaceAddParams: Equatable, Sendable {
    public let source: String
    public let refName: String?
    public let sparsePaths: [String]?

    private enum CodingKeys: String, CodingKey {
        case source
        case refName
        case sparsePaths
    }

    public init(source: String, refName: String? = nil, sparsePaths: [String]? = nil) {
        self.source = source
        self.refName = refName
        self.sparsePaths = sparsePaths
    }
}

extension MarketplaceAddParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        refName = try container.decodeIfPresent(String.self, forKey: .refName)
        sparsePaths = try container.decodeIfPresent([String].self, forKey: .sparsePaths)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encodeNilOrValue(refName, forKey: .refName)
        try container.encodeNilOrValue(sparsePaths, forKey: .sparsePaths)
    }
}

public struct MarketplaceAddResponse: Equatable, Codable, Sendable {
    public let marketplaceName: String
    public let installedRoot: AbsolutePath
    public let alreadyAdded: Bool

    public init(marketplaceName: String, installedRoot: AbsolutePath, alreadyAdded: Bool) {
        self.marketplaceName = marketplaceName
        self.installedRoot = installedRoot
        self.alreadyAdded = alreadyAdded
    }
}

public struct MarketplaceRemoveParams: Equatable, Codable, Sendable {
    public let marketplaceName: String

    public init(marketplaceName: String) {
        self.marketplaceName = marketplaceName
    }
}

public struct MarketplaceRemoveResponse: Equatable, Sendable {
    public let marketplaceName: String
    public let installedRoot: AbsolutePath?

    public init(marketplaceName: String, installedRoot: AbsolutePath? = nil) {
        self.marketplaceName = marketplaceName
        self.installedRoot = installedRoot
    }
}

extension MarketplaceRemoveResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case marketplaceName
        case installedRoot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplaceName = try container.decode(String.self, forKey: .marketplaceName)
        installedRoot = try container.decodeIfPresent(AbsolutePath.self, forKey: .installedRoot)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(marketplaceName, forKey: .marketplaceName)
        try container.encodeNilOrValue(installedRoot, forKey: .installedRoot)
    }
}

public struct MarketplaceUpgradeParams: Equatable, Sendable {
    public let marketplaceName: String?

    public init(marketplaceName: String? = nil) {
        self.marketplaceName = marketplaceName
    }
}

extension MarketplaceUpgradeParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case marketplaceName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplaceName = try container.decodeIfPresent(String.self, forKey: .marketplaceName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(marketplaceName, forKey: .marketplaceName)
    }
}

public struct MarketplaceUpgradeResponse: Equatable, Codable, Sendable {
    public let selectedMarketplaces: [String]
    public let upgradedRoots: [AbsolutePath]
    public let errors: [MarketplaceUpgradeErrorInfo]

    public init(
        selectedMarketplaces: [String],
        upgradedRoots: [AbsolutePath],
        errors: [MarketplaceUpgradeErrorInfo]
    ) {
        self.selectedMarketplaces = selectedMarketplaces
        self.upgradedRoots = upgradedRoots
        self.errors = errors
    }
}

public struct MarketplaceUpgradeErrorInfo: Equatable, Codable, Sendable {
    public let marketplaceName: String
    public let message: String

    public init(marketplaceName: String, message: String) {
        self.marketplaceName = marketplaceName
        self.message = message
    }
}

public struct PluginListParams: Equatable, Sendable {
    public let cwds: [AbsolutePath]?
    public let marketplaceKinds: [PluginListMarketplaceKind]?

    public init(cwds: [AbsolutePath]? = nil, marketplaceKinds: [PluginListMarketplaceKind]? = nil) {
        self.cwds = cwds
        self.marketplaceKinds = marketplaceKinds
    }
}

extension PluginListParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case cwds
        case marketplaceKinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwds = try container.decodeIfPresent([AbsolutePath].self, forKey: .cwds)
        marketplaceKinds = try container.decodeIfPresent([PluginListMarketplaceKind].self, forKey: .marketplaceKinds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(cwds, forKey: .cwds)
        try container.encodeNilOrValue(marketplaceKinds, forKey: .marketplaceKinds)
    }
}

public enum PluginListMarketplaceKind: String, Codable, Equatable, Sendable {
    case local
    case workspaceDirectory = "workspace-directory"
    case sharedWithMe = "shared-with-me"
}

public struct SkillsListParams: Equatable, Sendable {
    public let cwds: [String]
    public let forceReload: Bool

    private enum CodingKeys: String, CodingKey {
        case cwds
        case forceReload
    }

    public init(cwds: [String] = [], forceReload: Bool = false) {
        self.cwds = cwds
        self.forceReload = forceReload
    }
}

extension SkillsListParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwds = try container.decodeRustDefaulted([String].self, forKey: .cwds, defaultValue: [])
        forceReload = try container.decodeRustDefaulted(Bool.self, forKey: .forceReload, defaultValue: false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !cwds.isEmpty {
            try container.encode(cwds, forKey: .cwds)
        }
        if forceReload {
            try container.encode(forceReload, forKey: .forceReload)
        }
    }
}

public struct HooksListParams: Equatable, Sendable {
    public let cwds: [String]

    private enum CodingKeys: String, CodingKey {
        case cwds
    }

    public init(cwds: [String] = []) {
        self.cwds = cwds
    }
}

extension HooksListParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwds = try container.decodeRustDefaulted([String].self, forKey: .cwds, defaultValue: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !cwds.isEmpty {
            try container.encode(cwds, forKey: .cwds)
        }
    }
}

public struct PluginListResponse: Equatable, Sendable {
    public let marketplaces: [PluginMarketplaceEntry]
    public let marketplaceLoadErrors: [MarketplaceLoadErrorInfo]
    public let featuredPluginIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case marketplaces
        case marketplaceLoadErrors
        case featuredPluginIDs = "featuredPluginIds"
    }

    public init(
        marketplaces: [PluginMarketplaceEntry],
        marketplaceLoadErrors: [MarketplaceLoadErrorInfo] = [],
        featuredPluginIDs: [String] = []
    ) {
        self.marketplaces = marketplaces
        self.marketplaceLoadErrors = marketplaceLoadErrors
        self.featuredPluginIDs = featuredPluginIDs
    }
}

extension PluginListResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplaces = try container.decode([PluginMarketplaceEntry].self, forKey: .marketplaces)
        marketplaceLoadErrors = try container.decodeRustDefaulted(
            [MarketplaceLoadErrorInfo].self,
            forKey: .marketplaceLoadErrors,
            defaultValue: []
        )
        featuredPluginIDs = try container.decodeRustDefaulted(
            [String].self,
            forKey: .featuredPluginIDs,
            defaultValue: []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(marketplaces, forKey: .marketplaces)
        try container.encode(marketplaceLoadErrors, forKey: .marketplaceLoadErrors)
        try container.encode(featuredPluginIDs, forKey: .featuredPluginIDs)
    }
}

public struct MarketplaceLoadErrorInfo: Equatable, Codable, Sendable {
    public let marketplacePath: AbsolutePath
    public let message: String

    public init(marketplacePath: AbsolutePath, message: String) {
        self.marketplacePath = marketplacePath
        self.message = message
    }
}

public struct PluginReadParams: Equatable, Sendable {
    public let marketplacePath: AbsolutePath?
    public let remoteMarketplaceName: String?
    public let pluginName: String

    public init(marketplacePath: AbsolutePath? = nil, remoteMarketplaceName: String? = nil, pluginName: String) {
        self.marketplacePath = marketplacePath
        self.remoteMarketplaceName = remoteMarketplaceName
        self.pluginName = pluginName
    }
}

extension PluginReadParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case marketplacePath
        case remoteMarketplaceName
        case pluginName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplacePath = try container.decodeIfPresent(AbsolutePath.self, forKey: .marketplacePath)
        remoteMarketplaceName = try container.decodeIfPresent(String.self, forKey: .remoteMarketplaceName)
        pluginName = try container.decode(String.self, forKey: .pluginName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(marketplacePath, forKey: .marketplacePath)
        try container.encodeNilOrValue(remoteMarketplaceName, forKey: .remoteMarketplaceName)
        try container.encode(pluginName, forKey: .pluginName)
    }
}

public struct PluginReadResponse: Equatable, Codable, Sendable {
    public let plugin: PluginDetail

    public init(plugin: PluginDetail) {
        self.plugin = plugin
    }
}

public struct PluginSkillReadParams: Equatable, Codable, Sendable {
    public let remoteMarketplaceName: String
    public let remotePluginID: String
    public let skillName: String

    private enum CodingKeys: String, CodingKey {
        case remoteMarketplaceName
        case remotePluginID = "remotePluginId"
        case skillName
    }

    public init(remoteMarketplaceName: String, remotePluginID: String, skillName: String) {
        self.remoteMarketplaceName = remoteMarketplaceName
        self.remotePluginID = remotePluginID
        self.skillName = skillName
    }
}

public struct PluginSkillReadResponse: Equatable, Sendable {
    public let contents: String?

    public init(contents: String? = nil) {
        self.contents = contents
    }
}

extension PluginSkillReadResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case contents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contents = try container.decodeIfPresent(String.self, forKey: .contents)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(contents, forKey: .contents)
    }
}

public struct PluginMarketplaceEntry: Equatable, Sendable {
    public let name: String
    public let path: AbsolutePath?
    public let interface: MarketplaceInterface?
    public let plugins: [PluginSummary]

    public init(
        name: String,
        path: AbsolutePath? = nil,
        interface: MarketplaceInterface? = nil,
        plugins: [PluginSummary]
    ) {
        self.name = name
        self.path = path
        self.interface = interface
        self.plugins = plugins
    }
}

extension PluginMarketplaceEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case interface
        case plugins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decodeIfPresent(AbsolutePath.self, forKey: .path)
        interface = try container.decodeIfPresent(MarketplaceInterface.self, forKey: .interface)
        plugins = try container.decode([PluginSummary].self, forKey: .plugins)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeNilOrValue(path, forKey: .path)
        try container.encodeNilOrValue(interface, forKey: .interface)
        try container.encode(plugins, forKey: .plugins)
    }
}

public struct MarketplaceInterface: Equatable, Sendable {
    public let displayName: String?

    public init(displayName: String? = nil) {
        self.displayName = displayName
    }
}

extension MarketplaceInterface: Codable {
    private enum CodingKeys: String, CodingKey {
        case displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(displayName, forKey: .displayName)
    }
}

public enum PluginInstallPolicy: String, Codable, Equatable, Sendable {
    case notAvailable = "NOT_AVAILABLE"
    case available = "AVAILABLE"
    case installedByDefault = "INSTALLED_BY_DEFAULT"
}

public enum PluginAuthPolicy: String, Codable, Equatable, Sendable {
    case onInstall = "ON_INSTALL"
    case onUse = "ON_USE"
}

public enum PluginAvailability: Equatable, Sendable {
    case available
    case disabledByAdmin
}

extension PluginAvailability: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "AVAILABLE", "ENABLED":
            self = .available
        case "DISABLED_BY_ADMIN":
            self = .disabledByAdmin
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown PluginAvailability `\(value)`")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .available:
            try container.encode("AVAILABLE")
        case .disabledByAdmin:
            try container.encode("DISABLED_BY_ADMIN")
        }
    }
}

public struct PluginSummary: Equatable, Sendable {
    public let id: String
    public let name: String
    public let shareContext: PluginShareContext?
    public let source: PluginSource
    public let installed: Bool
    public let enabled: Bool
    public let installPolicy: PluginInstallPolicy
    public let authPolicy: PluginAuthPolicy
    public let availability: PluginAvailability
    public let interface: PluginInterface?
    public let keywords: [String]

    public init(
        id: String,
        name: String,
        shareContext: PluginShareContext? = nil,
        source: PluginSource,
        installed: Bool,
        enabled: Bool,
        installPolicy: PluginInstallPolicy,
        authPolicy: PluginAuthPolicy,
        availability: PluginAvailability = .available,
        interface: PluginInterface? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.shareContext = shareContext
        self.source = source
        self.installed = installed
        self.enabled = enabled
        self.installPolicy = installPolicy
        self.authPolicy = authPolicy
        self.availability = availability
        self.interface = interface
        self.keywords = keywords
    }
}

extension PluginSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case shareContext
        case source
        case installed
        case enabled
        case installPolicy
        case authPolicy
        case availability
        case interface
        case keywords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shareContext = try container.decodeIfPresent(PluginShareContext.self, forKey: .shareContext)
        source = try container.decode(PluginSource.self, forKey: .source)
        installed = try container.decode(Bool.self, forKey: .installed)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        installPolicy = try container.decode(PluginInstallPolicy.self, forKey: .installPolicy)
        authPolicy = try container.decode(PluginAuthPolicy.self, forKey: .authPolicy)
        availability = try container.decodeRustDefaulted(
            PluginAvailability.self,
            forKey: .availability,
            defaultValue: .available
        )
        interface = try container.decodeIfPresent(PluginInterface.self, forKey: .interface)
        keywords = try container.decodeRustDefaulted([String].self, forKey: .keywords, defaultValue: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeNilOrValue(shareContext, forKey: .shareContext)
        try container.encode(source, forKey: .source)
        try container.encode(installed, forKey: .installed)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(installPolicy, forKey: .installPolicy)
        try container.encode(authPolicy, forKey: .authPolicy)
        try container.encode(availability, forKey: .availability)
        try container.encodeNilOrValue(interface, forKey: .interface)
        try container.encode(keywords, forKey: .keywords)
    }
}

public struct PluginShareContext: Equatable, Sendable {
    public let remotePluginID: String
    public let shareURL: String?
    public let creatorAccountUserID: String?
    public let creatorName: String?
    public let shareTargets: [PluginSharePrincipal]?

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case shareURL = "shareUrl"
        case creatorAccountUserID = "creatorAccountUserId"
        case creatorName
        case shareTargets
    }

    public init(
        remotePluginID: String,
        shareURL: String? = nil,
        creatorAccountUserID: String? = nil,
        creatorName: String? = nil,
        shareTargets: [PluginSharePrincipal]? = nil
    ) {
        self.remotePluginID = remotePluginID
        self.shareURL = shareURL
        self.creatorAccountUserID = creatorAccountUserID
        self.creatorName = creatorName
        self.shareTargets = shareTargets
    }
}

extension PluginShareContext: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remotePluginID = try container.decode(String.self, forKey: .remotePluginID)
        shareURL = try container.decodeIfPresent(String.self, forKey: .shareURL)
        creatorAccountUserID = try container.decodeIfPresent(String.self, forKey: .creatorAccountUserID)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
        shareTargets = try container.decodeIfPresent([PluginSharePrincipal].self, forKey: .shareTargets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remotePluginID, forKey: .remotePluginID)
        try container.encodeNilOrValue(shareURL, forKey: .shareURL)
        try container.encodeNilOrValue(creatorAccountUserID, forKey: .creatorAccountUserID)
        try container.encodeNilOrValue(creatorName, forKey: .creatorName)
        try container.encodeNilOrValue(shareTargets, forKey: .shareTargets)
    }
}

public struct PluginDetail: Equatable, Sendable {
    public let marketplaceName: String
    public let marketplacePath: AbsolutePath?
    public let summary: PluginSummary
    public let description: String?
    public let skills: [SkillSummary]
    public let hooks: [PluginHookSummary]
    public let apps: [AppServerAppSummary]
    public let mcpServers: [String]

    public init(
        marketplaceName: String,
        marketplacePath: AbsolutePath? = nil,
        summary: PluginSummary,
        description: String? = nil,
        skills: [SkillSummary] = [],
        hooks: [PluginHookSummary] = [],
        apps: [AppServerAppSummary] = [],
        mcpServers: [String] = []
    ) {
        self.marketplaceName = marketplaceName
        self.marketplacePath = marketplacePath
        self.summary = summary
        self.description = description
        self.skills = skills
        self.hooks = hooks
        self.apps = apps
        self.mcpServers = mcpServers
    }
}

extension PluginDetail: Codable {
    private enum CodingKeys: String, CodingKey {
        case marketplaceName
        case marketplacePath
        case summary
        case description
        case skills
        case hooks
        case apps
        case mcpServers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplaceName = try container.decode(String.self, forKey: .marketplaceName)
        marketplacePath = try container.decodeIfPresent(AbsolutePath.self, forKey: .marketplacePath)
        summary = try container.decode(PluginSummary.self, forKey: .summary)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        skills = try container.decode([SkillSummary].self, forKey: .skills)
        hooks = try container.decode([PluginHookSummary].self, forKey: .hooks)
        apps = try container.decode([AppServerAppSummary].self, forKey: .apps)
        mcpServers = try container.decode([String].self, forKey: .mcpServers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(marketplaceName, forKey: .marketplaceName)
        try container.encodeNilOrValue(marketplacePath, forKey: .marketplacePath)
        try container.encode(summary, forKey: .summary)
        try container.encodeNilOrValue(description, forKey: .description)
        try container.encode(skills, forKey: .skills)
        try container.encode(hooks, forKey: .hooks)
        try container.encode(apps, forKey: .apps)
        try container.encode(mcpServers, forKey: .mcpServers)
    }
}

public struct PluginHookSummary: Equatable, Codable, Sendable {
    public let key: String
    public let eventName: AppServerHookEventName

    public init(key: String, eventName: AppServerHookEventName) {
        self.key = key
        self.eventName = eventName
    }

    public init(key: String, coreEventName: HookEventName) {
        self.init(key: key, eventName: AppServerHookEventName(core: coreEventName))
    }
}

public struct SkillSummary: Equatable, Sendable {
    public let name: String
    public let description: String
    public let shortDescription: String?
    public let interface: AppServerSkillInterface?
    public let path: AbsolutePath?
    public let enabled: Bool

    public init(
        name: String,
        description: String,
        shortDescription: String? = nil,
        interface: AppServerSkillInterface? = nil,
        path: AbsolutePath? = nil,
        enabled: Bool
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.interface = interface
        self.path = path
        self.enabled = enabled
    }
}

extension SkillSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case shortDescription
        case interface
        case path
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        interface = try container.decodeIfPresent(AppServerSkillInterface.self, forKey: .interface)
        path = try container.decodeIfPresent(AbsolutePath.self, forKey: .path)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encodeNilOrValue(shortDescription, forKey: .shortDescription)
        try container.encodeNilOrValue(interface, forKey: .interface)
        try container.encodeNilOrValue(path, forKey: .path)
        try container.encode(enabled, forKey: .enabled)
    }
}

public struct PluginInterface: Equatable, Sendable {
    public let displayName: String?
    public let shortDescription: String?
    public let longDescription: String?
    public let developerName: String?
    public let category: String?
    public let capabilities: [String]
    public let websiteURL: String?
    public let privacyPolicyURL: String?
    public let termsOfServiceURL: String?
    public let defaultPrompt: [String]?
    public let brandColor: String?
    public let composerIcon: AbsolutePath?
    public let composerIconURL: String?
    public let logo: AbsolutePath?
    public let logoURL: String?
    public let screenshots: [AbsolutePath]
    public let screenshotURLs: [String]

    private enum CodingKeys: String, CodingKey {
        case displayName
        case shortDescription
        case longDescription
        case developerName
        case category
        case capabilities
        case websiteURL = "websiteUrl"
        case privacyPolicyURL = "privacyPolicyUrl"
        case termsOfServiceURL = "termsOfServiceUrl"
        case defaultPrompt
        case brandColor
        case composerIcon
        case composerIconURL = "composerIconUrl"
        case logo
        case logoURL = "logoUrl"
        case screenshots
        case screenshotURLs = "screenshotUrls"
    }

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        longDescription: String? = nil,
        developerName: String? = nil,
        category: String? = nil,
        capabilities: [String] = [],
        websiteURL: String? = nil,
        privacyPolicyURL: String? = nil,
        termsOfServiceURL: String? = nil,
        defaultPrompt: [String]? = nil,
        brandColor: String? = nil,
        composerIcon: AbsolutePath? = nil,
        composerIconURL: String? = nil,
        logo: AbsolutePath? = nil,
        logoURL: String? = nil,
        screenshots: [AbsolutePath] = [],
        screenshotURLs: [String] = []
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.developerName = developerName
        self.category = category
        self.capabilities = capabilities
        self.websiteURL = websiteURL
        self.privacyPolicyURL = privacyPolicyURL
        self.termsOfServiceURL = termsOfServiceURL
        self.defaultPrompt = defaultPrompt
        self.brandColor = brandColor
        self.composerIcon = composerIcon
        self.composerIconURL = composerIconURL
        self.logo = logo
        self.logoURL = logoURL
        self.screenshots = screenshots
        self.screenshotURLs = screenshotURLs
    }
}

extension PluginInterface: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        longDescription = try container.decodeIfPresent(String.self, forKey: .longDescription)
        developerName = try container.decodeIfPresent(String.self, forKey: .developerName)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL)
        privacyPolicyURL = try container.decodeIfPresent(String.self, forKey: .privacyPolicyURL)
        termsOfServiceURL = try container.decodeIfPresent(String.self, forKey: .termsOfServiceURL)
        defaultPrompt = try container.decodeIfPresent([String].self, forKey: .defaultPrompt)
        brandColor = try container.decodeIfPresent(String.self, forKey: .brandColor)
        composerIcon = try container.decodeIfPresent(AbsolutePath.self, forKey: .composerIcon)
        composerIconURL = try container.decodeIfPresent(String.self, forKey: .composerIconURL)
        logo = try container.decodeIfPresent(AbsolutePath.self, forKey: .logo)
        logoURL = try container.decodeIfPresent(String.self, forKey: .logoURL)
        screenshots = try container.decode([AbsolutePath].self, forKey: .screenshots)
        screenshotURLs = try container.decode([String].self, forKey: .screenshotURLs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(displayName, forKey: .displayName)
        try container.encodeNilOrValue(shortDescription, forKey: .shortDescription)
        try container.encodeNilOrValue(longDescription, forKey: .longDescription)
        try container.encodeNilOrValue(developerName, forKey: .developerName)
        try container.encodeNilOrValue(category, forKey: .category)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encodeNilOrValue(websiteURL, forKey: .websiteURL)
        try container.encodeNilOrValue(privacyPolicyURL, forKey: .privacyPolicyURL)
        try container.encodeNilOrValue(termsOfServiceURL, forKey: .termsOfServiceURL)
        try container.encodeNilOrValue(defaultPrompt, forKey: .defaultPrompt)
        try container.encodeNilOrValue(brandColor, forKey: .brandColor)
        try container.encodeNilOrValue(composerIcon, forKey: .composerIcon)
        try container.encodeNilOrValue(composerIconURL, forKey: .composerIconURL)
        try container.encodeNilOrValue(logo, forKey: .logo)
        try container.encodeNilOrValue(logoURL, forKey: .logoURL)
        try container.encode(screenshots, forKey: .screenshots)
        try container.encode(screenshotURLs, forKey: .screenshotURLs)
    }
}

public enum PluginSource: Equatable, Sendable {
    case local(path: AbsolutePath)
    case git(url: String, path: String?, refName: String?, sha: String?)
    case remote
}

extension PluginSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case url
        case refName
        case sha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "local":
            self = .local(path: try container.decode(AbsolutePath.self, forKey: .path))
        case "git":
            self = .git(
                url: try container.decode(String.self, forKey: .url),
                path: try container.decodeIfPresent(String.self, forKey: .path),
                refName: try container.decodeIfPresent(String.self, forKey: .refName),
                sha: try container.decodeIfPresent(String.self, forKey: .sha)
            )
        case "remote":
            self = .remote
        case let value:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown PluginSource `\(value)`")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .local(path):
            try container.encode("local", forKey: .type)
            try container.encode(path, forKey: .path)
        case let .git(url, path, refName, sha):
            try container.encode("git", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeNilOrValue(path, forKey: .path)
            try container.encodeNilOrValue(refName, forKey: .refName)
            try container.encodeNilOrValue(sha, forKey: .sha)
        case .remote:
            try container.encode("remote", forKey: .type)
        }
    }
}

public struct AppServerSkillInterface: Equatable, Sendable {
    public let displayName: String?
    public let shortDescription: String?
    public let iconSmall: AbsolutePath?
    public let iconLarge: AbsolutePath?
    public let brandColor: String?
    public let defaultPrompt: String?

    private enum CodingKeys: String, CodingKey {
        case displayName
        case shortDescription
        case iconSmall
        case iconLarge
        case brandColor
        case defaultPrompt
    }

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        iconSmall: AbsolutePath? = nil,
        iconLarge: AbsolutePath? = nil,
        brandColor: String? = nil,
        defaultPrompt: String? = nil
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.iconSmall = iconSmall
        self.iconLarge = iconLarge
        self.brandColor = brandColor
        self.defaultPrompt = defaultPrompt
    }
}

extension AppServerSkillInterface: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        iconSmall = try container.decodeIfPresent(AbsolutePath.self, forKey: .iconSmall)
        iconLarge = try container.decodeIfPresent(AbsolutePath.self, forKey: .iconLarge)
        brandColor = try container.decodeIfPresent(String.self, forKey: .brandColor)
        defaultPrompt = try container.decodeIfPresent(String.self, forKey: .defaultPrompt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(displayName, forKey: .displayName)
        try container.encodeNilOrValue(shortDescription, forKey: .shortDescription)
        try container.encodeNilOrValue(iconSmall, forKey: .iconSmall)
        try container.encodeNilOrValue(iconLarge, forKey: .iconLarge)
        try container.encodeNilOrValue(brandColor, forKey: .brandColor)
        try container.encodeNilOrValue(defaultPrompt, forKey: .defaultPrompt)
    }
}

public struct AppServerAppSummary: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let installURL: String?
    public let needsAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case installURL = "installUrl"
        case needsAuth
    }

    public init(id: String, name: String, description: String? = nil, installURL: String? = nil, needsAuth: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.installURL = installURL
        self.needsAuth = needsAuth
    }
}

extension AppServerAppSummary: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        installURL = try container.decodeIfPresent(String.self, forKey: .installURL)
        needsAuth = try container.decode(Bool.self, forKey: .needsAuth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeNilOrValue(description, forKey: .description)
        try container.encodeNilOrValue(installURL, forKey: .installURL)
        try container.encode(needsAuth, forKey: .needsAuth)
    }
}

public struct SkillsConfigWriteParams: Equatable, Sendable {
    public let path: AbsolutePath?
    public let name: String?
    public let enabled: Bool

    public init(path: AbsolutePath? = nil, name: String? = nil, enabled: Bool) {
        self.path = path
        self.name = name
        self.enabled = enabled
    }
}

extension SkillsConfigWriteParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case name
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(AbsolutePath.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(path, forKey: .path)
        try container.encodeNilOrValue(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
    }
}

public struct SkillsConfigWriteResponse: Equatable, Codable, Sendable {
    public let effectiveEnabled: Bool

    public init(effectiveEnabled: Bool) {
        self.effectiveEnabled = effectiveEnabled
    }
}

public struct PluginInstallParams: Equatable, Sendable {
    public let marketplacePath: AbsolutePath?
    public let remoteMarketplaceName: String?
    public let pluginName: String

    public init(marketplacePath: AbsolutePath? = nil, remoteMarketplaceName: String? = nil, pluginName: String) {
        self.marketplacePath = marketplacePath
        self.remoteMarketplaceName = remoteMarketplaceName
        self.pluginName = pluginName
    }
}

extension PluginInstallParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case marketplacePath
        case remoteMarketplaceName
        case pluginName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marketplacePath = try container.decodeIfPresent(AbsolutePath.self, forKey: .marketplacePath)
        remoteMarketplaceName = try container.decodeIfPresent(String.self, forKey: .remoteMarketplaceName)
        pluginName = try container.decode(String.self, forKey: .pluginName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(marketplacePath, forKey: .marketplacePath)
        try container.encodeNilOrValue(remoteMarketplaceName, forKey: .remoteMarketplaceName)
        try container.encode(pluginName, forKey: .pluginName)
    }
}

public struct PluginInstallResponse: Equatable, Codable, Sendable {
    public let authPolicy: PluginAuthPolicy
    public let appsNeedingAuth: [AppServerAppSummary]

    public init(authPolicy: PluginAuthPolicy, appsNeedingAuth: [AppServerAppSummary] = []) {
        self.authPolicy = authPolicy
        self.appsNeedingAuth = appsNeedingAuth
    }
}

public struct PluginUninstallParams: Equatable, Codable, Sendable {
    public let pluginID: String

    private enum CodingKeys: String, CodingKey {
        case pluginID = "pluginId"
    }

    public init(pluginID: String) {
        self.pluginID = pluginID
    }
}

public struct PluginUninstallResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum PluginShareDiscoverability: String, Codable, Equatable, Sendable {
    case listed = "LISTED"
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

public enum PluginShareUpdateDiscoverability: String, Codable, Equatable, Sendable {
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

public enum PluginSharePrincipalType: String, Codable, Equatable, Sendable {
    case user
    case group
    case workspace
}

public struct PluginShareTarget: Equatable, Codable, Sendable {
    public let principalType: PluginSharePrincipalType
    public let principalID: String

    private enum CodingKeys: String, CodingKey {
        case principalType
        case principalID = "principalId"
    }

    public init(principalType: PluginSharePrincipalType, principalID: String) {
        self.principalType = principalType
        self.principalID = principalID
    }
}

public struct PluginSharePrincipal: Equatable, Codable, Sendable {
    public let principalType: PluginSharePrincipalType
    public let principalID: String
    public let name: String

    private enum CodingKeys: String, CodingKey {
        case principalType
        case principalID = "principalId"
        case name
    }

    public init(principalType: PluginSharePrincipalType, principalID: String, name: String) {
        self.principalType = principalType
        self.principalID = principalID
        self.name = name
    }
}

public struct PluginShareSaveParams: Equatable, Sendable {
    public let pluginPath: AbsolutePath
    public let remotePluginID: String?
    public let discoverability: PluginShareDiscoverability?
    public let shareTargets: [PluginShareTarget]?

    private enum CodingKeys: String, CodingKey {
        case pluginPath
        case remotePluginID = "remotePluginId"
        case discoverability
        case shareTargets
    }

    public init(
        pluginPath: AbsolutePath,
        remotePluginID: String? = nil,
        discoverability: PluginShareDiscoverability? = nil,
        shareTargets: [PluginShareTarget]? = nil
    ) {
        self.pluginPath = pluginPath
        self.remotePluginID = remotePluginID
        self.discoverability = discoverability
        self.shareTargets = shareTargets
    }
}

extension PluginShareSaveParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginPath = try container.decode(AbsolutePath.self, forKey: .pluginPath)
        remotePluginID = try container.decodeIfPresent(String.self, forKey: .remotePluginID)
        discoverability = try container.decodeIfPresent(PluginShareDiscoverability.self, forKey: .discoverability)
        shareTargets = try container.decodeIfPresent([PluginShareTarget].self, forKey: .shareTargets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pluginPath, forKey: .pluginPath)
        try container.encodeNilOrValue(remotePluginID, forKey: .remotePluginID)
        try container.encodeNilOrValue(discoverability, forKey: .discoverability)
        try container.encodeNilOrValue(shareTargets, forKey: .shareTargets)
    }
}

public struct PluginShareSaveResponse: Equatable, Codable, Sendable {
    public let remotePluginID: String
    public let shareURL: String

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case shareURL = "shareUrl"
    }

    public init(remotePluginID: String, shareURL: String) {
        self.remotePluginID = remotePluginID
        self.shareURL = shareURL
    }
}

public struct PluginShareUpdateTargetsParams: Equatable, Codable, Sendable {
    public let remotePluginID: String
    public let discoverability: PluginShareUpdateDiscoverability
    public let shareTargets: [PluginShareTarget]

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case discoverability
        case shareTargets
    }

    public init(
        remotePluginID: String,
        discoverability: PluginShareUpdateDiscoverability,
        shareTargets: [PluginShareTarget]
    ) {
        self.remotePluginID = remotePluginID
        self.discoverability = discoverability
        self.shareTargets = shareTargets
    }
}

public struct PluginShareUpdateTargetsResponse: Equatable, Codable, Sendable {
    public let principals: [PluginSharePrincipal]
    public let discoverability: PluginShareDiscoverability

    public init(principals: [PluginSharePrincipal], discoverability: PluginShareDiscoverability) {
        self.principals = principals
        self.discoverability = discoverability
    }
}

public struct PluginShareListParams: Equatable, Codable, Sendable {
    public init() {}
}

public struct PluginShareListResponse: Equatable, Codable, Sendable {
    public let data: [PluginShareListItem]

    public init(data: [PluginShareListItem]) {
        self.data = data
    }
}

public struct PluginShareListItem: Equatable, Sendable {
    public let plugin: PluginSummary
    public let shareURL: String
    public let localPluginPath: AbsolutePath?

    public init(plugin: PluginSummary, shareURL: String, localPluginPath: AbsolutePath? = nil) {
        self.plugin = plugin
        self.shareURL = shareURL
        self.localPluginPath = localPluginPath
    }
}

extension PluginShareListItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case plugin
        case shareURL = "shareUrl"
        case localPluginPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plugin = try container.decode(PluginSummary.self, forKey: .plugin)
        shareURL = try container.decode(String.self, forKey: .shareURL)
        localPluginPath = try container.decodeIfPresent(AbsolutePath.self, forKey: .localPluginPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plugin, forKey: .plugin)
        try container.encode(shareURL, forKey: .shareURL)
        try container.encodeNilOrValue(localPluginPath, forKey: .localPluginPath)
    }
}

public struct PluginShareCheckoutParams: Equatable, Codable, Sendable {
    public let remotePluginID: String

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
    }

    public init(remotePluginID: String) {
        self.remotePluginID = remotePluginID
    }
}

public struct PluginShareCheckoutResponse: Equatable, Codable, Sendable {
    public let remotePluginID: String
    public let pluginID: String
    public let pluginName: String
    public let pluginPath: AbsolutePath
    public let marketplaceName: String
    public let marketplacePath: AbsolutePath
    public let remoteVersion: String?

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case pluginID = "pluginId"
        case pluginName
        case pluginPath
        case marketplaceName
        case marketplacePath
        case remoteVersion
    }

    public init(
        remotePluginID: String,
        pluginID: String,
        pluginName: String,
        pluginPath: AbsolutePath,
        marketplaceName: String,
        marketplacePath: AbsolutePath,
        remoteVersion: String?
    ) {
        self.remotePluginID = remotePluginID
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.pluginPath = pluginPath
        self.marketplaceName = marketplaceName
        self.marketplacePath = marketplacePath
        self.remoteVersion = remoteVersion
    }
}

public struct PluginShareDeleteParams: Equatable, Codable, Sendable {
    public let remotePluginID: String

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
    }

    public init(remotePluginID: String) {
        self.remotePluginID = remotePluginID
    }
}

public struct PluginShareDeleteResponse: Equatable, Codable, Sendable {
    public init() {}
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
