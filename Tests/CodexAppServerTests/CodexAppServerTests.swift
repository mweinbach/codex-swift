@testable import CodexAppServer
import CodexCore
import Foundation
import XCTest

final class CodexAppServerTests: XCTestCase {
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

    private func decode(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
