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
        XCTAssertNotNil(data[0]["updatedAt"] as? Int)
        XCTAssertEqual(data[0]["sessionId"] as? String, newestID)
        XCTAssertEqual(data[0]["forkedFromId"] as? NSNull, NSNull())
        XCTAssertEqual(data[0]["ephemeral"] as? Bool, false)
        XCTAssertEqual((data[0]["status"] as? [String: Any])?["type"] as? String, "notLoaded")
        XCTAssertEqual(data[0]["cwd"] as? String, "/")
        XCTAssertEqual(data[0]["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(data[0]["source"] as? String, "cli")
        XCTAssertEqual(data[0]["threadSource"] as? NSNull, NSNull())
        XCTAssertEqual(data[0]["agentNickname"] as? NSNull, NSNull())
        XCTAssertEqual(data[0]["agentRole"] as? NSNull, NSNull())
        XCTAssertEqual(data[0]["name"] as? NSNull, NSNull())
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

    func testAppServerAttestationProviderRequestsCapableSubscribedClient() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"requestAttestation":true}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 1_000_000_000)
        async let headerValue = provider.header(for: Attestation.Context(threadID: threadID))

        let requestData = await notificationCapture.nextPayload()
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        XCTAssertEqual(request["method"] as? String, "attestation/generate")
        XCTAssertEqual((request["params"] as? [String: Any])?.isEmpty, true)
        let requestID = try XCTUnwrap(request["id"])

        let responseData = try JSONSerialization.data(withJSONObject: [
            "id": requestID,
            "result": [
                "token": "v1.client-attestation-payload"
            ]
        ])
        XCTAssertNil(processor.processLine(responseData))

        let resolvedHeaderValue = await headerValue
        XCTAssertEqual(resolvedHeaderValue, #"{"v":1,"s":0,"t":"v1.client-attestation-payload"}"#)
    }

    func testAppServerAttestationProviderSkipsClientWithoutCapability() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 1_000_000)
        let headerValue = await provider.header(for: Attestation.Context(threadID: threadID))

        XCTAssertNil(headerValue)
        let payloadCount = await notificationCapture.payloadsData().count
        XCTAssertEqual(payloadCount, 0)
    }

    func testAppServerAttestationProviderReportsTimeout() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"requestAttestation":true}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 2_000_000)
        async let headerValue = provider.header(for: Attestation.Context(threadID: threadID))
        _ = await notificationCapture.nextPayload()

        let resolvedHeaderValue = await headerValue
        XCTAssertEqual(resolvedHeaderValue, #"{"v":1,"s":1}"#)
    }

    func testAppServerAttestationProviderReportsClientError() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"requestAttestation":true}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 1_000_000_000)
        async let headerValue = provider.header(for: Attestation.Context(threadID: threadID))

        let requestData = await notificationCapture.nextPayload()
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        let requestID = try XCTUnwrap(request["id"])

        let responseData = try JSONSerialization.data(withJSONObject: [
            "id": requestID,
            "error": [
                "code": -32_000,
                "message": "client refused attestation"
            ]
        ])
        XCTAssertNil(processor.processLine(responseData))

        let resolvedHeaderValue = await headerValue
        XCTAssertEqual(resolvedHeaderValue, #"{"v":1,"s":2}"#)
    }

    func testAppServerAttestationProviderReportsMalformedResponse() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"requestAttestation":true}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 1_000_000_000)
        async let headerValue = provider.header(for: Attestation.Context(threadID: threadID))

        let requestData = await notificationCapture.nextPayload()
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        let requestID = try XCTUnwrap(request["id"])

        let responseData = try JSONSerialization.data(withJSONObject: [
            "id": requestID,
            "result": [
                "token": 42
            ]
        ])
        XCTAssertNil(processor.processLine(responseData))

        let resolvedHeaderValue = await headerValue
        XCTAssertEqual(resolvedHeaderValue, #"{"v":1,"s":4}"#)
    }

    func testAppServerAttestationProviderReportsRequestCanceledWhenSendFails() async throws {
        let temp = try TemporaryDirectory()
        let processor = CodexAppServerMessageProcessor(
            configuration: testConfiguration(codexHome: temp.url)
        )
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"requestAttestation":true}}}"#.utf8)))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let provider = processor.attestationProvider(timeoutNanoseconds: 1_000_000_000)
        let headerValue = await provider.header(for: Attestation.Context(threadID: threadID))

        XCTAssertEqual(headerValue, #"{"v":1,"s":3}"#)
    }

    func testLegacyNewConversationSummaryListenerAndSendMessage() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        retainedTemporaryDirectories.append(cwd)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let newConversation = try decode(processor.processLine(Data(#"{"id":1,"method":"newConversation","params":{"model":"gpt-legacy","modelProvider":"mock_provider","cwd":"\#(cwd.url.path)","approvalPolicy":"never","sandbox":"workspace-write","developerInstructions":"legacy dev notes"}}"#.utf8)))
        let newResult = try XCTUnwrap(newConversation["result"] as? [String: Any])
        let conversationID = try XCTUnwrap(newResult["conversationId"] as? String)
        let rolloutPath = try XCTUnwrap(newResult["rolloutPath"] as? String)
        XCTAssertEqual(newResult["model"] as? String, "gpt-legacy")
        XCTAssertEqual(newResult["reasoningEffort"] as? NSNull, NSNull())

        let addListener = try decode(processor.processLine(Data(#"{"id":2,"method":"addConversationListener","params":{"conversationId":"\#(conversationID)","experimentalRawEvents":false}}"#.utf8)))
        let listenerResult = try XCTUnwrap(addListener["result"] as? [String: Any])
        XCTAssertNotNil(listenerResult["subscriptionId"] as? String)

        let send = try decode(processor.processLine(Data(#"{"id":3,"method":"sendUserMessage","params":{"conversationId":"\#(conversationID)","items":[{"type":"text","data":{"text":"Hello legacy"}},{"type":"image","data":{"imageUrl":"https://example.test/legacy.png"}}]}}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(send["result"] as? [String: Any]).isEmpty)

        let summaryByID = try decode(processor.processLine(Data(#"{"id":4,"method":"getConversationSummary","params":{"conversationId":"\#(conversationID)"}}"#.utf8)))
        let summaryResult = try XCTUnwrap(summaryByID["result"] as? [String: Any])
        let summary = try XCTUnwrap(summaryResult["summary"] as? [String: Any])
        XCTAssertEqual(summary["conversationId"] as? String, conversationID)
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(summary["path"] as? String)).standardizedFileURL.path,
            URL(fileURLWithPath: rolloutPath).standardizedFileURL.path
        )
        XCTAssertEqual(summary["preview"] as? String, "Hello legacy")
        XCTAssertEqual(summary["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(summary["cwd"] as? String, cwd.url.path)

        let summaryByPath = try decode(processor.processLine(Data(#"{"id":5,"method":"getConversationSummary","params":{"rolloutPath":"\#(rolloutPath)"}}"#.utf8)))
        let pathSummary = try XCTUnwrap((summaryByPath["result"] as? [String: Any])?["summary"] as? [String: Any])
        XCTAssertEqual(pathSummary["conversationId"] as? String, conversationID)

        let removeListener = try decode(processor.processLine(Data(#"{"id":6,"method":"removeConversationListener","params":{"subscriptionId":"\#(try XCTUnwrap(listenerResult["subscriptionId"] as? String))"}}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(removeListener["result"] as? [String: Any]).isEmpty)

        let rollout = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        XCTAssertTrue(rollout.contains(#""originator":"codex_app_server""#))
        XCTAssertTrue(rollout.contains(#""instructions":"legacy dev notes""#))
        XCTAssertTrue(rollout.contains(#""message":"Hello legacy""#))
        XCTAssertTrue(rollout.contains(#""https:\/\/example.test\/legacy.png""#))
    }

    func testLegacySendUserTurnAndInterruptConversation() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let newConversation = try decode(processor.processLine(Data(#"{"id":1,"method":"newConversation","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let conversationID = try XCTUnwrap((newConversation["result"] as? [String: Any])?["conversationId"] as? String)

        let sendTurn = try decode(processor.processLine(Data(#"{"id":2,"method":"sendUserTurn","params":{"conversationId":"\#(conversationID)","items":[{"type":"text","data":{"text":"Turn text"}}],"cwd":"/tmp","approvalPolicy":"never","sandboxPolicy":{"type":"read-only"},"model":"gpt-test","summary":"auto"}}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(sendTurn["result"] as? [String: Any]).isEmpty)

        let interrupt = try decode(processor.processLine(Data(#"{"id":3,"method":"interruptConversation","params":{"conversationId":"\#(conversationID)"}}"#.utf8)))
        let interruptResult = try XCTUnwrap(interrupt["result"] as? [String: Any])
        XCTAssertEqual(interruptResult["abortReason"] as? String, "interrupted")

        let resume = try decode(processor.processLine(Data(#"{"id":4,"method":"thread/resume","params":{"threadId":"\#(conversationID)"}}"#.utf8)))
        let resumedThread = try XCTUnwrap((resume["result"] as? [String: Any])?["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0]["status"] as? String, "interrupted")
    }

    func testLegacyResumeConversationFromPathAndConversationID() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let newConversation = try decode(processor.processLine(Data(#"{"id":1,"method":"newConversation","params":{"model":"gpt-original","modelProvider":"mock_provider"}}"#.utf8)))
        let original = try XCTUnwrap(newConversation["result"] as? [String: Any])
        let originalID = try XCTUnwrap(original["conversationId"] as? String)
        let originalPath = try XCTUnwrap(original["rolloutPath"] as? String)

        _ = try decode(processor.processLine(Data(#"{"id":2,"method":"sendUserMessage","params":{"conversationId":"\#(originalID)","items":[{"type":"text","data":{"text":"Resume me"}}]}}"#.utf8)))

        let resumedByPath = try decode(processor.processLine(Data(#"{"id":3,"method":"resumeConversation","params":{"path":"\#(originalPath)","overrides":{"model":"gpt-resumed","modelProvider":"mock_provider","developerInstructions":"resume notes"}}}"#.utf8)))
        let pathResult = try XCTUnwrap(resumedByPath["result"] as? [String: Any])
        let resumedID = try XCTUnwrap(pathResult["conversationId"] as? String)
        let resumedPath = try XCTUnwrap(pathResult["rolloutPath"] as? String)
        XCTAssertNotEqual(resumedID, originalID)
        XCTAssertEqual(pathResult["model"] as? String, "gpt-resumed")
        let initialMessages = try XCTUnwrap(pathResult["initialMessages"] as? [[String: Any]])
        XCTAssertTrue(String(describing: initialMessages).contains("Resume me"))

        let resumedRollout = try String(contentsOfFile: resumedPath, encoding: .utf8)
        XCTAssertTrue(resumedRollout.contains(#""instructions":"resume notes""#))
        XCTAssertTrue(resumedRollout.contains(#""message":"Resume me""#))

        let resumedByID = try decode(processor.processLine(Data(#"{"id":4,"method":"resumeConversation","params":{"conversationId":"\#(originalID)","overrides":{"model":"gpt-resumed-id"}}}"#.utf8)))
        let idResult = try XCTUnwrap(resumedByID["result"] as? [String: Any])
        XCTAssertNotEqual(idResult["conversationId"] as? String, originalID)
        XCTAssertEqual(idResult["model"] as? String, "gpt-resumed-id")
        XCTAssertNotNil(idResult["rolloutPath"] as? String)
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

    func testReviewStartInlineRecordsReviewMarkerAndEmitsStartedNotification() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"review/start","params":{"threadId":"\#(threadID)","delivery":"inline","target":{"type":"commit","sha":"  1234567deadbeef  ","title":"  Tidy UI colors  "}}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(result["reviewThreadId"] as? String, threadID)
        let turn = try XCTUnwrap(result["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)
        XCTAssertEqual(turn["status"] as? String, "inProgress")
        XCTAssertEqual(turn["error"] as? NSNull, NSNull())
        let items = try XCTUnwrap(turn["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["id"] as? String, turnID)
        let content = try XCTUnwrap(items[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "commit 1234567: Tidy UI colors")
        XCTAssertEqual(messages[1]["method"] as? String, "turn/started")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(notificationParams["threadId"] as? String, threadID)

        let resume = try decode(processor.processLine(Data(#"{"id":3,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        let resumedItems = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        XCTAssertEqual(resumedItems[0]["type"] as? String, "enteredReviewMode")
        XCTAssertEqual(resumedItems[0]["review"] as? String, "commit 1234567: Tidy UI colors")
    }

    func testReviewStartDetachedCreatesReviewThread() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"review/start","params":{"threadId":"\#(threadID)","delivery":"detached","target":{"type":"custom","instructions":"  inspect parser  "}}}"#.utf8)))

        XCTAssertEqual(messages.count, 3)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        let reviewThreadID = try XCTUnwrap(result["reviewThreadId"] as? String)
        XCTAssertNotEqual(reviewThreadID, threadID)
        XCTAssertEqual(messages[1]["method"] as? String, "thread/started")
        let threadParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        let reviewThread = try XCTUnwrap(threadParams["thread"] as? [String: Any])
        XCTAssertEqual(reviewThread["id"] as? String, reviewThreadID)
        XCTAssertEqual(messages[2]["method"] as? String, "turn/started")
        let turnParams = try XCTUnwrap(messages[2]["params"] as? [String: Any])
        XCTAssertEqual(turnParams["threadId"] as? String, reviewThreadID)

        let resume = try decode(processor.processLine(Data(#"{"id":3,"method":"thread/resume","params":{"threadId":"\#(reviewThreadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        let items = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["review"] as? String, "inspect parser")
    }

    func testReviewStartRejectsEmptyTargets() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let branchError = try decode(processor.processLine(Data(#"{"id":2,"method":"review/start","params":{"threadId":"\#(threadID)","target":{"type":"baseBranch","branch":"   "}}}"#.utf8)))
        XCTAssertEqual((branchError["error"] as? [String: Any])?["code"] as? Int, -32600)
        XCTAssertEqual((branchError["error"] as? [String: Any])?["message"] as? String, "branch must not be empty")

        let shaError = try decode(processor.processLine(Data(#"{"id":3,"method":"review/start","params":{"threadId":"\#(threadID)","target":{"type":"commit","sha":"\t"}}}"#.utf8)))
        XCTAssertEqual((shaError["error"] as? [String: Any])?["code"] as? Int, -32600)
        XCTAssertEqual((shaError["error"] as? [String: Any])?["message"] as? String, "sha must not be empty")

        let customError = try decode(processor.processLine(Data(#"{"id":4,"method":"review/start","params":{"threadId":"\#(threadID)","target":{"type":"custom","instructions":"\n\n"}}}"#.utf8)))
        XCTAssertEqual((customError["error"] as? [String: Any])?["code"] as? Int, -32600)
        XCTAssertEqual((customError["error"] as? [String: Any])?["message"] as? String, "instructions must not be empty")
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
        XCTAssertEqual(result["model"] as? String, "gpt-5.5")
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

    func testThreadReadReturnsMetadataWithoutTurnsByDefault() throws {
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
            events: [.agentMessage(AgentMessageEvent(message: "Done"))]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        XCTAssertEqual(thread["id"] as? String, threadID)
        XCTAssertEqual(thread["sessionId"] as? String, threadID)
        XCTAssertEqual(thread["forkedFromId"] as? NSNull, NSNull())
        XCTAssertEqual(thread["preview"] as? String, "Saved user message")
        XCTAssertEqual(thread["ephemeral"] as? Bool, false)
        XCTAssertEqual(thread["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(thread["createdAt"] as? Int, 1_736_078_400)
        XCTAssertEqual(thread["updatedAt"] as? Int, 1_736_078_400)
        XCTAssertEqual((thread["status"] as? [String: Any])?["type"] as? String, "notLoaded")
        XCTAssertEqual(thread["path"] as? String, rolloutPath)
        XCTAssertEqual(thread["cwd"] as? String, "/")
        XCTAssertEqual(thread["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(thread["source"] as? String, "cli")
        XCTAssertEqual(thread["threadSource"] as? NSNull, NSNull())
        XCTAssertEqual(thread["agentNickname"] as? NSNull, NSNull())
        XCTAssertEqual(thread["agentRole"] as? NSNull, NSNull())
        XCTAssertEqual(thread["gitInfo"] as? NSNull, NSNull())
        XCTAssertEqual(thread["name"] as? NSNull, NSNull())
        XCTAssertEqual((thread["turns"] as? [Any])?.count, 0)
    }

    func testThreadForkCreatesNewThreadWithCopiedHistoryAndStartedNotification() throws {
        let temp = try TemporaryDirectory()
        let sourceID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider"
        )
        let sourcePath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: sourceID
        ))
        try appendRolloutEvents(to: sourcePath, timestamp: "2025-01-05T12:00:01Z", events: [
            .agentMessage(AgentMessageEvent(message: "Done"))
        ])
        let sourceContents = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/fork","params":{"threadId":"\#(sourceID)","threadSource":"user","excludeTurns":false}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertNil(result["sessionId"], "thread/fork should not include top-level sessionId")
        XCTAssertEqual(result["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(result["cwd"] as? String, "/")
        XCTAssertEqual(result["approvalPolicy"] as? String, "untrusted")
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let forkID = try XCTUnwrap(thread["id"] as? String)
        XCTAssertNotEqual(forkID, sourceID)
        XCTAssertEqual(thread["sessionId"] as? String, forkID)
        XCTAssertEqual(thread["forkedFromId"] as? String, sourceID)
        XCTAssertEqual(thread["preview"] as? String, "Saved user message")
        XCTAssertEqual(thread["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(thread["source"] as? String, "appServer")
        XCTAssertEqual(thread["threadSource"] as? String, "user")
        XCTAssertEqual(thread["name"] as? NSNull, NSNull())
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turnUserText(turns[0]), "Saved user message")
        XCTAssertEqual(turnAgentTexts(turns[0]), ["Done"])

        XCTAssertEqual(messages[1]["method"] as? String, "thread/started")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        let notificationThread = try XCTUnwrap(notificationParams["thread"] as? [String: Any])
        XCTAssertEqual(notificationThread["id"] as? String, forkID)
        XCTAssertEqual(notificationThread["forkedFromId"] as? String, sourceID)
        XCTAssertEqual((notificationThread["turns"] as? [Any])?.count, 0)

        let afterContents = try String(contentsOfFile: sourcePath, encoding: .utf8)
        XCTAssertEqual(afterContents, sourceContents)
    }

    func testThreadReadCanIncludeTurns() throws {
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
                .agentMessage(AgentMessageEvent(message: "Done")),
                .userMessage(UserMessageEvent(message: "Second turn")),
                .turnAborted(TurnAbortedEvent(reason: .interrupted))
            ]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/read","params":{"threadId":"\#(threadID)","includeTurns":true}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0]["status"] as? String, "completed")
        XCTAssertEqual(turns[1]["status"] as? String, "interrupted")
        let firstItems = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        XCTAssertEqual(firstItems.map { $0["type"] as? String }, ["userMessage", "agentMessage"])
        XCTAssertEqual(firstItems[1]["text"] as? String, "Done")
    }

    func testThreadReadRejectsInvalidThreadIDAndMissingRollout() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"thread/read","params":{"threadId":"not-a-uuid"}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(invalidError["message"] as? String, "invalid thread id: Invalid conversation id: not-a-uuid")

        let threadID = UUID().uuidString.lowercased()
        let missing = try appServerResponse(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(missingError["message"] as? String, "thread not loaded: \(threadID)")
    }

    func testThreadNameSetPersistsNameAndEmitsNotification() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider"
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/name/set","params":{"threadId":"\#(threadID)","name":"  Sharper thread name  "}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(messages[1]["method"] as? String, "thread/name/updated")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(notificationParams["threadId"] as? String, threadID)
        XCTAssertEqual(notificationParams["threadName"] as? String, "Sharper thread name")

        let index = try String(contentsOf: temp.url.appendingPathComponent("session_index.jsonl"), encoding: .utf8)
        XCTAssertTrue(index.contains(#""thread_name":"Sharper thread name""#))

        let read = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let thread = try XCTUnwrap(readResult["thread"] as? [String: Any])
        XCTAssertEqual(thread["name"] as? String, "Sharper thread name")
    }

    func testThreadNameSetRejectsEmptyOrMissingThread() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider"
        )

        let empty = try appServerResponse(
            #"{"id":1,"method":"thread/name/set","params":{"threadId":"\#(threadID)","name":"   "}}"#,
            codexHome: temp.url
        )
        let emptyError = try XCTUnwrap(empty["error"] as? [String: Any])
        XCTAssertEqual(emptyError["code"] as? Int, -32600)
        XCTAssertEqual(emptyError["message"] as? String, "thread name must not be empty")

        let missingID = UUID().uuidString.lowercased()
        let missing = try appServerResponse(
            #"{"id":2,"method":"thread/name/set","params":{"threadId":"\#(missingID)","name":"Name"}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(missingError["message"] as? String, "no rollout found for conversation id \(missingID)")
    }

    func testThreadMetadataUpdatePatchesGitInfoAndThreadReadSeesIt() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider",
            gitInfo: GitInfo(commitHash: "abc123", branch: "main", repositoryURL: "git@example.com:openai/codex.git")
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let update = try decode(processor.processLine(Data(
            #"{"id":1,"method":"thread/metadata/update","params":{"threadId":"\#(threadID)","gitInfo":{"branch":"  feature/sidebar-pr  ","originUrl":null}}}"#.utf8
        )))
        let updateResult = try XCTUnwrap(update["result"] as? [String: Any])
        let updatedThread = try XCTUnwrap(updateResult["thread"] as? [String: Any])
        let updatedGitInfo = try XCTUnwrap(updatedThread["gitInfo"] as? [String: Any])
        XCTAssertEqual(updatedThread["id"] as? String, threadID)
        XCTAssertEqual(updatedThread["sessionId"] as? String, threadID)
        XCTAssertEqual(updatedThread["preview"] as? String, "Saved user message")
        XCTAssertEqual(updatedGitInfo["sha"] as? String, "abc123")
        XCTAssertEqual(updatedGitInfo["branch"] as? String, "feature/sidebar-pr")
        XCTAssertNil(updatedGitInfo["originUrl"] as? String)

        let read = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let readThread = try XCTUnwrap(readResult["thread"] as? [String: Any])
        let readGitInfo = try XCTUnwrap(readThread["gitInfo"] as? [String: Any])
        XCTAssertEqual(readGitInfo["sha"] as? String, "abc123")
        XCTAssertEqual(readGitInfo["branch"] as? String, "feature/sidebar-pr")
        XCTAssertNil(readGitInfo["originUrl"] as? String)
    }

    func testThreadMetadataUpdateCanClearAllGitInfo() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-30-00",
            timestamp: "2025-01-06T08:30:00Z",
            preview: "Stored thread preview",
            provider: "mock_provider",
            gitInfo: GitInfo(commitHash: "abc123", branch: "feature/sidebar-pr", repositoryURL: "git@example.com:openai/codex.git")
        )

        let update = try appServerResponse(
            #"{"id":1,"method":"thread/metadata/update","params":{"threadId":"\#(threadID)","gitInfo":{"sha":null,"branch":null,"originUrl":null}}}"#,
            codexHome: temp.url
        )
        let updateResult = try XCTUnwrap(update["result"] as? [String: Any])
        let updatedThread = try XCTUnwrap(updateResult["thread"] as? [String: Any])
        XCTAssertEqual(updatedThread["gitInfo"] as? NSNull, NSNull())
    }

    func testThreadMetadataUpdateRejectsEmptyAndInvalidGitFields() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider"
        )

        let empty = try appServerResponse(
            #"{"id":1,"method":"thread/metadata/update","params":{"threadId":"\#(threadID)","gitInfo":{}}}"#,
            codexHome: temp.url
        )
        let emptyError = try XCTUnwrap(empty["error"] as? [String: Any])
        XCTAssertEqual(emptyError["code"] as? Int, -32600)
        XCTAssertEqual(emptyError["message"] as? String, "gitInfo must include at least one field")

        let blank = try appServerResponse(
            #"{"id":2,"method":"thread/metadata/update","params":{"threadId":"\#(threadID)","gitInfo":{"branch":"   "}}}"#,
            codexHome: temp.url
        )
        let blankError = try XCTUnwrap(blank["error"] as? [String: Any])
        XCTAssertEqual(blankError["code"] as? Int, -32600)
        XCTAssertEqual(blankError["message"] as? String, "gitInfo.branch must not be empty")
    }

    func testThreadCompactStartAndShellCommandReturnEmptyResults() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-00-00",
            timestamp: "2025-01-06T08:00:00Z",
            preview: "thread operation",
            provider: "mock_provider"
        )

        let compact = try appServerResponse(
            #"{"id":1,"method":"thread/compact/start","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let compactResult = try XCTUnwrap(compact["result"] as? [String: Any])
        XCTAssertTrue(compactResult.isEmpty)

        let shell = try appServerResponse(
            #"{"id":2,"method":"thread/shellCommand","params":{"threadId":"\#(threadID)","command":"  git status --short  "}}"#,
            codexHome: temp.url
        )
        let shellResult = try XCTUnwrap(shell["result"] as? [String: Any])
        XCTAssertTrue(shellResult.isEmpty)
    }

    func testThreadCompactStartAndShellCommandValidateInputs() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        let emptyCommand = try appServerResponse(
            #"{"id":1,"method":"thread/shellCommand","params":{"threadId":"\#(threadID)","command":"   "}}"#,
            codexHome: temp.url
        )
        let emptyCommandError = try XCTUnwrap(emptyCommand["error"] as? [String: Any])
        XCTAssertEqual(emptyCommandError["code"] as? Int, -32600)
        XCTAssertEqual(emptyCommandError["message"] as? String, "command must not be empty")

        let invalidThread = try appServerResponse(
            #"{"id":2,"method":"thread/compact/start","params":{"threadId":"not-a-thread-id"}}"#,
            codexHome: temp.url
        )
        let invalidThreadError = try XCTUnwrap(invalidThread["error"] as? [String: Any])
        XCTAssertEqual(invalidThreadError["code"] as? Int, -32600)
        XCTAssertTrue((invalidThreadError["message"] as? String)?.contains("invalid thread id") == true)

        let missingThread = try appServerResponse(
            #"{"id":3,"method":"thread/shellCommand","params":{"threadId":"\#(threadID)","command":"pwd"}}"#,
            codexHome: temp.url
        )
        let missingThreadError = try XCTUnwrap(missingThread["error"] as? [String: Any])
        XCTAssertEqual(missingThreadError["code"] as? Int, -32600)
        XCTAssertEqual(missingThreadError["message"] as? String, "thread not found: \(threadID)")
    }

    func testThreadBackgroundTerminalsCleanRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-05-00",
            timestamp: "2025-01-06T08:05:00Z",
            preview: "background terminal",
            provider: "mock_provider"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/backgroundTerminals/clean","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "thread/backgroundTerminals/clean requires experimentalApi capability"
        )
    }

    func testThreadBackgroundTerminalsCleanReturnsEmptyResultWhenExperimental() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-10-00",
            timestamp: "2025-01-06T08:10:00Z",
            preview: "background terminal",
            provider: "mock_provider"
        )
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: temp.url))
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"experimentalApi":true}}}"#.utf8)))

        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"thread/backgroundTerminals/clean","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)

        let invalid = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/backgroundTerminals/clean","params":{"threadId":"not-a-thread-id"}}"#.utf8
        )))
        let error = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.contains("invalid thread id") == true)
    }

    func testThreadElicitationCountersRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let start = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let threadID = try XCTUnwrap(((start[0]["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String)

        let response = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/increment_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "thread/increment_elicitation requires experimentalApi capability"
        )
    }

    func testThreadElicitationCountersTrackLoadedThreadCounts() throws {
        let temp = try TemporaryDirectory()
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: temp.url))
        _ = try decode(processor.processLine(Data(
            #"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"experimentalApi":true}}}"#.utf8
        )))
        let start = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let threadID = try XCTUnwrap(((start[0]["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String)

        let firstIncrement = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/increment_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual((firstIncrement["result"] as? [String: Any])?["count"] as? Int, 1)
        XCTAssertEqual((firstIncrement["result"] as? [String: Any])?["paused"] as? Bool, true)

        let secondIncrement = try decode(processor.processLine(Data(
            #"{"id":3,"method":"thread/increment_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual((secondIncrement["result"] as? [String: Any])?["count"] as? Int, 2)
        XCTAssertEqual((secondIncrement["result"] as? [String: Any])?["paused"] as? Bool, true)

        let firstDecrement = try decode(processor.processLine(Data(
            #"{"id":4,"method":"thread/decrement_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual((firstDecrement["result"] as? [String: Any])?["count"] as? Int, 1)
        XCTAssertEqual((firstDecrement["result"] as? [String: Any])?["paused"] as? Bool, true)

        let secondDecrement = try decode(processor.processLine(Data(
            #"{"id":5,"method":"thread/decrement_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual((secondDecrement["result"] as? [String: Any])?["count"] as? Int, 0)
        XCTAssertEqual((secondDecrement["result"] as? [String: Any])?["paused"] as? Bool, false)

        let zeroDecrement = try decode(processor.processLine(Data(
            #"{"id":6,"method":"thread/decrement_elicitation","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let error = try XCTUnwrap(zeroDecrement["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "out-of-band elicitation count is already zero")
    }

    func testThreadElicitationCountersValidateThreadIDsAndLoadedState() throws {
        let temp = try TemporaryDirectory()
        let persistedThreadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-15-00",
            timestamp: "2025-01-06T08:15:00Z",
            preview: "not loaded",
            provider: "mock_provider"
        )
        let processor = CodexAppServerMessageProcessor(configuration: testConfiguration(codexHome: temp.url))
        _ = try decode(processor.processLine(Data(
            #"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"},"capabilities":{"experimentalApi":true}}}"#.utf8
        )))

        let invalid = try decode(processor.processLine(Data(
            #"{"id":1,"method":"thread/increment_elicitation","params":{"threadId":"not-a-thread-id"}}"#.utf8
        )))
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertTrue((invalidError["message"] as? String)?.contains("invalid thread id") == true)

        let notLoaded = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/increment_elicitation","params":{"threadId":"\#(persistedThreadID)"}}"#.utf8
        )))
        let notLoadedError = try XCTUnwrap(notLoaded["error"] as? [String: Any])
        XCTAssertEqual(notLoadedError["code"] as? Int, -32600)
        XCTAssertEqual(notLoadedError["message"] as? String, "thread not found: \(persistedThreadID)")
    }

    func testThreadGoalMethodsReturnRustDisabledFeatureErrorByDefault() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        for (index, method) in ["thread/goal/set", "thread/goal/get", "thread/goal/clear"].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{"threadId":"\#(threadID)"}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "goals feature is disabled")
        }
    }

    func testThreadGoalMethodsPersistAndNotifyWhenFeatureEnabled() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        goals = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T07-30-00",
            timestamp: "2025-01-06T07:30:00Z",
            preview: "goal thread",
            provider: "mock_provider"
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let setMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"  keep polishing  ","status":"budgetLimited","tokenBudget":10}}"#.utf8
        )))
        XCTAssertEqual(setMessages.count, 2)
        let setResult = try XCTUnwrap(setMessages[0]["result"] as? [String: Any])
        let setGoal = try XCTUnwrap(setResult["goal"] as? [String: Any])
        XCTAssertEqual(setGoal["threadId"] as? String, threadID)
        XCTAssertEqual(setGoal["objective"] as? String, "keep polishing")
        XCTAssertEqual(setGoal["status"] as? String, "budgetLimited")
        XCTAssertEqual(setGoal["tokenBudget"] as? Int, 10)
        XCTAssertEqual(setGoal["tokensUsed"] as? Int, 0)
        XCTAssertEqual(setGoal["timeUsedSeconds"] as? Int, 0)

        XCTAssertEqual(setMessages[1]["method"] as? String, "thread/goal/updated")
        let updateParams = try XCTUnwrap(setMessages[1]["params"] as? [String: Any])
        XCTAssertEqual(updateParams["threadId"] as? String, threadID)
        XCTAssertEqual(updateParams["turnId"] as? NSNull, NSNull())
        let notifiedGoal = try XCTUnwrap(updateParams["goal"] as? [String: Any])
        XCTAssertEqual(notifiedGoal["objective"] as? String, "keep polishing")

        let get = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"thread/goal/get","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let getGoal = try XCTUnwrap((get[0]["result"] as? [String: Any])?["goal"] as? [String: Any])
        XCTAssertEqual(getGoal["status"] as? String, "budgetLimited")
        XCTAssertEqual(getGoal["tokenBudget"] as? Int, 10)

        let replacement = try decodeMessages(processor.processLine(Data(
            #"{"id":3,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"keep polishing"}}"#.utf8
        )))
        let replacementGoal = try XCTUnwrap((replacement[0]["result"] as? [String: Any])?["goal"] as? [String: Any])
        XCTAssertEqual(replacementGoal["status"] as? String, "budgetLimited")
        XCTAssertEqual(replacementGoal["tokenBudget"] as? Int, 10)

        let clear = try decodeMessages(processor.processLine(Data(
            #"{"id":4,"method":"thread/goal/clear","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual(clear.count, 2)
        XCTAssertEqual((clear[0]["result"] as? [String: Any])?["cleared"] as? Bool, true)
        XCTAssertEqual(clear[1]["method"] as? String, "thread/goal/cleared")
        XCTAssertEqual((clear[1]["params"] as? [String: Any])?["threadId"] as? String, threadID)

        let emptyGet = try decodeMessages(processor.processLine(Data(
            #"{"id":5,"method":"thread/goal/get","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual((emptyGet[0]["result"] as? [String: Any])?["goal"] as? NSNull, NSNull())

        let clearAgain = try decodeMessages(processor.processLine(Data(
            #"{"id":6,"method":"thread/goal/clear","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual(clearAgain.count, 1)
        XCTAssertEqual((clearAgain[0]["result"] as? [String: Any])?["cleared"] as? Bool, false)
    }

    func testThreadGoalMethodsValidateEnabledInputs() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        goals = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T07-45-00",
            timestamp: "2025-01-06T07:45:00Z",
            preview: "goal validation",
            provider: "mock_provider"
        )

        let emptyObjective = try appServerResponse(
            #"{"id":1,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"   "}}"#,
            codexHome: temp.url
        )
        let emptyObjectiveError = try XCTUnwrap(emptyObjective["error"] as? [String: Any])
        XCTAssertEqual(emptyObjectiveError["code"] as? Int, -32600)
        XCTAssertEqual(emptyObjectiveError["message"] as? String, "goal objective must not be empty")

        let zeroBudget = try appServerResponse(
            #"{"id":2,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"keep polishing","tokenBudget":0}}"#,
            codexHome: temp.url
        )
        let zeroBudgetError = try XCTUnwrap(zeroBudget["error"] as? [String: Any])
        XCTAssertEqual(zeroBudgetError["code"] as? Int, -32600)
        XCTAssertEqual(zeroBudgetError["message"] as? String, "goal budgets must be positive when provided")

        let missingGoal = try appServerResponse(
            #"{"id":3,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","status":"paused"}}"#,
            codexHome: temp.url
        )
        let missingGoalError = try XCTUnwrap(missingGoal["error"] as? [String: Any])
        XCTAssertEqual(missingGoalError["code"] as? Int, -32600)
        XCTAssertEqual(
            missingGoalError["message"] as? String,
            "cannot update goal for thread \(threadID): no goal exists"
        )
    }

    func testThreadMemoryModeSetAppendsSessionMetaMarker() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-30-00",
            timestamp: "2025-01-06T08:30:00Z",
            preview: "Stored thread preview",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))

        for (index, mode) in ["disabled", "enabled"].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"thread/memoryMode/set","params":{"threadId":"\#(threadID)","mode":"\#(mode)"}}"#,
                codexHome: temp.url
            )
            let result = try XCTUnwrap(response["result"] as? [String: Any])
            XCTAssertTrue(result.isEmpty)
        }

        let rollout = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        XCTAssertTrue(rollout.contains(#""memory_mode":"disabled""#))
        XCTAssertTrue(rollout.contains(#""memory_mode":"enabled""#))
        let lines = rollout.split(whereSeparator: \.isNewline)
        let sessionMetaLines = lines.filter { $0.contains(#""type":"session_meta""#) }
        XCTAssertEqual(sessionMetaLines.count, 3)
        XCTAssertTrue(sessionMetaLines.last?.contains(#""memory_mode":"enabled""#) == true)
    }

    func testThreadMemoryModeSetRejectsInvalidModeAndMissingThread() throws {
        let temp = try TemporaryDirectory()
        let missingID = UUID().uuidString.lowercased()

        let invalidMode = try appServerResponse(
            #"{"id":1,"method":"thread/memoryMode/set","params":{"threadId":"\#(missingID)","mode":"paused"}}"#,
            codexHome: temp.url
        )
        let invalidModeError = try XCTUnwrap(invalidMode["error"] as? [String: Any])
        XCTAssertEqual(invalidModeError["code"] as? Int, -32600)
        XCTAssertEqual(invalidModeError["message"] as? String, "invalid memory mode: paused")

        let missing = try appServerResponse(
            #"{"id":2,"method":"thread/memoryMode/set","params":{"threadId":"\#(missingID)","mode":"enabled"}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(missingError["message"] as? String, "no rollout found for conversation id \(missingID)")
    }

    func testThreadInjectItemsAppendsResponseItemsToRollout() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T09-30-00",
            timestamp: "2025-01-06T09:30:00Z",
            preview: "Stored thread preview",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))

        let response = try appServerResponse(
            """
            {"id":1,"method":"thread/inject_items","params":{"threadId":"\(threadID)","items":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Injected assistant context"}]}]}}
            """,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)

        let rollout = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        XCTAssertTrue(rollout.contains(#""type":"response_item""#))
        XCTAssertTrue(rollout.contains("Injected assistant context"))
        let history = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: rolloutPath))
        guard case let .resumed(resumed) = history else {
            return XCTFail("expected resumed rollout history")
        }
        XCTAssertTrue(resumed.history.contains {
            guard case let .responseItem(.message(_, role, content, _)) = $0 else {
                return false
            }
            return role == "assistant" && content == [.outputText(text: "Injected assistant context")]
        })
    }

    func testThreadInjectItemsRejectsEmptyInvalidAndMissingThread() throws {
        let temp = try TemporaryDirectory()
        let missingID = UUID().uuidString.lowercased()

        let empty = try appServerResponse(
            #"{"id":1,"method":"thread/inject_items","params":{"threadId":"\#(missingID)","items":[]}}"#,
            codexHome: temp.url
        )
        let emptyError = try XCTUnwrap(empty["error"] as? [String: Any])
        XCTAssertEqual(emptyError["code"] as? Int, -32600)
        XCTAssertEqual(emptyError["message"] as? String, "items must not be empty")

        let invalid = try appServerResponse(
            #"{"id":2,"method":"thread/inject_items","params":{"threadId":"\#(missingID)","items":[{"role":"assistant"}]}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertTrue((invalidError["message"] as? String)?.hasPrefix("items[0] is not a valid response item:") == true)

        let missing = try appServerResponse(
            #"{"id":3,"method":"thread/inject_items","params":{"threadId":"\#(missingID)","items":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Valid but missing thread"}]}]}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(missingError["message"] as? String, "no rollout found for conversation id \(missingID)")
    }

    func testMemoryResetClearsMemoryRootsAndPreservesDirectories() throws {
        let temp = try TemporaryDirectory()
        let memoryRoot = temp.url.appendingPathComponent("memories", isDirectory: true)
        let memoryExtensionsRoot = temp.url.appendingPathComponent("memories_extensions", isDirectory: true)
        let summaries = memoryRoot.appendingPathComponent("rollout_summaries", isDirectory: true)
        let extensionResources = memoryExtensionsRoot
            .appendingPathComponent("ad_hoc", isDirectory: true)
            .appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extensionResources, withIntermediateDirectories: true)
        try "stale memory\n".write(
            to: memoryRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "stale rollout\n".write(
            to: summaries.appendingPathComponent("stale.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "extension stale\n".write(
            to: extensionResources.appendingPathComponent("stale.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryExtensionsRoot.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionsRoot.path), [])
    }

    func testMemoryResetCreatesMissingRootsAndRejectsSymlinkedRoot() throws {
        let temp = try TemporaryDirectory()
        let missingRoots = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(missingRoots["result"] as? [String: Any])
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("memories").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("memories_extensions").path))

        let target = temp.url.appendingPathComponent("outside", isDirectory: true)
        let symlink = temp.url.appendingPathComponent("symlink_home", isDirectory: true)
            .appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep\n".write(
            to: target.appendingPathComponent("keep.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let rejected = try appServerResponse(
            #"{"id":2,"method":"memory/reset","params":{}}"#,
            codexHome: symlink.deletingLastPathComponent()
        )
        let error = try XCTUnwrap(rejected["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertTrue((error["message"] as? String)?.contains("refusing to clear symlinked memory root") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("keep.txt").path))
    }

    func testFsGetMetadataReturnsOnlyUsedFields() throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("note.txt", isDirectory: false)
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"fs/getMetadata","params":{"path":"\#(file.path)"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result.keys.sorted(), ["createdAtMs", "isDirectory", "isFile", "isSymlink", "modifiedAtMs"])
        XCTAssertEqual(result["isDirectory"] as? Bool, false)
        XCTAssertEqual(result["isFile"] as? Bool, true)
        XCTAssertEqual(result["isSymlink"] as? Bool, false)
        XCTAssertGreaterThan(result["modifiedAtMs"] as? Int64 ?? 0, 0)
    }

    func testFsGetMetadataReportsSymlink() throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("note.txt", isDirectory: false)
        let link = temp.url.appendingPathComponent("note-link.txt", isDirectory: false)
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let response = try appServerResponse(
            #"{"id":1,"method":"fs/getMetadata","params":{"path":"\#(link.path)"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isDirectory"] as? Bool, false)
        XCTAssertEqual(result["isFile"] as? Bool, true)
        XCTAssertEqual(result["isSymlink"] as? Bool, true)
    }

    func testFsMethodsCoverCurrentFsUtilsSurface() throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        let nestedFile = nested.appendingPathComponent("note.txt", isDirectory: false)
        let sourceFile = source.appendingPathComponent("root.txt", isDirectory: false)
        let copiedFile = temp.url.appendingPathComponent("copy.txt", isDirectory: false)
        let copiedDir = temp.url.appendingPathComponent("copied", isDirectory: true)
        let nestedPayload = Data("hello from app-server".utf8).base64EncodedString()
        let sourcePayload = Data("hello from source root".utf8).base64EncodedString()

        XCTAssertNotNil(try appServerResponse(
            #"{"id":1,"method":"fs/createDirectory","params":{"path":"\#(nested.path)"}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])
        XCTAssertNotNil(try appServerResponse(
            #"{"id":2,"method":"fs/writeFile","params":{"path":"\#(nestedFile.path)","dataBase64":"\#(nestedPayload)"}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])
        XCTAssertNotNil(try appServerResponse(
            #"{"id":3,"method":"fs/writeFile","params":{"path":"\#(sourceFile.path)","dataBase64":"\#(sourcePayload)"}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])

        let read = try appServerResponse(
            #"{"id":4,"method":"fs/readFile","params":{"path":"\#(nestedFile.path)"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((read["result"] as? [String: Any])?["dataBase64"] as? String, nestedPayload)

        XCTAssertNotNil(try appServerResponse(
            #"{"id":5,"method":"fs/copy","params":{"sourcePath":"\#(nestedFile.path)","destinationPath":"\#(copiedFile.path)","recursive":false}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])
        XCTAssertEqual(try String(contentsOf: copiedFile, encoding: .utf8), "hello from app-server")

        XCTAssertNotNil(try appServerResponse(
            #"{"id":6,"method":"fs/copy","params":{"sourcePath":"\#(source.path)","destinationPath":"\#(copiedDir.path)","recursive":true}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])
        XCTAssertEqual(
            try String(contentsOf: copiedDir.appendingPathComponent("nested/note.txt"), encoding: .utf8),
            "hello from app-server"
        )

        let directory = try appServerResponse(
            #"{"id":7,"method":"fs/readDirectory","params":{"path":"\#(source.path)"}}"#,
            codexHome: temp.url
        )
        let entries = try XCTUnwrap((directory["result"] as? [String: Any])?["entries"] as? [[String: Any]])
            .sorted { ($0["fileName"] as? String ?? "") < ($1["fileName"] as? String ?? "") }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["fileName"] as? String, "nested")
        XCTAssertEqual(entries[0]["isDirectory"] as? Bool, true)
        XCTAssertEqual(entries[0]["isFile"] as? Bool, false)
        XCTAssertEqual(entries[1]["fileName"] as? String, "root.txt")
        XCTAssertEqual(entries[1]["isDirectory"] as? Bool, false)
        XCTAssertEqual(entries[1]["isFile"] as? Bool, true)

        XCTAssertNotNil(try appServerResponse(
            #"{"id":8,"method":"fs/remove","params":{"path":"\#(copiedDir.path)"}}"#,
            codexHome: temp.url
        )["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedDir.path))
    }

    func testFsWriteFileAcceptsBase64BytesAndRejectsInvalidBase64() throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("blob.bin", isDirectory: false)
        let bytes = Data([0, 1, 2, 255])

        let write = try appServerResponse(
            #"{"id":1,"method":"fs/writeFile","params":{"path":"\#(file.path)","dataBase64":"\#(bytes.base64EncodedString())"}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(write["result"] as? [String: Any])
        XCTAssertEqual(try Data(contentsOf: file), bytes)

        let read = try appServerResponse(
            #"{"id":2,"method":"fs/readFile","params":{"path":"\#(file.path)"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((read["result"] as? [String: Any])?["dataBase64"] as? String, bytes.base64EncodedString())

        let invalid = try appServerResponse(
            #"{"id":3,"method":"fs/writeFile","params":{"path":"\#(file.path)","dataBase64":"%%%"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.hasPrefix("fs/writeFile requires valid base64 dataBase64:") == true)
    }

    func testFsMethodsRejectRelativePaths() throws {
        let temp = try TemporaryDirectory()
        let absoluteFile = temp.url.appendingPathComponent("absolute.txt", isDirectory: false)
        try "hello".write(to: absoluteFile, atomically: true, encoding: .utf8)
        let expected = "Invalid request: AbsolutePathBuf deserialized without a base path"

        let read = try appServerResponse(#"{"id":1,"method":"fs/readFile","params":{"path":"relative.txt"}}"#, codexHome: temp.url)
        XCTAssertEqual((read["error"] as? [String: Any])?["message"] as? String, expected)
        let write = try appServerResponse(#"{"id":2,"method":"fs/writeFile","params":{"path":"relative.txt","dataBase64":"aGVsbG8="}}"#, codexHome: temp.url)
        XCTAssertEqual((write["error"] as? [String: Any])?["message"] as? String, expected)
        let create = try appServerResponse(#"{"id":3,"method":"fs/createDirectory","params":{"path":"relative-dir","recursive":null}}"#, codexHome: temp.url)
        XCTAssertEqual((create["error"] as? [String: Any])?["message"] as? String, expected)
        let metadata = try appServerResponse(#"{"id":4,"method":"fs/getMetadata","params":{"path":"relative.txt"}}"#, codexHome: temp.url)
        XCTAssertEqual((metadata["error"] as? [String: Any])?["message"] as? String, expected)
        let directory = try appServerResponse(#"{"id":5,"method":"fs/readDirectory","params":{"path":"relative-dir"}}"#, codexHome: temp.url)
        XCTAssertEqual((directory["error"] as? [String: Any])?["message"] as? String, expected)
        let remove = try appServerResponse(#"{"id":6,"method":"fs/remove","params":{"path":"relative.txt","recursive":null,"force":null}}"#, codexHome: temp.url)
        XCTAssertEqual((remove["error"] as? [String: Any])?["message"] as? String, expected)
        let copySource = try appServerResponse(
            #"{"id":7,"method":"fs/copy","params":{"sourcePath":"relative.txt","destinationPath":"\#(absoluteFile.path)","recursive":false}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((copySource["error"] as? [String: Any])?["message"] as? String, expected)
        let copyDestination = try appServerResponse(
            #"{"id":8,"method":"fs/copy","params":{"sourcePath":"\#(absoluteFile.path)","destinationPath":"relative-copy.txt","recursive":false}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((copyDestination["error"] as? [String: Any])?["message"] as? String, expected)
    }

    func testFsCopyRejectsDirectoryWithoutRecursiveAndDescendantCopy() throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let withoutRecursive = try appServerResponse(
            #"{"id":1,"method":"fs/copy","params":{"sourcePath":"\#(source.path)","destinationPath":"\#(temp.url.appendingPathComponent("dest").path)","recursive":false}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (withoutRecursive["error"] as? [String: Any])?["message"] as? String,
            "fs/copy requires recursive: true when sourcePath is a directory"
        )

        let descendant = try appServerResponse(
            #"{"id":2,"method":"fs/copy","params":{"sourcePath":"\#(source.path)","destinationPath":"\#(nested.appendingPathComponent("copy").path)","recursive":true}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (descendant["error"] as? [String: Any])?["message"] as? String,
            "fs/copy cannot copy a directory to itself or one of its descendants"
        )
    }

    func testFsCopyPreservesSymlinksInRecursiveCopy() throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        let copied = temp.url.appendingPathComponent("copied", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("nested-link", isDirectory: false).path,
            withDestinationPath: "nested"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"fs/copy","params":{"sourcePath":"\#(source.path)","destinationPath":"\#(copied.path)","recursive":true}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(response["result"] as? [String: Any])
        let copiedLink = copied.appendingPathComponent("nested-link", isDirectory: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: copiedLink.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path), "nested")
    }

    func testFsWatchReportsDirectoryChangesAndUnwatchStopsNotifications() async throws {
        let temp = try TemporaryDirectory()
        let watched = temp.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        let watch = try decode(processor.processLine(Data(
            #"{"id":1,"method":"fs/watch","params":{"watchId":"watch-repo","path":"\#(watched.path)"}}"#.utf8
        )))
        XCTAssertEqual((watch["result"] as? [String: Any])?["path"] as? String, watched.path)

        let changedFile = watched.appendingPathComponent("FETCH_HEAD", isDirectory: false)
        try "updated\n".write(to: changedFile, atomically: true, encoding: .utf8)
        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        XCTAssertEqual(notification["method"] as? String, "fs/changed")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["watchId"] as? String, "watch-repo")
        XCTAssertEqual(params["changedPaths"] as? [String], [changedFile.path])

        let unwatch = try decode(processor.processLine(Data(
            #"{"id":2,"method":"fs/unwatch","params":{"watchId":"watch-repo"}}"#.utf8
        )))
        XCTAssertNotNil(unwatch["result"] as? [String: Any])
        try "refs\n".write(
            to: watched.appendingPathComponent("packed-refs", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(nanoseconds: 600_000_000)
        let payloadsAfterUnwatch = await notificationCapture.payloadsData()
        XCTAssertEqual(payloadsAfterUnwatch, [])
    }

    func testFsWatchAllowsMissingFileTargetsAndRejectsDuplicateOrRelativeWatch() async throws {
        let temp = try TemporaryDirectory()
        let watched = temp.url.appendingPathComponent("FETCH_HEAD", isDirectory: false)
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        let watch = try decode(processor.processLine(Data(
            #"{"id":1,"method":"fs/watch","params":{"watchId":"watch-fetch","path":"\#(watched.path)"}}"#.utf8
        )))
        XCTAssertEqual((watch["result"] as? [String: Any])?["path"] as? String, watched.path)

        let duplicate = try decode(processor.processLine(Data(
            #"{"id":2,"method":"fs/watch","params":{"watchId":"watch-fetch","path":"\#(watched.path)"}}"#.utf8
        )))
        XCTAssertEqual(
            (duplicate["error"] as? [String: Any])?["message"] as? String,
            "watchId already exists: watch-fetch"
        )

        let relative = try decode(processor.processLine(Data(
            #"{"id":3,"method":"fs/watch","params":{"watchId":"watch-relative","path":"relative-path"}}"#.utf8
        )))
        XCTAssertEqual(
            (relative["error"] as? [String: Any])?["message"] as? String,
            "Invalid request: AbsolutePathBuf deserialized without a base path"
        )

        try "origin/main\n".write(to: watched, atomically: true, encoding: .utf8)
        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["watchId"] as? String, "watch-fetch")
        XCTAssertEqual(params["changedPaths"] as? [String], [watched.path])
    }

    func testAppListReturnsEmptyPageWhenConnectorsUnavailable() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"app/list","params":{"limit":50,"cursor":null,"threadId":null,"forceRefetch":false}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual((result["data"] as? [Any])?.count, 0)
        XCTAssertTrue(result["nextCursor"] is NSNull)
    }

    func testAppListRejectsInvalidAndOutOfRangeCursor() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"app/list","params":{"cursor":"abc"}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(invalidError["message"] as? String, "invalid cursor: abc")

        let beyond = try appServerResponse(
            #"{"id":2,"method":"app/list","params":{"cursor":"1"}}"#,
            codexHome: temp.url
        )
        let beyondError = try XCTUnwrap(beyond["error"] as? [String: Any])
        XCTAssertEqual(beyondError["code"] as? Int, -32600)
        XCTAssertEqual(beyondError["message"] as? String, "cursor 1 exceeds total apps 0")
    }

    func testPluginListReturnsRustEmptyResponseWhenPluginsUnavailable() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{"cwds":["\#(cwd.url.path)"],"forceRemoteSync":true,"marketplaceKinds":["local"]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual((result["marketplaces"] as? [Any])?.count, 0)
        XCTAssertEqual((result["marketplaceLoadErrors"] as? [Any])?.count, 0)
        XCTAssertEqual(result["featuredPluginIds"] as? [String], [])
    }

    func testPluginListLoadsConfiguredLocalMarketplace() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let sourcePath = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        try """
        [marketplaces.debug]
        source_type = "local"
        source = "\(sourcePath)"

        [plugins."weather@debug"]
        enabled = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let marketplaces = try XCTUnwrap(result["marketplaces"] as? [[String: Any]])
        XCTAssertEqual(marketplaces.count, 1)
        XCTAssertEqual(marketplaces[0]["name"] as? String, "debug")
        XCTAssertEqual(
            marketplaces[0]["path"] as? String,
            sourceRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        )
        let marketplaceInterface = try XCTUnwrap(marketplaces[0]["interface"] as? [String: Any])
        XCTAssertEqual(marketplaceInterface["displayName"] as? String, "Debug Marketplace")

        let plugins = try XCTUnwrap(marketplaces[0]["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["id"] as? String, "weather@debug")
        XCTAssertEqual(plugins[0]["name"] as? String, "weather")
        XCTAssertEqual(plugins[0]["installed"] as? Bool, false)
        XCTAssertEqual(plugins[0]["enabled"] as? Bool, true)
        XCTAssertEqual(plugins[0]["installPolicy"] as? String, "INSTALLED_BY_DEFAULT")
        XCTAssertEqual(plugins[0]["authPolicy"] as? String, "ON_USE")
        XCTAssertEqual(plugins[0]["availability"] as? String, "AVAILABLE")
        XCTAssertEqual(plugins[0]["keywords"] as? [String], ["forecast", "local"])
        let source = try XCTUnwrap(plugins[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "local")
        XCTAssertEqual(
            source["path"] as? String,
            sourceRoot.appendingPathComponent("plugins/weather", isDirectory: true).standardizedFileURL.path
        )
        let interface = try XCTUnwrap(plugins[0]["interface"] as? [String: Any])
        XCTAssertEqual(interface["displayName"] as? String, "Weather")
        XCTAssertEqual(interface["shortDescription"] as? String, "Local weather tools")
        XCTAssertEqual(interface["capabilities"] as? [String], ["mcp", "skills"])
        XCTAssertEqual((result["marketplaceLoadErrors"] as? [Any])?.count, 0)
        XCTAssertEqual(result["featuredPluginIds"] as? [String], [])

        let remoteOnly = try appServerResponse(
            #"{"id":2,"method":"plugin/list","params":{"marketplaceKinds":["workspace-directory"]}}"#,
            codexHome: temp.url
        )
        let remoteOnlyResult = try XCTUnwrap(remoteOnly["result"] as? [String: Any])
        XCTAssertEqual((remoteOnlyResult["marketplaces"] as? [Any])?.count, 0)
    }

    func testPluginListValidatesMarketplaceKindsAndAbsoluteCwds() throws {
        let temp = try TemporaryDirectory()

        let invalidKind = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{"marketplaceKinds":["bogus"]}}"#,
            codexHome: temp.url
        )
        let invalidKindError = try XCTUnwrap(invalidKind["error"] as? [String: Any])
        XCTAssertEqual(invalidKindError["code"] as? Int, -32602)
        XCTAssertEqual(
            invalidKindError["message"] as? String,
            "unknown variant `bogus`, expected one of `local`, `workspace-directory`, `shared-with-me`"
        )

        let relativeCwd = try appServerResponse(
            #"{"id":2,"method":"plugin/list","params":{"cwds":["relative/path"]}}"#,
            codexHome: temp.url
        )
        let relativeCwdError = try XCTUnwrap(relativeCwd["error"] as? [String: Any])
        XCTAssertEqual(relativeCwdError["code"] as? Int, -32600)
        XCTAssertEqual(
            relativeCwdError["message"] as? String,
            "Invalid request: AbsolutePathBuf deserialized without a base path"
        )
    }

    func testPluginReadReturnsConfiguredLocalPluginDetail() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let marketplacePath = sourceRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        try """
        [features]
        plugin_hooks = true

        [plugins."weather@debug"]
        enabled = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let plugin = try XCTUnwrap(result["plugin"] as? [String: Any])
        XCTAssertEqual(plugin["marketplaceName"] as? String, "debug")
        XCTAssertEqual(plugin["marketplacePath"] as? String, marketplacePath)
        XCTAssertEqual(plugin["description"] as? String, "Reads local weather")

        let skills = try XCTUnwrap(plugin["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0]["name"] as? String, "weather:forecast")
        XCTAssertEqual(skills[0]["description"] as? String, "forecast local weather")
        XCTAssertEqual(skills[0]["enabled"] as? Bool, true)
        XCTAssertTrue(skills[0]["interface"] is NSNull)
        XCTAssertTrue((skills[0]["path"] as? String)?.hasSuffix("/skills/forecast/SKILL.md") == true)

        let hooks = try XCTUnwrap(plugin["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, "weather@debug:hooks/hooks.json:session_start:0:0")
        XCTAssertEqual(hooks[0]["eventName"] as? String, "sessionStart")

        let apps = try XCTUnwrap(plugin["apps"] as? [[String: Any]])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0]["id"] as? String, "connector_weather")
        XCTAssertEqual(apps[0]["name"] as? String, "Weather")
        XCTAssertEqual(apps[0]["needsAuth"] as? Bool, false)

        XCTAssertEqual(plugin["mcpServers"] as? [String], ["weather"])

        let summary = try XCTUnwrap(plugin["summary"] as? [String: Any])
        XCTAssertEqual(summary["id"] as? String, "weather@debug")
        XCTAssertEqual(summary["enabled"] as? Bool, true)
        XCTAssertEqual(summary["keywords"] as? [String], ["forecast", "local"])
        let source = try XCTUnwrap(summary["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "local")

        let missing = try appServerResponse(
            #"{"id":2,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"missing"}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(
            missingError["message"] as? String,
            "plugin `missing` was not found in marketplace `debug`"
        )
    }

    func testPluginReadUsesManifestDeclaredLocalCapabilityPaths() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let marketplacePath = sourceRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        let pluginRoot = sourceRoot.appendingPathComponent("plugins/weather", isDirectory: true)
        try """
        [features]
        plugin_hooks = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try """
        {
          "name": "weather",
          "description": "Reads local weather",
          "keywords": ["forecast", "local"],
          "skills": "./custom-skills",
          "apps": "./config/apps.json",
          "mcpServers": "./config/mcp.json",
          "hooks": ["./config/one-hooks.json", "./config/two-hooks.json"],
          "interface": {
            "displayName": "Weather",
            "shortDescription": "Local weather tools",
            "capabilities": ["mcp", "skills"]
          }
        }
        """.write(
            to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let customSkillDirectory = pluginRoot.appendingPathComponent("custom-skills/radar", isDirectory: true)
        try FileManager.default.createDirectory(at: customSkillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: radar
        description: read local radar
        ---
        """.write(
            to: customSkillDirectory.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let configDirectory = pluginRoot.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try """
        {
          "apps": {
            "radar": {
              "id": "connector_radar",
              "name": "Radar"
            }
          }
        }
        """.write(
            to: configDirectory.appendingPathComponent("apps.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "mcpServers": {
            "radar": {
              "command": "radar-mcp"
            }
          }
        }
        """.write(
            to: configDirectory.appendingPathComponent("mcp.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo pre"
                  }
                ]
              }
            ]
          }
        }
        """.write(
            to: configDirectory.appendingPathComponent("one-hooks.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo post"
                  }
                ]
              }
            ]
          }
        }
        """.write(
            to: configDirectory.appendingPathComponent("two-hooks.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let plugin = try XCTUnwrap((response["result"] as? [String: Any])?["plugin"] as? [String: Any])

        let skills = try XCTUnwrap(plugin["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.map { $0["name"] as? String }, ["weather:forecast", "weather:radar"])

        let hooks = try XCTUnwrap(plugin["hooks"] as? [[String: Any]])
        XCTAssertEqual(
            hooks.map { $0["key"] as? String },
            [
                "weather@debug:config/one-hooks.json:pre_tool_use:0:0",
                "weather@debug:config/two-hooks.json:post_tool_use:0:0"
            ]
        )

        let apps = try XCTUnwrap(plugin["apps"] as? [[String: Any]])
        XCTAssertEqual(apps.map { $0["id"] as? String }, ["connector_radar"])
        XCTAssertEqual(plugin["mcpServers"] as? [String], ["radar"])
    }

    func testPluginReadValidatesSourceAndReportsRemoteDisabled() throws {
        let temp = try TemporaryDirectory()
        let marketplace = temp.url.appendingPathComponent("marketplace.json").path

        let missingSource = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"pluginName":"gmail"}}"#,
            codexHome: temp.url
        )
        let missingSourceError = try XCTUnwrap(missingSource["error"] as? [String: Any])
        XCTAssertEqual(missingSourceError["code"] as? Int, -32600)
        XCTAssertEqual(
            missingSourceError["message"] as? String,
            "plugin/read requires exactly one of marketplacePath or remoteMarketplaceName"
        )

        let duplicateSource = try appServerResponse(
            #"{"id":2,"method":"plugin/read","params":{"marketplacePath":"\#(marketplace)","remoteMarketplaceName":"openai-curated","pluginName":"gmail"}}"#,
            codexHome: temp.url
        )
        let duplicateSourceError = try XCTUnwrap(duplicateSource["error"] as? [String: Any])
        XCTAssertEqual(duplicateSourceError["code"] as? Int, -32600)
        XCTAssertEqual(
            duplicateSourceError["message"] as? String,
            "plugin/read requires exactly one of marketplacePath or remoteMarketplaceName"
        )

        let remoteDisabled = try appServerResponse(
            #"{"id":3,"method":"plugin/read","params":{"remoteMarketplaceName":"openai-curated","pluginName":"plugins~Plugin_gmail"}}"#,
            codexHome: temp.url
        )
        let remoteDisabledError = try XCTUnwrap(remoteDisabled["error"] as? [String: Any])
        XCTAssertEqual(remoteDisabledError["code"] as? Int, -32600)
        XCTAssertEqual(
            remoteDisabledError["message"] as? String,
            "remote plugin read is not enabled for marketplace openai-curated"
        )
    }

    func testPluginSkillReadReportsRemoteDisabled() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/skill/read","params":{"remoteMarketplaceName":"openai-curated","remotePluginId":"plugins~Plugin_gmail","skillName":""}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "remote plugin skill read is not enabled for marketplace openai-curated"
        )
    }

    func testPluginShareRoutesReportDisabledWhenFeatureUnavailable() throws {
        let temp = try TemporaryDirectory()
        let pluginPath = temp.url.appendingPathComponent("plugin").path

        let save = try appServerResponse(
            #"{"id":1,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","remotePluginId":"bad id"}}"#,
            codexHome: temp.url
        )
        let saveError = try XCTUnwrap(save["error"] as? [String: Any])
        XCTAssertEqual(saveError["code"] as? Int, -32600)
        XCTAssertEqual(saveError["message"] as? String, "plugin sharing is not enabled")

        let update = try appServerResponse(
            #"{"id":2,"method":"plugin/share/updateTargets","params":{"remotePluginId":"bad id","discoverability":"UNLISTED","shareTargets":[{"principalType":"workspace","principalId":"workspace-1"}]}}"#,
            codexHome: temp.url
        )
        let updateError = try XCTUnwrap(update["error"] as? [String: Any])
        XCTAssertEqual(updateError["code"] as? Int, -32600)
        XCTAssertEqual(updateError["message"] as? String, "plugin sharing is not enabled")

        let list = try appServerResponse(
            #"{"id":3,"method":"plugin/share/list","params":{}}"#,
            codexHome: temp.url
        )
        let listError = try XCTUnwrap(list["error"] as? [String: Any])
        XCTAssertEqual(listError["code"] as? Int, -32600)
        XCTAssertEqual(listError["message"] as? String, "plugin sharing is not enabled")

        let delete = try appServerResponse(
            #"{"id":4,"method":"plugin/share/delete","params":{"remotePluginId":"bad id"}}"#,
            codexHome: temp.url
        )
        let deleteError = try XCTUnwrap(delete["error"] as? [String: Any])
        XCTAssertEqual(deleteError["code"] as? Int, -32600)
        XCTAssertEqual(deleteError["message"] as? String, "plugin sharing is not enabled")
    }

    func testPluginInstallValidatesSourceAndReportsRemoteDisabled() throws {
        let temp = try TemporaryDirectory()
        let marketplace = temp.url.appendingPathComponent("marketplace.json").path

        let missingSource = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"pluginName":"gmail"}}"#,
            codexHome: temp.url
        )
        let missingSourceError = try XCTUnwrap(missingSource["error"] as? [String: Any])
        XCTAssertEqual(missingSourceError["code"] as? Int, -32600)
        XCTAssertEqual(
            missingSourceError["message"] as? String,
            "plugin/install requires exactly one of marketplacePath or remoteMarketplaceName"
        )

        let duplicateSource = try appServerResponse(
            #"{"id":2,"method":"plugin/install","params":{"marketplacePath":"\#(marketplace)","remoteMarketplaceName":"openai-curated","pluginName":"plugins~Plugin_gmail"}}"#,
            codexHome: temp.url
        )
        let duplicateSourceError = try XCTUnwrap(duplicateSource["error"] as? [String: Any])
        XCTAssertEqual(duplicateSourceError["code"] as? Int, -32600)
        XCTAssertEqual(
            duplicateSourceError["message"] as? String,
            "plugin/install requires exactly one of marketplacePath or remoteMarketplaceName"
        )

        let remoteDisabled = try appServerResponse(
            #"{"id":3,"method":"plugin/install","params":{"remoteMarketplaceName":"openai-curated","pluginName":"plugins~Plugin_gmail"}}"#,
            codexHome: temp.url
        )
        let remoteDisabledError = try XCTUnwrap(remoteDisabled["error"] as? [String: Any])
        XCTAssertEqual(remoteDisabledError["code"] as? Int, -32600)
        XCTAssertEqual(
            remoteDisabledError["message"] as? String,
            "remote plugin install is not enabled for marketplace openai-curated"
        )
    }

    func testPluginInstallAndUninstallLocalPluginCacheAndConfig() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let marketplacePath = sourceRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        let installedRoot = temp.url
            .appendingPathComponent("plugins/cache/debug/weather/local", isDirectory: true)
        let installedManifest = installedRoot
            .appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false)

        let install = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let installResult = try XCTUnwrap(install["result"] as? [String: Any])
        XCTAssertEqual(installResult["authPolicy"] as? String, "ON_USE")
        XCTAssertEqual((installResult["appsNeedingAuth"] as? [Any])?.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedManifest.path))
        let configAfterInstall = try String(
            contentsOf: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(configAfterInstall.contains(#"[plugins."weather@debug"]"#))
        XCTAssertTrue(configAfterInstall.contains("enabled = true"))

        let uninstall = try appServerResponse(
            #"{"id":2,"method":"plugin/uninstall","params":{"pluginId":"weather@debug"}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(uninstall["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedRoot.path))
        let configAfterUninstall = try String(
            contentsOf: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertFalse(configAfterUninstall.contains(#"[plugins."weather@debug"]"#))
    }

    func testPluginUninstallValidatesIdsAndReportsRemoteDisabled() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"plugin/uninstall","params":{"pluginId":"bad id","forceRemoteSync":true}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(invalidError["message"] as? String, "invalid remote plugin id")

        let remoteDisabled = try appServerResponse(
            #"{"id":2,"method":"plugin/uninstall","params":{"pluginId":"plugins~Plugin_gmail","forceRemoteSync":true}}"#,
            codexHome: temp.url
        )
        let remoteDisabledError = try XCTUnwrap(remoteDisabled["error"] as? [String: Any])
        XCTAssertEqual(remoteDisabledError["code"] as? Int, -32600)
        XCTAssertEqual(remoteDisabledError["message"] as? String, "remote plugin uninstall is not enabled")
    }

    func testMarketplaceUpgradeReturnsRustEmptyOutcomeWithoutConfiguredGitMarketplaces() throws {
        let temp = try TemporaryDirectory()

        let all = try appServerResponse(
            #"{"id":1,"method":"marketplace/upgrade","params":{}}"#,
            codexHome: temp.url
        )
        let allResult = try XCTUnwrap(all["result"] as? [String: Any])
        XCTAssertEqual(allResult["selectedMarketplaces"] as? [String], [])
        XCTAssertEqual(allResult["upgradedRoots"] as? [String], [])
        XCTAssertEqual((allResult["errors"] as? [Any])?.count, 0)

        try """
        [marketplaces.local]
        source_type = "local"
        source = "/tmp/marketplace"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let missingGit = try appServerResponse(
            #"{"id":2,"method":"marketplace/upgrade","params":{"marketplaceName":"local"}}"#,
            codexHome: temp.url
        )
        let missingGitError = try XCTUnwrap(missingGit["error"] as? [String: Any])
        XCTAssertEqual(missingGitError["code"] as? Int, -32600)
        XCTAssertEqual(
            missingGitError["message"] as? String,
            "marketplace `local` is not configured as a Git marketplace"
        )
    }

    func testMarketplaceAddRecordsLocalDirectoryAndDuplicateSource() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRoot(named: "debug", in: temp.url)
        let sourcePath = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let sourceJSON = jsonString(sourcePath)

        let first = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":\#(sourceJSON)}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        XCTAssertEqual(firstResult["marketplaceName"] as? String, "debug")
        XCTAssertEqual(firstResult["installedRoot"] as? String, sourcePath)
        XCTAssertEqual(firstResult["alreadyAdded"] as? Bool, false)

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[marketplaces.debug]"))
        XCTAssertTrue(config.contains(#"source_type = "local""#))
        XCTAssertTrue(config.contains(#"source = "\#(sourcePath)""#))

        let duplicate = try appServerResponse(
            #"{"id":2,"method":"marketplace/add","params":{"source":\#(sourceJSON)}}"#,
            codexHome: temp.url
        )
        let duplicateResult = try XCTUnwrap(duplicate["result"] as? [String: Any])
        XCTAssertEqual(duplicateResult["marketplaceName"] as? String, "debug")
        XCTAssertEqual(duplicateResult["installedRoot"] as? String, sourcePath)
        XCTAssertEqual(duplicateResult["alreadyAdded"] as? Bool, true)
    }

    func testMarketplaceAddRejectsConflictingLocalSourceForExistingName() throws {
        let temp = try TemporaryDirectory()
        let firstRoot = try makeLocalMarketplaceRoot(named: "debug", in: temp.url, suffix: "one")
        let secondRoot = try makeLocalMarketplaceRoot(named: "debug", in: temp.url, suffix: "two")
        let firstJSON = jsonString(firstRoot.resolvingSymlinksInPath().standardizedFileURL.path)
        let secondJSON = jsonString(secondRoot.resolvingSymlinksInPath().standardizedFileURL.path)

        _ = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":\#(firstJSON)}}"#,
            codexHome: temp.url
        )

        let conflict = try appServerResponse(
            #"{"id":2,"method":"marketplace/add","params":{"source":\#(secondJSON)}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(conflict["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "marketplace 'debug' is already added from a different source; remove it before adding this source"
        )
    }

    func testMarketplaceAddValidatesLocalSourceBeforeConfigMutation() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRoot(named: "debug", in: temp.url)
        let sourcePath = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let sourceJSON = jsonString(sourcePath)

        let sparse = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":\#(sourceJSON),"sparsePaths":["plugins/debug"]}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (sparse["error"] as? [String: Any])?["message"] as? String,
            "--sparse is only supported for git marketplace sources"
        )

        let ref = try appServerResponse(
            #"{"id":2,"method":"marketplace/add","params":{"source":\#(sourceJSON),"refName":"main"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (ref["error"] as? [String: Any])?["message"] as? String,
            "--ref is only supported for git marketplace sources"
        )

        let file = temp.url.appendingPathComponent("marketplace-file.json", isDirectory: false)
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        let filePathJSON = jsonString(file.path)
        let fileResponse = try appServerResponse(
            #"{"id":3,"method":"marketplace/add","params":{"source":\#(filePathJSON)}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (fileResponse["error"] as? [String: Any])?["message"] as? String,
            "local marketplace source must be a directory, not a file"
        )

        let invalid = try appServerResponse(
            #"{"id":4,"method":"marketplace/add","params":{"source":"not a source"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (invalid["error"] as? [String: Any])?["message"] as? String,
            "invalid marketplace source format; expected owner/repo, a git URL, or a local marketplace path"
        )

        let missingManifestRoot = temp.url.appendingPathComponent("missing-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: missingManifestRoot, withIntermediateDirectories: true)
        let missingManifestJSON = jsonString(missingManifestRoot.path)
        let missingManifest = try appServerResponse(
            #"{"id":5,"method":"marketplace/add","params":{"source":\#(missingManifestJSON)}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(
            (missingManifest["error"] as? [String: Any])?["message"] as? String,
            "invalid marketplace file `\(missingManifestRoot.path)`: marketplace root does not contain a supported manifest"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("config.toml").path))
    }

    func testMarketplaceRemoveDeletesConfigAndInstalledRoot() throws {
        let temp = try TemporaryDirectory()
        try """
        [marketplaces.debug]
        source_type = "git"
        source = "https://github.com/owner/repo.git"
        ref = "main"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let installedRoot = temp.url
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installedRoot.appendingPathComponent(".agents/plugins", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: installedRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"marketplace/remove","params":{"marketplaceName":"debug"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["marketplaceName"] as? String, "debug")
        XCTAssertEqual(result["installedRoot"] as? String, installedRoot.standardizedFileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedRoot.path))
        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertFalse(config.contains("[marketplaces.debug]"))
    }

    func testMarketplaceRemoveValidatesNameAndUnknownMarketplace() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"marketplace/remove","params":{"marketplaceName":"bad name"}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(
            invalidError["message"] as? String,
            "invalid marketplace name: only ASCII letters, digits, `_`, and `-` are allowed"
        )

        let unknown = try appServerResponse(
            #"{"id":2,"method":"marketplace/remove","params":{"marketplaceName":"debug"}}"#,
            codexHome: temp.url
        )
        let unknownError = try XCTUnwrap(unknown["error"] as? [String: Any])
        XCTAssertEqual(unknownError["code"] as? Int, -32600)
        XCTAssertEqual(
            unknownError["message"] as? String,
            "marketplace `debug` is not configured or installed"
        )

        try """
        [marketplaces.Debug]
        source_type = "git"
        source = "https://github.com/owner/repo.git"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let caseMismatch = try appServerResponse(
            #"{"id":3,"method":"marketplace/remove","params":{"marketplaceName":"debug"}}"#,
            codexHome: temp.url
        )
        let caseMismatchError = try XCTUnwrap(caseMismatch["error"] as? [String: Any])
        XCTAssertEqual(caseMismatchError["code"] as? Int, -32600)
        XCTAssertEqual(
            caseMismatchError["message"] as? String,
            "marketplace `debug` does not match configured marketplace `Debug` exactly"
        )
    }

    func testExternalAgentConfigDetectAndEmptyImportReturnRustShapes() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"includeHome":false,"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: temp.url
        )
        let detectResult = try XCTUnwrap(detect["result"] as? [String: Any])
        XCTAssertEqual((detectResult["items"] as? [Any])?.count, 0)

        let emptyImport = try appServerResponse(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[]}}"#,
            codexHome: temp.url
        )
        let emptyImportResult = try XCTUnwrap(emptyImport["result"] as? [String: Any])
        XCTAssertTrue(emptyImportResult.isEmpty)

        let nonEmptyImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"CONFIG","description":"Config","cwd":null}]}}"#,
            codexHome: temp.url
        )
        let nonEmptyImportError = try XCTUnwrap(nonEmptyImport["error"] as? [String: Any])
        XCTAssertEqual(nonEmptyImportError["code"] as? Int, -32600)
        XCTAssertEqual(nonEmptyImportError["message"] as? String, "external agent config import is not implemented")
    }

    func testMcpResourceAndToolCallsValidateThreadBeforeLiveDispatch() throws {
        let temp = try TemporaryDirectory()
        let threadID = ConversationId().description

        let resourceInvalidThread = try appServerResponse(
            #"{"id":1,"method":"mcpServer/resource/read","params":{"threadId":"not-a-thread","server":"filesystem","uri":"file:///tmp/a"}}"#,
            codexHome: temp.url
        )
        let resourceInvalidThreadError = try XCTUnwrap(resourceInvalidThread["error"] as? [String: Any])
        XCTAssertEqual(resourceInvalidThreadError["code"] as? Int, -32600)
        XCTAssertTrue((resourceInvalidThreadError["message"] as? String)?.hasPrefix("invalid thread id: ") == true)

        let resourceMissingThread = try appServerResponse(
            #"{"id":2,"method":"mcpServer/resource/read","params":{"threadId":"\#(threadID)","server":"filesystem","uri":"file:///tmp/a"}}"#,
            codexHome: temp.url
        )
        let resourceMissingThreadError = try XCTUnwrap(resourceMissingThread["error"] as? [String: Any])
        XCTAssertEqual(resourceMissingThreadError["code"] as? Int, -32600)
        XCTAssertEqual(resourceMissingThreadError["message"] as? String, "thread not found: \(threadID)")

        let toolMissingThread = try appServerResponse(
            #"{"id":3,"method":"mcpServer/tool/call","params":{"threadId":"\#(threadID)","server":"filesystem","tool":"read_file","arguments":{}}}"#,
            codexHome: temp.url
        )
        let toolMissingThreadError = try XCTUnwrap(toolMissingThread["error"] as? [String: Any])
        XCTAssertEqual(toolMissingThreadError["code"] as? Int, -32600)
        XCTAssertEqual(toolMissingThreadError["message"] as? String, "thread not found: \(threadID)")
    }

    func testThreadTurnsListPaginatesAndSummarizesByDefault() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "first",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        try appendRolloutEvents(to: rolloutPath, timestamp: "2025-01-05T12:00:01Z", events: [
            .agentMessage(AgentMessageEvent(message: "draft")),
            .agentMessage(AgentMessageEvent(message: "final")),
            .userMessage(UserMessageEvent(message: "second")),
            .agentMessage(AgentMessageEvent(message: "second done")),
            .userMessage(UserMessageEvent(message: "third"))
        ])

        let firstPage = try appServerResponse(
            #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","limit":2}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(firstPage["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.map(turnUserText), ["third", "second"])
        XCTAssertTrue(firstData.allSatisfy { $0["itemsView"] as? String == "summary" })
        XCTAssertEqual(turnAgentTexts(firstData[0]), [])
        XCTAssertEqual(turnAgentTexts(firstData[1]), ["second done"])
        let nextCursor = try XCTUnwrap(firstResult["nextCursor"] as? String)
        let backwardsCursor = try XCTUnwrap(firstResult["backwardsCursor"] as? String)

        let secondPage = try appServerResponse(
            #"{"id":2,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","cursor":\#(jsonString(nextCursor)),"limit":10}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(secondPage["result"] as? [String: Any])
        let secondData = try XCTUnwrap(secondResult["data"] as? [[String: Any]])
        XCTAssertEqual(secondData.map(turnUserText), ["first"])
        XCTAssertEqual(turnAgentTexts(secondData[0]), ["final"])

        try appendRolloutEvents(to: rolloutPath, timestamp: "2025-01-05T12:00:02Z", events: [
            .userMessage(UserMessageEvent(message: "fourth"))
        ])
        let newerPage = try appServerResponse(
            #"{"id":3,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","cursor":\#(jsonString(backwardsCursor)),"sortDirection":"asc","limit":10}}"#,
            codexHome: temp.url
        )
        let newerResult = try XCTUnwrap(newerPage["result"] as? [String: Any])
        let newerData = try XCTUnwrap(newerResult["data"] as? [[String: Any]])
        XCTAssertEqual(newerData.map(turnUserText), ["third", "fourth"])
    }

    func testThreadTurnsListSupportsItemsViewAndUnsupportedItemsHydration() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "first",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        try appendRolloutEvents(to: rolloutPath, timestamp: "2025-01-05T12:00:01Z", events: [
            .agentMessage(AgentMessageEvent(message: "draft")),
            .agentMessage(AgentMessageEvent(message: "final"))
        ])

        let full = try appServerResponse(
            #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","itemsView":"full"}}"#,
            codexHome: temp.url
        )
        let fullTurn = try XCTUnwrap(((full["result"] as? [String: Any])?["data"] as? [[String: Any]])?.first)
        XCTAssertEqual(fullTurn["itemsView"] as? String, "full")
        XCTAssertEqual(turnAgentTexts(fullTurn), ["draft", "final"])

        let notLoaded = try appServerResponse(
            #"{"id":2,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","itemsView":"notLoaded"}}"#,
            codexHome: temp.url
        )
        let notLoadedTurn = try XCTUnwrap(((notLoaded["result"] as? [String: Any])?["data"] as? [[String: Any]])?.first)
        XCTAssertEqual(notLoadedTurn["itemsView"] as? String, "notLoaded")
        XCTAssertEqual((notLoadedTurn["items"] as? [Any])?.count, 0)

        let unsupported = try appServerResponse(
            #"{"id":3,"method":"thread/turns/items/list","params":{"threadId":"\#(threadID)","turnId":"turn-1"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(unsupported["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertEqual(error["message"] as? String, "thread/turns/items/list is not supported yet")
    }

    func testThreadLoadedListPaginatesLoadedThreadIDs() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let firstStart = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)
        ))
        let secondStart = try decodeMessages(processor.processLine(
            Data(#"{"id":2,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)
        ))
        let firstID = try XCTUnwrap(((firstStart[0]["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String)
        let secondID = try XCTUnwrap(((secondStart[0]["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String)
        let expected = [firstID, secondID].sorted()

        let firstPage = try decode(processor.processLine(
            Data(#"{"id":3,"method":"thread/loaded/list","params":{"limit":1}}"#.utf8)
        ))
        let firstResult = try XCTUnwrap(firstPage["result"] as? [String: Any])
        XCTAssertEqual(firstResult["data"] as? [String], [expected[0]])
        XCTAssertEqual(firstResult["nextCursor"] as? String, expected[0])

        let secondPage = try decode(processor.processLine(
            Data(#"{"id":4,"method":"thread/loaded/list","params":{"limit":1,"cursor":"\#(expected[0])"}}"#.utf8)
        ))
        let secondResult = try XCTUnwrap(secondPage["result"] as? [String: Any])
        XCTAssertEqual(secondResult["data"] as? [String], [expected[1]])
        XCTAssertEqual(secondResult["nextCursor"] as? NSNull, NSNull())
    }

    func testThreadLoadedListRejectsInvalidCursorAndKeepsUnsubscribedThreadLoaded() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let start = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)
        ))
        let threadID = try XCTUnwrap(((start[0]["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String)

        let unsubscribe = try decode(processor.processLine(
            Data(#"{"id":2,"method":"thread/unsubscribe","params":{"threadId":"\#(threadID)"}}"#.utf8)
        ))
        XCTAssertEqual((unsubscribe["result"] as? [String: Any])?["status"] as? String, "unsubscribed")

        let list = try decode(processor.processLine(
            Data(#"{"id":3,"method":"thread/loaded/list","params":{}}"#.utf8)
        ))
        let result = try XCTUnwrap(list["result"] as? [String: Any])
        XCTAssertEqual(result["data"] as? [String], [threadID])
        XCTAssertEqual(result["nextCursor"] as? NSNull, NSNull())

        let invalid = try decode(processor.processLine(
            Data(#"{"id":4,"method":"thread/loaded/list","params":{"cursor":"bogus"}}"#.utf8)
        ))
        let error = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid cursor: bogus")
    }

    func testThreadUnsubscribeReportsSubscriptionStatus() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let first = try decode(processor.processLine(Data(#"{"id":2,"method":"thread/unsubscribe","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        XCTAssertEqual((first["result"] as? [String: Any])?["status"] as? String, "unsubscribed")

        let second = try decode(processor.processLine(Data(#"{"id":3,"method":"thread/unsubscribe","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        XCTAssertEqual((second["result"] as? [String: Any])?["status"] as? String, "notSubscribed")
    }

    func testThreadUnsubscribeReportsNotLoadedAndRejectsInvalidThreadID() throws {
        let temp = try TemporaryDirectory()
        let persistedThreadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Persisted but not loaded",
            provider: "mock_provider"
        )
        let missingThreadID = UUID().uuidString.lowercased()

        let persistedNotLoaded = try appServerResponse(
            #"{"id":0,"method":"thread/unsubscribe","params":{"threadId":"\#(persistedThreadID)"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((persistedNotLoaded["result"] as? [String: Any])?["status"] as? String, "notLoaded")

        let notLoaded = try appServerResponse(
            #"{"id":1,"method":"thread/unsubscribe","params":{"threadId":"\#(missingThreadID)"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((notLoaded["result"] as? [String: Any])?["status"] as? String, "notLoaded")

        let invalid = try appServerResponse(
            #"{"id":2,"method":"thread/unsubscribe","params":{"threadId":"not-a-uuid"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "invalid thread id: Invalid conversation id: not-a-uuid")
    }

    func testThreadResumeRebuildsImageGenerationEvents() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Generate an image",
            provider: "mock_provider"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let savedPath = try AbsolutePath(absolutePath: "/tmp/generated.png")
        try appendRolloutEvents(
            to: rolloutPath,
            timestamp: "2025-01-05T12:00:01Z",
            events: [
                .imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1")),
                .imageGenerationEnd(ImageGenerationEndEvent(
                    callID: "ig-1",
                    status: "completed",
                    revisedPrompt: "A tiny blue square",
                    result: "Zm9v",
                    savedPath: savedPath
                ))
            ]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        let items = try XCTUnwrap(turns[0]["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["type"] as? String }, ["userMessage", "imageGeneration"])
        let image = items[1]
        XCTAssertEqual(image["id"] as? String, "ig-1")
        XCTAssertEqual(image["status"] as? String, "completed")
        XCTAssertEqual(image["revisedPrompt"] as? String, "A tiny blue square")
        XCTAssertEqual(image["result"] as? String, "Zm9v")
        XCTAssertEqual(image["savedPath"] as? String, "/tmp/generated.png")
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

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let messages = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/archive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(messages[1]["method"] as? String, "thread/archived")
        let params = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rolloutPath))
        let archivedPath = temp.url
            .appendingPathComponent("archived_sessions", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: rolloutPath).lastPathComponent, isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedPath.path))
    }

    func testThreadUnarchiveRestoresRolloutAndEmitsNotification() throws {
        let temp = try TemporaryDirectory()
        let id = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "restore me",
            provider: "openai"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: id))
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        _ = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/archive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))
        let messages = try decodeMessages(processor.processLine(
            Data(#"{"id":2,"method":"thread/unarchive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        XCTAssertEqual(thread["id"] as? String, id)
        XCTAssertEqual(thread["preview"] as? String, "restore me")
        XCTAssertEqual(thread["status"].flatMap { ($0 as? [String: Any])?["type"] as? String }, "notLoaded")
        XCTAssertEqual(messages[1]["method"] as? String, "thread/unarchived")
        let params = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolloutPath))
        XCTAssertNotNil(try RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: id))
    }

    func testThreadUnarchiveRejectsInvalidOrMissingArchivedThread() throws {
        let temp = try TemporaryDirectory()
        let invalid = try appServerResponse(
            #"{"id":1,"method":"thread/unarchive","params":{"threadId":"not-a-uuid"}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertTrue((invalidError["message"] as? String)?.contains("invalid thread id:") == true)

        let missingID = UUID().uuidString.lowercased()
        let missing = try appServerResponse(
            #"{"id":2,"method":"thread/unarchive","params":{"threadId":"\#(missingID)"}}"#,
            codexHome: temp.url
        )
        let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(missingError["code"] as? Int, -32600)
        XCTAssertEqual(missingError["message"] as? String, "thread not archived: \(missingID)")
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
        XCTAssertEqual(result["codexHome"] as? String, temp.url.standardizedFileURL.path)
        XCTAssertEqual(result["platformFamily"] as? String, "unix")
        #if os(macOS)
            XCTAssertEqual(result["platformOs"] as? String, "macos")
        #elseif os(Linux)
            XCTAssertEqual(result["platformOs"] as? String, "linux")
        #elseif os(Windows)
            XCTAssertEqual(result["platformOs"] as? String, "windows")
        #else
            XCTAssertEqual(result["platformOs"] as? String, "unknown")
        #endif
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

    func testAccountLoginChatGPTStartsServerAndCancelReportsCanceled() throws {
        let temp = try TemporaryDirectory()
        try #"forced_chatgpt_workspace_id = "ws-v2""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgpt"}}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        XCTAssertEqual(loginResult["type"] as? String, "chatgpt")
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)
        let authURL = try XCTUnwrap(loginResult["authUrl"] as? String)
        XCTAssertNotNil(UUID(uuidString: loginID))
        XCTAssertTrue(authURL.contains("allowed_workspace_id=ws-v2"))

        let cancel = try decode(processor.processLine(Data(#"{"id":2,"method":"account/login/cancel","params":{"loginId":"\#(loginID)"}}"#.utf8)))
        let cancelResult = try XCTUnwrap(cancel["result"] as? [String: Any])
        XCTAssertEqual(cancelResult["status"] as? String, "canceled")

        let cancelAgain = try decode(processor.processLine(Data(#"{"id":3,"method":"account/login/cancel","params":{"loginId":"\#(loginID)"}}"#.utf8)))
        let cancelAgainResult = try XCTUnwrap(cancelAgain["result"] as? [String: Any])
        XCTAssertEqual(cancelAgainResult["status"] as? String, "notFound")
    }

    func testLegacyLoginChatGPTStartsServerWithForcedWorkspaceAndCanCancel() throws {
        let temp = try TemporaryDirectory()
        try #"forced_chatgpt_workspace_id = "ws-forced""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"loginChatGpt"}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)
        let authURL = try XCTUnwrap(loginResult["authUrl"] as? String)
        XCTAssertNotNil(UUID(uuidString: loginID))
        XCTAssertTrue(authURL.contains("allowed_workspace_id=ws-forced"))

        let cancel = try decode(processor.processLine(Data(#"{"id":2,"method":"cancelLoginChatGpt","params":{"loginId":"\#(loginID)"}}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(cancel["result"] as? [String: Any]).isEmpty)
    }

    func testLegacyLoginChatGPTRejectedWhenForcedAPIAndCancelReportsMissing() throws {
        let temp = try TemporaryDirectory()
        try #"forced_login_method = "api""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let forcedResponse = try appServerResponse(
            #"{"id":1,"method":"loginChatGpt"}"#,
            codexHome: temp.url
        )
        let forcedError = try XCTUnwrap(forcedResponse["error"] as? [String: Any])
        XCTAssertEqual(forcedError["code"] as? Int, -32600)
        XCTAssertEqual(forcedError["message"] as? String, "ChatGPT login is disabled. Use API key login instead.")

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let missingID = "11111111-1111-1111-1111-111111111111"
        let cancel = try decode(processor.processLine(Data(#"{"id":2,"method":"cancelLoginChatGpt","params":{"loginId":"\#(missingID)"}}"#.utf8)))
        let cancelError = try XCTUnwrap(cancel["error"] as? [String: Any])
        XCTAssertEqual(cancelError["code"] as? Int, -32600)
        XCTAssertEqual(cancelError["message"] as? String, "login id not found: \(missingID)")
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
        XCTAssertEqual(firstData[0]["id"] as? String, "gpt-5.5")
        XCTAssertEqual(firstData[0]["displayName"] as? String, "GPT-5.5")
        XCTAssertEqual(firstData[0]["description"] as? String, "Frontier model for complex coding, research, and real-world work.")
        XCTAssertTrue(firstData[0]["upgrade"] is NSNull)
        XCTAssertTrue(firstData[0]["upgradeInfo"] is NSNull)
        let availabilityNux = try XCTUnwrap(firstData[0]["availabilityNux"] as? [String: Any])
        XCTAssertTrue((availabilityNux["message"] as? String)?.contains("GPT-5.5") == true)
        XCTAssertEqual(firstData[0]["hidden"] as? Bool, false)
        XCTAssertEqual(firstData[0]["defaultReasoningEffort"] as? String, "medium")
        XCTAssertEqual(firstData[0]["inputModalities"] as? [String], ["text", "image"])
        XCTAssertEqual(firstData[0]["supportsPersonality"] as? Bool, true)
        XCTAssertEqual(firstData[0]["additionalSpeedTiers"] as? [String], ["fast"])
        let serviceTiers = try XCTUnwrap(firstData[0]["serviceTiers"] as? [[String: Any]])
        XCTAssertEqual(serviceTiers.first?["id"] as? String, "priority")
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

        let allVisible = try appServerResponse(
            #"{"id":3,"method":"model/list","params":{"limit":100}}"#,
            codexHome: temp.url
        )
        let allVisibleResult = try XCTUnwrap(allVisible["result"] as? [String: Any])
        let visibleData = try XCTUnwrap(allVisibleResult["data"] as? [[String: Any]])
        XCTAssertEqual(visibleData.map { $0["id"] as? String }, [
            "gpt-5.5",
            "gpt-5.4",
            "gpt-5.4-mini",
            "gpt-5.3-codex",
            "gpt-5.2"
        ])
        XCTAssertFalse(visibleData.contains { $0["hidden"] as? Bool == true })

        let codex53 = try XCTUnwrap(visibleData.first { $0["id"] as? String == "gpt-5.3-codex" })
        XCTAssertEqual(codex53["upgrade"] as? String, "gpt-5.4")
        let upgradeInfo = try XCTUnwrap(codex53["upgradeInfo"] as? [String: Any])
        XCTAssertEqual(upgradeInfo["model"] as? String, "gpt-5.4")
        XCTAssertTrue(upgradeInfo["upgradeCopy"] is NSNull)
        XCTAssertTrue(upgradeInfo["modelLink"] is NSNull)
        XCTAssertTrue((upgradeInfo["migrationMarkdown"] as? String)?.contains("Introducing GPT-5.4") == true)

        let withHidden = try appServerResponse(
            #"{"id":4,"method":"model/list","params":{"limit":100,"includeHidden":true}}"#,
            codexHome: temp.url
        )
        let withHiddenResult = try XCTUnwrap(withHidden["result"] as? [String: Any])
        let hiddenData = try XCTUnwrap(withHiddenResult["data"] as? [[String: Any]])
        let reviewModel = try XCTUnwrap(hiddenData.first { $0["id"] as? String == "codex-auto-review" })
        XCTAssertEqual(reviewModel["hidden"] as? Bool, true)
        XCTAssertEqual(hiddenData.count, 6)
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

    func testModelProviderCapabilitiesReadReturnsDefaultProviderCapabilities() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"modelProvider/capabilities/read","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["namespaceTools"] as? Bool, true)
        XCTAssertEqual(result["imageGeneration"] as? Bool, true)
        XCTAssertEqual(result["webSearch"] as? Bool, true)
    }

    func testModelProviderCapabilitiesReadReturnsAmazonBedrockCapabilities() throws {
        let temp = try TemporaryDirectory()
        try #"model_provider = "amazon-bedrock""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"modelProvider/capabilities/read","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["namespaceTools"] as? Bool, false)
        XCTAssertEqual(result["imageGeneration"] as? Bool, false)
        XCTAssertEqual(result["webSearch"] as? Bool, false)
    }

    func testWindowsSandboxReadinessReportsNotConfiguredOffWindows() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"windowsSandbox/readiness"}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "notConfigured")
    }

    func testWindowsSandboxSetupStartReturnsStartedAndCompletionNotificationOffWindows() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"windowsSandbox/setupStart","params":{"mode":"unelevated"}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)

        let response = messages[0]
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["started"] as? Bool, true)

        let notification = messages[1]
        XCTAssertEqual(notification["method"] as? String, "windowsSandbox/setupCompleted")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["mode"] as? String, "unelevated")
        XCTAssertEqual(params["success"] as? Bool, false)
        XCTAssertEqual(params["error"] as? String, "legacy Windows sandbox setup is only supported on Windows")
    }

    func testWindowsSandboxSetupStartRejectsRelativeCwdBeforeStarting() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"windowsSandbox/setupStart","params":{"mode":"unelevated","cwd":"relative-root"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.contains("Invalid request") == true)
    }

    func testExperimentalFeatureListReturnsRustV2ShapeAndPaginates() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        memories = true
        shell_tool = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let first = try appServerResponse(
            #"{"id":1,"method":"experimentalFeature/list","params":{"limit":2}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.count, 2)
        XCTAssertEqual(firstData[0]["name"] as? String, "undo")
        XCTAssertEqual(firstData[0]["stage"] as? String, "removed")
        XCTAssertTrue(firstData[0]["displayName"] is NSNull)
        XCTAssertEqual(firstData[0]["enabled"] as? Bool, false)
        XCTAssertEqual(firstData[0]["defaultEnabled"] as? Bool, false)
        XCTAssertEqual(firstData[1]["name"] as? String, "shell_tool")
        XCTAssertEqual(firstData[1]["stage"] as? String, "stable")
        XCTAssertEqual(firstData[1]["enabled"] as? Bool, false)
        XCTAssertEqual(firstData[1]["defaultEnabled"] as? Bool, true)
        XCTAssertEqual(firstResult["nextCursor"] as? String, "2")

        let all = try appServerResponse(
            #"{"id":2,"method":"experimentalFeature/list","params":{"limit":100}}"#,
            codexHome: temp.url
        )
        let allResult = try XCTUnwrap(all["result"] as? [String: Any])
        let allData = try XCTUnwrap(allResult["data"] as? [[String: Any]])
        XCTAssertEqual(allData.count, FeatureRegistry.specs.count)
        XCTAssertTrue(allResult["nextCursor"] is NSNull)
        XCTAssertEqual(allData.map { $0["name"] as? String }, FeatureRegistry.specs.map(\.key))

        let terminalResize = try XCTUnwrap(allData.first { $0["name"] as? String == "terminal_resize_reflow" })
        XCTAssertEqual(terminalResize["stage"] as? String, "beta")
        XCTAssertEqual(terminalResize["displayName"] as? String, "Terminal resize reflow")
        XCTAssertEqual(
            terminalResize["description"] as? String,
            "Rebuild Codex-owned transcript scrollback when the terminal width changes."
        )
        XCTAssertEqual(terminalResize["announcement"] as? String, "")
        XCTAssertEqual(terminalResize["enabled"] as? Bool, true)
        XCTAssertEqual(terminalResize["defaultEnabled"] as? Bool, true)

        let memories = try XCTUnwrap(allData.first { $0["name"] as? String == "memories" })
        XCTAssertEqual(memories["stage"] as? String, "beta")
        XCTAssertEqual(memories["displayName"] as? String, "Memories")
        XCTAssertEqual(memories["enabled"] as? Bool, true)
        XCTAssertEqual(memories["defaultEnabled"] as? Bool, false)
    }

    func testExperimentalFeatureListRejectsInvalidCursorWithRustErrorCode() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"experimentalFeature/list","params":{"cursor":"bogus"}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(invalidError["message"] as? String, "invalid cursor: bogus")

        let beyond = try appServerResponse(
            #"{"id":2,"method":"experimentalFeature/list","params":{"cursor":"9999"}}"#,
            codexHome: temp.url
        )
        let beyondError = try XCTUnwrap(beyond["error"] as? [String: Any])
        XCTAssertEqual(beyondError["code"] as? Int, -32600)
        XCTAssertEqual(
            beyondError["message"] as? String,
            "cursor 9999 exceeds total feature flags \(FeatureRegistry.specs.count)"
        )
    }

    func testExperimentalFeatureEnablementSetAppliesToFeatureListAndConfigRead() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let set = try decode(processor.processLine(Data(
            #"{"id":1,"method":"experimentalFeature/enablement/set","params":{"enablement":{"memories":true,"plugins":false,"tool_search":false}}}"#.utf8
        )))
        let setResult = try XCTUnwrap(set["result"] as? [String: Any])
        let setEnablement = try XCTUnwrap(setResult["enablement"] as? [String: Bool])
        XCTAssertEqual(setEnablement["memories"], true)
        XCTAssertEqual(setEnablement["plugins"], false)
        XCTAssertEqual(setEnablement["tool_search"], false)

        let list = try decode(processor.processLine(Data(
            #"{"id":2,"method":"experimentalFeature/list","params":{"limit":100}}"#.utf8
        )))
        let listResult = try XCTUnwrap(list["result"] as? [String: Any])
        let listData = try XCTUnwrap(listResult["data"] as? [[String: Any]])
        let memories = try XCTUnwrap(listData.first { $0["name"] as? String == "memories" })
        let plugins = try XCTUnwrap(listData.first { $0["name"] as? String == "plugins" })
        let toolSearch = try XCTUnwrap(listData.first { $0["name"] as? String == "tool_search" })
        XCTAssertEqual(memories["enabled"] as? Bool, true)
        XCTAssertEqual(plugins["enabled"] as? Bool, false)
        XCTAssertEqual(toolSearch["enabled"] as? Bool, false)

        let read = try decode(processor.processLine(Data(
            #"{"id":3,"method":"config/read","params":{}}"#.utf8
        )))
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(readResult["config"] as? [String: Any])
        let features = try XCTUnwrap(config["features"] as? [String: Any])
        XCTAssertEqual(features["memories"] as? Bool, true)
        XCTAssertEqual(features["plugins"] as? Bool, false)
        XCTAssertEqual(features["tool_search"] as? Bool, false)
    }

    func testExperimentalFeatureEnablementSetDoesNotOverrideUserConfig() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        memories = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        _ = try decode(processor.processLine(Data(
            #"{"id":1,"method":"experimentalFeature/enablement/set","params":{"enablement":{"memories":true}}}"#.utf8
        )))
        let read = try decode(processor.processLine(Data(
            #"{"id":2,"method":"config/read","params":{}}"#.utf8
        )))
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(readResult["config"] as? [String: Any])
        let features = try XCTUnwrap(config["features"] as? [String: Any])
        XCTAssertEqual(features["memories"] as? Bool, false)

        let list = try decode(processor.processLine(Data(
            #"{"id":3,"method":"experimentalFeature/list","params":{"limit":100}}"#.utf8
        )))
        let listResult = try XCTUnwrap(list["result"] as? [String: Any])
        let listData = try XCTUnwrap(listResult["data"] as? [[String: Any]])
        let memories = try XCTUnwrap(listData.first { $0["name"] as? String == "memories" })
        XCTAssertEqual(memories["enabled"] as? Bool, false)
    }

    func testExperimentalFeatureEnablementSetRejectsUnsupportedAndNonCanonicalFeatures() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let unsupported = try decode(processor.processLine(Data(
            #"{"id":1,"method":"experimentalFeature/enablement/set","params":{"enablement":{"personality":false}}}"#.utf8
        )))
        let unsupportedError = try XCTUnwrap(unsupported["error"] as? [String: Any])
        XCTAssertEqual(unsupportedError["code"] as? Int, -32600)
        XCTAssertTrue((unsupportedError["message"] as? String)?.contains("unsupported feature enablement `personality`") == true)
        XCTAssertTrue((unsupportedError["message"] as? String)?.contains("apps, memories, plugins, remote_control, tool_search, tool_suggest, tool_call_mcp_elicitation") == true)

        let alias = try decode(processor.processLine(Data(
            #"{"id":2,"method":"experimentalFeature/enablement/set","params":{"enablement":{"memory_tool":true}}}"#.utf8
        )))
        let aliasError = try XCTUnwrap(alias["error"] as? [String: Any])
        XCTAssertEqual(aliasError["code"] as? Int, -32600)
        XCTAssertEqual(
            aliasError["message"] as? String,
            "invalid feature enablement `memory_tool`: use canonical feature key `memories`"
        )
    }

    func testCollaborationModeListReturnsRustPresets() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"collaborationMode/list","params":{}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0]["name"] as? String, "Plan")
        XCTAssertEqual(data[0]["mode"] as? String, "plan")
        XCTAssertTrue(data[0]["model"] is NSNull)
        XCTAssertEqual(data[0]["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(data[1]["name"] as? String, "Default")
        XCTAssertEqual(data[1]["mode"] as? String, "default")
        XCTAssertTrue(data[1]["model"] is NSNull)
        XCTAssertTrue(data[1]["reasoning_effort"] is NSNull)
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

    func testMcpServerReloadReturnsEmptyResult() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"config/mcpServer/reload"}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
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
        mcp_oauth_callback_port = 5678
        mcp_oauth_callback_url = "https://oauth.github.test/callback"

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
        XCTAssertEqual(requests[0].callbackPort, 5678)
        XCTAssertEqual(requests[0].callbackURL, "https://oauth.github.test/callback")
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

    func testSkillsConfigWriteTogglesPathSelectorAndAffectsSkillsList() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let skill = codexHome.url.appendingPathComponent("skills/demo/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillContents(name: "demo", description: "user skill").write(to: skill, atomically: true, encoding: .utf8)

        let disable = try appServerResponse(
            #"{"id":1,"method":"skills/config/write","params":{"path":"\#(skill.path)","enabled":false}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((disable["result"] as? [String: Any])?["effectiveEnabled"] as? Bool, false)
        XCTAssertEqual(
            try String(contentsOf: codexHome.url.appendingPathComponent("config.toml"), encoding: .utf8),
            """
            [[skills.config]]
            path = "\(skill.path)"
            enabled = false
            """ + "\n"
        )

        let disabledList = try appServerResponse(
            #"{"id":2,"method":"skills/list","params":{"cwds":["\#(cwd.url.path)"],"forceReload":true}}"#,
            codexHome: codexHome.url
        )
        let disabledData = try XCTUnwrap((disabledList["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertEqual((disabledData[0]["skills"] as? [[String: Any]])?.count, 0)

        let enable = try appServerResponse(
            #"{"id":3,"method":"skills/config/write","params":{"path":"\#(skill.path)","enabled":true}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((enable["result"] as? [String: Any])?["effectiveEnabled"] as? Bool, true)
        XCTAssertEqual(
            try String(contentsOf: codexHome.url.appendingPathComponent("config.toml"), encoding: .utf8),
            ""
        )
    }

    func testSkillsConfigWriteTogglesNameSelectorAndValidatesSelectors() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let skill = codexHome.url.appendingPathComponent("skills/yeet/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillContents(name: "github:yeet", description: "user skill").write(to: skill, atomically: true, encoding: .utf8)

        let disable = try appServerResponse(
            #"{"id":1,"method":"skills/config/write","params":{"name":"  github:yeet  ","enabled":false}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((disable["result"] as? [String: Any])?["effectiveEnabled"] as? Bool, false)
        XCTAssertEqual(
            try String(contentsOf: codexHome.url.appendingPathComponent("config.toml"), encoding: .utf8),
            """
            [[skills.config]]
            name = "github:yeet"
            enabled = false
            """ + "\n"
        )

        let disabledList = try appServerResponse(
            #"{"id":2,"method":"skills/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let disabledData = try XCTUnwrap((disabledList["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertEqual((disabledData[0]["skills"] as? [[String: Any]])?.count, 0)

        for (index, params) in [
            #"{"path":"\#(skill.path)","name":"github:yeet","enabled":false}"#,
            #"{"name":"   ","enabled":false}"#,
            #"{"enabled":false}"#
        ].enumerated() {
            let invalid = try appServerResponse(
                #"{"id":\#(index + 3),"method":"skills/config/write","params":\#(params)}"#,
                codexHome: codexHome.url
            )
            let error = try XCTUnwrap(invalid["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32602)
            XCTAssertEqual(error["message"] as? String, "skills/config/write requires exactly one of path or name")
        }
    }

    func testHooksListReturnsUserCommandHooks() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        try """
        [hooks]

        [[hooks.PreToolUse]]
        matcher = "Bash"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 /tmp/listed-hook.py"
        timeout = 5
        statusMessage = "running listed hook"
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["cwd"] as? String, cwd.url.path)
        XCTAssertEqual((data[0]["warnings"] as? [Any])?.count, 0)
        XCTAssertEqual((data[0]["errors"] as? [Any])?.count, 0)
        let hooks = try XCTUnwrap(data[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["eventName"] as? String, "preToolUse")
        XCTAssertEqual(hooks[0]["handlerType"] as? String, "command")
        XCTAssertEqual(hooks[0]["matcher"] as? String, "Bash")
        XCTAssertEqual(hooks[0]["command"] as? String, "python3 /tmp/listed-hook.py")
        XCTAssertEqual(hooks[0]["timeoutSec"] as? Int, 5)
        XCTAssertEqual(hooks[0]["statusMessage"] as? String, "running listed hook")
        XCTAssertEqual(hooks[0]["source"] as? String, "user")
        XCTAssertTrue(hooks[0]["pluginId"] is NSNull)
        XCTAssertEqual(hooks[0]["displayOrder"] as? Int, 0)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, true)
        XCTAssertEqual(hooks[0]["isManaged"] as? Bool, false)
        XCTAssertTrue((hooks[0]["currentHash"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "untrusted")
    }

    func testHooksListRespectsDisabledHooksFeature() throws {
        let codexHome = try TemporaryDirectory()
        try """
        [features]
        hooks = false

        [[hooks.PreToolUse]]
        matcher = "Bash"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "echo hidden"
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual((data[0]["hooks"] as? [Any])?.count, 0)
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

    func testConfigRequirementsReadReturnsNullWhenUnset() throws {
        let temp = try TemporaryDirectory()
        let missingRequirements = temp.url.appendingPathComponent("missing-requirements.toml", isDirectory: false)
        let response = try appServerResponse(
            #"{"id":1,"method":"configRequirements/read","params":{}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: missingRequirements)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result["requirements"] is NSNull)
    }

    func testConfigRequirementsReadReturnsRustShapeForAllowedPoliciesAndSandboxes() throws {
        let temp = try TemporaryDirectory()
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        allowed_approval_policies = ["untrusted", "on-request"]
        allowed_sandbox_modes = ["read-only", "workspace-write", "external-sandbox"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"configRequirements/read","params":{}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let requirements = try XCTUnwrap(result["requirements"] as? [String: Any])
        XCTAssertEqual(requirements["allowedApprovalPolicies"] as? [String], ["untrusted", "on-request"])
        XCTAssertEqual(requirements["allowedSandboxModes"] as? [String], ["read-only", "workspace-write"])
        XCTAssertTrue(requirements["allowedApprovalsReviewers"] is NSNull)
        XCTAssertTrue(requirements["allowedWebSearchModes"] is NSNull)
        XCTAssertTrue(requirements["featureRequirements"] is NSNull)
        XCTAssertTrue(requirements["hooks"] is NSNull)
        XCTAssertTrue(requirements["enforceResidency"] is NSNull)
        XCTAssertTrue(requirements["network"] is NSNull)
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

    func testCommandExecFollowUpsReportNoActiveProcess() throws {
        let temp = try TemporaryDirectory()

        let write = try appServerResponse(
            #"{"id":1,"method":"command/exec/write","params":{"processId":"proc-1","deltaBase64":"aGk="}}"#,
            codexHome: temp.url
        )
        let writeError = try XCTUnwrap(write["error"] as? [String: Any])
        XCTAssertEqual(writeError["code"] as? Int, -32600)
        XCTAssertEqual(writeError["message"] as? String, #"no active command/exec for process id "proc-1""#)

        let resize = try appServerResponse(
            #"{"id":2,"method":"command/exec/resize","params":{"processId":"proc-1","size":{"rows":24,"cols":80}}}"#,
            codexHome: temp.url
        )
        let resizeError = try XCTUnwrap(resize["error"] as? [String: Any])
        XCTAssertEqual(resizeError["code"] as? Int, -32600)
        XCTAssertEqual(resizeError["message"] as? String, #"no active command/exec for process id "proc-1""#)

        let terminate = try appServerResponse(
            #"{"id":3,"method":"command/exec/terminate","params":{"processId":"proc-1"}}"#,
            codexHome: temp.url
        )
        let terminateError = try XCTUnwrap(terminate["error"] as? [String: Any])
        XCTAssertEqual(terminateError["code"] as? Int, -32600)
        XCTAssertEqual(terminateError["message"] as? String, #"no active command/exec for process id "proc-1""#)
    }

    func testCommandExecFollowUpsValidateWriteAndResizeParams() throws {
        let temp = try TemporaryDirectory()

        let emptyWrite = try appServerResponse(
            #"{"id":1,"method":"command/exec/write","params":{"processId":"proc-1"}}"#,
            codexHome: temp.url
        )
        let emptyWriteError = try XCTUnwrap(emptyWrite["error"] as? [String: Any])
        XCTAssertEqual(emptyWriteError["code"] as? Int, -32602)
        XCTAssertEqual(emptyWriteError["message"] as? String, "command/exec/write requires deltaBase64 or closeStdin")

        let badBase64 = try appServerResponse(
            #"{"id":2,"method":"command/exec/write","params":{"processId":"proc-1","deltaBase64":"%%%bad%%%"}}"#,
            codexHome: temp.url
        )
        let badBase64Error = try XCTUnwrap(badBase64["error"] as? [String: Any])
        XCTAssertEqual(badBase64Error["code"] as? Int, -32602)
        XCTAssertEqual(badBase64Error["message"] as? String, "invalid deltaBase64: invalid base64 data")

        let zeroSize = try appServerResponse(
            #"{"id":3,"method":"command/exec/resize","params":{"processId":"proc-1","size":{"rows":0,"cols":80}}}"#,
            codexHome: temp.url
        )
        let zeroSizeError = try XCTUnwrap(zeroSize["error"] as? [String: Any])
        XCTAssertEqual(zeroSizeError["code"] as? Int, -32602)
        XCTAssertEqual(zeroSizeError["message"] as? String, "command/exec size rows and cols must be greater than 0")
    }

    func testProcessFollowUpsReportNoActiveProcess() throws {
        let temp = try TemporaryDirectory()

        let write = try appServerResponse(
            #"{"id":1,"method":"process/writeStdin","params":{"processHandle":"proc-1","deltaBase64":"aGk="}}"#,
            codexHome: temp.url
        )
        let writeError = try XCTUnwrap(write["error"] as? [String: Any])
        XCTAssertEqual(writeError["code"] as? Int, -32600)
        XCTAssertEqual(writeError["message"] as? String, #"no active process for process handle "proc-1""#)

        let resize = try appServerResponse(
            #"{"id":2,"method":"process/resizePty","params":{"processHandle":"proc-1","size":{"rows":24,"cols":80}}}"#,
            codexHome: temp.url
        )
        let resizeError = try XCTUnwrap(resize["error"] as? [String: Any])
        XCTAssertEqual(resizeError["code"] as? Int, -32600)
        XCTAssertEqual(resizeError["message"] as? String, #"no active process for process handle "proc-1""#)

        let kill = try appServerResponse(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-1"}}"#,
            codexHome: temp.url
        )
        let killError = try XCTUnwrap(kill["error"] as? [String: Any])
        XCTAssertEqual(killError["code"] as? Int, -32600)
        XCTAssertEqual(killError["message"] as? String, #"no active process for process handle "proc-1""#)
    }

    func testProcessSpawnValidatesRustParamsBeforeLiveLifecycle() throws {
        let temp = try TemporaryDirectory()

        let emptyCommand = try appServerResponse(
            #"{"id":1,"method":"process/spawn","params":{"command":[],"processHandle":"proc-1","cwd":"\#(temp.url.path)"}}"#,
            codexHome: temp.url
        )
        let emptyCommandError = try XCTUnwrap(emptyCommand["error"] as? [String: Any])
        XCTAssertEqual(emptyCommandError["code"] as? Int, -32600)
        XCTAssertEqual(emptyCommandError["message"] as? String, "command must not be empty")

        let emptyHandle = try appServerResponse(
            #"{"id":2,"method":"process/spawn","params":{"command":["echo"],"processHandle":"","cwd":"\#(temp.url.path)"}}"#,
            codexHome: temp.url
        )
        let emptyHandleError = try XCTUnwrap(emptyHandle["error"] as? [String: Any])
        XCTAssertEqual(emptyHandleError["code"] as? Int, -32600)
        XCTAssertEqual(emptyHandleError["message"] as? String, "processHandle must not be empty")

        let relativeCwd = try appServerResponse(
            #"{"id":3,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"relative"}}"#,
            codexHome: temp.url
        )
        let relativeCwdError = try XCTUnwrap(relativeCwd["error"] as? [String: Any])
        XCTAssertEqual(relativeCwdError["code"] as? Int, -32600)
        XCTAssertEqual(
            relativeCwdError["message"] as? String,
            "Invalid request: AbsolutePathBuf deserialized without a base path"
        )

        let sizeWithoutTty = try appServerResponse(
            #"{"id":4,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","size":{"rows":24,"cols":80}}}"#,
            codexHome: temp.url
        )
        let sizeWithoutTtyError = try XCTUnwrap(sizeWithoutTty["error"] as? [String: Any])
        XCTAssertEqual(sizeWithoutTtyError["code"] as? Int, -32602)
        XCTAssertEqual(sizeWithoutTtyError["message"] as? String, "process/spawn size requires tty: true")

        let negativeTimeout = try appServerResponse(
            #"{"id":5,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","timeoutMs":-1}}"#,
            codexHome: temp.url
        )
        let negativeTimeoutError = try XCTUnwrap(negativeTimeout["error"] as? [String: Any])
        XCTAssertEqual(negativeTimeoutError["code"] as? Int, -32602)
        XCTAssertEqual(
            negativeTimeoutError["message"] as? String,
            "process/spawn timeoutMs must be non-negative, got -1"
        )

        let zeroSize = try appServerResponse(
            #"{"id":6,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","tty":true,"size":{"rows":0,"cols":80}}}"#,
            codexHome: temp.url
        )
        let zeroSizeError = try XCTUnwrap(zeroSize["error"] as? [String: Any])
        XCTAssertEqual(zeroSizeError["code"] as? Int, -32602)
        XCTAssertEqual(zeroSizeError["message"] as? String, "process size rows and cols must be greater than 0")
    }

    func testProcessFollowUpsValidateWriteAndResizeParams() throws {
        let temp = try TemporaryDirectory()

        let emptyWrite = try appServerResponse(
            #"{"id":1,"method":"process/writeStdin","params":{"processHandle":"proc-1"}}"#,
            codexHome: temp.url
        )
        let emptyWriteError = try XCTUnwrap(emptyWrite["error"] as? [String: Any])
        XCTAssertEqual(emptyWriteError["code"] as? Int, -32602)
        XCTAssertEqual(emptyWriteError["message"] as? String, "process/writeStdin requires deltaBase64 or closeStdin")

        let badBase64 = try appServerResponse(
            #"{"id":2,"method":"process/writeStdin","params":{"processHandle":"proc-1","deltaBase64":"%%%bad%%%"}}"#,
            codexHome: temp.url
        )
        let badBase64Error = try XCTUnwrap(badBase64["error"] as? [String: Any])
        XCTAssertEqual(badBase64Error["code"] as? Int, -32602)
        XCTAssertEqual(badBase64Error["message"] as? String, "invalid deltaBase64: invalid base64 data")

        let zeroSize = try appServerResponse(
            #"{"id":3,"method":"process/resizePty","params":{"processHandle":"proc-1","size":{"rows":0,"cols":80}}}"#,
            codexHome: temp.url
        )
        let zeroSizeError = try XCTUnwrap(zeroSize["error"] as? [String: Any])
        XCTAssertEqual(zeroSizeError["code"] as? Int, -32602)
        XCTAssertEqual(zeroSizeError["message"] as? String, "process size rows and cols must be greater than 0")
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

    private func nextNotificationPayload(
        _ capture: AppServerNotificationCapture,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                await capture.nextPayload()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw AppServerTestTimeout()
            }
            let value = try await group.next()
            group.cancelAll()
            return try XCTUnwrap(value)
        }
    }

    private func testConfiguration(
        codexHome: URL,
        requiresOpenAIAuth: Bool = true,
        feedback: CodexFeedback = CodexFeedback(),
        feedbackUploadTransport: any FeedbackUploadTransport = URLSessionFeedbackUploadTransport(),
        accountRateLimitsFetcher: any AccountRateLimitsFetching = URLSessionAccountRateLimitsFetcher(),
        authRefreshTransport: AppServerAuthRefreshTransport? = nil,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter,
        configLayerOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides()
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
            mcpOAuthLoginStarter: mcpOAuthLoginStarter,
            configLayerOverrides: configLayerOverrides
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

    private func turnUserText(_ turn: [String: Any]) -> String {
        let items = turn["items"] as? [[String: Any]] ?? []
        guard let user = items.first(where: { $0["type"] as? String == "userMessage" }),
              let content = user["content"] as? [[String: Any]],
              let textItem = content.first(where: { $0["type"] as? String == "text" })
        else {
            return ""
        }
        return textItem["text"] as? String ?? ""
    }

    private func turnAgentTexts(_ turn: [String: Any]) -> [String] {
        let items = turn["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard item["type"] as? String == "agentMessage" else {
                return nil
            }
            return item["text"] as? String
        }
    }

    private func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }

    @discardableResult
    private func writeRollout(
        codexHome: URL,
        filenameTimestamp: String,
        timestamp: String,
        preview: String,
        provider: String?,
        source: SessionSource = .cli,
        gitInfo: GitInfo? = nil
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
            ), git: gitInfo))
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

    private func makeLocalMarketplaceRoot(
        named name: String,
        in parent: URL,
        suffix: String = "source"
    ) throws -> URL {
        let root = parent.appendingPathComponent("marketplace-\(suffix)", isDirectory: true)
        let manifestDirectory = root.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try """
        {
          "name": "\(name)",
          "plugins": []
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func makeLocalMarketplaceRootWithPlugin(
        named name: String,
        pluginName: String,
        in parent: URL
    ) throws -> URL {
        let root = parent.appendingPathComponent("marketplace-\(name)", isDirectory: true)
        let manifestDirectory = root.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try """
        {
          "name": "\(name)",
          "interface": {
            "displayName": "Debug Marketplace"
          },
          "plugins": [
            {
              "name": "\(pluginName)",
              "source": "./plugins/\(pluginName)",
              "policy": {
                "installation": "INSTALLED_BY_DEFAULT",
                "authentication": "ON_USE"
              }
            }
          ]
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let pluginManifestDirectory = root
            .appendingPathComponent("plugins/\(pluginName)", isDirectory: true)
            .appendingPathComponent(".codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginManifestDirectory, withIntermediateDirectories: true)
        try """
        {
          "name": "\(pluginName)",
          "description": "Reads local weather",
          "keywords": ["forecast", "local"],
          "interface": {
            "displayName": "Weather",
            "shortDescription": "Local weather tools",
            "capabilities": ["mcp", "skills"]
          }
        }
        """.write(
            to: pluginManifestDirectory.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let pluginRoot = root.appendingPathComponent("plugins/\(pluginName)", isDirectory: true)
        let skillDirectory = pluginRoot.appendingPathComponent("skills/forecast", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: forecast
        description: forecast local weather
        ---
        """.write(
            to: skillDirectory.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "apps": {
            "weather": {
              "id": "connector_weather",
              "name": "Weather"
            }
          }
        }
        """.write(
            to: pluginRoot.appendingPathComponent(".app.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "mcpServers": {
            "weather": {
              "command": "weather-mcp"
            }
          }
        }
        """.write(
            to: pluginRoot.appendingPathComponent(".mcp.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let hookDirectory = pluginRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hookDirectory, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo startup"
                  }
                ]
              }
            ]
          }
        }
        """.write(
            to: hookDirectory.appendingPathComponent("hooks.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return root
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

private struct AppServerTestTimeout: Error {}

private actor AppServerNotificationCapture {
    private var payloads: [Data] = []
    private var waiters: [CheckedContinuation<Data, Never>] = []

    func append(_ data: Data) {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: data)
            return
        }
        payloads.append(data)
    }

    func payloadsData() -> [Data] {
        payloads
    }

    func nextPayload() async -> Data {
        if !payloads.isEmpty {
            return payloads.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
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
