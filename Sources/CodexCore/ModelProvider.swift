import Foundation

public enum ProviderAccount: Equatable, Sendable {
    case apiKey
    case chatGPT(email: String, planType: PlanType)
    case amazonBedrock
}

public struct ProviderAccountState: Equatable, Sendable {
    public let account: ProviderAccount?
    public let requiresOpenAIAuth: Bool

    public init(account: ProviderAccount?, requiresOpenAIAuth: Bool) {
        self.account = account
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }
}

public enum ProviderAccountError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingChatGPTAccountDetails

    public var description: String {
        switch self {
        case .missingChatGPTAccountDetails:
            return "email and plan type are required for chatgpt authentication"
        }
    }
}

/// Runtime model-provider behavior owned by a configured model backend.
///
/// Implementations adapt `ModelProviderInfo` into runtime capabilities, auth,
/// and app-visible account state. Values returned from this protocol are safe to
/// pass across task boundaries, and implementations must preserve the configured
/// provider's authentication isolation.
public protocol ModelProvider: Sendable {
    var info: ModelProviderInfo { get }

    func capabilities() -> ModelProviderCapabilities
    func supportsAttestation() -> Bool
    func accountState() throws -> ProviderAccountState
    func apiProvider(environment: [String: String]) -> APIProvider
    func runtimeBaseURL() -> String?
    func apiAuth(environment: [String: String]) throws -> StaticAPIAuthProvider
}

public enum ModelProviderFactory {
    public static func create(
        providerInfo: ModelProviderInfo,
        auth: AuthDotJSON? = nil
    ) -> any ModelProvider {
        if providerInfo.isAmazonBedrock() {
            return AmazonBedrockModelProvider(info: providerInfo)
        }
        return ConfiguredModelProvider(info: providerInfo, auth: auth)
    }
}

public struct ConfiguredModelProvider: ModelProvider {
    public let info: ModelProviderInfo
    private let auth: AuthDotJSON?

    public init(info: ModelProviderInfo, auth: AuthDotJSON? = nil) {
        self.info = info
        self.auth = auth
    }

    public func capabilities() -> ModelProviderCapabilities {
        info.capabilities()
    }

    public func supportsAttestation() -> Bool {
        effectiveAuthMode?.isChatGPT == true && auth?.tokens != nil
    }

    public func accountState() throws -> ProviderAccountState {
        guard info.requiresOpenAIAuth else {
            return ProviderAccountState(account: nil, requiresOpenAIAuth: false)
        }

        let account: ProviderAccount?
        if auth?.openAIAPIKey != nil {
            account = .apiKey
        } else if let tokens = auth?.tokens, effectiveAuthMode?.isChatGPT == true {
            guard let email = tokens.idToken.email,
                  let planType = tokens.idToken.chatGPTPlanType?.providerPlanType
            else {
                throw ProviderAccountError.missingChatGPTAccountDetails
            }
            account = .chatGPT(email: email, planType: planType)
        } else {
            account = nil
        }

        return ProviderAccountState(account: account, requiresOpenAIAuth: true)
    }

    public func apiProvider(environment: [String: String] = ProcessInfo.processInfo.environment) -> APIProvider {
        info.toAPIProvider(authMode: effectiveAuthMode, environment: environment)
    }

    public func runtimeBaseURL() -> String? {
        info.baseURL
    }

    public func apiAuth(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> StaticAPIAuthProvider {
        try APIAuthResolver.authProvider(auth: auth, provider: info, environment: environment)
    }

    private var effectiveAuthMode: AuthMode? {
        if auth?.openAIAPIKey != nil {
            return .apiKey
        }
        if let authMode = auth?.authMode {
            return authMode
        }
        if auth?.tokens != nil {
            return .chatGPT
        }
        return nil
    }
}

public struct AmazonBedrockModelProvider: ModelProvider {
    public let info: ModelProviderInfo

    public init(info: ModelProviderInfo = ModelProviderInfo.createAmazonBedrockProvider()) {
        self.info = info
    }

    public func capabilities() -> ModelProviderCapabilities {
        info.capabilities()
    }

    public func supportsAttestation() -> Bool {
        false
    }

    public func accountState() throws -> ProviderAccountState {
        ProviderAccountState(account: .amazonBedrock, requiresOpenAIAuth: false)
    }

    public func apiProvider(environment: [String: String] = ProcessInfo.processInfo.environment) -> APIProvider {
        info.toAPIProvider(authMode: nil, environment: environment)
    }

    public func runtimeBaseURL() -> String? {
        info.baseURL
    }

    public func apiAuth(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> StaticAPIAuthProvider {
        StaticAPIAuthProvider()
    }
}

private extension ChatGPTPlanType {
    var providerPlanType: PlanType? {
        switch self {
        case let .known(plan):
            PlanType.fromRawValue(plan.rawValue)
        case let .unknown(value):
            PlanType.fromRawValue(value)
        }
    }
}
