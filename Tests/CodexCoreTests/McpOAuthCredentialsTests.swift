import CodexCore
import Foundation
import XCTest

final class McpOAuthCredentialsTests: XCTestCase {
    func testStoreKeyMatchesRustPayloadHash() throws {
        XCTAssertEqual(
            try McpOAuthCredentialStore.storeKey(
                serverName: "test-server",
                url: "https://example.test"
            ),
            "test-server|3462539a3f539c2e"
        )
    }

    func testHasOAuthTokensReadsFallbackFileByEntryContents() throws {
        let temp = try McpOAuthTemporaryDirectory()
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                "stub": fallbackEntry(
                    serverName: "github",
                    serverURL: "https://example.com/mcp"
                )
            ]
        )

        XCTAssertTrue(try McpOAuthCredentialStore.hasOAuthTokens(
            serverName: "github",
            url: "https://example.com/mcp",
            codexHome: temp.url,
            mode: .file
        ))
        XCTAssertFalse(try McpOAuthCredentialStore.hasOAuthTokens(
            serverName: "github",
            url: "https://example.com/other",
            codexHome: temp.url,
            mode: .file
        ))
    }

    func testAuthStatusResolverReportsStoredOAuthTokens() throws {
        let temp = try McpOAuthTemporaryDirectory()
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                "stub": fallbackEntry(
                    serverName: "linear",
                    serverURL: "https://linear.example/mcp"
                )
            ]
        )
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

        XCTAssertEqual(
            McpAuthStatusResolver.authStatuses(
                for: servers,
                codexHome: temp.url,
                storeMode: .file
            ),
            ["linear": .oauth]
        )
    }

    func testDeleteOAuthTokensRemovesKeyringAndFallbackFile() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let keyringStore = InMemoryMcpKeyringStore()
        let serverName = "linear"
        let serverURL = "https://linear.example/mcp"
        let key = try McpOAuthCredentialStore.storeKey(serverName: serverName, url: serverURL)
        try keyringStore.save(
            service: McpOAuthCredentialStore.keyringService,
            account: key,
            value: #"{"server_name":"linear"}"#
        )
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                key: fallbackEntry(
                    serverName: serverName,
                    serverURL: serverURL
                )
            ]
        )

        XCTAssertTrue(try McpOAuthCredentialStore.deleteOAuthTokens(
            serverName: serverName,
            url: serverURL,
            codexHome: temp.url,
            mode: .auto,
            keyringStore: keyringStore
        ))
        XCTAssertNil(keyringStore.value(service: McpOAuthCredentialStore.keyringService, account: key))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent(McpOAuthCredentialStore.fallbackFilename).path
        ))
        XCTAssertFalse(try McpOAuthCredentialStore.deleteOAuthTokens(
            serverName: serverName,
            url: serverURL,
            codexHome: temp.url,
            mode: .auto,
            keyringStore: keyringStore
        ))
    }

    func testDeleteOAuthTokensIgnoresKeyringErrorsInFileMode() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let keyringStore = InMemoryMcpKeyringStore()
        keyringStore.deleteError = McpOAuthTestError("boom")
        let serverName = "linear"
        let serverURL = "https://linear.example/mcp"
        let key = try McpOAuthCredentialStore.storeKey(serverName: serverName, url: serverURL)
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                key: fallbackEntry(
                    serverName: serverName,
                    serverURL: serverURL
                )
            ]
        )

        XCTAssertTrue(try McpOAuthCredentialStore.deleteOAuthTokens(
            serverName: serverName,
            url: serverURL,
            codexHome: temp.url,
            mode: .file,
            keyringStore: keyringStore
        ))
    }
}

private final class McpOAuthTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-mcp-oauth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func fallbackEntry(serverName: String, serverURL: String) -> [String: Any] {
    [
        "server_name": serverName,
        "server_url": serverURL,
        "client_id": "client-id",
        "access_token": "access-token",
        "refresh_token": "refresh-token",
        "scopes": ["profile"]
    ]
}

private func writeFallbackStore(codexHome: URL, entries: [String: [String: Any]]) throws {
    let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
    try data.write(to: codexHome.appendingPathComponent(McpOAuthCredentialStore.fallbackFilename))
}

private struct McpOAuthTestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class InMemoryMcpKeyringStore: AuthKeyringStore, @unchecked Sendable {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var entries: [Key: String] = [:]

    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    func load(service: String, account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return entries[Key(service: service, account: account)]
    }

    func save(service: String, account: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let saveError {
            throw saveError
        }
        entries[Key(service: service, account: account)] = value
    }

    func delete(service: String, account: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let deleteError {
            throw deleteError
        }
        return entries.removeValue(forKey: Key(service: service, account: account)) != nil
    }

    func value(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[Key(service: service, account: account)]
    }
}
