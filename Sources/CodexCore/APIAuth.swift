import Foundation

public protocol APIAuthProvider: Sendable {
    var bearerToken: String? { get }
    var accountID: String? { get }
}

public struct StaticAPIAuthProvider: APIAuthProvider, Equatable, Sendable {
    public let bearerToken: String?
    public let accountID: String?

    public init(bearerToken: String? = nil, accountID: String? = nil) {
        self.bearerToken = bearerToken
        self.accountID = accountID
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

        if let providerAuth = provider.auth,
           let token = try? await commandRunner.resolveToken(config: providerAuth) {
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

        if let token = auth.bearerToken {
            let value = "Bearer \(token)"
            if isValidHeaderValue(value) {
                copy.headers[authorization] = value
            }
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
