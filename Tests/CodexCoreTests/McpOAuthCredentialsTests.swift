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

    func testLoadOAuthTokensReadsFallbackFileAndRestoresExpiresIn() throws {
        let temp = try McpOAuthTemporaryDirectory()
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                "stub": fallbackEntry(
                    serverName: "github",
                    serverURL: "https://example.com/mcp",
                    expiresAt: 4_600_000
                )
            ]
        )

        let tokens = try McpOAuthCredentialStore.loadOAuthTokens(
            serverName: "github",
            url: "https://example.com/mcp",
            codexHome: temp.url,
            mode: .file,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(tokens?.serverName, "github")
        XCTAssertEqual(tokens?.url, "https://example.com/mcp")
        XCTAssertEqual(tokens?.clientID, "client-id")
        XCTAssertEqual(tokens?.tokenResponse.accessToken, "access-token")
        XCTAssertEqual(tokens?.tokenResponse.refreshToken, "refresh-token")
        XCTAssertEqual(tokens?.tokenResponse.scopes, ["profile"])
        XCTAssertEqual(tokens?.tokenResponse.expiresIn, 3_600)
        XCTAssertEqual(tokens?.expiresAt, 4_600_000)
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

    func testAuthStatusResolverIgnoresStoredOAuthTokensForDisabledServersLikeRust() throws {
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
                ),
                enabled: false
            )
        ]

        XCTAssertEqual(
            McpAuthStatusResolver.authStatuses(
                for: servers,
                codexHome: temp.url,
                storeMode: .file
            ),
            ["linear": .unsupported]
        )
    }

    func testSaveOAuthTokensWritesFallbackFileShapeAndPermissions() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let tokens = sampleStoredTokens(expiresAt: nil)

        try McpOAuthCredentialStore.saveOAuthTokens(
            tokens,
            codexHome: temp.url,
            mode: .file,
            now: Date(timeIntervalSince1970: 1_000)
        )

        let key = try McpOAuthCredentialStore.storeKey(serverName: tokens.serverName, url: tokens.url)
        let fallbackURL = temp.url.appendingPathComponent(McpOAuthCredentialStore.fallbackFilename)
        let data = try Data(contentsOf: fallbackURL)
        let store = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let entry = try XCTUnwrap(store[key])
        XCTAssertEqual(entry["server_name"] as? String, tokens.serverName)
        XCTAssertEqual(entry["server_url"] as? String, tokens.url)
        XCTAssertEqual(entry["client_id"] as? String, tokens.clientID)
        XCTAssertEqual(entry["access_token"] as? String, tokens.tokenResponse.accessToken)
        XCTAssertEqual(entry["refresh_token"] as? String, tokens.tokenResponse.refreshToken)
        XCTAssertEqual(entry["scopes"] as? [String], tokens.tokenResponse.scopes)
        XCTAssertEqual((entry["expires_at"] as? NSNumber)?.uint64Value, 4_600_000)

        let attributes = try FileManager.default.attributesOfItem(atPath: fallbackURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testSaveOAuthTokensPrefersKeyringAndRemovesFallbackFile() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let keyringStore = InMemoryMcpKeyringStore()
        let tokens = sampleStoredTokens()
        let key = try McpOAuthCredentialStore.storeKey(serverName: tokens.serverName, url: tokens.url)
        try writeFallbackStore(
            codexHome: temp.url,
            entries: [
                key: fallbackEntry(serverName: tokens.serverName, serverURL: tokens.url)
            ]
        )

        try McpOAuthCredentialStore.saveOAuthTokens(
            tokens,
            codexHome: temp.url,
            mode: .auto,
            keyringStore: keyringStore
        )

        let serialized = try XCTUnwrap(keyringStore.value(service: McpOAuthCredentialStore.keyringService, account: key))
        XCTAssertEqual(try JSONDecoder().decode(McpOAuthStoredTokens.self, from: Data(serialized.utf8)), tokens)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent(McpOAuthCredentialStore.fallbackFilename).path
        ))
    }

    func testSaveOAuthTokensFallsBackToFileWhenKeyringFailsInAutoMode() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let keyringStore = InMemoryMcpKeyringStore()
        keyringStore.saveError = McpOAuthTestError("boom")
        let tokens = sampleStoredTokens()

        try McpOAuthCredentialStore.saveOAuthTokens(
            tokens,
            codexHome: temp.url,
            mode: .auto,
            keyringStore: keyringStore
        )

        let key = try McpOAuthCredentialStore.storeKey(serverName: tokens.serverName, url: tokens.url)
        XCTAssertNil(keyringStore.value(service: McpOAuthCredentialStore.keyringService, account: key))
        XCTAssertTrue(try McpOAuthCredentialStore.hasOAuthTokens(
            serverName: tokens.serverName,
            url: tokens.url,
            codexHome: temp.url,
            mode: .file
        ))
    }

    func testLoadOAuthTokensReadsKeyringAndRestoresExpiresIn() throws {
        let temp = try McpOAuthTemporaryDirectory()
        let keyringStore = InMemoryMcpKeyringStore()
        var tokens = sampleStoredTokens(tokenExpiresIn: nil)
        let key = try McpOAuthCredentialStore.storeKey(serverName: tokens.serverName, url: tokens.url)
        let data = try JSONEncoder().encode(tokens)
        try keyringStore.save(
            service: McpOAuthCredentialStore.keyringService,
            account: key,
            value: String(decoding: data, as: UTF8.self)
        )

        tokens.tokenResponse.expiresIn = 3_600
        let loaded = try McpOAuthCredentialStore.loadOAuthTokens(
            serverName: tokens.serverName,
            url: tokens.url,
            codexHome: temp.url,
            mode: .keyring,
            keyringStore: keyringStore,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(loaded, tokens)
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

private func fallbackEntry(serverName: String, serverURL: String, expiresAt: UInt64? = nil) -> [String: Any] {
    var entry: [String: Any] = [
        "server_name": serverName,
        "server_url": serverURL,
        "client_id": "client-id",
        "access_token": "access-token",
        "refresh_token": "refresh-token",
        "scopes": ["profile"]
    ]
    if let expiresAt {
        entry["expires_at"] = expiresAt
    }
    return entry
}

private func sampleStoredTokens(
    expiresAt: UInt64? = 4_600_000,
    tokenExpiresIn: UInt64? = 3_600
) -> McpOAuthStoredTokens {
    McpOAuthStoredTokens(
        serverName: "test-server",
        url: "https://example.test",
        clientID: "client-id",
        tokenResponse: McpOAuthTokenResponse(
            accessToken: "access-token",
            expiresIn: tokenExpiresIn,
            refreshToken: "refresh-token",
            scopes: ["scope-a", "scope-b"]
        ),
        expiresAt: expiresAt
    )
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
