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
    func apiProvider(environment: [String: String]) throws -> APIProvider
    func runtimeBaseURL() throws -> String?
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

    public func apiProvider(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> APIProvider {
        info.toAPIProvider(authMode: effectiveAuthMode, environment: environment)
    }

    public func runtimeBaseURL() throws -> String? {
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

    public func apiProvider(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> APIProvider {
        let configured = info.toAPIProvider(authMode: nil, environment: environment)
        return APIProvider(
            name: configured.name,
            baseURL: try bedrockRuntimeBaseURL(),
            queryParams: configured.queryParams,
            wireAPI: configured.wireAPI,
            headers: configured.headers,
            retry: configured.retry,
            streamIdleTimeoutMilliseconds: configured.streamIdleTimeoutMilliseconds
        )
    }

    public func runtimeBaseURL() throws -> String? {
        try bedrockRuntimeBaseURL()
    }

    public func apiAuth(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> StaticAPIAuthProvider {
        if let token = environment[Self.awsBearerTokenEnvVar]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            guard aws.regionFromConfig != nil else {
                throw ModelProviderError.amazonBedrockBearerTokenMissingRegion
            }
            return StaticAPIAuthProvider(bearerToken: token)
        }
        return StaticAPIAuthProvider()
    }

    private static let awsBearerTokenEnvVar = "AWS_BEARER_TOKEN_BEDROCK"

    private var aws: ModelProviderAWSAuthInfo {
        info.aws ?? ModelProviderAWSAuthInfo()
    }

    private func bedrockRuntimeBaseURL() throws -> String {
        let region = aws.regionFromConfig ?? "us-east-1"
        guard Self.supportedMantleRegions.contains(region) else {
            throw ModelProviderError.unsupportedAmazonBedrockRegion(region)
        }
        return "https://bedrock-mantle.\(region).api.aws/openai/v1"
    }

    private static let supportedMantleRegions: Set<String> = [
        "us-east-2",
        "us-east-1",
        "us-west-2",
        "ap-southeast-3",
        "ap-south-1",
        "ap-northeast-1",
        "eu-central-1",
        "eu-west-1",
        "eu-west-2",
        "eu-south-1",
        "eu-north-1",
        "sa-east-1"
    ]
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
