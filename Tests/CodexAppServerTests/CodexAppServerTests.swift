@testable import CodexAppServer
import CodexCore
import Foundation
import XCTest

final class CodexAppServerTests: XCTestCase {
    private var retainedTemporaryDirectories: [TemporaryDirectory] = []

    func testThreadListReturnsRolloutsWithRustAppServerShape() throws {
        let temp = try TemporaryDirectory()
        let newestID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Hello A",
            provider: "openai"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T12-00-00",
            timestamp: "2025-01-01T12:00:00Z",
            preview: "Hello B",
            provider: "other"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":1,"modelProviders":["openai"]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertNotNil(result["nextCursor"] as? String)
        XCTAssertEqual(data[0]["id"] as? String, newestID)
        XCTAssertEqual(data[0]["preview"] as? String, "Hello A")
        XCTAssertEqual(data[0]["modelProvider"] as? String, "openai")
        XCTAssertEqual(data[0]["createdAt"] as? Int, 1_735_819_200)
        XCTAssertEqual(data[0]["cwd"] as? String, "/")
        XCTAssertEqual(data[0]["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(data[0]["source"] as? String, "cli")
        XCTAssertEqual((data[0]["turns"] as? [Any])?.count, 0)
    }

    func testLegacyListConversationsUsesPageSizeCursorAndDefaultProvider() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Hello A",
            provider: nil
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T12-00-00",
            timestamp: "2025-01-01T12:00:00Z",
            preview: "Hello B",
            provider: "other"
        )

        let first = try appServerResponse(
            #"{"id":"list","method":"listConversations","params":{"pageSize":1,"modelProviders":["openai"]}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstItems = try XCTUnwrap(firstResult["items"] as? [[String: Any]])
        XCTAssertEqual(firstItems.count, 1)
        XCTAssertEqual(firstItems[0]["preview"] as? String, "Hello A")
        XCTAssertEqual(firstItems[0]["modelProvider"] as? String, "openai")
        XCTAssertEqual(firstItems[0]["source"] as? String, "cli")
        XCTAssertNotNil(firstResult["nextCursor"] as? String)

        let second = try appServerResponse(
            #"{"id":"list2","method":"listConversations","params":{"pageSize":1,"modelProviders":["openai"],"cursor":"\#(firstResult["nextCursor"] as! String)"}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(second["result"] as? [String: Any])
        let secondItems = try XCTUnwrap(secondResult["items"] as? [[String: Any]])
        XCTAssertTrue(secondItems.isEmpty)
        XCTAssertNil(secondResult["nextCursor"])
    }

    func testListingWithoutProviderFilterDefaultsToConfiguredProvider() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Other provider",
            provider: "other"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Default provider",
            provider: "openai"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Default provider"])
    }

    func testEmptyProviderFilterListsAllInteractiveProviders() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Other provider",
            provider: "other"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Default provider",
            provider: "openai"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"modelProviders":[]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Other provider", "Default provider"])
    }

