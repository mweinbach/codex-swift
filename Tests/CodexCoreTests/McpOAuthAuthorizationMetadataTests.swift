import CodexCore
import Foundation
import XCTest

final class McpOAuthAuthorizationMetadataTests: XCTestCase {
    func testDirectAuthorizationServerDiscoveryMatchesRustOrderingAndHeaders() async throws {
        let probe = OAuthAuthorizationMetadataProbe(responses: [
            "example.com/.well-known/oauth-authorization-server/mcp": .init(statusCode: 404, body: Data()),
            "example.com/mcp/.well-known/oauth-authorization-server": .init(
                statusCode: 200,
                body: authorizationMetadataJSON()
            )
        ])

        let metadata = try await McpOAuthAuthorizationMetadataDiscovery.discoverMetadata(
            url: "https://example.com/mcp?ignored=1#fragment",
            httpHeaders: ["X-Static": "static"],
            envHttpHeaders: ["X-Env": "TOKEN"],
            environment: ["TOKEN": "secret"],
            transport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertEqual(metadata?.authorizationEndpoint, "https://auth.example/authorize")
        XCTAssertEqual(metadata?.tokenEndpoint, "https://auth.example/token")
        XCTAssertEqual(metadata?.registrationEndpoint, "https://auth.example/register")
        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.hostPath), [
            "example.com/.well-known/oauth-authorization-server/mcp",
            "example.com/mcp/.well-known/oauth-authorization-server"
        ])
        XCTAssertEqual(requests[0].query, nil)
        XCTAssertEqual(requests[0].fragment, nil)
        XCTAssertEqual(requests[0].headers[McpOAuthDiscovery.discoveryHeader], McpOAuthDiscovery.discoveryVersion)
        XCTAssertEqual(requests[0].headers["X-Static"], "static")
        XCTAssertEqual(requests[0].headers["X-Env"], "secret")
    }

    func testResourceMetadataDiscoveryFromWWWAuthenticateHeader() async throws {
        let probe = OAuthAuthorizationMetadataProbe(responses: [
            "resource.example/api/mcp": .init(
                statusCode: 401,
                body: Data(),
                headers: [
                    "WWW-Authenticate": [
                        #"Bearer error="invalid_request", resource_metadata="/.well-known/oauth-protected-resource/api/mcp""#
                    ]
                ]
            ),
            "resource.example/.well-known/oauth-protected-resource/api/mcp": .init(
                statusCode: 200,
                body: Data(#"{"authorization_servers":["https://auth.example/tenant"]}"#.utf8)
            ),
            "auth.example/.well-known/oauth-authorization-server/tenant": .init(
                statusCode: 200,
                body: authorizationMetadataJSON()
            )
        ])

        let metadata = try await McpOAuthAuthorizationMetadataDiscovery.discoverMetadata(
            url: "https://resource.example/api/mcp",
            transport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertEqual(metadata?.authorizationEndpoint, "https://auth.example/authorize")
        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.hostPath), [
            "resource.example/.well-known/oauth-authorization-server/api/mcp",
            "resource.example/api/mcp/.well-known/oauth-authorization-server",
            "resource.example/.well-known/oauth-authorization-server",
            "resource.example/api/mcp",
            "resource.example/.well-known/oauth-protected-resource/api/mcp",
            "auth.example/.well-known/oauth-authorization-server/tenant"
        ])
    }

    func testResourceMetadataDiscoveryAcceptsWellKnownAuthorizationServerURL() async throws {
        let probe = OAuthAuthorizationMetadataProbe(responses: [
            "resource.example/.well-known/oauth-protected-resource/api": .init(
                statusCode: 200,
                body: Data(#"{"authorization_server":"https://auth.example/.well-known/oauth-authorization-server/custom"}"#.utf8)
            ),
            "auth.example/.well-known/oauth-authorization-server/custom": .init(
                statusCode: 200,
                body: authorizationMetadataJSON()
            )
        ])

        let metadata = try await McpOAuthAuthorizationMetadataDiscovery.discoverMetadata(
            url: "https://resource.example/api",
            transport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertEqual(metadata?.tokenEndpoint, "https://auth.example/token")
    }

    func testHeaderValueParserMatchesRustCases() throws {
        XCTAssertEqual(
            McpOAuthAuthorizationMetadataDiscovery.parseNextHeaderValue(#""example", realm="foo""#)?.0,
            "example"
        )
        let escaped = McpOAuthAuthorizationMetadataDiscovery.parseNextHeaderValue(#"   "a\"b\\c" ,next=value"#)
        XCTAssertEqual(escaped?.0, #"a"b\c"#)
        XCTAssertEqual(escaped?.1, 12)
        XCTAssertEqual(
            McpOAuthAuthorizationMetadataDiscovery.parseNextHeaderValue(#"  https://example.com/meta; error="invalid_token""#)?.0,
            "https://example.com/meta"
        )
        XCTAssertNil(McpOAuthAuthorizationMetadataDiscovery.parseNextHeaderValue(#""unterminated,value"#))
    }

    func testResourceMetadataHeaderExtractionSupportsAbsoluteAndRelativeURLs() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/api"))
        XCTAssertEqual(
            McpOAuthAuthorizationMetadataDiscovery.extractResourceMetadataURL(
                from: #"Bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource/api""#,
                baseURL: baseURL
            )?.absoluteString,
            "https://example.com/.well-known/oauth-protected-resource/api"
        )
        XCTAssertEqual(
            McpOAuthAuthorizationMetadataDiscovery.extractResourceMetadataURL(
                from: #"Bearer error="invalid_request", resource_metadata="/.well-known/oauth-protected-resource/api""#,
                baseURL: baseURL
            )?.absoluteString,
            "https://example.com/.well-known/oauth-protected-resource/api"
        )
    }
}

private struct RecordedAuthorizationMetadataRequest: Equatable, Sendable {
    let hostPath: String
    let query: String?
    let fragment: String?
    let headers: [String: String]
}

private actor OAuthAuthorizationMetadataProbe {
    private let responses: [String: McpOAuthDiscoveryHTTPResponse]
    private var recordedRequests: [RecordedAuthorizationMetadataRequest] = []

    init(responses: [String: McpOAuthDiscoveryHTTPResponse]) {
        self.responses = responses
    }

    func handle(_ request: URLRequest) -> McpOAuthDiscoveryHTTPResponse {
        let url = request.url
        let key = "\(url?.host ?? "")\(url?.path ?? "")"
        recordedRequests.append(RecordedAuthorizationMetadataRequest(
            hostPath: key,
            query: url?.query,
            fragment: url?.fragment,
            headers: request.allHTTPHeaderFields ?? [:]
        ))
        return responses[key] ?? McpOAuthDiscoveryHTTPResponse(statusCode: 404, body: Data())
    }

    func requests() -> [RecordedAuthorizationMetadataRequest] {
        recordedRequests
    }
}

private func authorizationMetadataJSON() -> Data {
    Data(
        #"""
        {
          "authorization_endpoint": "https://auth.example/authorize",
          "token_endpoint": "https://auth.example/token",
          "registration_endpoint": "https://auth.example/register",
          "scopes_supported": ["profile", "email"],
          "response_types_supported": ["code"],
          "client_id_metadata_document_supported": true
        }
        """#.utf8
    )
}
