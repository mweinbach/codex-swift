import Foundation

public struct McpOAuthCallbackResult: Equatable, Sendable {
    public let code: String
    public let state: String

    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

public struct McpOAuthProviderError: Error, Equatable, CustomStringConvertible, Sendable {
    public let oauthError: String?
    public let errorDescription: String?

    public init(oauthError: String?, errorDescription: String?) {
        self.oauthError = oauthError
        self.errorDescription = errorDescription
    }

    public var description: String {
        switch (oauthError, errorDescription) {
        case let (error?, description?):
            return "OAuth provider returned `\(error)`: \(description)"
        case let (error?, nil):
            return "OAuth provider returned `\(error)`"
        case let (nil, description?):
            return "OAuth error: \(description)"
        case (nil, nil):
            return "OAuth provider returned an error"
        }
    }
}

public enum McpOAuthCallbackOutcome: Equatable, Sendable {
    case success(McpOAuthCallbackResult)
    case providerError(McpOAuthProviderError)
    case invalid
}

public enum McpOAuthCallbackParser {
    public static func parse(path: String, callbackPath: String = "/callback") -> McpOAuthCallbackResult? {
        guard case let .success(result) = parseOutcome(path: path, callbackPath: callbackPath) else {
            return nil
        }
        return result
    }

    public static func parseOutcome(path: String, callbackPath: String = "/callback") -> McpOAuthCallbackOutcome {
        guard let queryStart = path.firstIndex(of: "?") else {
            return .invalid
        }
        let route = String(path[..<queryStart])
        guard route == callbackPath else {
            return .invalid
        }

        let query = path[path.index(after: queryStart)...]
        var code: String?
        var state: String?
        var oauthError: String?
        var errorDescription: String?

        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let equals = pair.firstIndex(of: "=") else {
                continue
            }

            let key = String(pair[..<equals])
            let rawValue = String(pair[pair.index(after: equals)...])
            guard let value = rawValue.removingPercentEncoding else {
                continue
            }

            switch key {
            case "code":
                code = value
            case "state":
                state = value
            case "error":
                oauthError = value
            case "error_description":
                errorDescription = value
            default:
                continue
            }
        }

        guard let code, let state else {
            if oauthError != nil || errorDescription != nil {
                return .providerError(McpOAuthProviderError(
                    oauthError: oauthError,
                    errorDescription: errorDescription
                ))
            }
            return .invalid
        }
        return .success(McpOAuthCallbackResult(code: code, state: state))
    }
}
