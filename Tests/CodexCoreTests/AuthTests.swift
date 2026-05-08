import CodexCore
import XCTest

final class AuthTests: XCTestCase {
    func testAuthCredentialsStoreModeUsesLowercaseWireValues() throws {
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""file""#.utf8)), .file)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""keyring""#.utf8)), .keyring)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""auto""#.utf8)), .auto)
        XCTAssertEqual(String(data: try JSONEncoder().encode(AuthCredentialsStoreMode.file), encoding: .utf8), #""file""#)
    }

    func testLoadsFileBackedAuthJSONTokenData() throws {
        let dir = try AuthTemporaryDirectory()
        let auth = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "header.payload.signature",
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "account-id"
          },
          "last_refresh": "2026-05-07T00:00:00Z"
        }
        """
        try auth.write(to: dir.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let loaded = try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)
        XCTAssertEqual(loaded?.tokens?.accessToken, "access-token")
        XCTAssertEqual(loaded?.tokens?.accountID, "account-id")
        XCTAssertEqual(loaded?.lastRefresh, "2026-05-07T00:00:00Z")
    }

    func testMissingAuthJSONReturnsNil() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertNil(try CodexAuthStorage.loadTokenData(codexHome: dir.url, mode: .auto))
    }

    func testKeyringModeReportsUnavailableUntilPorted() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertThrowsError(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .keyring)) { error in
            XCTAssertEqual(error as? CodexAuthStorageError, .keyringStoreNotAvailable)
        }
    }

    func testCodexHomeHonorsExistingEnvironmentPath() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertEqual(try CodexHome.find(environment: ["CODEX_HOME": dir.url.path]).path, dir.url.resolvingSymlinksInPath().path)
    }

    func testCodexHomeRejectsMissingEnvironmentPath() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        XCTAssertThrowsError(try CodexHome.find(environment: ["CODEX_HOME": missing])) { error in
            XCTAssertEqual(error as? CodexHomeError, .codexHomeDoesNotExist(missing))
        }
    }
}

private final class AuthTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
