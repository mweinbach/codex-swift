@testable import CodexAppServer
import CodexCore
import Foundation
import XCTest

final class CodexAppServerTests: XCTestCase {
    private var retainedTemporaryDirectories: [TemporaryDirectory] = []
    private static let rateLimitsUsageJSON = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 42,
          "limit_window_seconds": 3600,
          "reset_after_seconds": 120,
          "reset_at": 1737000000
        },
        "secondary_window": {
          "used_percent": 5,
          "limit_window_seconds": 86400,
          "reset_after_seconds": 43200,
          "reset_at": 1737043200
        }
      }
    }
    """

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

    func testThreadStartCreatesRolloutAndEmitsStartedNotification() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        retainedTemporaryDirectories.append(cwd)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"model":"gpt-test","modelProvider":"mock_provider","cwd":"\#(cwd.url.path)","approvalPolicy":"never","sandbox":"workspace-write","developerInstructions":"dev notes"}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(result["model"] as? String, "gpt-test")
        XCTAssertEqual(result["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(result["cwd"] as? String, cwd.url.path)
        XCTAssertEqual(result["approvalPolicy"] as? String, "never")
        XCTAssertEqual((result["sandbox"] as? [String: Any])?["type"] as? String, "workspace-write")
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        XCTAssertEqual(thread["preview"] as? String, "")
        XCTAssertEqual(thread["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(thread["cwd"] as? String, cwd.url.path)
        XCTAssertEqual(thread["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(thread["source"] as? String, "appServer")
        XCTAssertEqual((thread["turns"] as? [Any])?.count, 0)

        XCTAssertEqual(messages[1]["method"] as? String, "thread/started")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        let notificationThread = try XCTUnwrap(notificationParams["thread"] as? [String: Any])
        XCTAssertEqual(notificationThread["id"] as? String, threadID)

        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let rollout = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        XCTAssertTrue(rollout.contains(#""originator":"codex_app_server""#))
        XCTAssertTrue(rollout.contains(#""instructions":"dev notes""#))
    }

    func testTurnStartRecordsUserInputAndEmitsStartedNotification() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Hello"},{"type":"image","url":"https://example.test/one.png"}]}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(result["turn"] as? [String: Any])
        XCTAssertNotNil(turn["id"] as? String)
        XCTAssertEqual((turn["items"] as? [Any])?.count, 0)
        XCTAssertEqual(turn["status"] as? String, "inProgress")
        XCTAssertEqual(turn["error"] as? NSNull, NSNull())
        XCTAssertEqual(messages[1]["method"] as? String, "turn/started")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(notificationParams["threadId"] as? String, threadID)
        let notificationTurn = try XCTUnwrap(notificationParams["turn"] as? [String: Any])
        XCTAssertEqual(notificationTurn["id"] as? String, turn["id"] as? String)

        let resume = try decode(processor.processLine(Data(#"{"id":3,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        let items = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        let content = try XCTUnwrap(items[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "Hello")
        XCTAssertEqual(content[1]["url"] as? String, "https://example.test/one.png")
    }

    func testTurnInterruptRecordsAbortAndEmitsCompletedNotification() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let turnMessages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Interrupt me"}]}}"#.utf8)))
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":3,"method":"turn/interrupt","params":{"threadId":"\#(threadID)","turnId":"\#(turnID)"}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(messages[1]["method"] as? String, "turn/completed")
        let params = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, threadID)
        let completedTurn = try XCTUnwrap(params["turn"] as? [String: Any])
        XCTAssertEqual(completedTurn["id"] as? String, turnID)
        XCTAssertEqual((completedTurn["items"] as? [Any])?.count, 0)
        XCTAssertEqual(completedTurn["status"] as? String, "interrupted")
        XCTAssertEqual(completedTurn["error"] as? NSNull, NSNull())

        let resume = try decode(processor.processLine(Data(#"{"id":4,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0]["status"] as? String, "interrupted")
    }

    func testThreadResumeReturnsThreadWithRebuiltTurns() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        try appendRolloutEvents(
            to: rolloutPath,
            timestamp: "2025-01-05T12:00:01Z",
            events: [
                .agentReasoning(AgentReasoningEvent(text: "thinking")),
                .agentReasoningRawContent(AgentReasoningRawContentEvent(text: "raw thought")),
                .agentMessage(AgentMessageEvent(message: "Done")),
                .userMessage(UserMessageEvent(message: "Second turn", images: ["https://example.test/image.png"])),
                .turnAborted(TurnAbortedEvent(reason: .interrupted))
            ]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["model"] as? String, "gpt-5.2-codex")
        XCTAssertEqual(result["modelProvider"] as? String, "openai")
        XCTAssertEqual(result["approvalPolicy"] as? String, "untrusted")
        XCTAssertEqual((result["sandbox"] as? [String: Any])?["type"] as? String, "read-only")
        XCTAssertEqual(result["reasoningEffort"] as? NSNull, NSNull())
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        XCTAssertEqual(thread["id"] as? String, threadID)
        XCTAssertEqual(thread["preview"] as? String, "Saved user message")
        XCTAssertEqual(thread["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(thread["cwd"] as? String, "/")
        XCTAssertEqual(thread["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(thread["source"] as? String, "cli")
        XCTAssertEqual(thread["gitInfo"] as? NSNull, NSNull())
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0]["id"] as? String, "turn-1")
        XCTAssertEqual(turns[0]["status"] as? String, "completed")
        let firstItems = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        XCTAssertEqual(firstItems.map { $0["type"] as? String }, ["userMessage", "reasoning", "agentMessage"])
        let firstUserContent = try XCTUnwrap(firstItems[0]["content"] as? [[String: Any]])
        XCTAssertEqual(firstUserContent.count, 1)
        XCTAssertEqual(firstUserContent[0]["type"] as? String, "text")
        XCTAssertEqual(firstUserContent[0]["text"] as? String, "Saved user message")
        XCTAssertEqual(firstItems[1]["summary"] as? [String], ["thinking"])
        XCTAssertEqual(firstItems[1]["content"] as? [String], ["raw thought"])
        XCTAssertEqual(firstItems[2]["text"] as? String, "Done")
        XCTAssertEqual(turns[1]["id"] as? String, "turn-2")
        XCTAssertEqual(turns[1]["status"] as? String, "interrupted")
        let secondItems = try XCTUnwrap(turns[1]["items"] as? [[String: Any]])
        let secondContent = try XCTUnwrap(secondItems[0]["content"] as? [[String: Any]])
        XCTAssertEqual(secondContent[0]["type"] as? String, "text")
        XCTAssertEqual(secondContent[0]["text"] as? String, "Second turn")
        XCTAssertEqual(secondContent[1]["type"] as? String, "image")
        XCTAssertEqual(secondContent[1]["url"] as? String, "https://example.test/image.png")
    }

    func testThreadResumeRejectsMissingRollout() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "no rollout found for conversation id \(threadID)")
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

    func testAccountLoginChatGPTRejectedWhenForcedAPI() throws {
        let temp = try TemporaryDirectory()
        try #"forced_login_method = "api""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"account/login/start","params":{"type":"chatgpt"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "ChatGPT login is disabled. Use API key login instead.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testAccountLoginCancelReturnsNotFoundForUnknownLoginID() throws {
        let temp = try TemporaryDirectory()
        let loginID = "11111111-1111-1111-1111-111111111111"

        let response = try appServerResponse(
            #"{"id":1,"method":"account/login/cancel","params":{"loginId":"\#(loginID)"}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "notFound")
    }

    func testAccountLoginCancelRejectsInvalidLoginID() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"account/login/cancel","params":{"loginId":"not-a-uuid"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid login id: not-a-uuid")
    }

    func testFeedbackUploadUsesInjectedTransportAndReturnsThreadID() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "feedback rollout",
            provider: "openai"
        )
        let feedback = CodexFeedback()
        feedback.makeWriter().write(Data("captured logs".utf8))
        let transport = AppServerRecordingFeedbackUploadTransport()
        let configuration = testConfiguration(
            codexHome: temp.url,
            feedback: feedback,
            feedbackUploadTransport: transport
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"feedback/upload","params":{"classification":"bad_result","reason":"wrong answer","threadId":"\#(threadID)","includeLogs":true}}"#,
            configuration: configuration
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["threadId"] as? String, threadID)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let envelope = String(decoding: requests[0].envelope, as: UTF8.self)
        XCTAssertTrue(envelope.contains(#""classification":"bad_result""#))
        XCTAssertTrue(envelope.contains("captured logs"))
        XCTAssertTrue(envelope.contains("feedback rollout"))
    }

    func testFeedbackUploadRejectsInvalidThreadID() throws {
        let temp = try TemporaryDirectory()
        let transport = AppServerRecordingFeedbackUploadTransport()
        let configuration = testConfiguration(codexHome: temp.url, feedbackUploadTransport: transport)

        let response = try appServerResponse(
            #"{"id":1,"method":"feedback/upload","params":{"classification":"bug","threadId":"not-a-uuid","includeLogs":false}}"#,
            configuration: configuration
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid thread id: Invalid conversation id: not-a-uuid")
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

    func testAccountReadRefreshTokenUpdatesStoredChatGPTTokens() async throws {
        let temp = try TemporaryDirectory()
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: temp.url,
            apiKey: nil,
            idToken: fakeJWT(email: "user@example.com", plan: "pro"),
            accessToken: "old-access-token",
            refreshToken: "old-refresh-token",
            now: staleDate
        )
        let capture = AppServerRefreshCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            authRefreshTransport: { request in
                await capture.append(request)
                return AuthRefreshHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"new-access-token","refresh_token":"new-refresh-token"}"#.utf8)
                )
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"account/read","params":{"refreshToken":true}}"#,
            configuration: configuration
        )

        let accountResult = try XCTUnwrap(response["result"] as? [String: Any])
        let account = try XCTUnwrap(accountResult["account"] as? [String: Any])
        XCTAssertEqual(account["type"] as? String, "chatgpt")
        XCTAssertEqual(account["email"] as? String, "user@example.com")
        XCTAssertEqual(account["planType"] as? String, "pro")
        let stored = try CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file)
        XCTAssertEqual(stored?.tokens?.accessToken, "new-access-token")
        XCTAssertEqual(stored?.tokens?.refreshToken, "new-refresh-token")
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url, URL(string: CodexAuthStorage.defaultRefreshTokenURL))
        XCTAssertEqual(requests[0].method, "POST")
    }

    func testAuthStatusRefreshTokenReturnsUpdatedAccessToken() async throws {
        let temp = try TemporaryDirectory()
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: temp.url,
            apiKey: nil,
            idToken: fakeJWT(email: "user@example.com", plan: "pro"),
            accessToken: "old-access-token",
            refreshToken: "old-refresh-token",
            now: staleDate
        )
        let configuration = testConfiguration(
            codexHome: temp.url,
            authRefreshTransport: { _ in
                AuthRefreshHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"new-access-token","refresh_token":"new-refresh-token"}"#.utf8)
                )
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"getAuthStatus","params":{"includeToken":true,"refreshToken":true}}"#,
            configuration: configuration
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["authMethod"] as? String, "chatgpt")
        XCTAssertEqual(result["authToken"] as? String, "new-access-token")
        XCTAssertEqual(result["requiresOpenAIAuth"] as? Bool, true)
    }

    func testAccountRateLimitsReadRequiresAuthentication() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"account/rateLimits/read","params":{}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "codex account authentication required to read rate limits")
    }

    func testAccountRateLimitsReadRequiresChatGPTAuthentication() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-test")

        let response = try appServerResponse(
            #"{"id":1,"method":"account/rateLimits/read","params":{}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "chatgpt authentication required to read rate limits")
    }

    func testAccountRateLimitsReadUsesFetcherAndReturnsV2Shape() async throws {
        let temp = try TemporaryDirectory()
        try #"chatgpt_base_url = "https://chatgpt.test/base/""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: temp.url,
            apiKey: nil,
            idToken: fakeJWT(email: "user@example.com", plan: "pro"),
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )
        let fetcher = AppServerRecordingAccountRateLimitsFetcher(snapshot: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 42, windowMinutes: 60, resetsAt: 1_737_000_000),
            secondary: RateLimitWindow(usedPercent: 5, windowMinutes: 1_440, resetsAt: 1_737_043_200),
            credits: nil,
            planType: .pro
        ))
        let configuration = testConfiguration(codexHome: temp.url, accountRateLimitsFetcher: fetcher)

        let response = try appServerResponse(
            #"{"id":1,"method":"account/rateLimits/read","params":{}}"#,
            configuration: configuration
        )

        let requests = await fetcher.requests
        XCTAssertEqual(requests, [
            AppServerRecordingAccountRateLimitsFetcher.Request(
                baseURL: "https://chatgpt.test/base/",
                accessToken: "access-token",
                accountID: "acct-test"
            )
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let rateLimits = try XCTUnwrap(result["rateLimits"] as? [String: Any])
        XCTAssertEqual(rateLimits["planType"] as? String, "pro")
        XCTAssertTrue(rateLimits["credits"] is NSNull)

        let primary = try XCTUnwrap(rateLimits["primary"] as? [String: Any])
        XCTAssertEqual(primary["usedPercent"] as? Double, 42)
        XCTAssertEqual(primary["windowDurationMins"] as? Int, 60)
        XCTAssertEqual(primary["resetsAt"] as? Int, 1_737_000_000)

        let secondary = try XCTUnwrap(rateLimits["secondary"] as? [String: Any])
        XCTAssertEqual(secondary["usedPercent"] as? Double, 5)
        XCTAssertEqual(secondary["windowDurationMins"] as? Int, 1_440)
        XCTAssertEqual(secondary["resetsAt"] as? Int, 1_737_043_200)
    }

    func testURLSessionAccountRateLimitsFetcherUsesCodexAPIUsagePath() async throws {
        let capture = AppServerRequestCapture()
        let fetcher = URLSessionAccountRateLimitsFetcher { request in
            await capture.append(request)
            return AccountRateLimitsHTTPResponse(statusCode: 200, body: Data(Self.rateLimitsUsageJSON.utf8))
        }

        let snapshot = try await fetcher.fetchRateLimits(
            baseURL: "https://api.example.test/",
            accessToken: "chatgpt-token",
            accountID: "account-123"
        )

        let requests = await capture.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, URL(string: "https://api.example.test/api/codex/usage"))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.headers["Authorization"] ?? nil, "Bearer chatgpt-token")
        XCTAssertEqual(request.headers["chatgpt-account-id"] ?? nil, "account-123")
        XCTAssertEqual(snapshot.primary?.usedPercent, 42)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 60)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 1_440)
        XCTAssertEqual(snapshot.planType, .pro)
    }

    func testURLSessionAccountRateLimitsFetcherUsesWhamUsagePathForChatGPTBackend() async throws {
        let capture = AppServerRequestCapture()
        let fetcher = URLSessionAccountRateLimitsFetcher { request in
            await capture.append(request)
            return AccountRateLimitsHTTPResponse(statusCode: 200, body: Data(Self.rateLimitsUsageJSON.utf8))
        }

        _ = try await fetcher.fetchRateLimits(
            baseURL: "https://chatgpt.com/",
            accessToken: "chatgpt-token",
            accountID: "account-123"
        )

        let requests = await capture.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, URL(string: "https://chatgpt.com/backend-api/wham/usage"))
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

    func testMcpServerStatusListReturnsConfiguredServersAndPaginates() throws {
        let temp = try TemporaryDirectory()
        try """
        [mcp_servers.docs]
        command = "docs-mcp"
        args = ["--stdio"]

        [mcp_servers.github]
        url = "https://mcp.github.test/mcp"
        bearer_token_env_var = "GITHUB_TOKEN"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let first = try appServerResponse(
            #"{"id":1,"method":"mcpServerStatus/list","params":{"limit":1}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.count, 1)
        XCTAssertEqual(firstData[0]["name"] as? String, "docs")
        XCTAssertEqual(firstData[0]["authStatus"] as? String, "unsupported")
        XCTAssertEqual((firstData[0]["tools"] as? [String: Any])?.count, 0)
        XCTAssertEqual((firstData[0]["resources"] as? [Any])?.count, 0)
        XCTAssertEqual((firstData[0]["resourceTemplates"] as? [Any])?.count, 0)
        XCTAssertEqual(firstResult["nextCursor"] as? String, "1")

        let second = try appServerResponse(
            #"{"id":2,"method":"mcpServerStatus/list","params":{"cursor":"1"}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(second["result"] as? [String: Any])
        let secondData = try XCTUnwrap(secondResult["data"] as? [[String: Any]])
        XCTAssertEqual(secondData.map { $0["name"] as? String }, ["github"])
        XCTAssertEqual(secondData[0]["authStatus"] as? String, "bearer_token")
        XCTAssertNil(secondResult["nextCursor"])
    }

    func testMcpServerStatusListRejectsInvalidCursor() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"mcpServerStatus/list","params":{"cursor":"bogus"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid cursor: bogus")
    }

    func testMcpServerOAuthLoginRejectsUnknownServer() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"mcpServer/oauth/login","params":{"name":"missing"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "No MCP server named 'missing' found.")
    }

    func testMcpServerOAuthLoginRejectsStdioServer() throws {
        let temp = try TemporaryDirectory()
        try """
        [mcp_servers.docs]
        command = "docs-mcp"
        args = ["--stdio"]
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"mcpServer/oauth/login","params":{"name":"docs"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "OAuth login is only supported for streamable HTTP servers.")
    }

    func testMcpServerOAuthLoginReturnsAuthorizationURLAndEmitsCompletion() async throws {
        let temp = try TemporaryDirectory()
        try """
        mcp_oauth_credentials_store = "file"

        [mcp_servers.github]
        url = "https://mcp.github.test/mcp"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let loginCapture = AppServerMcpOAuthLoginCapture()
        let notificationCapture = AppServerNotificationCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            mcpOAuthLoginStarter: { request, completion in
                await loginCapture.append(request)
                await completion(true, nil)
                return AppServerMcpOAuthLoginStarted(authorizationURL: "https://auth.github.test/authorize")
            }
        )
        let processor = try initializedProcessor(
            configuration: configuration,
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"mcpServer/oauth/login","params":{"name":"github","scopes":["repo"],"timeoutSecs":7}}"#.utf8)))

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["authorizationUrl"] as? String, "https://auth.github.test/authorize")
        let requests = await loginCapture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].name, "github")
        XCTAssertEqual(requests[0].serverURL, "https://mcp.github.test/mcp")
        XCTAssertEqual(requests[0].storeMode, .file)
        XCTAssertEqual(requests[0].scopes, ["repo"])
        XCTAssertEqual(requests[0].timeoutSeconds, 7)
        let notifications = try await notificationCapture.payloadsData()
            .flatMap { try decodeMessages($0) }
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0]["method"] as? String, "mcpServer/oauthLogin/completed")
        let params = try XCTUnwrap(notifications[0]["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "github")
        XCTAssertEqual(params["success"] as? Bool, true)
        XCTAssertNil(params["error"])
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
        try appServerResponse(
            line,
            configuration: testConfiguration(codexHome: codexHome),
            initializeFirst: initializeFirst
        )
    }

    private func appServerResponse(
        _ line: String,
        configuration: CodexAppServerConfiguration,
        initializeFirst: Bool = true
    ) throws -> [String: Any] {
        let processor = CodexAppServerMessageProcessor(configuration: configuration)
        if initializeFirst {
            _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        }
        return try decode(processor.processLine(Data(line.utf8)))
    }

    private func initializedProcessor(
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink? = nil
    ) throws -> CodexAppServerMessageProcessor {
        let processor = CodexAppServerMessageProcessor(configuration: configuration, notificationSink: notificationSink)
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        return processor
    }

    private func testConfiguration(
        codexHome: URL,
        requiresOpenAIAuth: Bool = true,
        feedback: CodexFeedback = CodexFeedback(),
        feedbackUploadTransport: any FeedbackUploadTransport = URLSessionFeedbackUploadTransport(),
        accountRateLimitsFetcher: any AccountRateLimitsFetching = URLSessionAccountRateLimitsFetcher(),
        authRefreshTransport: AppServerAuthRefreshTransport? = nil,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter
    ) -> CodexAppServerConfiguration {
        CodexAppServerConfiguration(
            codexHome: codexHome,
            requiresOpenAIAuth: requiresOpenAIAuth,
            environment: [
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: codexHome
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ],
            feedback: feedback,
            feedbackUploadTransport: feedbackUploadTransport,
            accountRateLimitsFetcher: accountRateLimitsFetcher,
            authRefreshTransport: authRefreshTransport,
            mcpOAuthLoginStarter: mcpOAuthLoginStarter
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

    private func appendRolloutEvents(to path: String, timestamp: String, events: [EventMessage]) throws {
        let encoder = JSONEncoder()
        let lines = try events.map { event in
            let line = RolloutLine(timestamp: timestamp, item: .eventMsg(event))
            return String(data: try encoder.encode(line), encoding: .utf8)!
        }.joined(separator: "\n")
        let url = URL(fileURLWithPath: path)
        let existing = try String(contentsOf: url, encoding: .utf8)
        try (existing + "\n" + lines).write(to: url, atomically: true, encoding: .utf8)
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

private actor AppServerRecordingFeedbackUploadTransport: FeedbackUploadTransport {
    private(set) var requests: [FeedbackUploadRequest] = []

    func upload(_ request: FeedbackUploadRequest) async throws {
        requests.append(request)
    }
}

private actor AppServerRequestCapture {
    struct Request: Equatable {
        let url: URL?
        let method: String?
        let headers: [String: String]
    }

    private(set) var requests: [Request] = []

    func append(_ request: URLRequest) {
        requests.append(Request(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:]
        ))
    }
}

private actor AppServerRefreshCapture {
    struct Request: Equatable {
        let url: URL?
        let method: String?
    }

    private(set) var requests: [Request] = []

    func append(_ request: URLRequest) {
        requests.append(Request(url: request.url, method: request.httpMethod))
    }
}

private actor AppServerMcpOAuthLoginCapture {
    private(set) var requests: [AppServerMcpOAuthLoginStartRequest] = []

    func append(_ request: AppServerMcpOAuthLoginStartRequest) {
        requests.append(request)
    }
}

private actor AppServerNotificationCapture {
    private var payloads: [Data] = []

    func append(_ data: Data) {
        payloads.append(data)
    }

    func payloadsData() -> [Data] {
        payloads
    }
}

private actor AppServerRecordingAccountRateLimitsFetcher: AccountRateLimitsFetching {
    struct Request: Equatable {
        let baseURL: String
        let accessToken: String
        let accountID: String
    }

    private let snapshot: RateLimitSnapshot
    private(set) var requests: [Request] = []

    init(snapshot: RateLimitSnapshot) {
        self.snapshot = snapshot
    }

    func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> RateLimitSnapshot {
        requests.append(Request(baseURL: baseURL, accessToken: accessToken, accountID: accountID))
        return snapshot
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
