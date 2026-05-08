import CodexCore
import Foundation
import XCTest

final class McpOAuthDiscoveryTests: XCTestCase {
    func testDiscoveryPathsMatchRustOrdering() {
        XCTAssertEqual(
            McpOAuthDiscovery.discoveryPaths(basePath: ""),
            ["/.well-known/oauth-authorization-server"]
        )
        XCTAssertEqual(
            McpOAuthDiscovery.discoveryPaths(basePath: "/mcp"),
            [
                "/.well-known/oauth-authorization-server/mcp",
                "/mcp/.well-known/oauth-authorization-server",
                "/.well-known/oauth-authorization-server"
            ]
        )
        XCTAssertEqual(
            McpOAuthDiscovery.discoveryPaths(basePath: "/api/mcp/"),
            [
                "/.well-known/oauth-authorization-server/api/mcp",
                "/api/mcp/.well-known/oauth-authorization-server",
                "/.well-known/oauth-authorization-server"
            ]
        )
    }

    func testSupportsOAuthLoginProbesCandidatesWithDiscoveryAndDefaultHeaders() async throws {
        let probe = OAuthDiscoveryProbe(responses: [
            "/.well-known/oauth-authorization-server/mcp": McpOAuthDiscoveryHTTPResponse(
                statusCode: 404,
                body: Data()
            ),
            "/mcp/.well-known/oauth-authorization-server": McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"authorization_endpoint":"https://auth.example/authorize","token_endpoint":"https://auth.example/token"}"#.utf8)
            )
        ])

        let supported = try await McpOAuthDiscovery.supportsOAuthLogin(
            url: "https://example.test/mcp?keep=query",
            httpHeaders: [
                "X-Static": "static",
                "Bad Header": "skipped"
            ],
            envHttpHeaders: [
                "Authorization": "TOKEN_ENV",
                "X-Empty": "EMPTY_ENV"
            ],
            environment: [
                "TOKEN_ENV": "Bearer env-token",
                "EMPTY_ENV": "  "
            ],
            transport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertTrue(supported)
        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.path), [
            "/.well-known/oauth-authorization-server/mcp",
            "/mcp/.well-known/oauth-authorization-server"
        ])
        XCTAssertEqual(requests.map(\.query), ["keep=query", "keep=query"])
        XCTAssertEqual(requests[0].headers[McpOAuthDiscovery.discoveryHeader], McpOAuthDiscovery.discoveryVersion)
        XCTAssertEqual(requests[0].headers["X-Static"], "static")
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer env-token")
        XCTAssertNil(requests[0].headers["Bad Header"])
        XCTAssertNil(requests[0].headers["X-Empty"])
    }

    func testSupportsOAuthLoginReturnsFalseForIncompleteMetadata() async throws {
        let probe = OAuthDiscoveryProbe(responses: [
            "/.well-known/oauth-authorization-server": McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"authorization_endpoint":"https://auth.example/authorize"}"#.utf8)
            )
        ])

        let supported = try await McpOAuthDiscovery.supportsOAuthLogin(
            url: "https://example.test",
            environment: [:],
            transport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertFalse(supported)
        let paths = await probe.paths()
        XCTAssertEqual(paths, ["/.well-known/oauth-authorization-server"])
    }

    func testAsyncAuthStatusResolverReportsNotLoggedInWhenDiscoverySucceeds() async throws {
        let temp = try OAuthDiscoveryTemporaryDirectory()
        let probe = OAuthDiscoveryProbe(responses: [
            "/.well-known/oauth-authorization-server/mcp": McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"authorization_endpoint":"https://auth.example/authorize","token_endpoint":"https://auth.example/token"}"#.utf8)
            )
        ])
        let servers = [
            "linear": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://linear.example/mcp",
                    bearerTokenEnvVar: nil,
                    httpHeaders: nil,
                    envHttpHeaders: nil
                )
            )
        ]

        let statuses = await McpAuthStatusResolver.authStatuses(
            for: servers,
            codexHome: temp.url,
            storeMode: .file,
            environment: [:],
            discoveryTransport: { request in
                await probe.handle(request)
            }
        )

        XCTAssertEqual(statuses, ["linear": .notLoggedIn])
    }
}

private struct RecordedOAuthDiscoveryRequest: Equatable, Sendable {
    let path: String
    let query: String?
    let headers: [String: String]
}

private actor OAuthDiscoveryProbe {
    private let responses: [String: McpOAuthDiscoveryHTTPResponse]
    private var recordedRequests: [RecordedOAuthDiscoveryRequest] = []

    init(responses: [String: McpOAuthDiscoveryHTTPResponse]) {
        self.responses = responses
    }

    func handle(_ request: URLRequest) -> McpOAuthDiscoveryHTTPResponse {
        recordedRequests.append(RecordedOAuthDiscoveryRequest(
            path: request.url?.path ?? "",
            query: request.url?.query,
            headers: request.allHTTPHeaderFields ?? [:]
        ))
        return responses[request.url?.path ?? ""] ?? McpOAuthDiscoveryHTTPResponse(statusCode: 404, body: Data())
    }

    func requests() -> [RecordedOAuthDiscoveryRequest] {
        recordedRequests
    }

    func paths() -> [String] {
        recordedRequests.map(\.path)
    }
}

private final class OAuthDiscoveryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-mcp-oauth-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
