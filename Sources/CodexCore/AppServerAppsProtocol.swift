import Foundation

public struct AppsListParams: Equatable, Sendable {
    public let cursor: String?
    public let limit: UInt32?
    public let threadID: String?
    public let forceRefetch: Bool

    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
        case threadID = "threadId"
        case forceRefetch
    }

    public init(cursor: String? = nil, limit: UInt32? = nil, threadID: String? = nil, forceRefetch: Bool = false) {
        self.cursor = cursor
        self.limit = limit
        self.threadID = threadID
        self.forceRefetch = forceRefetch
    }
}

extension AppsListParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        forceRefetch = try container.decodeRustDefaulted(Bool.self, forKey: .forceRefetch, defaultValue: false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(cursor, forKey: .cursor)
        try container.encodeNilOrValue(limit, forKey: .limit)
        try container.encodeNilOrValue(threadID, forKey: .threadID)
        if forceRefetch {
            try container.encode(forceRefetch, forKey: .forceRefetch)
        }
    }
}

public struct AppBranding: Equatable, Sendable {
    public let category: String?
    public let developer: String?
    public let website: String?
    public let privacyPolicy: String?
    public let termsOfService: String?
    public let isDiscoverableApp: Bool

    public init(
        category: String? = nil,
        developer: String? = nil,
        website: String? = nil,
        privacyPolicy: String? = nil,
        termsOfService: String? = nil,
        isDiscoverableApp: Bool
    ) {
        self.category = category
        self.developer = developer
        self.website = website
        self.privacyPolicy = privacyPolicy
        self.termsOfService = termsOfService
        self.isDiscoverableApp = isDiscoverableApp
    }
}

extension AppBranding: Codable {
    private enum CodingKeys: String, CodingKey {
        case category
        case developer
        case website
        case privacyPolicy
        case termsOfService
        case isDiscoverableApp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        privacyPolicy = try container.decodeIfPresent(String.self, forKey: .privacyPolicy)
        termsOfService = try container.decodeIfPresent(String.self, forKey: .termsOfService)
        isDiscoverableApp = try container.decode(Bool.self, forKey: .isDiscoverableApp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(category, forKey: .category)
        try container.encodeNilOrValue(developer, forKey: .developer)
        try container.encodeNilOrValue(website, forKey: .website)
        try container.encodeNilOrValue(privacyPolicy, forKey: .privacyPolicy)
        try container.encodeNilOrValue(termsOfService, forKey: .termsOfService)
        try container.encode(isDiscoverableApp, forKey: .isDiscoverableApp)
    }
}

public struct AppReview: Equatable, Codable, Sendable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

public struct AppScreenshot: Equatable, Sendable {
    public let url: String?
    public let fileID: String?
    public let userPrompt: String

    private enum CodingKeys: String, CodingKey {
        case url
        case fileID = "fileId"
        case legacyFileID = "file_id"
        case userPrompt
        case legacyUserPrompt = "user_prompt"
    }

    public init(url: String? = nil, fileID: String? = nil, userPrompt: String) {
        self.url = url
        self.fileID = fileID
        self.userPrompt = userPrompt
    }
}

extension AppScreenshot: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        fileID = try container.decodeIfPresent(String.self, forKey: .fileID)
            ?? container.decodeIfPresent(String.self, forKey: .legacyFileID)
        userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt)
            ?? container.decode(String.self, forKey: .legacyUserPrompt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(url, forKey: .url)
        try container.encodeNilOrValue(fileID, forKey: .fileID)
        try container.encode(userPrompt, forKey: .userPrompt)
    }
}

public struct AppMetadata: Equatable, Sendable {
    public let review: AppReview?
    public let categories: [String]?
    public let subCategories: [String]?
    public let seoDescription: String?
    public let screenshots: [AppScreenshot]?
    public let developer: String?
    public let version: String?
    public let versionID: String?
    public let versionNotes: String?
    public let firstPartyType: String?
    public let firstPartyRequiresInstall: Bool?
    public let showInComposerWhenUnlinked: Bool?

    public init(
        review: AppReview? = nil,
        categories: [String]? = nil,
        subCategories: [String]? = nil,
        seoDescription: String? = nil,
        screenshots: [AppScreenshot]? = nil,
        developer: String? = nil,
        version: String? = nil,
        versionID: String? = nil,
        versionNotes: String? = nil,
        firstPartyType: String? = nil,
        firstPartyRequiresInstall: Bool? = nil,
        showInComposerWhenUnlinked: Bool? = nil
    ) {
        self.review = review
        self.categories = categories
        self.subCategories = subCategories
        self.seoDescription = seoDescription
        self.screenshots = screenshots
        self.developer = developer
        self.version = version
        self.versionID = versionID
        self.versionNotes = versionNotes
        self.firstPartyType = firstPartyType
        self.firstPartyRequiresInstall = firstPartyRequiresInstall
        self.showInComposerWhenUnlinked = showInComposerWhenUnlinked
    }
}

