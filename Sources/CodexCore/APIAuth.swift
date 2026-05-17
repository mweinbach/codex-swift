import Foundation

public protocol APIAuthProvider: Sendable {
    var authorizationHeader: String? { get }
    var bearerToken: String? { get }
    var accountID: String? { get }
}

public struct StaticAPIAuthProvider: APIAuthProvider, Equatable, Sendable {
    private let explicitAuthorizationHeader: String?
    public let bearerToken: String?
    public let accountID: String?
    public var authorizationHeader: String? {
        explicitAuthorizationHeader ?? bearerToken.map { "Bearer \($0)" }
    }

    public init(
        bearerToken: String? = nil,
        accountID: String? = nil,
        authorizationHeader: String? = nil
    ) {
        self.explicitAuthorizationHeader = authorizationHeader
        self.bearerToken = bearerToken
        self.accountID = accountID
    }
}

public extension APIAuthProvider {
    var authorizationHeader: String? {
        bearerToken.map { "Bearer \($0)" }
    }
}

public enum APIAuthResolver {
    public static func authProvider(
        auth: AuthDotJSON?,
        provider: ModelProviderInfo,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> StaticAPIAuthProvider {
        if let apiKey = try provider.apiKey(environment: environment) {
            return StaticAPIAuthProvider(bearerToken: apiKey)
        }

        if let token = provider.experimentalBearerToken {
            return StaticAPIAuthProvider(bearerToken: token)
        }

        if let apiKey = auth?.openAIAPIKey {
            return StaticAPIAuthProvider(bearerToken: apiKey)
        }

        if let tokens = auth?.tokens {
            return StaticAPIAuthProvider(
                bearerToken: tokens.accessToken,
                accountID: tokens.accountID
            )
        }

        return StaticAPIAuthProvider()
    }

    public static func authProvider(
        auth: AuthDotJSON?,
        provider: ModelProviderInfo,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: ProviderAuthCommandRunner
    ) async throws -> StaticAPIAuthProvider {
        if let apiKey = try provider.apiKey(environment: environment) {
            return StaticAPIAuthProvider(bearerToken: apiKey)
        }

        if let token = provider.experimentalBearerToken {
            return StaticAPIAuthProvider(bearerToken: token)
        }

        if let providerAuth = provider.auth {
            guard let token = try? await commandRunner.resolveToken(config: providerAuth) else {
                return StaticAPIAuthProvider()
            }
            return StaticAPIAuthProvider(bearerToken: token)
        }

        if let apiKey = auth?.openAIAPIKey {
            return StaticAPIAuthProvider(bearerToken: apiKey)
        }

        if let tokens = auth?.tokens {
            return StaticAPIAuthProvider(
                bearerToken: tokens.accessToken,
                accountID: tokens.accountID
            )
        }

        return StaticAPIAuthProvider()
    }
}

public enum APIAuthHeaders {
    public static let authorization = "authorization"
    public static let chatGPTAccountID = "ChatGPT-Account-ID"

    public static func addAuthHeaders<Auth: APIAuthProvider>(
        _ auth: Auth,
        to request: APIRequest
    ) -> APIRequest {
        var copy = request

        if let value = auth.authorizationHeader, isValidHeaderValue(value) {
            copy.headers[authorization] = value
        }

        if let accountID = auth.accountID, isValidHeaderValue(accountID) {
            copy.headers[chatGPTAccountID] = accountID
        }

        return copy
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
        }
    }
}

public extension APIRequest {
    func addingAuthHeaders<Auth: APIAuthProvider>(from auth: Auth) -> APIRequest {
        APIAuthHeaders.addAuthHeaders(auth, to: self)
    }
}

public extension URLRequest {
    mutating func addAuthHeaders<Auth: APIAuthProvider>(from auth: Auth) {
        if let value = auth.authorizationHeader,
           APIAuthHeaders.isValidURLRequestHeaderValue(value) {
            setValue(value, forHTTPHeaderField: APIAuthHeaders.authorization)
        }
        if let accountID = auth.accountID,
           APIAuthHeaders.isValidURLRequestHeaderValue(accountID) {
            setValue(accountID, forHTTPHeaderField: APIAuthHeaders.chatGPTAccountID)
        }
    }
}

public extension APIAuthHeaders {
    static func isValidURLRequestHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
        }
    }
}
