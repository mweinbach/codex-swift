import CodexCore
import XCTest

final class McpOAuthScopesTests: XCTestCase {
    func testResolveOAuthScopesPrefersExplicit() {
        let resolved = McpOAuthScopes.resolve(
            explicitScopes: ["explicit"],
            configuredScopes: ["configured"],
            discoveredScopes: ["discovered"]
        )

        XCTAssertEqual(
            resolved,
            ResolvedMcpOAuthScopes(scopes: ["explicit"], source: .explicit)
        )
    }

    func testResolveOAuthScopesPrefersConfiguredOverDiscovered() {
        let resolved = McpOAuthScopes.resolve(
            explicitScopes: nil,
            configuredScopes: ["configured"],
            discoveredScopes: ["discovered"]
        )

        XCTAssertEqual(
            resolved,
            ResolvedMcpOAuthScopes(scopes: ["configured"], source: .configured)
        )
    }

    func testResolveOAuthScopesUsesDiscoveredWhenNeeded() {
        let resolved = McpOAuthScopes.resolve(
            explicitScopes: nil,
            configuredScopes: nil,
            discoveredScopes: ["discovered"]
        )

        XCTAssertEqual(
            resolved,
            ResolvedMcpOAuthScopes(scopes: ["discovered"], source: .discovered)
        )
    }

    func testResolveOAuthScopesPreservesExplicitlyEmptyConfiguredScopes() {
        let resolved = McpOAuthScopes.resolve(
            explicitScopes: nil,
            configuredScopes: [],
            discoveredScopes: ["ignored"]
        )

        XCTAssertEqual(
            resolved,
            ResolvedMcpOAuthScopes(scopes: [], source: .configured)
        )
    }

    func testResolveOAuthScopesFallsBackToEmpty() {
        let resolved = McpOAuthScopes.resolve(
            explicitScopes: nil,
            configuredScopes: nil,
            discoveredScopes: nil
        )

        XCTAssertEqual(
            resolved,
            ResolvedMcpOAuthScopes(scopes: [], source: .empty)
        )
    }

    func testShouldRetryWithoutScopesOnlyForDiscoveredProviderErrors() {
        let discovered = ResolvedMcpOAuthScopes(scopes: ["scope"], source: .discovered)
        let providerError = McpOAuthProviderError(
            oauthError: "invalid_scope",
            errorDescription: "scope rejected"
        )

        XCTAssertTrue(McpOAuthScopes.shouldRetryWithoutScopes(discovered, error: providerError))
        XCTAssertFalse(McpOAuthScopes.shouldRetryWithoutScopes(
            ResolvedMcpOAuthScopes(scopes: ["scope"], source: .configured),
            error: providerError
        ))
        XCTAssertFalse(McpOAuthScopes.shouldRetryWithoutScopes(
            discovered,
            error: McpOAuthCallbackServerError.callbackTimedOut
        ))
    }
}