    func testThreadListFiltersToInteractiveSourcesAndClampsLimit() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Exec session",
            provider: "openai",
            source: .exec
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Interactive session",
            provider: "openai",
            source: .cli
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":0}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Interactive session"])
    }

    func testThreadArchiveMovesRolloutIntoArchivedDirectory() throws {
        let temp = try TemporaryDirectory()
        let id = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "archive me",
            provider: "openai"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: id))

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/archive","params":{"threadId":"\#(id)"}}"#,
            codexHome: temp.url
        )

        XCTAssertNotNil(response["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: rolloutPath))
        let archivedPath = temp.url
            .appendingPathComponent("archived_sessions", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: rolloutPath).lastPathComponent, isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedPath.path))
    }

    func testArchiveConversationMovesExplicitRolloutIntoArchivedDirectory() throws {
        let temp = try TemporaryDirectory()
        let id = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "archive legacy",
            provider: "openai"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: id))

        let response = try appServerResponse(
            #"{"id":1,"method":"archiveConversation","params":{"conversation_id":"\#(id)","rollout_path":"\#(rolloutPath)"}}"#,
            codexHome: temp.url
        )

        XCTAssertNotNil(response["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: rolloutPath))
        let archivedPath = temp.url
            .appendingPathComponent("archived_sessions", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: rolloutPath).lastPathComponent, isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedPath.path))
    }

    func testArchiveConversationRejectsRolloutOutsideSessionsDirectory() throws {
        let temp = try TemporaryDirectory()
        let id = UUID().uuidString.lowercased()
        let path = temp.url.appendingPathComponent("rollout-2025-01-02T03-04-05-\(id).jsonl")
        try "not a session".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: temp.url.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"archiveConversation","params":{"conversation_id":"\#(id)","rollout_path":"\#(path.path)"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "rollout path `\(path.path)` must be in sessions directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testInitializeUsesAppServerJSONRPCShapeWithoutJsonrpcField() throws {
        let temp = try TemporaryDirectory()
        let response = try appServerResponse(
            #"{"id":9,"method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#,
            codexHome: temp.url,
            initializeFirst: false
        )
        XCTAssertEqual(response["id"] as? Int, 9)
        XCTAssertNil(response["jsonrpc"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let userAgent = try XCTUnwrap(result["userAgent"] as? String)
        XCTAssertTrue(userAgent.hasPrefix("codex_swift/0.0.0 "))
        XCTAssertTrue(userAgent.hasSuffix(" (test; 0)"))
    }

    func testRequestsRequireInitializeAndRejectDuplicateInitialize() throws {
        let temp = try TemporaryDirectory()
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: temp.url))

        let beforeInit = try decode(processor.processLine(Data(#"{"id":1,"method":"thread/list","params":{}}"#.utf8)))
        let beforeError = try XCTUnwrap(beforeInit["error"] as? [String: Any])
        XCTAssertEqual(beforeError["code"] as? Int, -32600)
        XCTAssertEqual(beforeError["message"] as? String, "Not initialized")

        _ = try decode(processor.processLine(Data(#"{"id":2,"method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        let duplicate = try decode(processor.processLine(Data(#"{"id":3,"method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        let duplicateError = try XCTUnwrap(duplicate["error"] as? [String: Any])
        XCTAssertEqual(duplicateError["code"] as? Int, -32600)
        XCTAssertEqual(duplicateError["message"] as? String, "Already initialized")
    }

    func testGetUserAgentReturnsInitializedUserAgent() throws {
        let temp = try TemporaryDirectory()
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: temp.url))

        let initialize = try decode(processor.processLine(Data(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-app-server-tests","version":"0.1.0"}}}"#.utf8)))
        let initializedAgent = try XCTUnwrap((initialize["result"] as? [String: Any])?["userAgent"] as? String)
        let response = try decode(processor.processLine(Data(#"{"id":2,"method":"getUserAgent"}"#.utf8)))
        let result = try XCTUnwrap(response["result"] as? [String: Any])

        XCTAssertEqual(result["userAgent"] as? String, initializedAgent)
        XCTAssertTrue(initializedAgent.hasSuffix(" (codex-app-server-tests; 0.1.0)"))
    }

    func testGetAuthStatusReportsAPIKeyAndOptionalToken() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-test")

        let status = try appServerResponse(
            #"{"id":1,"method":"getAuthStatus","params":{}}"#,
            codexHome: temp.url
        )
        let statusResult = try XCTUnwrap(status["result"] as? [String: Any])
        XCTAssertEqual(statusResult["authMethod"] as? String, "apikey")
        XCTAssertTrue(statusResult["authToken"] is NSNull)
        XCTAssertEqual(statusResult["requiresOpenAIAuth"] as? Bool, true)

        let withToken = try appServerResponse(
            #"{"id":2,"method":"getAuthStatus","params":{"includeToken":true}}"#,
            codexHome: temp.url
        )
        let tokenResult = try XCTUnwrap(withToken["result"] as? [String: Any])
        XCTAssertEqual(tokenResult["authMethod"] as? String, "apikey")
        XCTAssertEqual(tokenResult["authToken"] as? String, "sk-test")
        XCTAssertEqual(tokenResult["requiresOpenAIAuth"] as? Bool, true)
    }

    func testLoginApiKeyPersistsAuthAndEmitsLegacyNotification() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"loginApiKey","params":{"apiKey":"sk-test-key"}}"#.utf8)))
        XCTAssertEqual(messages.count, 2)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(messages[1]["method"] as? String, "authStatusChange")
        XCTAssertEqual((messages[1]["params"] as? [String: Any])?["authMethod"] as? String, "apikey")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))

        let status = try decode(processor.processLine(Data(#"{"id":2,"method":"getAuthStatus","params":{"includeToken":true}}"#.utf8)))
        let result = try XCTUnwrap(status["result"] as? [String: Any])
        XCTAssertEqual(result["authMethod"] as? String, "apikey")
        XCTAssertEqual(result["authToken"] as? String, "sk-test-key")
    }

    func testLoginApiKeyRejectedWhenForcedChatGPT() throws {
        let temp = try TemporaryDirectory()
        try #"forced_login_method = "chatgpt""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"loginApiKey","params":{"apiKey":"sk-test-key"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "API key login is disabled. Use ChatGPT login instead.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testLogoutChatGPTRemovesAuthAndEmitsLegacyNotification() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-test")
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"logoutChatGpt"}"#.utf8)))
        XCTAssertEqual(messages.count, 2)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(messages[1]["method"] as? String, "authStatusChange")
        XCTAssertTrue((messages[1]["params"] as? [String: Any])?["authMethod"] is NSNull)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))

        let status = try decode(processor.processLine(Data(#"{"id":2,"method":"getAuthStatus","params":{"includeToken":true}}"#.utf8)))
        let result = try XCTUnwrap(status["result"] as? [String: Any])
        XCTAssertTrue(result["authMethod"] is NSNull)
        XCTAssertTrue(result["authToken"] is NSNull)
    }

    func testAccountLoginAPIKeyPersistsAuthAndEmitsV2Notifications() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"apiKey","apiKey":"sk-test-key"}}"#.utf8)))
        XCTAssertEqual(messages.count, 3)

        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(result["type"] as? String, "apiKey")

        XCTAssertEqual(messages[1]["method"] as? String, "account/login/completed")
        let completed = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertTrue(completed["loginId"] is NSNull)
        XCTAssertEqual(completed["success"] as? Bool, true)
        XCTAssertTrue(completed["error"] is NSNull)

        XCTAssertEqual(messages[2]["method"] as? String, "account/updated")
        XCTAssertEqual((messages[2]["params"] as? [String: Any])?["authMode"] as? String, "apikey")

        let account = try decode(processor.processLine(Data(#"{"id":2,"method":"account/read","params":{}}"#.utf8)))
        let accountResult = try XCTUnwrap(account["result"] as? [String: Any])
        let accountPayload = try XCTUnwrap(accountResult["account"] as? [String: Any])
        XCTAssertEqual(accountPayload["type"] as? String, "apiKey")
    }

    func testAccountLoginAPIKeyRejectedWhenForcedChatGPT() throws {
        let temp = try TemporaryDirectory()
        try #"forced_login_method = "chatgpt""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"account/login/start","params":{"type":"apiKey","apiKey":"sk-test-key"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "API key login is disabled. Use ChatGPT login instead.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testAccountLogoutRemovesAuthAndEmitsV2Notification() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-test")
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"account/logout"}"#.utf8)))
        XCTAssertEqual(messages.count, 2)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(messages[1]["method"] as? String, "account/updated")
        XCTAssertTrue((messages[1]["params"] as? [String: Any])?["authMode"] is NSNull)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))

        let account = try decode(processor.processLine(Data(#"{"id":2,"method":"account/read","params":{}}"#.utf8)))
        let result = try XCTUnwrap(account["result"] as? [String: Any])
        XCTAssertTrue(result["account"] is NSNull)
    }

    func testAccountAndUserInfoReportChatGPTIdentity() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: temp.url,
            apiKey: nil,
            idToken: fakeJWT(email: "user@example.com", plan: "pro"),
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )

        let accountResponse = try appServerResponse(
            #"{"id":1,"method":"account/read","params":{"refreshToken":false}}"#,
            codexHome: temp.url
        )
        let accountResult = try XCTUnwrap(accountResponse["result"] as? [String: Any])
        let account = try XCTUnwrap(accountResult["account"] as? [String: Any])
        XCTAssertEqual(account["type"] as? String, "chatgpt")
        XCTAssertEqual(account["email"] as? String, "user@example.com")
        XCTAssertEqual(account["planType"] as? String, "pro")
        XCTAssertEqual(accountResult["requiresOpenAIAuth"] as? Bool, true)

        let userInfoResponse = try appServerResponse(
            #"{"id":2,"method":"userInfo"}"#,
            codexHome: temp.url
        )
        let userInfo = try XCTUnwrap(userInfoResponse["result"] as? [String: Any])
        XCTAssertEqual(userInfo["allegedUserEmail"] as? String, "user@example.com")
    }

    func testAuthReadAPIsRespectProviderWithoutOpenAIAuth() throws {
        let temp = try TemporaryDirectory()
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [:]
        )
        let processor = try initializedProcessor(configuration: configuration)

        let status = try decode(processor.processLine(Data(#"{"id":1,"method":"getAuthStatus","params":{"includeToken":true}}"#.utf8)))
        let statusResult = try XCTUnwrap(status["result"] as? [String: Any])
        XCTAssertTrue(statusResult["authMethod"] is NSNull)
        XCTAssertTrue(statusResult["authToken"] is NSNull)
        XCTAssertEqual(statusResult["requiresOpenAIAuth"] as? Bool, false)

        let accountResponse = try decode(processor.processLine(Data(#"{"id":2,"method":"account/read","params":{}}"#.utf8)))
        let accountResult = try XCTUnwrap(accountResponse["result"] as? [String: Any])
        XCTAssertTrue(accountResult["account"] is NSNull)
        XCTAssertEqual(accountResult["requiresOpenAIAuth"] as? Bool, false)
    }

    func testModelListReturnsRustV2ShapeAndPaginates() throws {
        let temp = try TemporaryDirectory()

        let first = try appServerResponse(
            #"{"id":1,"method":"model/list","params":{"limit":2}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.count, 2)
        XCTAssertEqual(firstData[0]["id"] as? String, "gpt-5.1-codex-max")
        XCTAssertEqual(firstData[0]["displayName"] as? String, "gpt-5.1-codex-max")
        XCTAssertEqual(firstData[0]["defaultReasoningEffort"] as? String, "medium")
        XCTAssertEqual(firstData[0]["isDefault"] as? Bool, true)
        let efforts = try XCTUnwrap(firstData[0]["supportedReasoningEfforts"] as? [[String: Any]])
        XCTAssertEqual(efforts[0]["reasoningEffort"] as? String, "low")
        XCTAssertNotNil(firstResult["nextCursor"] as? String)

        let second = try appServerResponse(
            #"{"id":2,"method":"model/list","params":{"limit":2,"cursor":"\#(firstResult["nextCursor"] as! String)"}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(second["result"] as? [String: Any])
        let secondData = try XCTUnwrap(secondResult["data"] as? [[String: Any]])
        XCTAssertFalse(secondData.isEmpty)
        XCTAssertNotEqual(secondData[0]["id"] as? String, firstData[0]["id"] as? String)
    }

    func testModelListRejectsInvalidCursorWithRustErrorCode() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"model/list","params":{"cursor":"bogus"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid cursor: bogus")
    }

    func testSkillsListReturnsRepoUserAndSystemSkillsWithPriorityDedupe() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let repoSkill = cwd.url.appendingPathComponent(".codex/skills/repo/SKILL.md", isDirectory: false)
        let userSkill = codexHome.url.appendingPathComponent("skills/user/SKILL.md", isDirectory: false)
        let duplicateUserSkill = codexHome.url.appendingPathComponent("skills/duplicate/SKILL.md", isDirectory: false)
        let systemSkill = codexHome.url.appendingPathComponent("skills/.system/system/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: repoSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: duplicateUserSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillContents(name: "duplicate", description: "repo wins").write(to: repoSkill, atomically: true, encoding: .utf8)
        try skillContents(name: "alpha", description: "user skill", shortDescription: "short user")
            .write(to: userSkill, atomically: true, encoding: .utf8)
        try skillContents(name: "duplicate", description: "user duplicate")
            .write(to: duplicateUserSkill, atomically: true, encoding: .utf8)
        try skillContents(name: "system", description: "system skill").write(to: systemSkill, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"skills/list","params":{"cwds":["\#(cwd.url.path)"],"forceReload":true}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["cwd"] as? String, cwd.url.path)
        let skills = try XCTUnwrap(data[0]["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.map { $0["name"] as? String }, ["alpha", "duplicate", "system"])
        XCTAssertEqual(skills[0]["scope"] as? String, "user")
        XCTAssertEqual(skills[0]["shortDescription"] as? String, "short user")
        XCTAssertEqual(skills[1]["description"] as? String, "repo wins")
        XCTAssertEqual(skills[1]["scope"] as? String, "repo")
        XCTAssertEqual(skills[2]["scope"] as? String, "system")
        XCTAssertEqual((data[0]["errors"] as? [Any])?.count, 0)
    }

    func testSkillsListReportsInvalidUserSkillErrors() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let badSkill = codexHome.url.appendingPathComponent("skills/bad/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: badSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        name: bad
        ---
        body
        """.write(to: badSkill, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"skills/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let errors = try XCTUnwrap(data[0]["errors"] as? [[String: Any]])
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(
            (errors[0]["path"] as? String)?.replacingOccurrences(of: "/private/var/", with: "/var/"),
            badSkill.path
        )
        XCTAssertEqual(errors[0]["message"] as? String, "missing field `description`")
    }

    func testConfigReadReturnsEffectiveConfigOriginsAndLayers() throws {
        let temp = try TemporaryDirectory()
        try """
        model = "gpt-user"
        sandbox_mode = "workspace-write"

        [tools]
        web_search = true
        view_image = false
        """.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"config/read","params":{"includeLayers":true}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "gpt-user")
        XCTAssertEqual(config["sandbox_mode"] as? String, "workspace-write")
        let tools = try XCTUnwrap(config["tools"] as? [String: Any])
        XCTAssertEqual(tools["web_search"] as? Bool, true)
        XCTAssertEqual(tools["view_image"] as? Bool, false)

        let origins = try XCTUnwrap(result["origins"] as? [String: Any])
        let modelOrigin = try XCTUnwrap(origins["model"] as? [String: Any])
        let modelOriginName = try XCTUnwrap(modelOrigin["name"] as? [String: Any])
        XCTAssertEqual(modelOriginName["type"] as? String, "user")
        XCTAssertEqual(
            modelOriginName["file"] as? String,
            temp.url.appendingPathComponent("config.toml", isDirectory: false).standardizedFileURL.path
        )

        let webSearchOrigin = try XCTUnwrap(origins["tools.web_search"] as? [String: Any])
        let webSearchOriginName = try XCTUnwrap(webSearchOrigin["name"] as? [String: Any])
        XCTAssertEqual(webSearchOriginName["type"] as? String, "user")
        XCTAssertTrue((modelOrigin["version"] as? String)?.hasPrefix("sha256:") == true)

        let layers = try XCTUnwrap(result["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.first?["name"].flatMap { ($0 as? [String: Any])?["type"] as? String }, "user")
        XCTAssertEqual((layers.first?["config"] as? [String: Any])?["model"] as? String, "gpt-user")
    }

    func testConfigReadOmitsLayersByDefault() throws {
        let temp = try TemporaryDirectory()
        try #"model = "gpt-user""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"config/read","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual((result["config"] as? [String: Any])?["model"] as? String, "gpt-user")
        XCTAssertNotNil(result["origins"] as? [String: Any])
        XCTAssertNil(result["layers"])
    }

    func testConfigValueWriteReplacesValueAndReturnsRustShape() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try #"model = "gpt-old""#.write(to: configFile, atomically: true, encoding: .utf8)

        let read = try appServerResponse(
            #"{"id":1,"method":"config/read","params":{}}"#,
            codexHome: temp.url
        )
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let origins = try XCTUnwrap(readResult["origins"] as? [String: Any])
        let modelOrigin = try XCTUnwrap(origins["model"] as? [String: Any])
        let expectedVersion = try XCTUnwrap(modelOrigin["version"] as? String)

        let response = try appServerResponse(
            #"{"id":2,"method":"config/value/write","params":{"keyPath":"model","value":"gpt-new","mergeStrategy":"replace","expectedVersion":"\#(expectedVersion)"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertTrue((result["version"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertEqual(result["filePath"] as? String, configFile.standardizedFileURL.path)
        XCTAssertTrue(result["overriddenMetadata"] is NSNull)

        let verify = try appServerResponse(
            #"{"id":3,"method":"config/read","params":{}}"#,
            codexHome: temp.url
        )
        let verifyResult = try XCTUnwrap(verify["result"] as? [String: Any])
        let config = try XCTUnwrap(verifyResult["config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "gpt-new")
    }

    func testConfigValueWriteRejectsVersionConflict() throws {
        let temp = try TemporaryDirectory()
        try #"model = "gpt-old""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"model","value":"gpt-new","mergeStrategy":"replace","expectedVersion":"sha256:stale"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "Configuration was modified since last read. Fetch latest version and retry."
        )
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["config_write_error_code"] as? String, "configVersionConflict")
    }

    func testConfigBatchWriteAppliesMultipleEdits() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)
        let writableRoot = temp.url.appendingPathComponent("workspace", isDirectory: true).path

        let response = try appServerResponse(
            #"{"id":1,"method":"config/batchWrite","params":{"filePath":"\#(configFile.path)","edits":[{"keyPath":"sandbox_mode","value":"workspace-write","mergeStrategy":"replace"},{"keyPath":"sandbox_workspace_write","value":{"writable_roots":["\#(writableRoot)"],"network_access":false},"mergeStrategy":"replace"}]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(result["filePath"] as? String, configFile.standardizedFileURL.path)

        let verify = try appServerResponse(
            #"{"id":2,"method":"config/read","params":{}}"#,
            codexHome: temp.url
        )
        let verifyResult = try XCTUnwrap(verify["result"] as? [String: Any])
        let config = try XCTUnwrap(verifyResult["config"] as? [String: Any])
        XCTAssertEqual(config["sandbox_mode"] as? String, "workspace-write")
        let sandbox = try XCTUnwrap(config["sandbox_workspace_write"] as? [String: Any])
        XCTAssertEqual(sandbox["writable_roots"] as? [String], [writableRoot])
        XCTAssertEqual(sandbox["network_access"] as? Bool, false)
    }

    func testGetUserSavedConfigReturnsLegacyRustShape() throws {
        let temp = try TemporaryDirectory()
        let writableRoot = temp.url.appendingPathComponent("workspace", isDirectory: true).path
        try """
        model = "gpt-5.1-codex-max"
        approval_policy = "on-request"
        sandbox_mode = "workspace-write"
        model_reasoning_summary = "detailed"
        model_reasoning_effort = "high"
        model_verbosity = "medium"
        profile = "test"
        forced_chatgpt_workspace_id = "12345678-0000-0000-0000-000000000000"
        forced_login_method = "chatgpt"

        [sandbox_workspace_write]
        writable_roots = ["\(writableRoot)"]
        network_access = true
        exclude_tmpdir_env_var = true
        exclude_slash_tmp = true

        [tools]
        web_search = false
        view_image = true

        [profiles.test]
        model = "gpt-4o"
        approval_policy = "on-request"
        model_reasoning_effort = "high"
        model_reasoning_summary = "detailed"
        model_verbosity = "medium"
        model_provider = "openai"
        chatgpt_base_url = "https://api.chatgpt.com"
        """.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"getUserSavedConfig","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        XCTAssertEqual(config["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(config["sandboxMode"] as? String, "workspace-write")
        XCTAssertEqual(config["forcedChatgptWorkspaceId"] as? String, "12345678-0000-0000-0000-000000000000")
        XCTAssertEqual(config["forcedLoginMethod"] as? String, "chatgpt")
        XCTAssertEqual(config["model"] as? String, "gpt-5.1-codex-max")
        XCTAssertEqual(config["modelReasoningEffort"] as? String, "high")
        XCTAssertEqual(config["modelReasoningSummary"] as? String, "detailed")
        XCTAssertEqual(config["modelVerbosity"] as? String, "medium")
        XCTAssertEqual(config["profile"] as? String, "test")

        let sandboxSettings = try XCTUnwrap(config["sandboxSettings"] as? [String: Any])
        XCTAssertEqual(sandboxSettings["writableRoots"] as? [String], [writableRoot])
        XCTAssertEqual(sandboxSettings["networkAccess"] as? Bool, true)
        XCTAssertEqual(sandboxSettings["excludeTmpdirEnvVar"] as? Bool, true)
        XCTAssertEqual(sandboxSettings["excludeSlashTmp"] as? Bool, true)

        let tools = try XCTUnwrap(config["tools"] as? [String: Any])
        XCTAssertEqual(tools["webSearch"] as? Bool, false)
        XCTAssertEqual(tools["viewImage"] as? Bool, true)

        let profiles = try XCTUnwrap(config["profiles"] as? [String: Any])
        let profile = try XCTUnwrap(profiles["test"] as? [String: Any])
        XCTAssertEqual(profile["model"] as? String, "gpt-4o")
        XCTAssertEqual(profile["modelProvider"] as? String, "openai")
        XCTAssertEqual(profile["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(profile["modelReasoningEffort"] as? String, "high")
        XCTAssertEqual(profile["modelReasoningSummary"] as? String, "detailed")
        XCTAssertEqual(profile["modelVerbosity"] as? String, "medium")
        XCTAssertEqual(profile["chatgptBaseUrl"] as? String, "https://api.chatgpt.com")
    }

    func testGetUserSavedConfigEmptyReturnsNullOptionsAndEmptyProfiles() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"getUserSavedConfig","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        XCTAssertTrue(config["approvalPolicy"] is NSNull)
        XCTAssertTrue(config["sandboxMode"] is NSNull)
        XCTAssertTrue(config["sandboxSettings"] is NSNull)
        XCTAssertTrue(config["forcedChatgptWorkspaceId"] is NSNull)
        XCTAssertTrue(config["forcedLoginMethod"] is NSNull)
        XCTAssertTrue(config["model"] is NSNull)
        XCTAssertTrue(config["modelReasoningEffort"] is NSNull)
        XCTAssertTrue(config["modelReasoningSummary"] is NSNull)
        XCTAssertTrue(config["modelVerbosity"] is NSNull)
        XCTAssertTrue(config["tools"] is NSNull)
        XCTAssertTrue(config["profile"] is NSNull)
        XCTAssertEqual((config["profiles"] as? [String: Any])?.isEmpty, true)
    }

    func testGitDiffToRemoteReturnsLegacyRustShape() throws {
        let (repo, branch) = try createGitRepositoryWithRemote()
        let remoteSha = try runGit(["rev-parse", "origin/\(branch)"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "modified".write(to: repo.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"gitDiffToRemote","params":{"cwd":"\#(repo.path)"}}"#,
            codexHome: try TemporaryDirectory().url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["sha"] as? String, remoteSha)
        let diff = try XCTUnwrap(result["diff"] as? String)
        XCTAssertTrue(diff.contains("test.txt"))
        XCTAssertTrue(diff.contains("untracked.txt"))
        XCTAssertTrue(diff.contains("modified"))
    }

    func testGitDiffToRemoteReturnsInvalidRequestOutsideRepo() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"gitDiffToRemote","params":{"cwd":"\#(temp.url.path)"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            #"failed to compute git diff to remote for cwd: "\#(temp.url.path)""#
        )
    }

    func testFuzzyFileSearchReturnsMatchesWithIndices() throws {
        let codexHome = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        try "x".write(to: root.url.appendingPathComponent("abc"), atomically: true, encoding: .utf8)
        try "x".write(to: root.url.appendingPathComponent("abcde"), atomically: true, encoding: .utf8)
        try "x".write(to: root.url.appendingPathComponent("abexy"), atomically: true, encoding: .utf8)
        try "x".write(to: root.url.appendingPathComponent("zzz.txt"), atomically: true, encoding: .utf8)
        let subdir = root.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "x".write(to: subdir.appendingPathComponent("abce"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"fuzzyFileSearch","params":{"query":"abe","roots":["\#(root.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let files = try XCTUnwrap(result["files"] as? [[String: Any]])
        XCTAssertEqual(files.map { $0["path"] as? String }, ["abexy", "abcde", "sub/abce"])
        XCTAssertEqual(files[0]["root"] as? String, root.url.path)
        XCTAssertEqual(files[0]["file_name"] as? String, "abexy")
        XCTAssertEqual(files[0]["indices"] as? [Int], [0, 1, 2])
        XCTAssertEqual(files[1]["indices"] as? [Int], [0, 1, 4])
        XCTAssertEqual(files[2]["indices"] as? [Int], [4, 5, 7])
    }

    func testFuzzyFileSearchEmptyQueryReturnsNoFilesAndAcceptsCancellationToken() throws {
        let codexHome = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        try "x".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)

        let empty = try appServerResponse(
            #"{"id":1,"method":"fuzzyFileSearch","params":{"query":"","roots":["\#(root.url.path)"],"cancellationToken":"token"}}"#,
            codexHome: codexHome.url
        )
        let emptyResult = try XCTUnwrap(empty["result"] as? [String: Any])
        XCTAssertEqual((emptyResult["files"] as? [Any])?.count, 0)

        let response = try appServerResponse(
            #"{"id":2,"method":"fuzzyFileSearch","params":{"query":"alp","roots":["\#(root.url.path)"],"cancellationToken":"token"}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let files = try XCTUnwrap(result["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0]["path"] as? String, "alpha.txt")
    }

    func testCommandExecReturnsStdoutStderrAndExitCode() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","pwd; echo err >&2"],"cwd":"\#(cwd.url.path)"}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(
            (result["stdout"] as? String)?.replacingOccurrences(of: "/private/var/", with: "/var/"),
            cwd.url.path + "\n"
        )
        XCTAssertEqual(result["stderr"] as? String, "err\n")
    }

    func testExecOneOffCommandResolvesExecutableThroughEnvironmentPath() throws {
        let codexHome = try TemporaryDirectory()
        let configuration = CodexAppServerConfiguration(
            codexHome: codexHome.url,
            environment: [
                "PATH": "/bin:/usr/bin",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: codexHome.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )
        let processor = try initializedProcessor(configuration: configuration)

        let response = try decode(
            processor.processLine(
                Data(#"{"id":1,"method":"execOneOffCommand","params":{"command":["sh","-c","printf legacy"]}}"#.utf8)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "legacy")
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testExecOneOffCommandRejectsEmptyCommand() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"execOneOffCommand","params":{"command":[]}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "command must not be empty")
    }

    func testSetDefaultModelPersistsTopLevelModelAndClearsReasoningEffort() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try """
        model = "gpt-5.1-codex-max"
        model_reasoning_effort = "medium"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"setDefaultModel","params":{"model":"gpt-4.1"}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(response["result"] as? [String: Any])

        let contents = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains(#"model = "gpt-4.1""#))
        XCTAssertFalse(contents.contains("model_reasoning_effort"))
    }

    func testSetDefaultModelUpdatesActiveProfile() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try """
        profile = "dev"
        model = "top-level"

        [profiles.dev]
        model = "old"
        model_reasoning_effort = "low"

        [profiles.prod]
        model = "prod"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"setDefaultModel","params":{"model":"gpt-5.1-codex","reasoningEffort":"high"}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(response["result"] as? [String: Any])

        let contents = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains(#"profile = "dev""#))
        XCTAssertTrue(contents.contains(#"model = "top-level""#))
        XCTAssertTrue(contents.contains("[profiles.dev]"))
        XCTAssertTrue(contents.contains(#"model = "gpt-5.1-codex""#))
        XCTAssertTrue(contents.contains(#"model_reasoning_effort = "high""#))
        XCTAssertTrue(contents.contains("[profiles.prod]"))
        XCTAssertTrue(contents.contains(#"model = "prod""#))
    }

    private func appServerResponse(
        _ line: String,
        codexHome: URL,
        initializeFirst: Bool = true
    ) throws -> [String: Any] {
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: codexHome))
        if initializeFirst {
            _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        }
        return try decode(processor.processLine(Data(line.utf8)))
    }

    private func initializedProcessor(configuration: CodexAppServerConfiguration) throws -> CodexAppServerMessageProcessor {
        let processor = CodexAppServerMessageProcessor(configuration: configuration)
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        return processor
    }

    private func testConfiguration(
        codexHome: URL,
        requiresOpenAIAuth: Bool = true
    ) -> CodexAppServerConfiguration {
        CodexAppServerConfiguration(
            codexHome: codexHome,
            requiresOpenAIAuth: requiresOpenAIAuth,
            environment: [
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: codexHome
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )
    }

    private func skillContents(name: String, description: String, shortDescription: String? = nil) -> String {
        var lines = [
            "---",
            "name: \(name)",
            "description: \(description)"
        ]
        if let shortDescription {
            lines.append("metadata:")
            lines.append("  short-description: \(shortDescription)")
        }
        lines.append("---")
        lines.append("body")
        return lines.joined(separator: "\n") + "\n"
    }

    private func decode(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeMessages(_ data: Data?) throws -> [[String: Any]] {
        let data = try XCTUnwrap(data)
        let payload = String(data: data, encoding: .utf8) ?? ""
        return try payload.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let lineData = Data(line.utf8)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: lineData) as? [String: Any])
        }
    }

    @discardableResult
    private func writeRollout(
        codexHome: URL,
        filenameTimestamp: String,
        timestamp: String,
        preview: String,
        provider: String?,
        source: SessionSource = .cli
    ) throws -> String {
        let id = UUID().uuidString.lowercased()
        let path = codexHome
            .appendingPathComponent("sessions/2025/01/02", isDirectory: true)
            .appendingPathComponent("rollout-\(filenameTimestamp)-\(id).jsonl", isDirectory: false)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let conversationID = try ConversationId(string: id)
        let meta = RolloutLine(
            timestamp: timestamp,
            item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                id: conversationID,
                timestamp: timestamp,
                cwd: "/",
                originator: "codex_cli_rs",
                cliVersion: "0.0.0",
                source: source,
                modelProvider: provider
            )))
        )
        let user = RolloutLine(
            timestamp: timestamp,
            item: .eventMsg(.userMessage(UserMessageEvent(message: preview)))
        )
        let encoder = JSONEncoder()
        let lines = try [meta, user].map { line in
            String(data: try encoder.encode(line), encoding: .utf8)!
        }.joined(separator: "\n")
        try lines.write(to: path, atomically: true, encoding: .utf8)
        return id
    }

    private func fakeJWT(email: String, plan: String) throws -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": plan,
                "chatgpt_account_id": "acct-test"
            ]
        ]
        return try [
            base64URL(header),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private func createGitRepositoryWithRemote() throws -> (repo: URL, branch: String) {
        let temp = try TemporaryDirectory()
        retainedTemporaryDirectories.append(temp)
        let repo = temp.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo)
        try runGit(["config", "user.name", "Test User"], cwd: repo)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo)
        try "test content".write(to: repo.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "test.txt"], cwd: repo)
        try runGit(["commit", "-m", "Initial commit"], cwd: repo)

        let remote = temp.url.appendingPathComponent("remote.git", isDirectory: true)
        try runGit(["init", "--bare", remote.path], cwd: temp.url)
        try runGit(["remote", "add", "origin", remote.path], cwd: repo)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["push", "-u", "origin", branch], cwd: repo)
        return (repo, branch)
    }

    @discardableResult
    private func runGit(
        _ args: [String],
        cwd: URL
    ) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")) failed: \(stderr)")
        return (stdout, stderr)
    }

    private func base64URL(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
