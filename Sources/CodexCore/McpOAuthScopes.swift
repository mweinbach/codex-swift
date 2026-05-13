import Foundation

public enum McpOAuthScopesSource: Equatable, Sendable {
    case explicit
    case configured
    case discovered
    case empty
}

public struct ResolvedMcpOAuthScopes: Equatable, Sendable {
    public let scopes: [String]
    public let source: McpOAuthScopesSource

    public init(scopes: [String], source: McpOAuthScopesSource) {
        self.scopes = scopes
        self.source = source
    }
}

public enum McpOAuthScopes {
    public static func resolve(
        explicitScopes: [String]?,
        configuredScopes: [String]?,
        discoveredScopes: [String]?
    ) -> ResolvedMcpOAuthScopes {
        if let explicitScopes {
            return ResolvedMcpOAuthScopes(scopes: explicitScopes, source: .explicit)
        }

        if let configuredScopes {
            return ResolvedMcpOAuthScopes(scopes: configuredScopes, source: .configured)
        }

        if let discoveredScopes, !discoveredScopes.isEmpty {
            return ResolvedMcpOAuthScopes(scopes: discoveredScopes, source: .discovered)
        }

        return ResolvedMcpOAuthScopes(scopes: [], source: .empty)
    }

    public static func shouldRetryWithoutScopes(
        _ resolvedScopes: ResolvedMcpOAuthScopes,
        error: Error
    ) -> Bool {
        resolvedScopes.source == .discovered && error is McpOAuthProviderError
    }
}
