import Foundation

fileprivate struct AppServerConfigCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

fileprivate extension KeyedDecodingContainer where Key == AppServerConfigCodingKey {
    func decodeAdditionalFields(excluding excludedKeys: Set<String>) throws -> [String: JSONValue] {
        var additional: [String: JSONValue] = [:]
        for key in allKeys where !excludedKeys.contains(key.stringValue) {
            additional[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
        return additional
    }
}

fileprivate extension KeyedEncodingContainer where Key == AppServerConfigCodingKey {
    mutating func encodeAdditionalFields(_ additional: [String: JSONValue]) throws {
        for key in additional.keys.sorted() {
            try encode(additional[key], forKey: AppServerConfigCodingKey(stringValue: key))
        }
    }
}

public struct TextPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public struct TextRange: Codable, Equatable, Sendable {
    public let start: TextPosition
    public let end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }
}

public struct ConfigWarningNotification: Equatable, Sendable {
    public let summary: String
    public let details: String?
    public let path: String?
    public let range: TextRange?

    public init(
        summary: String,
        details: String? = nil,
        path: String? = nil,
        range: TextRange? = nil
    ) {
        self.summary = summary
        self.details = details
        self.path = path
        self.range = range
    }
}

extension ConfigWarningNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case summary
        case details
        case path
        case range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        range = try container.decodeIfPresent(TextRange.self, forKey: .range)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encodeNilOrValue(details, forKey: .details)
        if let path {
            try container.encode(path, forKey: .path)
        }
        if let range {
            try container.encode(range, forKey: .range)
        }
    }
}

extension AppServerProtocol {
    public struct WebSearchLocation: Codable, Equatable, Sendable {
        public let country: String?
        public let region: String?
        public let city: String?
        public let timezone: String?

        public init(country: String? = nil, region: String? = nil, city: String? = nil, timezone: String? = nil) {
            self.country = country
            self.region = region
            self.city = city
            self.timezone = timezone
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(country, forKey: .country)
            try container.encodeNilOrValue(region, forKey: .region)
            try container.encodeNilOrValue(city, forKey: .city)
            try container.encodeNilOrValue(timezone, forKey: .timezone)
        }
    }

    public struct WebSearchToolConfig: Codable, Equatable, Sendable {
        public let contextSize: WebSearchContextSize?
        public let allowedDomains: [String]?
        public let location: WebSearchLocation?

        private enum CodingKeys: String, CodingKey {
            case contextSize = "context_size"
            case allowedDomains = "allowed_domains"
            case location
        }

        public init(
            contextSize: WebSearchContextSize? = nil,
            allowedDomains: [String]? = nil,
            location: WebSearchLocation? = nil
        ) {
            self.contextSize = contextSize
            self.allowedDomains = allowedDomains
            self.location = location
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(contextSize, forKey: .contextSize)
            try container.encodeNilOrValue(allowedDomains, forKey: .allowedDomains)
            try container.encodeNilOrValue(location, forKey: .location)
        }
    }

    public struct SandboxWorkspaceWrite: Codable, Equatable, Sendable {
        public let writableRoots: [String]
        public let networkAccess: Bool
        public let excludeTmpdirEnvVar: Bool
        public let excludeSlashTmp: Bool

        private enum CodingKeys: String, CodingKey {
            case writableRoots = "writable_roots"
            case networkAccess = "network_access"
            case excludeTmpdirEnvVar = "exclude_tmpdir_env_var"
            case excludeSlashTmp = "exclude_slash_tmp"
        }