extension AppMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case review
        case categories
        case subCategories
        case seoDescription
        case screenshots
        case developer
        case version
        case versionID = "versionId"
        case versionNotes
        case firstPartyType
        case firstPartyRequiresInstall
        case showInComposerWhenUnlinked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        review = try container.decodeIfPresent(AppReview.self, forKey: .review)
        categories = try container.decodeIfPresent([String].self, forKey: .categories)
        subCategories = try container.decodeIfPresent([String].self, forKey: .subCategories)
        seoDescription = try container.decodeIfPresent(String.self, forKey: .seoDescription)
        screenshots = try container.decodeIfPresent([AppScreenshot].self, forKey: .screenshots)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        versionID = try container.decodeIfPresent(String.self, forKey: .versionID)
        versionNotes = try container.decodeIfPresent(String.self, forKey: .versionNotes)
        firstPartyType = try container.decodeIfPresent(String.self, forKey: .firstPartyType)
        firstPartyRequiresInstall = try container.decodeIfPresent(Bool.self, forKey: .firstPartyRequiresInstall)
        showInComposerWhenUnlinked = try container.decodeIfPresent(Bool.self, forKey: .showInComposerWhenUnlinked)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(review, forKey: .review)
        try container.encodeNilOrValue(categories, forKey: .categories)
        try container.encodeNilOrValue(subCategories, forKey: .subCategories)
        try container.encodeNilOrValue(seoDescription, forKey: .seoDescription)
        try container.encodeNilOrValue(screenshots, forKey: .screenshots)
        try container.encodeNilOrValue(developer, forKey: .developer)
        try container.encodeNilOrValue(version, forKey: .version)
        try container.encodeNilOrValue(versionID, forKey: .versionID)
        try container.encodeNilOrValue(versionNotes, forKey: .versionNotes)
        try container.encodeNilOrValue(firstPartyType, forKey: .firstPartyType)
        try container.encodeNilOrValue(firstPartyRequiresInstall, forKey: .firstPartyRequiresInstall)
        try container.encodeNilOrValue(showInComposerWhenUnlinked, forKey: .showInComposerWhenUnlinked)
    }
}

public struct AppInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let logoURL: String?
    public let logoURLDark: String?
    public let distributionChannel: String?
    public let branding: AppBranding?
    public let appMetadata: AppMetadata?
    public let labels: [String: String]?
    public let installURL: String?
    public let isAccessible: Bool
    public let isEnabled: Bool
    public let pluginDisplayNames: [String]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        logoURL: String? = nil,
        logoURLDark: String? = nil,
        distributionChannel: String? = nil,
        branding: AppBranding? = nil,
        appMetadata: AppMetadata? = nil,
        labels: [String: String]? = nil,
        installURL: String? = nil,
        isAccessible: Bool = false,
        isEnabled: Bool = true,
        pluginDisplayNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.logoURL = logoURL
        self.logoURLDark = logoURLDark
        self.distributionChannel = distributionChannel
        self.branding = branding
        self.appMetadata = appMetadata
        self.labels = labels
        self.installURL = installURL
        self.isAccessible = isAccessible
        self.isEnabled = isEnabled
        self.pluginDisplayNames = pluginDisplayNames
    }
}

extension AppInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case logoURL = "logoUrl"
        case logoURLDark = "logoUrlDark"
        case distributionChannel
        case branding
        case appMetadata
        case labels
        case installURL = "installUrl"
        case isAccessible
        case isEnabled
        case pluginDisplayNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        logoURL = try container.decodeIfPresent(String.self, forKey: .logoURL)
        logoURLDark = try container.decodeIfPresent(String.self, forKey: .logoURLDark)
        distributionChannel = try container.decodeIfPresent(String.self, forKey: .distributionChannel)
        branding = try container.decodeIfPresent(AppBranding.self, forKey: .branding)
        appMetadata = try container.decodeIfPresent(AppMetadata.self, forKey: .appMetadata)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        installURL = try container.decodeIfPresent(String.self, forKey: .installURL)
        isAccessible = try container.decodeRustDefaulted(Bool.self, forKey: .isAccessible, defaultValue: false)
        isEnabled = try container.decodeRustDefaulted(Bool.self, forKey: .isEnabled, defaultValue: true)
        pluginDisplayNames = try container.decodeRustDefaulted(
            [String].self,
            forKey: .pluginDisplayNames,
            defaultValue: []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeNilOrValue(description, forKey: .description)
        try container.encodeNilOrValue(logoURL, forKey: .logoURL)
        try container.encodeNilOrValue(logoURLDark, forKey: .logoURLDark)
        try container.encodeNilOrValue(distributionChannel, forKey: .distributionChannel)
        try container.encodeNilOrValue(branding, forKey: .branding)
        try container.encodeNilOrValue(appMetadata, forKey: .appMetadata)
        try container.encodeNilOrValue(labels, forKey: .labels)
        try container.encodeNilOrValue(installURL, forKey: .installURL)
        try container.encode(isAccessible, forKey: .isAccessible)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(pluginDisplayNames, forKey: .pluginDisplayNames)
    }
}

public typealias AppSummary = AppServerAppSummary

public struct AppsListResponse: Equatable, Sendable {
    public let data: [AppInfo]
    public let nextCursor: String?

    public init(data: [AppInfo], nextCursor: String? = nil) {
        self.data = data
        self.nextCursor = nextCursor
    }
}

extension AppsListResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([AppInfo].self, forKey: .data)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeNilOrValue(nextCursor, forKey: .nextCursor)
    }
}

public struct AppListUpdatedNotification: Equatable, Codable, Sendable {
    public let data: [AppInfo]

    public init(data: [AppInfo]) {
        self.data = data
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