        public init(
            writableRoots: [String] = [],
            networkAccess: Bool = false,
            excludeTmpdirEnvVar: Bool = false,
            excludeSlashTmp: Bool = false
        ) {
            self.writableRoots = writableRoots
            self.networkAccess = networkAccess
            self.excludeTmpdirEnvVar = excludeTmpdirEnvVar
            self.excludeSlashTmp = excludeSlashTmp
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.writableRoots) {
                writableRoots = try container.decode([String].self, forKey: .writableRoots)
            } else {
                writableRoots = []
            }
            networkAccess = try container.decodeRustDefaulted(Bool.self, forKey: .networkAccess, defaultValue: false)
            excludeTmpdirEnvVar = try container.decodeRustDefaulted(
                Bool.self,
                forKey: .excludeTmpdirEnvVar,
                defaultValue: false
            )
            excludeSlashTmp = try container.decodeRustDefaulted(Bool.self, forKey: .excludeSlashTmp, defaultValue: false)
        }
    }

    public struct ToolsV2: Codable, Equatable, Sendable {
        public let webSearch: WebSearchToolConfig?

        private enum CodingKeys: String, CodingKey {
            case webSearch = "web_search"
        }

        public init(webSearch: WebSearchToolConfig? = nil) {
            self.webSearch = webSearch
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(webSearch, forKey: .webSearch)
        }
    }

    public struct ProfileV2: Codable, Equatable, Sendable {
        public let model: String?
        public let modelProvider: String?
        public let approvalPolicy: AskForApproval?
        public let approvalsReviewer: ApprovalsReviewer?
        public let serviceTier: String?
        public let modelReasoningEffort: ReasoningEffort?
        public let modelReasoningSummary: ReasoningSummary?
        public let modelVerbosity: Verbosity?
        public let webSearch: WebSearchMode?
        public let tools: ToolsV2?
        public let chatgptBaseURL: String?
        public let additional: [String: JSONValue]

        private static let knownKeys: Set<String> = [
            "model",
            "model_provider",
            "approval_policy",
            "approvals_reviewer",
            "service_tier",
            "model_reasoning_effort",
            "model_reasoning_summary",
            "model_verbosity",
            "web_search",
            "tools",
            "chatgpt_base_url"
        ]

        public init(
            model: String? = nil,
            modelProvider: String? = nil,
            approvalPolicy: AskForApproval? = nil,
            approvalsReviewer: ApprovalsReviewer? = nil,
            serviceTier: String? = nil,
            modelReasoningEffort: ReasoningEffort? = nil,
            modelReasoningSummary: ReasoningSummary? = nil,
            modelVerbosity: Verbosity? = nil,
            webSearch: WebSearchMode? = nil,
            tools: ToolsV2? = nil,
            chatgptBaseURL: String? = nil,
            additional: [String: JSONValue] = [:]
        ) {
            self.model = model
            self.modelProvider = modelProvider
            self.approvalPolicy = approvalPolicy
            self.approvalsReviewer = approvalsReviewer
            self.serviceTier = serviceTier
            self.modelReasoningEffort = modelReasoningEffort
            self.modelReasoningSummary = modelReasoningSummary
            self.modelVerbosity = modelVerbosity
            self.webSearch = webSearch
            self.tools = tools
            self.chatgptBaseURL = chatgptBaseURL
            self.additional = additional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AppServerConfigCodingKey.self)
            model = try container.decodeIfPresent(String.self, forKey: AppServerConfigCodingKey(stringValue: "model"))
            modelProvider = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_provider")
            )
            approvalPolicy = try container.decodeIfPresent(
                AskForApproval.self,
                forKey: AppServerConfigCodingKey(stringValue: "approval_policy")
            )
            approvalsReviewer = try container.decodeIfPresent(
                ApprovalsReviewer.self,
                forKey: AppServerConfigCodingKey(stringValue: "approvals_reviewer")
            )
            serviceTier = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "service_tier")
            )
            modelReasoningEffort = try container.decodeIfPresent(
                ReasoningEffort.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_effort")
            )
            modelReasoningSummary = try container.decodeIfPresent(
                ReasoningSummary.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_summary")
            )
            modelVerbosity = try container.decodeIfPresent(
                Verbosity.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_verbosity")
            )
            webSearch = try container.decodeIfPresent(
                WebSearchMode.self,
                forKey: AppServerConfigCodingKey(stringValue: "web_search")
            )
            tools = try container.decodeIfPresent(ToolsV2.self, forKey: AppServerConfigCodingKey(stringValue: "tools"))
            chatgptBaseURL = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "chatgpt_base_url")
            )
            additional = try container.decodeAdditionalFields(excluding: Self.knownKeys)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AppServerConfigCodingKey.self)
            try container.encodeNilOrValue(model, forKey: AppServerConfigCodingKey(stringValue: "model"))
            try container.encodeNilOrValue(
                modelProvider,
                forKey: AppServerConfigCodingKey(stringValue: "model_provider")
            )
            try container.encodeNilOrValue(
                approvalPolicy,
                forKey: AppServerConfigCodingKey(stringValue: "approval_policy")
            )
            try container.encodeNilOrValue(
                approvalsReviewer,
                forKey: AppServerConfigCodingKey(stringValue: "approvals_reviewer")
            )
            try container.encodeNilOrValue(serviceTier, forKey: AppServerConfigCodingKey(stringValue: "service_tier"))
            try container.encodeNilOrValue(
                modelReasoningEffort,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_effort")
            )
            try container.encodeNilOrValue(
                modelReasoningSummary,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_summary")
            )
            try container.encodeNilOrValue(
                modelVerbosity,
                forKey: AppServerConfigCodingKey(stringValue: "model_verbosity")
            )
            try container.encodeNilOrValue(webSearch, forKey: AppServerConfigCodingKey(stringValue: "web_search"))
            try container.encodeNilOrValue(tools, forKey: AppServerConfigCodingKey(stringValue: "tools"))
            try container.encodeNilOrValue(
                chatgptBaseURL,
                forKey: AppServerConfigCodingKey(stringValue: "chatgpt_base_url")
            )
            try container.encodeAdditionalFields(additional)
        }
    }

    public enum AppToolApproval: String, Codable, Equatable, Sendable {
        case auto
        case prompt
        case approve
    }

    public struct AppsDefaultConfig: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let destructiveEnabled: Bool
        public let openWorldEnabled: Bool

        private enum CodingKeys: String, CodingKey {
            case enabled
            case destructiveEnabled = "destructive_enabled"
            case openWorldEnabled = "open_world_enabled"
        }

        public init(enabled: Bool = true, destructiveEnabled: Bool = true, openWorldEnabled: Bool = true) {
            self.enabled = enabled
            self.destructiveEnabled = destructiveEnabled
            self.openWorldEnabled = openWorldEnabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeRustDefaulted(Bool.self, forKey: .enabled, defaultValue: true)
            destructiveEnabled = try container.decodeRustDefaulted(
                Bool.self,
                forKey: .destructiveEnabled,
                defaultValue: true
            )
            openWorldEnabled = try container.decodeRustDefaulted(Bool.self, forKey: .openWorldEnabled, defaultValue: true)
        }
    }

    public struct AppToolConfig: Codable, Equatable, Sendable {
        public let enabled: Bool?
        public let approvalMode: AppToolApproval?

        private enum CodingKeys: String, CodingKey {
            case enabled
            case approvalMode = "approval_mode"
        }

        public init(enabled: Bool? = nil, approvalMode: AppToolApproval? = nil) {
            self.enabled = enabled
            self.approvalMode = approvalMode
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(enabled, forKey: .enabled)
            try container.encodeNilOrValue(approvalMode, forKey: .approvalMode)
        }
    }

    public struct AppToolsConfig: Codable, Equatable, Sendable {
        public let tools: [String: AppToolConfig]

        public init(tools: [String: AppToolConfig] = [:]) {
            self.tools = tools
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AppServerConfigCodingKey.self)
            var tools: [String: AppToolConfig] = [:]
            for key in container.allKeys {
                tools[key.stringValue] = try container.decode(AppToolConfig.self, forKey: key)
            }
            self.tools = tools
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AppServerConfigCodingKey.self)
            for key in tools.keys.sorted() {
                try container.encode(tools[key], forKey: AppServerConfigCodingKey(stringValue: key))
            }
        }
    }

    public struct AppConfig: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let destructiveEnabled: Bool?
        public let openWorldEnabled: Bool?
        public let defaultToolsApprovalMode: AppToolApproval?
        public let defaultToolsEnabled: Bool?
        public let tools: AppToolsConfig?

        private enum CodingKeys: String, CodingKey {
            case enabled
            case destructiveEnabled = "destructive_enabled"
            case openWorldEnabled = "open_world_enabled"
            case defaultToolsApprovalMode = "default_tools_approval_mode"
            case defaultToolsEnabled = "default_tools_enabled"
            case tools
        }

        public init(
            enabled: Bool = true,
            destructiveEnabled: Bool? = nil,
            openWorldEnabled: Bool? = nil,
            defaultToolsApprovalMode: AppToolApproval? = nil,
            defaultToolsEnabled: Bool? = nil,
            tools: AppToolsConfig? = nil
        ) {
            self.enabled = enabled
            self.destructiveEnabled = destructiveEnabled
            self.openWorldEnabled = openWorldEnabled
            self.defaultToolsApprovalMode = defaultToolsApprovalMode
            self.defaultToolsEnabled = defaultToolsEnabled
            self.tools = tools
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeRustDefaulted(Bool.self, forKey: .enabled, defaultValue: true)
            destructiveEnabled = try container.decodeIfPresent(Bool.self, forKey: .destructiveEnabled)
            openWorldEnabled = try container.decodeIfPresent(Bool.self, forKey: .openWorldEnabled)
            defaultToolsApprovalMode = try container.decodeIfPresent(
                AppToolApproval.self,
                forKey: .defaultToolsApprovalMode
            )
            defaultToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultToolsEnabled)
            tools = try container.decodeIfPresent(AppToolsConfig.self, forKey: .tools)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
            try container.encodeNilOrValue(destructiveEnabled, forKey: .destructiveEnabled)
            try container.encodeNilOrValue(openWorldEnabled, forKey: .openWorldEnabled)
            try container.encodeNilOrValue(defaultToolsApprovalMode, forKey: .defaultToolsApprovalMode)
            try container.encodeNilOrValue(defaultToolsEnabled, forKey: .defaultToolsEnabled)
            try container.encodeNilOrValue(tools, forKey: .tools)
        }
    }

    public struct AppsConfig: Codable, Equatable, Sendable {
        public let defaultConfig: AppsDefaultConfig?
        public let apps: [String: AppConfig]

        private static let defaultKey = "_default"

        public init(defaultConfig: AppsDefaultConfig? = nil, apps: [String: AppConfig] = [:]) {
            self.defaultConfig = defaultConfig
            self.apps = apps
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AppServerConfigCodingKey.self)
            defaultConfig = try container.decodeIfPresent(
                AppsDefaultConfig.self,
                forKey: AppServerConfigCodingKey(stringValue: Self.defaultKey)
            )
            var apps: [String: AppConfig] = [:]
            for key in container.allKeys where key.stringValue != Self.defaultKey {
                apps[key.stringValue] = try container.decode(AppConfig.self, forKey: key)
            }
            self.apps = apps
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AppServerConfigCodingKey.self)
            try container.encodeNilOrValue(
                defaultConfig,
                forKey: AppServerConfigCodingKey(stringValue: Self.defaultKey)
            )
            for key in apps.keys.sorted() {
                try container.encode(apps[key], forKey: AppServerConfigCodingKey(stringValue: key))
            }
        }
    }

    public struct AnalyticsConfig: Codable, Equatable, Sendable {
        public let enabled: Bool?
        public let additional: [String: JSONValue]

        private static let knownKeys: Set<String> = ["enabled"]

        public init(enabled: Bool? = nil, additional: [String: JSONValue] = [:]) {
            self.enabled = enabled
            self.additional = additional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AppServerConfigCodingKey.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: AppServerConfigCodingKey(stringValue: "enabled"))
            additional = try container.decodeAdditionalFields(excluding: Self.knownKeys)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AppServerConfigCodingKey.self)
            try container.encodeNilOrValue(enabled, forKey: AppServerConfigCodingKey(stringValue: "enabled"))
            try container.encodeAdditionalFields(additional)
        }
    }

    public struct Config: Codable, Equatable, Sendable {
        public enum ForcedChatGPTWorkspaceIDs: Codable, Equatable, Sendable {
            case single(String)
            case multiple([String])

            public var values: [String] {
                switch self {
                case let .single(value):
                    return [value]
                case let .multiple(values):
                    return values
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .single(value)
                    return
                }
                self = .multiple(try container.decode([String].self))
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case let .single(value):
                    try container.encode(value)
                case let .multiple(values):
                    try container.encode(values)
                }
            }
        }

        public let model: String?
        public let reviewModel: String?
        public let modelContextWindow: Int64?
        public let modelAutoCompactTokenLimit: Int64?
        public let modelProvider: String?
        public let approvalPolicy: AskForApproval?
        public let approvalsReviewer: ApprovalsReviewer?
        public let sandboxMode: SandboxMode?
        public let sandboxWorkspaceWrite: SandboxWorkspaceWrite?
        public let forcedChatGPTWorkspaceID: ForcedChatGPTWorkspaceIDs?
        public let forcedLoginMethod: ForcedLoginMethod?
        public let webSearch: WebSearchMode?
        public let tools: ToolsV2?
        public let profile: String?
        public let profiles: [String: ProfileV2]
        public let instructions: String?
        public let developerInstructions: String?
        public let compactPrompt: String?
        public let modelReasoningEffort: ReasoningEffort?
        public let modelReasoningSummary: ReasoningSummary?
        public let modelVerbosity: Verbosity?
        public let serviceTier: String?
        public let analytics: AnalyticsConfig?
        public let apps: AppsConfig?
        public let desktop: [String: JSONValue]?
        public let additional: [String: JSONValue]

        private static let knownKeys: Set<String> = [
            "model",
            "review_model",
            "model_context_window",
            "model_auto_compact_token_limit",
            "model_provider",
            "approval_policy",
            "approvals_reviewer",
            "sandbox_mode",
            "sandbox_workspace_write",
            "forced_chatgpt_workspace_id",
            "forced_login_method",
            "web_search",
            "tools",
            "profile",
            "profiles",
            "instructions",
            "developer_instructions",
            "compact_prompt",
            "model_reasoning_effort",
            "model_reasoning_summary",
            "model_verbosity",
            "service_tier",
            "analytics",
            "apps",
            "desktop"
        ]

        public init(
            model: String? = nil,
            reviewModel: String? = nil,
            modelContextWindow: Int64? = nil,
            modelAutoCompactTokenLimit: Int64? = nil,
            modelProvider: String? = nil,
            approvalPolicy: AskForApproval? = nil,
            approvalsReviewer: ApprovalsReviewer? = nil,
            sandboxMode: SandboxMode? = nil,
            sandboxWorkspaceWrite: SandboxWorkspaceWrite? = nil,
            forcedChatGPTWorkspaceID: ForcedChatGPTWorkspaceIDs? = nil,
            forcedLoginMethod: ForcedLoginMethod? = nil,
            webSearch: WebSearchMode? = nil,
            tools: ToolsV2? = nil,
            profile: String? = nil,
            profiles: [String: ProfileV2] = [:],
            instructions: String? = nil,
            developerInstructions: String? = nil,
            compactPrompt: String? = nil,
            modelReasoningEffort: ReasoningEffort? = nil,
            modelReasoningSummary: ReasoningSummary? = nil,
            modelVerbosity: Verbosity? = nil,
            serviceTier: String? = nil,
            analytics: AnalyticsConfig? = nil,
            apps: AppsConfig? = nil,
            desktop: [String: JSONValue]? = nil,
            additional: [String: JSONValue] = [:]
        ) {
            self.model = model
            self.reviewModel = reviewModel
            self.modelContextWindow = modelContextWindow
            self.modelAutoCompactTokenLimit = modelAutoCompactTokenLimit
            self.modelProvider = modelProvider
            self.approvalPolicy = approvalPolicy
            self.approvalsReviewer = approvalsReviewer
            self.sandboxMode = sandboxMode
            self.sandboxWorkspaceWrite = sandboxWorkspaceWrite
            self.forcedChatGPTWorkspaceID = forcedChatGPTWorkspaceID
            self.forcedLoginMethod = forcedLoginMethod
            self.webSearch = webSearch
            self.tools = tools
            self.profile = profile
            self.profiles = profiles
            self.instructions = instructions
            self.developerInstructions = developerInstructions
            self.compactPrompt = compactPrompt
            self.modelReasoningEffort = modelReasoningEffort
            self.modelReasoningSummary = modelReasoningSummary
            self.modelVerbosity = modelVerbosity
            self.serviceTier = serviceTier
            self.analytics = analytics
            self.apps = apps
            self.desktop = desktop
            self.additional = additional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AppServerConfigCodingKey.self)
            model = try container.decodeIfPresent(String.self, forKey: AppServerConfigCodingKey(stringValue: "model"))
            reviewModel = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "review_model")
            )
            modelContextWindow = try container.decodeIfPresent(
                Int64.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_context_window")
            )
            modelAutoCompactTokenLimit = try container.decodeIfPresent(
                Int64.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_auto_compact_token_limit")
            )
            modelProvider = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_provider")
            )
            approvalPolicy = try container.decodeIfPresent(
                AskForApproval.self,
                forKey: AppServerConfigCodingKey(stringValue: "approval_policy")
            )
            approvalsReviewer = try container.decodeIfPresent(
                ApprovalsReviewer.self,
                forKey: AppServerConfigCodingKey(stringValue: "approvals_reviewer")
            )
            sandboxMode = try container.decodeIfPresent(
                SandboxMode.self,
                forKey: AppServerConfigCodingKey(stringValue: "sandbox_mode")
            )
            sandboxWorkspaceWrite = try container.decodeIfPresent(
                SandboxWorkspaceWrite.self,
                forKey: AppServerConfigCodingKey(stringValue: "sandbox_workspace_write")
            )
            forcedChatGPTWorkspaceID = try container.decodeIfPresent(
                ForcedChatGPTWorkspaceIDs.self,
                forKey: AppServerConfigCodingKey(stringValue: "forced_chatgpt_workspace_id")
            )
            forcedLoginMethod = try container.decodeIfPresent(
                ForcedLoginMethod.self,
                forKey: AppServerConfigCodingKey(stringValue: "forced_login_method")
            )
            webSearch = try container.decodeIfPresent(
                WebSearchMode.self,
                forKey: AppServerConfigCodingKey(stringValue: "web_search")
            )
            tools = try container.decodeIfPresent(ToolsV2.self, forKey: AppServerConfigCodingKey(stringValue: "tools"))
            profile = try container.decodeIfPresent(String.self, forKey: AppServerConfigCodingKey(stringValue: "profile"))
            let profilesKey = AppServerConfigCodingKey(stringValue: "profiles")
            if container.contains(profilesKey) {
                profiles = try container.decode([String: ProfileV2].self, forKey: profilesKey)
            } else {
                profiles = [:]
            }
            instructions = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "instructions")
            )
            developerInstructions = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "developer_instructions")
            )
            compactPrompt = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "compact_prompt")
            )
            modelReasoningEffort = try container.decodeIfPresent(
                ReasoningEffort.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_effort")
            )
            modelReasoningSummary = try container.decodeIfPresent(
                ReasoningSummary.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_summary")
            )
            modelVerbosity = try container.decodeIfPresent(
                Verbosity.self,
                forKey: AppServerConfigCodingKey(stringValue: "model_verbosity")
            )
            serviceTier = try container.decodeIfPresent(
                String.self,
                forKey: AppServerConfigCodingKey(stringValue: "service_tier")
            )
            analytics = try container.decodeIfPresent(
                AnalyticsConfig.self,
                forKey: AppServerConfigCodingKey(stringValue: "analytics")
            )
            apps = try container.decodeIfPresent(AppsConfig.self, forKey: AppServerConfigCodingKey(stringValue: "apps"))
            desktop = try container.decodeIfPresent(
                [String: JSONValue].self,
                forKey: AppServerConfigCodingKey(stringValue: "desktop")
            )
            additional = try container.decodeAdditionalFields(excluding: Self.knownKeys)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AppServerConfigCodingKey.self)
            try container.encodeNilOrValue(model, forKey: AppServerConfigCodingKey(stringValue: "model"))
            try container.encodeNilOrValue(reviewModel, forKey: AppServerConfigCodingKey(stringValue: "review_model"))
            try container.encodeNilOrValue(
                modelContextWindow,
                forKey: AppServerConfigCodingKey(stringValue: "model_context_window")
            )
            try container.encodeNilOrValue(
                modelAutoCompactTokenLimit,
                forKey: AppServerConfigCodingKey(stringValue: "model_auto_compact_token_limit")
            )
            try container.encodeNilOrValue(modelProvider, forKey: AppServerConfigCodingKey(stringValue: "model_provider"))
            try container.encodeNilOrValue(
                approvalPolicy,
                forKey: AppServerConfigCodingKey(stringValue: "approval_policy")
            )
            try container.encodeNilOrValue(
                approvalsReviewer,
                forKey: AppServerConfigCodingKey(stringValue: "approvals_reviewer")
            )
            try container.encodeNilOrValue(sandboxMode, forKey: AppServerConfigCodingKey(stringValue: "sandbox_mode"))
            try container.encodeNilOrValue(
                sandboxWorkspaceWrite,
                forKey: AppServerConfigCodingKey(stringValue: "sandbox_workspace_write")
            )
            try container.encodeNilOrValue(
                forcedChatGPTWorkspaceID,
                forKey: AppServerConfigCodingKey(stringValue: "forced_chatgpt_workspace_id")
            )
            try container.encodeNilOrValue(
                forcedLoginMethod,
                forKey: AppServerConfigCodingKey(stringValue: "forced_login_method")
            )
            try container.encodeNilOrValue(webSearch, forKey: AppServerConfigCodingKey(stringValue: "web_search"))
            try container.encodeNilOrValue(tools, forKey: AppServerConfigCodingKey(stringValue: "tools"))
            try container.encodeNilOrValue(profile, forKey: AppServerConfigCodingKey(stringValue: "profile"))
            try container.encode(profiles, forKey: AppServerConfigCodingKey(stringValue: "profiles"))
            try container.encodeNilOrValue(instructions, forKey: AppServerConfigCodingKey(stringValue: "instructions"))
            try container.encodeNilOrValue(
                developerInstructions,
                forKey: AppServerConfigCodingKey(stringValue: "developer_instructions")
            )
            try container.encodeNilOrValue(
                compactPrompt,
                forKey: AppServerConfigCodingKey(stringValue: "compact_prompt")
            )
            try container.encodeNilOrValue(
                modelReasoningEffort,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_effort")
            )
            try container.encodeNilOrValue(
                modelReasoningSummary,
                forKey: AppServerConfigCodingKey(stringValue: "model_reasoning_summary")
            )
            try container.encodeNilOrValue(
                modelVerbosity,
                forKey: AppServerConfigCodingKey(stringValue: "model_verbosity")
            )
            try container.encodeNilOrValue(serviceTier, forKey: AppServerConfigCodingKey(stringValue: "service_tier"))
            try container.encodeNilOrValue(analytics, forKey: AppServerConfigCodingKey(stringValue: "analytics"))
            try container.encodeNilOrValue(apps, forKey: AppServerConfigCodingKey(stringValue: "apps"))
            try container.encodeNilOrValue(desktop, forKey: AppServerConfigCodingKey(stringValue: "desktop"))
            try container.encodeAdditionalFields(additional)
        }
    }

    public struct ConfigReadParams: Codable, Equatable, Sendable {
        public let includeLayers: Bool
        public let cwd: String?

        private enum CodingKeys: String, CodingKey {
            case includeLayers
            case cwd
        }

        public init(includeLayers: Bool = false, cwd: String? = nil) {
            self.includeLayers = includeLayers
            self.cwd = cwd
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(includeLayers, forKey: .includeLayers)
            try container.encodeNilOrValue(cwd, forKey: .cwd)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            includeLayers = try container.decodeRustDefaulted(Bool.self, forKey: .includeLayers, defaultValue: false)
            cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        }
    }

    public struct ConfigReadResponse: Codable, Equatable, Sendable {
        public let config: Config
        public let origins: [String: ConfigLayerMetadata]
        public let layers: [ConfigLayer]?

        private enum CodingKeys: String, CodingKey {
            case config
            case origins
            case layers
        }

        public init(config: Config, origins: [String: ConfigLayerMetadata], layers: [ConfigLayer]? = nil) {
            self.config = config
            self.origins = origins
            self.layers = layers
        }
    }

    public struct ConfigLayer: Codable, Equatable, Sendable {
        public let name: ConfigLayerSource
        public let version: String
        public let config: Config
        public let disabledReason: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case version
            case config
            case disabledReason
        }

        public init(name: ConfigLayerSource, version: String, config: Config, disabledReason: String? = nil) {
            self.name = name
            self.version = version
            self.config = config
            self.disabledReason = disabledReason
        }
    }

    public struct ConfigRequirements: Codable, Equatable, Sendable {
        public let allowedApprovalPolicies: [AskForApproval]?
        public let allowedApprovalsReviewers: [ApprovalsReviewer]?
        public let allowedSandboxModes: [SandboxMode]?
        public let allowedWebSearchModes: [WebSearchMode]?
        public let allowManagedHooksOnly: Bool?
        public let featureRequirements: [String: Bool]?
        public let hooks: ManagedHooksRequirements?
        public let enforceResidency: ResidencyRequirement?
        public let network: NetworkRequirements?

        public init(
            allowedApprovalPolicies: [AskForApproval]? = nil,
            allowedApprovalsReviewers: [ApprovalsReviewer]? = nil,
            allowedSandboxModes: [SandboxMode]? = nil,
            allowedWebSearchModes: [WebSearchMode]? = nil,
            allowManagedHooksOnly: Bool? = nil,
            featureRequirements: [String: Bool]? = nil,
            hooks: ManagedHooksRequirements? = nil,
            enforceResidency: ResidencyRequirement? = nil,
            network: NetworkRequirements? = nil
        ) {
            self.allowedApprovalPolicies = allowedApprovalPolicies
            self.allowedApprovalsReviewers = allowedApprovalsReviewers
            self.allowedSandboxModes = allowedSandboxModes
            self.allowedWebSearchModes = allowedWebSearchModes
            self.allowManagedHooksOnly = allowManagedHooksOnly
            self.featureRequirements = featureRequirements
            self.hooks = hooks
            self.enforceResidency = enforceResidency
            self.network = network
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(allowedApprovalPolicies, forKey: .allowedApprovalPolicies)
            try container.encodeNilOrValue(allowedApprovalsReviewers, forKey: .allowedApprovalsReviewers)
            try container.encodeNilOrValue(allowedSandboxModes, forKey: .allowedSandboxModes)
            try container.encodeNilOrValue(allowedWebSearchModes, forKey: .allowedWebSearchModes)
            try container.encodeNilOrValue(allowManagedHooksOnly, forKey: .allowManagedHooksOnly)
            try container.encodeNilOrValue(featureRequirements, forKey: .featureRequirements)
            try container.encodeNilOrValue(hooks, forKey: .hooks)
            try container.encodeNilOrValue(enforceResidency, forKey: .enforceResidency)
            try container.encodeNilOrValue(network, forKey: .network)
        }
    }

    public struct ManagedHooksRequirements: Codable, Equatable, Sendable {
        public let managedDir: String?
        public let windowsManagedDir: String?
        public let preToolUse: [ConfiguredHookMatcherGroup]
        public let permissionRequest: [ConfiguredHookMatcherGroup]
        public let postToolUse: [ConfiguredHookMatcherGroup]
        public let preCompact: [ConfiguredHookMatcherGroup]
        public let postCompact: [ConfiguredHookMatcherGroup]
        public let sessionStart: [ConfiguredHookMatcherGroup]
        public let userPromptSubmit: [ConfiguredHookMatcherGroup]
        public let stop: [ConfiguredHookMatcherGroup]

        private enum CodingKeys: String, CodingKey {
            case managedDir
            case windowsManagedDir
            case preToolUse = "PreToolUse"
            case permissionRequest = "PermissionRequest"
            case postToolUse = "PostToolUse"
            case preCompact = "PreCompact"
            case postCompact = "PostCompact"
            case sessionStart = "SessionStart"
            case userPromptSubmit = "UserPromptSubmit"
            case stop = "Stop"
        }

        public init(
            managedDir: String? = nil,
            windowsManagedDir: String? = nil,
            preToolUse: [ConfiguredHookMatcherGroup] = [],
            permissionRequest: [ConfiguredHookMatcherGroup] = [],
            postToolUse: [ConfiguredHookMatcherGroup] = [],
            preCompact: [ConfiguredHookMatcherGroup] = [],
            postCompact: [ConfiguredHookMatcherGroup] = [],
            sessionStart: [ConfiguredHookMatcherGroup] = [],
            userPromptSubmit: [ConfiguredHookMatcherGroup] = [],
            stop: [ConfiguredHookMatcherGroup] = []
        ) {
            self.managedDir = managedDir
            self.windowsManagedDir = windowsManagedDir
            self.preToolUse = preToolUse
            self.permissionRequest = permissionRequest
            self.postToolUse = postToolUse
            self.preCompact = preCompact
            self.postCompact = postCompact
            self.sessionStart = sessionStart
            self.userPromptSubmit = userPromptSubmit
            self.stop = stop
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(managedDir, forKey: .managedDir)
            try container.encodeNilOrValue(windowsManagedDir, forKey: .windowsManagedDir)
            try container.encode(preToolUse, forKey: .preToolUse)
            try container.encode(permissionRequest, forKey: .permissionRequest)
            try container.encode(postToolUse, forKey: .postToolUse)
            try container.encode(preCompact, forKey: .preCompact)
            try container.encode(postCompact, forKey: .postCompact)
            try container.encode(sessionStart, forKey: .sessionStart)
            try container.encode(userPromptSubmit, forKey: .userPromptSubmit)
            try container.encode(stop, forKey: .stop)
        }
    }

    public struct ConfiguredHookMatcherGroup: Codable, Equatable, Sendable {
        public let matcher: String?
        public let hooks: [ConfiguredHookHandler]

        public init(matcher: String? = nil, hooks: [ConfiguredHookHandler]) {
            self.matcher = matcher
            self.hooks = hooks
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(matcher, forKey: .matcher)
            try container.encode(hooks, forKey: .hooks)
        }
    }

    public enum ConfiguredHookHandler: Codable, Equatable, Sendable {
        case command(command: String, commandWindows: String?, timeoutSec: UInt64?, async: Bool, statusMessage: String?)
        case prompt
        case agent

        private enum CodingKeys: String, CodingKey {
            case type
            case command
            case commandWindows
            case timeoutSec
            case `async`
            case statusMessage
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "command":
                self = .command(
                    command: try container.decode(String.self, forKey: .command),
                    commandWindows: try container.decodeIfPresent(String.self, forKey: .commandWindows),
                    timeoutSec: try container.decodeIfPresent(UInt64.self, forKey: .timeoutSec),
                    async: try container.decode(Bool.self, forKey: .async),
                    statusMessage: try container.decodeIfPresent(String.self, forKey: .statusMessage)
                )
            case "prompt":
                self = .prompt
            case "agent":
                self = .agent
            case let type:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown ConfiguredHookHandler type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .command(command, commandWindows, timeoutSec, async, statusMessage):
                try container.encode("command", forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encodeNilOrValue(commandWindows, forKey: .commandWindows)
                try container.encodeNilOrValue(timeoutSec, forKey: .timeoutSec)
                try container.encode(async, forKey: .async)
                try container.encodeNilOrValue(statusMessage, forKey: .statusMessage)
            case .prompt:
                try container.encode("prompt", forKey: .type)
            case .agent:
                try container.encode("agent", forKey: .type)
            }
        }
    }

    public struct NetworkRequirements: Codable, Equatable, Sendable {
        public let enabled: Bool?
        public let httpPort: UInt16?
        public let socksPort: UInt16?
        public let allowUpstreamProxy: Bool?
        public let dangerouslyAllowNonLoopbackProxy: Bool?
        public let dangerouslyAllowAllUnixSockets: Bool?
        public let domains: [String: NetworkDomainPermission]?
        public let managedAllowedDomainsOnly: Bool?
        public let allowedDomains: [String]?
        public let deniedDomains: [String]?
        public let unixSockets: [String: NetworkUnixSocketPermission]?
        public let allowUnixSockets: [String]?
        public let allowLocalBinding: Bool?

        public init(
            enabled: Bool? = nil,
            httpPort: UInt16? = nil,
            socksPort: UInt16? = nil,
            allowUpstreamProxy: Bool? = nil,
            dangerouslyAllowNonLoopbackProxy: Bool? = nil,
            dangerouslyAllowAllUnixSockets: Bool? = nil,
            domains: [String: NetworkDomainPermission]? = nil,
            managedAllowedDomainsOnly: Bool? = nil,
            allowedDomains: [String]? = nil,
            deniedDomains: [String]? = nil,
            unixSockets: [String: NetworkUnixSocketPermission]? = nil,
            allowUnixSockets: [String]? = nil,
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
            self.allowedDomains = allowedDomains
            self.deniedDomains = deniedDomains
            self.unixSockets = unixSockets
            self.allowUnixSockets = allowUnixSockets
            self.allowLocalBinding = allowLocalBinding
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(enabled, forKey: .enabled)
            try container.encodeNilOrValue(httpPort, forKey: .httpPort)
            try container.encodeNilOrValue(socksPort, forKey: .socksPort)
            try container.encodeNilOrValue(allowUpstreamProxy, forKey: .allowUpstreamProxy)
            try container.encodeNilOrValue(
                dangerouslyAllowNonLoopbackProxy,
                forKey: .dangerouslyAllowNonLoopbackProxy
            )
            try container.encodeNilOrValue(
                dangerouslyAllowAllUnixSockets,
                forKey: .dangerouslyAllowAllUnixSockets
            )
            try container.encodeNilOrValue(domains, forKey: .domains)
            try container.encodeNilOrValue(managedAllowedDomainsOnly, forKey: .managedAllowedDomainsOnly)
            try container.encodeNilOrValue(allowedDomains, forKey: .allowedDomains)
            try container.encodeNilOrValue(deniedDomains, forKey: .deniedDomains)
            try container.encodeNilOrValue(unixSockets, forKey: .unixSockets)
            try container.encodeNilOrValue(allowUnixSockets, forKey: .allowUnixSockets)
            try container.encodeNilOrValue(allowLocalBinding, forKey: .allowLocalBinding)
        }
    }

    public enum NetworkDomainPermission: String, Codable, Equatable, Sendable {
        case allow
        case deny
    }

    public enum NetworkUnixSocketPermission: String, Codable, Equatable, Sendable {
        case allow
        case none
    }

    public enum ResidencyRequirement: String, Codable, Equatable, Sendable {
        case us
    }

    public struct ConfigRequirementsReadResponse: Codable, Equatable, Sendable {
        public let requirements: ConfigRequirements?

        private enum CodingKeys: String, CodingKey {
            case requirements
        }

        public init(requirements: ConfigRequirements?) {
            self.requirements = requirements
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(requirements, forKey: .requirements)
        }
    }

    public enum ConfigMergeStrategy: String, Codable, Equatable, Sendable {
        case replace
        case upsert
    }

    public enum ConfigWriteStatus: String, Codable, Equatable, Sendable {
        case ok
        case okOverridden
    }

    public enum ConfigWriteErrorCode: String, Codable, Equatable, Sendable {
        case configLayerReadonly
        case configVersionConflict
        case configValidationError
        case configPathNotFound
        case configSchemaUnknownKey
        case userLayerNotFound
    }

    public struct OverriddenConfigMetadata: Codable, Equatable, Sendable {
        public let message: String
        public let overridingLayer: ConfigLayerMetadata
        public let effectiveValue: JSONValue

        public init(message: String, overridingLayer: ConfigLayerMetadata, effectiveValue: JSONValue) {
            self.message = message
            self.overridingLayer = overridingLayer
            self.effectiveValue = effectiveValue
        }
    }

    public struct ConfigWriteResponse: Codable, Equatable, Sendable {
        public let status: ConfigWriteStatus
        public let version: String
        public let filePath: AbsolutePath
        public let overriddenMetadata: OverriddenConfigMetadata?

        private enum CodingKeys: String, CodingKey {
            case status
            case version
            case filePath
            case overriddenMetadata
        }

        public init(
            status: ConfigWriteStatus,
            version: String,
            filePath: AbsolutePath,
            overriddenMetadata: OverriddenConfigMetadata? = nil
        ) {
            self.status = status
            self.version = version
            self.filePath = filePath
            self.overriddenMetadata = overriddenMetadata
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(version, forKey: .version)
            try container.encode(filePath, forKey: .filePath)
            try container.encodeNilOrValue(overriddenMetadata, forKey: .overriddenMetadata)
        }
    }

    public struct ConfigValueWriteParams: Codable, Equatable, Sendable {
        public let keyPath: String
        public let value: JSONValue
        public let mergeStrategy: ConfigMergeStrategy
        public let filePath: String?
        public let expectedVersion: String?

        private enum CodingKeys: String, CodingKey {
            case keyPath
            case value
            case mergeStrategy
            case filePath
            case expectedVersion
        }

        public init(
            keyPath: String,
            value: JSONValue,
            mergeStrategy: ConfigMergeStrategy,
            filePath: String? = nil,
            expectedVersion: String? = nil
        ) {
            self.keyPath = keyPath
            self.value = value
            self.mergeStrategy = mergeStrategy
            self.filePath = filePath
            self.expectedVersion = expectedVersion
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keyPath, forKey: .keyPath)
            try container.encode(value, forKey: .value)
            try container.encode(mergeStrategy, forKey: .mergeStrategy)
            try container.encodeNilOrValue(filePath, forKey: .filePath)
            try container.encodeNilOrValue(expectedVersion, forKey: .expectedVersion)
        }
    }

    public struct ConfigBatchWriteParams: Codable, Equatable, Sendable {
        public let edits: [ConfigEdit]
        public let filePath: String?
        public let expectedVersion: String?
        public let reloadUserConfig: Bool

        private enum CodingKeys: String, CodingKey {
            case edits
            case filePath
            case expectedVersion
            case reloadUserConfig
        }

        public init(
            edits: [ConfigEdit],
            filePath: String? = nil,
            expectedVersion: String? = nil,
            reloadUserConfig: Bool = false
        ) {
            self.edits = edits
            self.filePath = filePath
            self.expectedVersion = expectedVersion
            self.reloadUserConfig = reloadUserConfig
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(edits, forKey: .edits)
            try container.encodeNilOrValue(filePath, forKey: .filePath)
            try container.encodeNilOrValue(expectedVersion, forKey: .expectedVersion)
            if reloadUserConfig {
                try container.encode(reloadUserConfig, forKey: .reloadUserConfig)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            edits = try container.decode([ConfigEdit].self, forKey: .edits)
            filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
            expectedVersion = try container.decodeIfPresent(String.self, forKey: .expectedVersion)
            reloadUserConfig = try container.contains(.reloadUserConfig)
                ? container.decode(Bool.self, forKey: .reloadUserConfig)
                : false
        }
    }

    public struct ConfigEdit: Codable, Equatable, Sendable {
        public let keyPath: String
        public let value: JSONValue
        public let mergeStrategy: ConfigMergeStrategy

        public init(keyPath: String, value: JSONValue, mergeStrategy: ConfigMergeStrategy) {
            self.keyPath = keyPath
            self.value = value
            self.mergeStrategy = mergeStrategy
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
