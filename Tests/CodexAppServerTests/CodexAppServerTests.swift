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
      },
      "rate_limit_reached_type": {
        "type": "workspace_member_usage_limit_reached"
      },
      "additional_rate_limits": [
        {
          "limit_name": "codex_other",
          "metered_feature": "codex_other",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 88,
              "limit_window_seconds": 1800,
              "reset_after_seconds": 600,
              "reset_at": 1735693200
            }
          }
        }
      ]
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
        XCTAssertEqual(result["serviceTier"] as? NSNull, NSNull())
        XCTAssertEqual(result["cwd"] as? String, cwd.url.path)
        XCTAssertEqual(result["instructionSources"] as? [String], [])
        XCTAssertEqual(result["approvalPolicy"] as? String, "never")
        XCTAssertEqual(result["approvalsReviewer"] as? String, "user")
        XCTAssertEqual((result["sandbox"] as? [String: Any])?["type"] as? String, "workspace-write")
        XCTAssertEqual(result["permissionProfile"] as? NSNull, NSNull())
        XCTAssertEqual(result["activePermissionProfile"] as? NSNull, NSNull())
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

    func testThreadStartExperimentalFieldsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let cases: [(String, String)] = [
            (#"{"approvalPolicy":{"type":"granular","sandboxApproval":true}}"#, "askForApproval.granular"),
            (#"{"environments":[]}"#, "thread/start.environments"),
            (#"{"dynamicTools":[]}"#, "thread/start.dynamicTools"),
            (#"{"permissions":{"profile":"readOnly"}}"#, "thread/start.permissions"),
            (#"{"mockExperimentalField":"mock"}"#, "thread/start.mockExperimentalField"),
            (#"{"experimentalRawEvents":true}"#, "thread/start.experimentalRawEvents"),
            (#"{"persistFullHistory":true}"#, "thread/start.persistFullHistory")
        ]

        for (index, testCase) in cases.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"thread/start","params":\#(testCase.0)}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(testCase.1) requires experimentalApi capability")
        }
    }

    func testThreadStartExperimentalFalseFlagsDoNotRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"experimentalRawEvents":false,"persistFullHistory":false}}"#.utf8)))

        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertNil(messages[0]["error"])
    }

    func testThreadStartRejectsPermissionsWithSandbox() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"sandbox":"read-only","permissions":{"profile":"readOnly"}}}"#.utf8)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "`permissions` cannot be combined with `sandbox`")
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

    func testTurnStartExperimentalFieldsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let cases: [(String, String)] = [
            (#""responsesapiClientMetadata":{"k":"v"}"#, "turn/start.responsesapiClientMetadata"),
            (#""environments":[]"#, "turn/start.environments"),
            (#""approvalPolicy":{"type":"granular","sandboxApproval":true}"#, "askForApproval.granular"),
            (#""permissions":{"profile":"readOnly"}"#, "turn/start.permissions"),
            (#""collaborationMode":{"mode":"plan"}"#, "turn/start.collaborationMode")
        ]

        for (index, testCase) in cases.enumerated() {
            let response = try decode(processor.processLine(Data(#"{"id":\#(index + 10),"method":"turn/start","params":{"threadId":"00000000-0000-0000-0000-000000000000","input":[{"type":"text","text":"Hello"}],\#(testCase.0)}}"#.utf8)))
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(testCase.1) requires experimentalApi capability")
        }
    }

    func testTurnStartRejectsPermissionsWithSandboxPolicy() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(#"{"id":10,"method":"turn/start","params":{"threadId":"00000000-0000-0000-0000-000000000000","input":[{"type":"text","text":"Hello"}],"permissions":{"profile":"readOnly"},"sandboxPolicy":{"mode":"readOnly"}}}"#.utf8)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "`permissions` cannot be combined with `sandboxPolicy`")
    }

    func testTurnSteerAppendsInputAndReturnsActiveTurnID() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let turnMessages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Start"}]}}"#.utf8)))
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)

        let steer = try decode(processor.processLine(Data(#"{"id":3,"method":"turn/steer","params":{"threadId":"\#(threadID)","expectedTurnId":"\#(turnID)","input":[{"type":"text","text":"Steer"},{"type":"image","url":"https://example.test/two.png"}]}}"#.utf8)))

        let steerResult = try XCTUnwrap(steer["result"] as? [String: Any])
        XCTAssertEqual(steerResult["turnId"] as? String, turnID)

        let resume = try decode(processor.processLine(Data(#"{"id":4,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 2)
        let steeredItems = try XCTUnwrap(turns[1]["items"] as? [[String: Any]])
        XCTAssertEqual(steeredItems.count, 1)
        let steeredContent = try XCTUnwrap(steeredItems[0]["content"] as? [[String: Any]])
        XCTAssertEqual(steeredContent[0]["text"] as? String, "Steer")
        XCTAssertEqual(steeredContent[1]["url"] as? String, "https://example.test/two.png")
    }

    func testTurnSteerRejectsNoActiveMismatchedAndEmptyInputs() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let noActive = try decode(processor.processLine(Data(#"{"id":2,"method":"turn/steer","params":{"threadId":"\#(threadID)","expectedTurnId":"turn-does-not-exist","input":[{"type":"text","text":"Steer"}]}}"#.utf8)))
        let noActiveError = try XCTUnwrap(noActive["error"] as? [String: Any])
        XCTAssertEqual(noActiveError["code"] as? Int, -32600)
        XCTAssertEqual(noActiveError["message"] as? String, "no active turn to steer")

        let turnMessages = try decodeMessages(processor.processLine(Data(#"{"id":3,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Start"}]}}"#.utf8)))
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)

        let mismatch = try decode(processor.processLine(Data(#"{"id":4,"method":"turn/steer","params":{"threadId":"\#(threadID)","expectedTurnId":"wrong-turn","input":[{"type":"text","text":"Steer"}]}}"#.utf8)))
        let mismatchError = try XCTUnwrap(mismatch["error"] as? [String: Any])
        XCTAssertEqual(mismatchError["code"] as? Int, -32600)
        XCTAssertEqual(mismatchError["message"] as? String, "expected active turn id `wrong-turn` but found `\(turnID)`")

        let empty = try decode(processor.processLine(Data(#"{"id":5,"method":"turn/steer","params":{"threadId":"\#(threadID)","expectedTurnId":"\#(turnID)","input":[]}}"#.utf8)))
        let emptyError = try XCTUnwrap(empty["error"] as? [String: Any])
        XCTAssertEqual(emptyError["code"] as? Int, -32600)
        XCTAssertEqual(emptyError["message"] as? String, "input must not be empty")
    }

    func testTurnSteerExperimentalMetadataRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"turn/steer","params":{"threadId":"00000000-0000-0000-0000-000000000000","expectedTurnId":"turn-id","input":[{"type":"text","text":"Steer"}],"responsesapiClientMetadata":{"k":"v"}}}"#.utf8)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "turn/steer.responsesapiClientMetadata requires experimentalApi capability")
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

    func testRuntimeTurnDiffEventEmitsUpdatedNotification() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )
        let unifiedDiff = """
        diff --git a/Sources/One.swift b/Sources/One.swift
        --- a/Sources/One.swift
        +++ b/Sources/One.swift
        @@ -1 +1 @@
        -old
        +new
        """

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .turnDiff(TurnDiffEvent(unifiedDiff: unifiedDiff))
        )

        let messages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["method"] as? String, "turn/diff/updated")
        let params = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["turnId"] as? String, "turn-1")
        XCTAssertEqual(params["diff"] as? String, unifiedDiff)
    }

    func testAcceptedLineAnalyticsUploadsOnTurnCompletion() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let uploader = AppServerRecordingAcceptedLineAnalyticsUploader()
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            cwd: cwd.url,
            acceptedLineAnalyticsUploader: uploader
        ))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"model":"gpt-analytics","modelProvider":"mock_provider","cwd":"\#(cwd.url.path)"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let turnMessages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"edit"}]}}"#.utf8)))
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)
        let unifiedDiff = """
        diff --git a/Sources/One.swift b/Sources/One.swift
        --- a/Sources/One.swift
        +++ b/Sources/One.swift
        @@ -1 +1 @@
        -let oldValue = 1
        +let acceptedValue = 2
        """

        await processor.handleRuntimeEvent(
            threadID: threadID,
            turnID: turnID,
            event: .turnDiff(TurnDiffEvent(unifiedDiff: unifiedDiff))
        )
        _ = try decodeMessages(processor.processLine(Data(#"{"id":3,"method":"turn/interrupt","params":{"threadId":"\#(threadID)","turnId":"\#(turnID)"}}"#.utf8)))

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        let events = try XCTUnwrap(requests.first?.events)
        XCTAssertEqual(events.count, 1)
        let params = events[0].eventParams
        XCTAssertEqual(params.turnID, turnID)
        XCTAssertEqual(params.threadID, threadID)
        XCTAssertEqual(params.modelSlug, "gpt-analytics")
        XCTAssertEqual(params.productSurface, "codex")
        XCTAssertEqual(params.acceptedAddedLines, 1)
        XCTAssertEqual(params.acceptedDeletedLines, 1)
        XCTAssertEqual(params.lineFingerprints.count, 1)
        XCTAssertEqual(
            params.lineFingerprints[0].lineHash,
            AcceptedLines.fingerprintHash(domain: "line", value: "let acceptedValue = 2")
        )
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
        XCTAssertEqual(result["serviceTier"] as? NSNull, NSNull())
        XCTAssertEqual(result["instructionSources"] as? [String], [])
        XCTAssertEqual(result["approvalPolicy"] as? String, "untrusted")
        XCTAssertEqual(result["approvalsReviewer"] as? String, "user")
        XCTAssertEqual((result["sandbox"] as? [String: Any])?["type"] as? String, "read-only")
        XCTAssertEqual(result["permissionProfile"] as? NSNull, NSNull())
        XCTAssertEqual(result["activePermissionProfile"] as? NSNull, NSNull())
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

    func testThreadResumeExperimentalFieldsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let cases: [(String, String)] = [
            (#""approvalPolicy":{"type":"granular","sandboxApproval":true}"#, "askForApproval.granular"),
            (#""history":[]"#, "thread/resume.history"),
            (#""path":"/tmp/rollout.jsonl""#, "thread/resume.path"),
            (#""permissions":{"profile":"readOnly"}"#, "thread/resume.permissions"),
            (#""excludeTurns":true"#, "thread/resume.excludeTurns"),
            (#""persistFullHistory":true"#, "thread/resume.persistFullHistory")
        ]

        for (index, testCase) in cases.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"thread/resume","params":{"threadId":"00000000-0000-0000-0000-000000000000",\#(testCase.0)}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(testCase.1) requires experimentalApi capability")
        }
    }

    func testThreadResumeRejectsPermissionsWithSandbox() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"thread/resume","params":{"threadId":"00000000-0000-0000-0000-000000000000","sandbox":"read-only","permissions":{"profile":"readOnly"}}}"#.utf8)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "`permissions` cannot be combined with `sandbox`")
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

    func testThreadForkExperimentalFieldsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let cases: [(String, String)] = [
            (#""path":"/tmp/source.jsonl""#, "thread/fork.path"),
            (#""approvalPolicy":{"type":"granular","sandboxApproval":true}"#, "askForApproval.granular"),
            (#""permissions":{"profile":"readOnly"}"#, "thread/fork.permissions"),
            (#""excludeTurns":true"#, "thread/fork.excludeTurns"),
            (#""persistFullHistory":true"#, "thread/fork.persistFullHistory")
        ]

        for (index, testCase) in cases.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"thread/fork","params":{"threadId":"00000000-0000-0000-0000-000000000000",\#(testCase.0)}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(testCase.1) requires experimentalApi capability")
        }
    }

    func testThreadForkRejectsPermissionsWithSandbox() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"thread/fork","params":{"threadId":"00000000-0000-0000-0000-000000000000","sandbox":"read-only","permissions":{"profile":"readOnly"}}}"#.utf8)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "`permissions` cannot be combined with `sandbox`")
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

    func testThreadApproveGuardianDeniedActionValidatesEventAndThread() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-03-00",
            timestamp: "2025-01-06T08:03:00Z",
            preview: "guardian operation",
            provider: "mock_provider"
        )

        let accepted = try appServerResponse(
            """
            {"id":1,"method":"thread/approveGuardianDeniedAction","params":{"threadId":"\(threadID)","event":{"id":"guardian-1","turn_id":"turn-1","started_at_ms":1234,"status":"denied","risk_level":"high","action":{"type":"command","source":"shell","command":"rm -rf build","cwd":"/repo"}}}}
            """,
            codexHome: temp.url
        )
        let acceptedResult = try XCTUnwrap(accepted["result"] as? [String: Any])
        XCTAssertTrue(acceptedResult.isEmpty)

        let invalidEvent = try appServerResponse(
            #"{"id":2,"method":"thread/approveGuardianDeniedAction","params":{"threadId":"\#(threadID)","event":{"id":"guardian-2","action":{"type":"command","source":"shell","command":"pwd","cwd":"/repo"}}}}"#,
            codexHome: temp.url
        )
        let invalidEventError = try XCTUnwrap(invalidEvent["error"] as? [String: Any])
        XCTAssertEqual(invalidEventError["code"] as? Int, -32600)
        XCTAssertTrue((invalidEventError["message"] as? String)?.hasPrefix("invalid Guardian denial event:") == true)

        let missingThreadID = UUID().uuidString.lowercased()
        let missingThread = try appServerResponse(
            """
            {"id":3,"method":"thread/approveGuardianDeniedAction","params":{"threadId":"\(missingThreadID)","event":{"id":"guardian-3","status":"denied","action":{"type":"command","source":"shell","command":"pwd","cwd":"/repo"}}}}
            """,
            codexHome: temp.url
        )
        let missingThreadError = try XCTUnwrap(missingThread["error"] as? [String: Any])
        XCTAssertEqual(missingThreadError["code"] as? Int, -32600)
        XCTAssertEqual(missingThreadError["message"] as? String, "thread not found: \(missingThreadID)")
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

    func testThreadGoalMethodsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        for (index, method) in ["thread/goal/set", "thread/goal/get", "thread/goal/clear"].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{"threadId":"\#(threadID)"}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(method) requires experimentalApi capability")
        }
    }

    func testThreadGoalMethodsReturnRustDisabledFeatureErrorWhenExperimentalAPIEnabled() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        for (index, method) in ["thread/goal/set", "thread/goal/get", "thread/goal/clear"].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{"threadId":"\#(threadID)"}}"#,
                codexHome: temp.url,
                experimentalAPIEnabled: true
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
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

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
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let emptyObjectiveError = try XCTUnwrap(emptyObjective["error"] as? [String: Any])
        XCTAssertEqual(emptyObjectiveError["code"] as? Int, -32600)
        XCTAssertEqual(emptyObjectiveError["message"] as? String, "goal objective must not be empty")

        let zeroBudget = try appServerResponse(
            #"{"id":2,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"keep polishing","tokenBudget":0}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let zeroBudgetError = try XCTUnwrap(zeroBudget["error"] as? [String: Any])
        XCTAssertEqual(zeroBudgetError["code"] as? Int, -32600)
        XCTAssertEqual(zeroBudgetError["message"] as? String, "goal budgets must be positive when provided")

        let missingGoal = try appServerResponse(
            #"{"id":3,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","status":"paused"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
                codexHome: temp.url,
                experimentalAPIEnabled: true
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

    func testThreadMemoryModeSetRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let threadID = UUID().uuidString.lowercased()

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/memoryMode/set","params":{"threadId":"\#(threadID)","mode":"disabled"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "thread/memoryMode/set requires experimentalApi capability")
    }

    func testThreadMemoryModeSetRejectsInvalidModeAndMissingThread() throws {
        let temp = try TemporaryDirectory()
        let missingID = UUID().uuidString.lowercased()

        let invalidMode = try appServerResponse(
            #"{"id":1,"method":"thread/memoryMode/set","params":{"threadId":"\#(missingID)","mode":"paused"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let invalidModeError = try XCTUnwrap(invalidMode["error"] as? [String: Any])
        XCTAssertEqual(invalidModeError["code"] as? Int, -32600)
        XCTAssertEqual(invalidModeError["message"] as? String, "invalid memory mode: paused")

        let missing = try appServerResponse(
            #"{"id":2,"method":"thread/memoryMode/set","params":{"threadId":"\#(missingID)","mode":"enabled"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryExtensionsRoot.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionsRoot.path), [])
    }

    func testMemoryResetRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "memory/reset requires experimentalApi capability")
    }

    func testMemoryResetCreatesMissingRootsAndRejectsSymlinkedRoot() throws {
        let temp = try TemporaryDirectory()
        let missingRoots = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
            codexHome: symlink.deletingLastPathComponent(),
            experimentalAPIEnabled: true
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

    func testPluginReadDescribesUninstalledGitSourceWithoutCloning() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("marketplace", isDirectory: true)
        let manifestDirectory = sourceRoot.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let missingRemote = temp.url.appendingPathComponent("missing-remote-plugin-repo", isDirectory: true)
        let missingRemoteURL = URL(fileURLWithPath: missingRemote.path, isDirectory: true).absoluteString
        try """
        {
          "name": "debug",
          "plugins": [
            {
              "name": "toolkit",
              "source": {
                "source": "git-subdir",
                "url": "\(missingRemoteURL)",
                "path": "plugins/toolkit",
                "ref": "main",
                "sha": "abc123"
              },
              "category": "Developer Tools"
            }
          ]
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let marketplacePath = manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false).path

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"toolkit"}}"#,
            codexHome: temp.url
        )
        let plugin = try XCTUnwrap((response["result"] as? [String: Any])?["plugin"] as? [String: Any])
        XCTAssertEqual(
            plugin["description"] as? String,
            "This is a cross-repo plugin. Install it to view more detailed information. The source of the plugin is \(missingRemoteURL), path `plugins/toolkit`, ref `main`, sha `abc123`."
        )
        XCTAssertEqual((plugin["skills"] as? [Any])?.count, 0)
        XCTAssertEqual((plugin["apps"] as? [Any])?.count, 0)
        XCTAssertEqual(plugin["mcpServers"] as? [String], [])
        let summary = try XCTUnwrap(plugin["summary"] as? [String: Any])
        XCTAssertEqual(summary["installed"] as? Bool, false)
        let source = try XCTUnwrap(summary["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "git")
        XCTAssertEqual(source["url"] as? String, missingRemoteURL)
        XCTAssertEqual(source["path"] as? String, "plugins/toolkit")
        let interface = try XCTUnwrap(summary["interface"] as? [String: Any])
        XCTAssertEqual(interface["category"] as? String, "Developer Tools")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temp.url.appendingPathComponent("plugins/.marketplace-plugin-source-staging", isDirectory: true).path
            )
        )
    }

    func testPluginReadUsesInstalledGitSourceCacheWithoutCloning() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("marketplace", isDirectory: true)
        let manifestDirectory = sourceRoot.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let missingRemote = temp.url.appendingPathComponent("missing-remote-plugin-repo", isDirectory: true)
        let missingRemoteURL = URL(fileURLWithPath: missingRemote.path, isDirectory: true).absoluteString
        try """
        {
          "name": "debug",
          "plugins": [
            {
              "name": "toolkit",
              "source": {
                "source": "git-subdir",
                "url": "\(missingRemoteURL)",
                "path": "plugins/toolkit"
              },
              "category": "Developer Tools"
            }
          ]
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        [features]
        plugin_hooks = true

        [plugins."toolkit@debug"]
        enabled = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let cachedRoot = temp.url.appendingPathComponent("plugins/cache/debug/toolkit/local", isDirectory: true)
        let manifestRoot = cachedRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        try """
        {
          "name": "toolkit",
          "description": "Cached toolkit plugin",
          "interface": {
            "displayName": "Toolkit"
          }
        }
        """.write(
            to: manifestRoot.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let skillRoot = cachedRoot.appendingPathComponent("skills/search", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)
        try """
        ---
        name: search
        description: search cached data
        ---
        """.write(to: skillRoot.appendingPathComponent("SKILL.md", isDirectory: false), atomically: true, encoding: .utf8)
        try """
        {"apps":{"calendar":{"id":"connector_calendar","name":"Calendar"}}}
        """.write(to: cachedRoot.appendingPathComponent(".app.json", isDirectory: false), atomically: true, encoding: .utf8)
        try """
        {"mcpServers":{"toolkit":{"command":"toolkit-mcp"}}}
        """.write(to: cachedRoot.appendingPathComponent(".mcp.json", isDirectory: false), atomically: true, encoding: .utf8)
        let hooksRoot = cachedRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  { "type": "command", "command": "echo startup" }
                ]
              }
            ]
          }
        }
        """.write(to: hooksRoot.appendingPathComponent("hooks.json", isDirectory: false), atomically: true, encoding: .utf8)

        let marketplacePath = manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false).path
        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"toolkit"}}"#,
            codexHome: temp.url
        )
        let plugin = try XCTUnwrap((response["result"] as? [String: Any])?["plugin"] as? [String: Any])
        XCTAssertEqual(plugin["description"] as? String, "Cached toolkit plugin")
        XCTAssertEqual((plugin["skills"] as? [[String: Any]])?.map { $0["name"] as? String }, ["toolkit:search"])
        XCTAssertEqual((plugin["apps"] as? [[String: Any]])?.map { $0["id"] as? String }, ["connector_calendar"])
        XCTAssertEqual(plugin["mcpServers"] as? [String], ["toolkit"])
        XCTAssertEqual(
            (plugin["hooks"] as? [[String: Any]])?.map { $0["key"] as? String },
            ["toolkit@debug:hooks/hooks.json:session_start:0:0"]
        )
        let summary = try XCTUnwrap(plugin["summary"] as? [String: Any])
        XCTAssertEqual(summary["installed"] as? Bool, true)
        XCTAssertEqual(summary["enabled"] as? Bool, true)
        let interface = try XCTUnwrap(summary["interface"] as? [String: Any])
        XCTAssertEqual(interface["displayName"] as? String, "Toolkit")
        XCTAssertEqual(interface["category"] as? String, "Developer Tools")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temp.url.appendingPathComponent("plugins/.marketplace-plugin-source-staging", isDirectory: true).path
            )
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

    func testPluginReadUsesInlineManifestHooks() throws {
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
          "hooks": [
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "echo inline one"
                      }
                    ]
                  }
                ]
              }
            },
            {
              "hooks": {
                "PostToolUse": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "echo inline two"
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
        """.write(
            to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let plugin = try XCTUnwrap((response["result"] as? [String: Any])?["plugin"] as? [String: Any])
        let hooks = try XCTUnwrap(plugin["hooks"] as? [[String: Any]])
        XCTAssertEqual(
            hooks.map { $0["key"] as? String },
            [
                "weather@debug:plugin.json#hooks[0]:pre_tool_use:0:0",
                "weather@debug:plugin.json#hooks[1]:post_tool_use:0:0"
            ]
        )
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
            #"{"id":1,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)"}}"#,
            codexHome: temp.url
        )
        let saveError = try XCTUnwrap(save["error"] as? [String: Any])
        XCTAssertEqual(saveError["code"] as? Int, -32600)
        XCTAssertEqual(saveError["message"] as? String, "plugin sharing is not enabled")

        let update = try appServerResponse(
            #"{"id":2,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins~Plugin_gmail","discoverability":"UNLISTED","shareTargets":[{"principalType":"user","principalId":"user-1"}]}}"#,
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
            #"{"id":4,"method":"plugin/share/delete","params":{"remotePluginId":"plugins~Plugin_gmail"}}"#,
            codexHome: temp.url
        )
        let deleteError = try XCTUnwrap(delete["error"] as? [String: Any])
        XCTAssertEqual(deleteError["code"] as? Int, -32600)
        XCTAssertEqual(deleteError["message"] as? String, "plugin sharing is not enabled")
    }

    func testPluginShareRoutesValidateRustRequestRulesBeforeDisabledRemoteFallback() throws {
        let temp = try TemporaryDirectory()
        let pluginPath = temp.url.appendingPathComponent("plugin").path

        let invalidSaveID = try appServerResponse(
            #"{"id":1,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","remotePluginId":"bad id"}}"#,
            codexHome: temp.url
        )
        let invalidSaveIDError = try XCTUnwrap(invalidSaveID["error"] as? [String: Any])
        XCTAssertEqual(invalidSaveIDError["code"] as? Int, -32600)
        XCTAssertEqual(invalidSaveIDError["message"] as? String, "invalid remote plugin id")

        let saveUpdateFields = try appServerResponse(
            #"{"id":2,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","remotePluginId":"plugins~Plugin_gmail","discoverability":"PRIVATE"}}"#,
            codexHome: temp.url
        )
        let saveUpdateFieldsError = try XCTUnwrap(saveUpdateFields["error"] as? [String: Any])
        XCTAssertEqual(saveUpdateFieldsError["code"] as? Int, -32600)
        XCTAssertEqual(
            saveUpdateFieldsError["message"] as? String,
            "discoverability and shareTargets are only supported when creating a plugin share; use plugin/share/updateTargets to update share settings"
        )

        let listedSave = try appServerResponse(
            #"{"id":3,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","discoverability":"LISTED"}}"#,
            codexHome: temp.url
        )
        let listedSaveError = try XCTUnwrap(listedSave["error"] as? [String: Any])
        XCTAssertEqual(listedSaveError["code"] as? Int, -32600)
        XCTAssertEqual(
            listedSaveError["message"] as? String,
            "discoverability LISTED is not supported for plugin/share/save; use UNLISTED or PRIVATE"
        )

        let saveWorkspaceTarget = try appServerResponse(
            #"{"id":5,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","discoverability":"UNLISTED","shareTargets":[{"principalType":"workspace","principalId":"workspace-1"}]}}"#,
            codexHome: temp.url
        )
        let saveWorkspaceTargetError = try XCTUnwrap(saveWorkspaceTarget["error"] as? [String: Any])
        XCTAssertEqual(saveWorkspaceTargetError["code"] as? Int, -32600)
        XCTAssertEqual(
            saveWorkspaceTargetError["message"] as? String,
            "shareTargets cannot include workspace principals; use discoverability UNLISTED for workspace link access"
        )

        let invalidUpdateID = try appServerResponse(
            #"{"id":7,"method":"plugin/share/updateTargets","params":{"remotePluginId":"bad id","discoverability":"UNLISTED","shareTargets":[]}}"#,
            codexHome: temp.url
        )
        let invalidUpdateIDError = try XCTUnwrap(invalidUpdateID["error"] as? [String: Any])
        XCTAssertEqual(invalidUpdateIDError["code"] as? Int, -32600)
        XCTAssertEqual(invalidUpdateIDError["message"] as? String, "invalid remote plugin id")

        let updateWorkspaceTarget = try appServerResponse(
            #"{"id":8,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins~Plugin_gmail","discoverability":"UNLISTED","shareTargets":[{"principalType":"workspace","principalId":"workspace-1"}]}}"#,
            codexHome: temp.url
        )
        let updateWorkspaceTargetError = try XCTUnwrap(updateWorkspaceTarget["error"] as? [String: Any])
        XCTAssertEqual(updateWorkspaceTargetError["code"] as? Int, -32600)
        XCTAssertEqual(
            updateWorkspaceTargetError["message"] as? String,
            "shareTargets cannot include workspace principals; use discoverability UNLISTED for workspace link access"
        )

        let invalidDeleteID = try appServerResponse(
            #"{"id":9,"method":"plugin/share/delete","params":{"remotePluginId":"bad id"}}"#,
            codexHome: temp.url
        )
        let invalidDeleteIDError = try XCTUnwrap(invalidDeleteID["error"] as? [String: Any])
        XCTAssertEqual(invalidDeleteIDError["code"] as? Int, -32600)
        XCTAssertEqual(invalidDeleteIDError["message"] as? String, "invalid remote plugin id")

        let unknownSaveDiscoverability = try appServerResponse(
            #"{"id":10,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath)","discoverability":"PUBLIC"}}"#,
            codexHome: temp.url
        )
        let unknownSaveDiscoverabilityError = try XCTUnwrap(unknownSaveDiscoverability["error"] as? [String: Any])
        XCTAssertEqual(unknownSaveDiscoverabilityError["code"] as? Int, -32602)
        XCTAssertEqual(
            unknownSaveDiscoverabilityError["message"] as? String,
            "unknown variant `PUBLIC`, expected one of `LISTED`, `UNLISTED`, `PRIVATE`"
        )

        let unknownUpdateDiscoverability = try appServerResponse(
            #"{"id":11,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins~Plugin_gmail","discoverability":"LISTED","shareTargets":[]}}"#,
            codexHome: temp.url
        )
        let unknownUpdateDiscoverabilityError = try XCTUnwrap(unknownUpdateDiscoverability["error"] as? [String: Any])
        XCTAssertEqual(unknownUpdateDiscoverabilityError["code"] as? Int, -32602)
        XCTAssertEqual(
            unknownUpdateDiscoverabilityError["message"] as? String,
            "unknown variant `LISTED`, expected `UNLISTED` or `PRIVATE`"
        )

        let missingUpdateTargets = try appServerResponse(
            #"{"id":12,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins~Plugin_gmail","discoverability":"UNLISTED"}}"#,
            codexHome: temp.url
        )
        let missingUpdateTargetsError = try XCTUnwrap(missingUpdateTargets["error"] as? [String: Any])
        XCTAssertEqual(missingUpdateTargetsError["code"] as? Int, -32602)
        XCTAssertEqual(missingUpdateTargetsError["message"] as? String, "missing field `shareTargets`")

        let missingSavePath = try appServerResponse(
            #"{"id":13,"method":"plugin/share/save","params":{}}"#,
            codexHome: temp.url
        )
        let missingSavePathError = try XCTUnwrap(missingSavePath["error"] as? [String: Any])
        XCTAssertEqual(missingSavePathError["code"] as? Int, -32602)
        XCTAssertEqual(missingSavePathError["message"] as? String, "missing field `pluginPath`")

        let missingUpdateID = try appServerResponse(
            #"{"id":14,"method":"plugin/share/updateTargets","params":{"discoverability":"UNLISTED","shareTargets":[]}}"#,
            codexHome: temp.url
        )
        let missingUpdateIDError = try XCTUnwrap(missingUpdateID["error"] as? [String: Any])
        XCTAssertEqual(missingUpdateIDError["code"] as? Int, -32602)
        XCTAssertEqual(missingUpdateIDError["message"] as? String, "missing field `remotePluginId`")

        let missingUpdateDiscoverability = try appServerResponse(
            #"{"id":15,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins~Plugin_gmail","shareTargets":[]}}"#,
            codexHome: temp.url
        )
        let missingUpdateDiscoverabilityError = try XCTUnwrap(missingUpdateDiscoverability["error"] as? [String: Any])
        XCTAssertEqual(missingUpdateDiscoverabilityError["code"] as? Int, -32602)
        XCTAssertEqual(missingUpdateDiscoverabilityError["message"] as? String, "missing field `discoverability`")

        let missingDeleteID = try appServerResponse(
            #"{"id":16,"method":"plugin/share/delete","params":{}}"#,
            codexHome: temp.url
        )
        let missingDeleteIDError = try XCTUnwrap(missingDeleteID["error"] as? [String: Any])
        XCTAssertEqual(missingDeleteIDError["code"] as? Int, -32602)
        XCTAssertEqual(missingDeleteIDError["message"] as? String, "missing field `remotePluginId`")
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

        let installedList = try appServerResponse(
            #"{"id":2,"method":"plugin/list","params":{"cwds":[\#(jsonString(sourceRoot.path))]}}"#,
            codexHome: temp.url
        )
        let installedMarketplaces = try XCTUnwrap((installedList["result"] as? [String: Any])?["marketplaces"] as? [[String: Any]])
        let installedPlugins = try XCTUnwrap(installedMarketplaces.first?["plugins"] as? [[String: Any]])
        XCTAssertEqual(installedPlugins.first?["installed"] as? Bool, true)
        XCTAssertEqual(installedPlugins.first?["enabled"] as? Bool, true)

        let installedRead = try appServerResponse(
            #"{"id":3,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let installedPlugin = try XCTUnwrap((installedRead["result"] as? [String: Any])?["plugin"] as? [String: Any])
        let installedSummary = try XCTUnwrap(installedPlugin["summary"] as? [String: Any])
        XCTAssertEqual(installedSummary["installed"] as? Bool, true)

        let uninstall = try appServerResponse(
            #"{"id":4,"method":"plugin/uninstall","params":{"pluginId":"weather@debug"}}"#,
            codexHome: temp.url
        )
        XCTAssertNotNil(uninstall["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedRoot.path))
        let configAfterUninstall = try String(
            contentsOf: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertFalse(configAfterUninstall.contains(#"[plugins."weather@debug"]"#))

        let uninstalledRead = try appServerResponse(
            #"{"id":5,"method":"plugin/read","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            codexHome: temp.url
        )
        let uninstalledPlugin = try XCTUnwrap((uninstalledRead["result"] as? [String: Any])?["plugin"] as? [String: Any])
        let uninstalledSummary = try XCTUnwrap(uninstalledPlugin["summary"] as? [String: Any])
        XCTAssertEqual(uninstalledSummary["installed"] as? Bool, false)
    }

    func testPluginInstallMaterializesGitSubdirPluginSource() throws {
        let temp = try TemporaryDirectory()
        let pluginRepo = temp.url.appendingPathComponent("plugin-repo", isDirectory: true)
        try writePluginFixture(
            root: pluginRepo,
            relativePath: "plugins/toolkit",
            pluginName: "toolkit",
            version: "1.2.3",
            marker: "from-git-install"
        )
        try runGit(["init"], cwd: pluginRepo)
        try runGit(["config", "user.name", "Test User"], cwd: pluginRepo)
        try runGit(["config", "user.email", "test@example.com"], cwd: pluginRepo)
        try runGit(["add", "."], cwd: pluginRepo)
        try runGit(["commit", "-m", "Initial plugin"], cwd: pluginRepo)

        let marketplaceRoot = temp.url.appendingPathComponent("marketplace", isDirectory: true)
        let manifestDirectory = marketplaceRoot.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let pluginRepoURL = URL(fileURLWithPath: pluginRepo.path, isDirectory: true).absoluteString
        try """
        {
          "name": "debug",
          "plugins": [
            {
              "name": "toolkit",
              "source": {
                "source": "git-subdir",
                "url": "\(pluginRepoURL)",
                "path": "plugins/toolkit"
              }
            }
          ]
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let marketplacePath = manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false).path

        let install = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"toolkit"}}"#,
            codexHome: temp.url
        )
        XCTAssertNil(install["error"])
        let installedRoot = temp.url.appendingPathComponent("plugins/cache/debug/toolkit/1.2.3", isDirectory: true)
        XCTAssertEqual(
            try String(contentsOf: installedRoot.appendingPathComponent("marker.txt", isDirectory: false), encoding: .utf8),
            "from-git-install"
        )
        let configAfterInstall = try String(
            contentsOf: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(configAfterInstall.contains(#"[plugins."toolkit@debug"]"#))
        XCTAssertTrue(configAfterInstall.contains("enabled = true"))
        let stagingRoot = temp.url.appendingPathComponent("plugins/.marketplace-plugin-source-staging", isDirectory: true)
        let leftoverCheckouts = (try? FileManager.default.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertEqual(leftoverCheckouts, [])
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

    func testMarketplaceUpgradeRefreshesConfiguredGitMarketplace() throws {
        let temp = try TemporaryDirectory()
        let marketplace = try makeGitMarketplaceSourceAndRemote(named: "debug", marker: "v1", in: temp.url)
        let gitConfig = temp.url.appendingPathComponent("gitconfig", isDirectory: false)
        try """
        [url "\(URL(fileURLWithPath: marketplace.remote.path).absoluteString)"]
            insteadOf = https://github.com/openai/debug-marketplace.git
        """.write(to: gitConfig, atomically: true, encoding: .utf8)
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "GIT_CONFIG_GLOBAL": gitConfig.path,
                "GIT_CONFIG_NOSYSTEM": "1",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )

        let add = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":"openai/debug-marketplace","refName":"\#(marketplace.branch)"}}"#,
            configuration: configuration
        )
        XCTAssertNil(add["error"])
        let installedRoot = temp.url
            .appendingPathComponent(".tmp/marketplaces/debug", isDirectory: true)
            .path
        let installedMarketplacePath = URL(fileURLWithPath: installedRoot)
            .appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false)
            .path

        let installPlugin = try appServerResponse(
            #"{"id":4,"method":"plugin/install","params":{"marketplacePath":"\#(installedMarketplacePath)","pluginName":"sample"}}"#,
            configuration: configuration
        )
        XCTAssertNil(installPlugin["error"])
        let cachedPluginMarker = temp.url
            .appendingPathComponent("plugins/cache/debug/sample/local/marker.txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: cachedPluginMarker, encoding: .utf8), "v1")

        try "v2".write(
            to: marketplace.source.appendingPathComponent("plugins/sample/marker.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "plugins/sample/marker.txt"], cwd: marketplace.source)
        try runGit(["commit", "-m", "Update marketplace"], cwd: marketplace.source)
        try runGit(["push", "origin", marketplace.branch], cwd: marketplace.source)
        let latestRevision = try runGit(["rev-parse", "HEAD"], cwd: marketplace.source)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let upgrade = try appServerResponse(
            #"{"id":2,"method":"marketplace/upgrade","params":{}}"#,
            configuration: configuration
        )
        let upgradeResult = try XCTUnwrap(upgrade["result"] as? [String: Any])
        XCTAssertEqual(upgradeResult["selectedMarketplaces"] as? [String], ["debug"])
        XCTAssertEqual(upgradeResult["upgradedRoots"] as? [String], [installedRoot])
        XCTAssertEqual((upgradeResult["errors"] as? [Any])?.count, 0)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: installedRoot).appendingPathComponent("plugins/sample/marker.txt"), encoding: .utf8),
            "v2"
        )
        XCTAssertEqual(try String(contentsOf: cachedPluginMarker, encoding: .utf8), "v2")
        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains(#"last_revision = "\#(latestRevision)""#))
        XCTAssertTrue(config.contains(#"ref = "\#(marketplace.branch)""#))
        let metadata = try String(
            contentsOf: URL(fileURLWithPath: installedRoot).appendingPathComponent(".codex-marketplace-install.json"),
            encoding: .utf8
        )
        XCTAssertTrue(metadata.contains(#""revision" : "\#(latestRevision)""#))

        let noOp = try appServerResponse(
            #"{"id":3,"method":"marketplace/upgrade","params":{"marketplaceName":"debug"}}"#,
            configuration: configuration
        )
        let noOpResult = try XCTUnwrap(noOp["result"] as? [String: Any])
        XCTAssertEqual(noOpResult["selectedMarketplaces"] as? [String], ["debug"])
        XCTAssertEqual(noOpResult["upgradedRoots"] as? [String], [])
        XCTAssertEqual((noOpResult["errors"] as? [Any])?.count, 0)
    }

    func testMarketplaceUpgradeRefreshesConfiguredGitSubdirPluginCache() throws {
        let temp = try TemporaryDirectory()
        let pluginRepo = temp.url.appendingPathComponent("plugin-repo", isDirectory: true)
        try writePluginFixture(
            root: pluginRepo,
            relativePath: "plugins/sample",
            pluginName: "sample",
            version: "1.2.3",
            marker: "from-git-subdir"
        )
        try runGit(["init"], cwd: pluginRepo)
        try runGit(["config", "user.name", "Test User"], cwd: pluginRepo)
        try runGit(["config", "user.email", "test@example.com"], cwd: pluginRepo)
        try runGit(["add", "."], cwd: pluginRepo)
        try runGit(["commit", "-m", "Initial plugin"], cwd: pluginRepo)

        let marketplaceSource = temp.url.appendingPathComponent("marketplace-git-subdir", isDirectory: true)
        let manifestDirectory = marketplaceSource.appendingPathComponent(".agents/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let pluginRepoURL = URL(fileURLWithPath: pluginRepo.path).absoluteString
        try """
        {
          "name": "debug",
          "plugins": [
            {
              "name": "sample",
              "source": {
                "source": "git-subdir",
                "url": "\(pluginRepoURL)",
                "path": "plugins/sample"
              }
            }
          ]
        }
        """.write(
            to: manifestDirectory.appendingPathComponent("marketplace.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["init"], cwd: marketplaceSource)
        try runGit(["config", "user.name", "Test User"], cwd: marketplaceSource)
        try runGit(["config", "user.email", "test@example.com"], cwd: marketplaceSource)
        try runGit(["add", "."], cwd: marketplaceSource)
        try runGit(["commit", "-m", "Initial marketplace"], cwd: marketplaceSource)
        let marketplaceRemote = temp.url.appendingPathComponent("marketplace-git-subdir.git", isDirectory: true)
        try runGit(["init", "--bare", marketplaceRemote.path], cwd: temp.url)
        try runGit(["remote", "add", "origin", marketplaceRemote.path], cwd: marketplaceSource)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: marketplaceSource)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["push", "-u", "origin", branch], cwd: marketplaceSource)

        let gitConfig = temp.url.appendingPathComponent("gitconfig", isDirectory: false)
        try """
        [url "\(URL(fileURLWithPath: marketplaceRemote.path).absoluteString)"]
            insteadOf = https://github.com/openai/debug-marketplace.git
        """.write(to: gitConfig, atomically: true, encoding: .utf8)
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "GIT_CONFIG_GLOBAL": gitConfig.path,
                "GIT_CONFIG_NOSYSTEM": "1",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )

        let add = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":"openai/debug-marketplace","refName":"\#(branch)"}}"#,
            configuration: configuration
        )
        XCTAssertNil(add["error"])

        let staleCache = temp.url.appendingPathComponent("plugins/cache/debug/sample/local", isDirectory: true)
        try FileManager.default.createDirectory(at: staleCache, withIntermediateDirectories: true)
        try "stale".write(
            to: staleCache.appendingPathComponent("marker.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let configPath = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let config = try String(contentsOf: configPath, encoding: .utf8)
        try (config + """

        [plugins."sample@debug"]
        enabled = true
        """).write(to: configPath, atomically: true, encoding: .utf8)

        try "touch".write(
            to: marketplaceSource.appendingPathComponent("upgrade-marker.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "upgrade-marker.txt"], cwd: marketplaceSource)
        try runGit(["commit", "-m", "Trigger marketplace upgrade"], cwd: marketplaceSource)
        try runGit(["push", "origin", branch], cwd: marketplaceSource)

        let upgrade = try appServerResponse(
            #"{"id":2,"method":"marketplace/upgrade","params":{}}"#,
            configuration: configuration
        )
        let upgradeResult = try XCTUnwrap(upgrade["result"] as? [String: Any])
        XCTAssertEqual(upgradeResult["selectedMarketplaces"] as? [String], ["debug"])
        XCTAssertEqual((upgradeResult["errors"] as? [Any])?.count, 0)
        let refreshedMarker = temp.url
            .appendingPathComponent("plugins/cache/debug/sample/1.2.3/marker.txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: refreshedMarker, encoding: .utf8), "from-git-subdir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleCache.path))
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

    func testMarketplaceAddClonesGitSourceAndRecordsDuplicate() throws {
        let temp = try TemporaryDirectory()
        let remote = try makeGitMarketplaceRemote(named: "debug", marker: "git ref", in: temp.url)
        let gitConfig = temp.url.appendingPathComponent("gitconfig", isDirectory: false)
        try """
        [url "\(URL(fileURLWithPath: remote.path).absoluteString)"]
            insteadOf = https://github.com/openai/debug-marketplace.git
        """.write(to: gitConfig, atomically: true, encoding: .utf8)
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "GIT_CONFIG_GLOBAL": gitConfig.path,
                "GIT_CONFIG_NOSYSTEM": "1",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )

        let first = try appServerResponse(
            #"{"id":1,"method":"marketplace/add","params":{"source":"openai/debug-marketplace"}}"#,
            configuration: configuration
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let installedRoot = temp.url
            .appendingPathComponent(".tmp/marketplaces/debug", isDirectory: true)
            .path
        XCTAssertEqual(firstResult["marketplaceName"] as? String, "debug")
        XCTAssertEqual(firstResult["installedRoot"] as? String, installedRoot)
        XCTAssertEqual(firstResult["alreadyAdded"] as? Bool, false)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: installedRoot).appendingPathComponent("plugins/sample/marker.txt"), encoding: .utf8),
            "git ref"
        )

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[marketplaces.debug]"))
        XCTAssertTrue(config.contains(#"source_type = "git""#))
        XCTAssertTrue(config.contains(#"source = "https://github.com/openai/debug-marketplace.git""#))

        let duplicate = try appServerResponse(
            #"{"id":2,"method":"marketplace/add","params":{"source":"openai/debug-marketplace"}}"#,
            configuration: configuration
        )
        let duplicateResult = try XCTUnwrap(duplicate["result"] as? [String: Any])
        XCTAssertEqual(duplicateResult["marketplaceName"] as? String, "debug")
        XCTAssertEqual(duplicateResult["installedRoot"] as? String, installedRoot)
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

        let unsupportedImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"UNKNOWN","description":"Unknown","cwd":null}]}}"#,
            codexHome: temp.url
        )
        let unsupportedImportError = try XCTUnwrap(unsupportedImport["error"] as? [String: Any])
        XCTAssertEqual(unsupportedImportError["code"] as? Int, -32600)
        XCTAssertEqual(unsupportedImportError["message"] as? String, "external agent config import for UNKNOWN is not implemented")
    }

    func testExternalAgentConfigDetectAndImportSessionsCreatesRolloutAndLedger() throws {
        let temp = try TemporaryDirectory()
        let codexHome = temp.url.appendingPathComponent("codex-home", isDirectory: true)
        let projectRoot = temp.url.appendingPathComponent("repo", isDirectory: true)
        let home = temp.url.appendingPathComponent("home", isDirectory: true)
        let sessionDir = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects/repo", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let sessionPath = sessionDir.appendingPathComponent("session.jsonl", isDirectory: false)
        let recentTimestamp = ISO8601DateFormatter().string(from: Date())
        let records = [
            #"{"type":"user","cwd":"\#(projectRoot.path)","timestamp":"\#(recentTimestamp)","message":{"content":"first request"}}"#,
            #"{"type":"assistant","cwd":"\#(projectRoot.path)","timestamp":"\#(recentTimestamp)","message":{"content":[{"type":"text","text":"first answer"}]}}"#,
            #"{"type":"user","cwd":"\#(projectRoot.path)","timestamp":"\#(recentTimestamp)","message":{"content":"second request"}}"#,
            #"{"type":"custom-title","customTitle":"Imported title"}"#
        ].joined(separator: "\n")
        try records.write(to: sessionPath, atomically: true, encoding: .utf8)
        let config = CodexAppServerConfiguration(
            codexHome: codexHome,
            environment: ["HOME": home.path]
        )
        let processor = try initializedProcessor(configuration: config)

        let detect = try decode(processor.processLine(Data(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"includeHome":true}}"#.utf8
        )))
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        let sessionsItem = try XCTUnwrap(items.first { $0["itemType"] as? String == "SESSIONS" })
        let details = try XCTUnwrap(sessionsItem["details"] as? [String: Any])
        let sessions = try XCTUnwrap(details["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        let detectedSessionPath = try XCTUnwrap(sessions[0]["path"] as? String)
        XCTAssertEqual(
            URL(fileURLWithPath: detectedSessionPath).resolvingSymlinksInPath().standardizedFileURL.path,
            sessionPath.resolvingSymlinksInPath().standardizedFileURL.path
        )
        XCTAssertEqual(sessions[0]["cwd"] as? String, projectRoot.path)
        XCTAssertEqual(sessions[0]["title"] as? String, "Imported title")

        let importMessage = #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"SESSIONS","description":"Sessions","cwd":null,"details":{"sessions":[{"path":"\#(detectedSessionPath)","cwd":"\#(projectRoot.path)","title":"Imported title"}]}}]}}"#
        let messages = try decodeMessages(processor.processLine(Data(importMessage.utf8)))
        if let error = messages.first?["error"] as? [String: Any] {
            XCTFail("unexpected import error: \(error)")
            return
        }
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let list = try decode(processor.processLine(Data(
            #"{"id":3,"method":"thread/list","params":{}}"#.utf8
        )))
        let threads = try XCTUnwrap((list["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0]["name"] as? String, "Imported title")
        let rolloutPath = try XCTUnwrap(threads[0]["path"] as? String)
        let rollout = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        XCTAssertTrue(rollout.contains("first request"))
        XCTAssertTrue(rollout.contains("first answer"))
        XCTAssertTrue(rollout.contains("second request"))
        XCTAssertTrue(rollout.contains("<EXTERNAL SESSION IMPORTED>"))
        XCTAssertTrue(rollout.contains(#""type":"task_started""#))
        XCTAssertTrue(rollout.contains(#""type":"task_complete""#))
        XCTAssertTrue(rollout.contains(#""turn_id":"external-import-turn-1""#))
        XCTAssertTrue(rollout.contains(#""turn_id":"external-import-turn-2""#))
        XCTAssertTrue(rollout.contains(#""last_agent_message":"first answer""#))
        XCTAssertTrue(rollout.contains(#""type":"token_count""#))
        XCTAssertTrue(rollout.contains(#""total_tokens":"#))
        let ledgerData = try Data(
            contentsOf: codexHome.appendingPathComponent("external_agent_session_imports.json", isDirectory: false)
        )
        let ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: ledgerData) as? [String: Any])
        let ledgerRecords = try XCTUnwrap(ledger["records"] as? [[String: Any]])
        XCTAssertEqual(ledgerRecords.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(ledgerRecords[0]["source_path"] as? String))
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path,
            URL(fileURLWithPath: detectedSessionPath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        )

        let detectAfterImport = try decode(processor.processLine(Data(
            #"{"id":4,"method":"externalAgentConfig/detect","params":{"includeHome":true}}"#.utf8
        )))
        let afterItems = try XCTUnwrap((detectAfterImport["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertNil(afterItems.first { $0["itemType"] as? String == "SESSIONS" })
    }

    func testExternalAgentConfigDetectConfigReportsRepoMigrationOnlyForMissingValues() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        let nested = repo.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let claudeSettings = repo.url.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeSettings, withIntermediateDirectories: true)
        try """
        {
          "env": { "ALPHA": "one" },
          "sandbox": { "enabled": true }
        }
        """.write(
            to: claudeSettings.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(nested.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item["itemType"] as? String, "CONFIG")
        XCTAssertEqual(item["cwd"] as? String, repo.url.path)
        XCTAssertEqual(item["details"] as? NSNull, NSNull())
        XCTAssertEqual(
            item["description"] as? String,
            "Migrate \(repo.url.path)/.claude/settings.json into \(repo.url.path)/.codex/config.toml"
        )

        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        sandbox_mode = "workspace-write"

        [shell_environment_policy]
        inherit = "core"

        [shell_environment_policy.set]
        ALPHA = "one"
        """.write(
            to: repo.url.appendingPathComponent(".codex/config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let alreadyMigrated = try appServerResponse(
            #"{"id":2,"method":"externalAgentConfig/detect","params":{"cwds":["\#(nested.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((alreadyMigrated["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigImportConfigMigratesRepoSettingsAndCompletes() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let claudeSettings = repo.url.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeSettings, withIntermediateDirectories: true)
        try """
        {
          "env": {
            "ALPHA": "one",
            "COUNT": 7,
            "DROP": null,
            "FLAG": true,
            "OBJECT": {}
          },
          "sandbox": { "enabled": false }
        }
        """.write(
            to: claudeSettings.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "env": { "ALPHA": "local", "BETA": "two" },
          "sandbox": { "enabled": true }
        }
        """.write(
            to: claudeSettings.appendingPathComponent("settings.local.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"CONFIG","description":"Config","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)

        let response = messages[0]
        XCTAssertEqual((response["result"] as? [String: Any])?.isEmpty, true)

        let notification = messages[1]
        XCTAssertEqual(notification["method"] as? String, "externalAgentConfig/import/completed")
        XCTAssertEqual((notification["params"] as? [String: Any])?.isEmpty, true)

        let migrated = try String(
            contentsOf: repo.url.appendingPathComponent(".codex/config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(migrated.contains(#"sandbox_mode = "workspace-write""#))
        XCTAssertTrue(migrated.contains(#"inherit = "core""#))
        XCTAssertTrue(migrated.contains(#"ALPHA = "local""#))
        XCTAssertTrue(migrated.contains(#"BETA = "two""#))
        XCTAssertTrue(migrated.contains(#"COUNT = "7""#))
        XCTAssertTrue(migrated.contains(#"FLAG = "true""#))
        XCTAssertFalse(migrated.contains("DROP"))
        XCTAssertFalse(migrated.contains("OBJECT"))
    }

    func testExternalAgentConfigDetectAndImportMcpServersMigratesConvertibleEntries() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let claude = repo.url.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try """
        {
          "enabledMcpjsonServers": ["api", "docs", "bad-env", "disabled"],
          "disabledMcpjsonServers": ["disabled"]
        }
        """.write(
            to: claude.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "mcpServers": {
            "docs": {
              "command": "npx",
              "args": ["-y", "docs"],
              "env": {
                "TOKEN": "${TOKEN}",
                "STATIC": "yes"
              }
            },
            "api": {
              "type": "http",
              "url": "https://example.com/mcp",
              "headers": {
                "Authorization": "Bearer ${API_TOKEN}",
                "X-Env": "${HEADER_ENV}",
                "X-Static": "abc"
              }
            },
            "bad-env": {
              "command": "node",
              "env": { "TOKEN": "prefix-${TOKEN}" }
            },
            "disabled": {
              "command": "node"
            }
          }
        }
        """.write(
            to: repo.url.appendingPathComponent(".mcp.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["MCP_SERVER_CONFIG"])
        XCTAssertEqual(items[0]["cwd"] as? String, repo.url.path)
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate MCP servers from \(repo.url.path) into \(repo.url.path)/.codex/config.toml"
        )
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        XCTAssertEqual(details["mcp_servers"] as? [[String: String]], [["name": "api"], ["name": "docs"]])

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"MCP_SERVER_CONFIG","description":"MCP","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let migrated = try String(
            contentsOf: repo.url.appendingPathComponent(".codex/config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(migrated.contains("[mcp_servers.api]"))
        XCTAssertTrue(migrated.contains(#"url = "https://example.com/mcp""#))
        XCTAssertTrue(migrated.contains(#"bearer_token_env_var = "API_TOKEN""#))
        XCTAssertTrue(migrated.contains("[mcp_servers.api.env_http_headers]"))
        XCTAssertTrue(migrated.contains(#"X-Env = "HEADER_ENV""#))
        XCTAssertTrue(migrated.contains("[mcp_servers.api.http_headers]"))
        XCTAssertTrue(migrated.contains(#"X-Static = "abc""#))
        XCTAssertTrue(migrated.contains("[mcp_servers.docs]"))
        XCTAssertTrue(migrated.contains(#"command = "npx""#))
        XCTAssertTrue(migrated.contains(#"args = ["-y", "docs"]"#))
        XCTAssertTrue(migrated.contains(#"env_vars = ["TOKEN"]"#))
        XCTAssertTrue(migrated.contains("[mcp_servers.docs.env]"))
        XCTAssertTrue(migrated.contains(#"STATIC = "yes""#))
        XCTAssertFalse(migrated.contains("bad-env"))
        XCTAssertFalse(migrated.contains("disabled"))

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportPluginsInstallsLocalMarketplacePlugins() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let marketplaceRoot = try makeLocalMarketplaceRootWithPlugin(
            named: "debug",
            pluginName: "weather",
            in: repo.url
        )
        let claude = repo.url.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try """
        {
          "enabledPlugins": {
            "weather@debug": true,
            "disabled@debug": false
          },
          "extraKnownMarketplaces": {
            "debug": {
              "source": "directory",
              "path": "./marketplace-debug"
            }
          }
        }
        """.write(
            to: claude.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["PLUGINS"])
        XCTAssertEqual(items[0]["cwd"] as? String, repo.url.path)
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate enabled plugins from \(repo.url.path)/.claude/settings.json"
        )
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        let plugins = try XCTUnwrap(details["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["marketplaceName"] as? String, "debug")
        XCTAssertEqual(plugins[0]["pluginNames"] as? [String], ["weather"])

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"PLUGINS","description":"Plugins","cwd":"\#(repo.url.path)","details":{"plugins":[{"marketplaceName":"debug","pluginNames":["weather"]}]}}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let config = try String(
            contentsOf: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(config.contains("[marketplaces.debug]"))
        XCTAssertTrue(config.contains(#"source = "\#(marketplaceRoot.path)""#))
        XCTAssertTrue(config.contains(#"[plugins."weather@debug"]"#))
        XCTAssertTrue(config.contains("enabled = true"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: codexHome.url
                .appendingPathComponent("plugins/cache/debug/weather/local/.codex-plugin/plugin.json", isDirectory: false)
                .path
        ))

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportHooksWritesHooksJsonAndCopiesScripts() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let claude = repo.url.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claude.appendingPathComponent("hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "echo copied".write(
            to: claude.appendingPathComponent("hooks/check.sh", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'./.claude/hooks/check.sh'",
                    "timeoutSec": "7",
                    "statusMessage": "Claude hook"
                  },
                  {
                    "type": "command",
                    "command": "echo skipped",
                    "async": true
                  }
                ]
              }
            ],
            "Stop": [
              {
                "matcher": "ignored",
                "hooks": [
                  {
                    "command": "echo done"
                  }
                ]
              }
            ]
          }
        }
        """.write(
            to: claude.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["HOOKS"])
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate hooks from \(claude.path) to \(repo.url.path)/.codex/hooks.json"
        )
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        XCTAssertEqual(details["hooks"] as? [[String: String]], [["name": "PreToolUse"], ["name": "Stop"]])

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"HOOKS","description":"Hooks","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let hooksPath = repo.url.appendingPathComponent(".codex/hooks.json", isDirectory: false)
        let hooksPayload = try decode(Data(contentsOf: hooksPath))
        let hooks = try XCTUnwrap(hooksPayload["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.count, 1)
        XCTAssertEqual(preToolUse[0]["matcher"] as? String, "Bash")
        let preHandlers = try XCTUnwrap(preToolUse[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(preHandlers.count, 1)
        XCTAssertEqual(preHandlers[0]["type"] as? String, "command")
        XCTAssertEqual(preHandlers[0]["timeout"] as? Int, 7)
        XCTAssertEqual(preHandlers[0]["statusMessage"] as? String, "Codex hook")
        XCTAssertEqual(
            preHandlers[0]["command"] as? String,
            "'\(repo.url.path)/.codex/hooks/check.sh'"
        )
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertNil(stop[0]["matcher"])
        XCTAssertEqual(
            try String(contentsOf: repo.url.appendingPathComponent(".codex/hooks/check.sh"), encoding: .utf8),
            "echo copied"
        )

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportSkillsCopiesMissingDirectories() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let claudeSkills = repo.url.appendingPathComponent(".claude/skills", isDirectory: true)
        let sourceSkill = claudeSkills.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceSkill.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: claudeSkills.appendingPathComponent("existing", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        Use Claude Code with CLAUDE.md.
        Do not replace claudecodehelper.
        """.write(
            to: sourceSkill.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "echo claude".write(
            to: sourceSkill.appendingPathComponent("scripts/run.sh", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let targetExisting = repo.url.appendingPathComponent(".agents/skills/existing", isDirectory: true)
        try FileManager.default.createDirectory(at: targetExisting, withIntermediateDirectories: true)

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["SKILLS"])
        XCTAssertEqual(items[0]["cwd"] as? String, repo.url.path)
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate skills from \(repo.url.path)/.claude/skills to \(repo.url.path)/.agents/skills"
        )

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"SKILLS","description":"Skills","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let copiedSkill = repo.url.appendingPathComponent(".agents/skills/demo/SKILL.md", isDirectory: false)
        let copiedSkillContents = try String(contentsOf: copiedSkill, encoding: .utf8)
        XCTAssertTrue(copiedSkillContents.contains("Use Codex with AGENTS.md."))
        XCTAssertTrue(copiedSkillContents.contains("Do not replace claudecodehelper."))
        XCTAssertEqual(
            try String(contentsOf: repo.url.appendingPathComponent(".agents/skills/demo/scripts/run.sh"), encoding: .utf8),
            "echo claude"
        )

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportCommandsRendersSupportedSkills() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let commands = repo.url.appendingPathComponent(".claude/commands", isDirectory: true)
        try FileManager.default.createDirectory(
            at: commands.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        ---
        description: Run Claude Code checks
        ---

        Ask Claude to inspect CLAUDE.md.
        """.write(
            to: commands.appendingPathComponent("nested/check.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        description: Needs args
        ---

        Use $ARGUMENTS here.
        """.write(
            to: commands.appendingPathComponent("unsupported.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        description: First duplicate
        ---

        One.
        """.write(
            to: commands.appendingPathComponent("dupe!.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        description: Second duplicate
        ---

        Two.
        """.write(
            to: commands.appendingPathComponent("dupe?.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "ignore me".write(
            to: commands.appendingPathComponent("README.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["COMMANDS"])
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate commands from \(commands.path) to \(repo.url.path)/.agents/skills"
        )
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        XCTAssertEqual(details["commands"] as? [[String: String]], [["name": "source-command-nested-check"]])

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"COMMANDS","description":"Commands","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")
        let skill = try String(
            contentsOf: repo.url.appendingPathComponent(".agents/skills/source-command-nested-check/SKILL.md"),
            encoding: .utf8
        )
        XCTAssertEqual(skill, """
        ---
        name: "source-command-nested-check"
        description: "Run Codex checks"
        ---

        # source-command-nested-check

        Use this skill when the user asks to run the migrated source command `nested-check`.

        ## Command Template

        Ask Codex to inspect AGENTS.md.

        """)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.url.appendingPathComponent(".agents/skills/source-command-unsupported").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.url.appendingPathComponent(".agents/skills/source-command-dupe").path
        ))

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportSubagentsRendersTomlAgents() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let agents = repo.url.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try """
        ---
        name: reviewer
        description: Claude Code reviewer
        permissionMode: acceptEdits
        effort: max
        ---

        Use Claude and CLAUDE.md for review.
        """.write(
            to: agents.appendingPathComponent("reviewer.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        name: empty
        description: Empty body
        ---

        """.write(
            to: agents.appendingPathComponent("empty.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: agents.appendingPathComponent("README.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["SUBAGENTS"])
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate subagents from \(agents.path) to \(repo.url.path)/.codex/agents"
        )
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        XCTAssertEqual(details["subagents"] as? [[String: String]], [["name": "reviewer"]])

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"SUBAGENTS","description":"Subagents","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")
        let rendered = try String(
            contentsOf: repo.url.appendingPathComponent(".codex/agents/reviewer.toml", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(rendered.contains(#"name = "reviewer""#))
        XCTAssertTrue(rendered.contains(#"description = "Codex reviewer""#))
        XCTAssertTrue(rendered.contains(#"model_reasoning_effort = "xhigh""#))
        XCTAssertTrue(rendered.contains(#"sandbox_mode = "workspace-write""#))
        XCTAssertTrue(rendered.contains(#"developer_instructions = "Use Codex and AGENTS.md for review.""#))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.url.appendingPathComponent(".codex/agents/empty.toml").path
        ))

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
    }

    func testExternalAgentConfigDetectAndImportAgentsMdUsesRepoSourcePriority() throws {
        let codexHome = try TemporaryDirectory()
        let repo = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "nested Claude Code".write(
            to: repo.url.appendingPathComponent(".claude/CLAUDE.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "root CLAUDE.md for Claude".write(
            to: repo.url.appendingPathComponent("CLAUDE.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["AGENTS_MD"])
        XCTAssertEqual(items[0]["cwd"] as? String, repo.url.path)
        XCTAssertEqual(
            items[0]["description"] as? String,
            "Migrate \(repo.url.path)/CLAUDE.md to \(repo.url.path)/AGENTS.md"
        )

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: codexHome.url))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"AGENTS_MD","description":"AGENTS","cwd":"\#(repo.url.path)"}]}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")
        XCTAssertEqual(
            try String(contentsOf: repo.url.appendingPathComponent("AGENTS.md", isDirectory: false), encoding: .utf8),
            "root AGENTS.md for Codex"
        )

        let afterImport = try appServerResponse(
            #"{"id":3,"method":"externalAgentConfig/detect","params":{"cwds":["\#(repo.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual(((afterImport["result"] as? [String: Any])?["items"] as? [Any])?.count, 0)
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

    func testMcpResourceReadWithoutThreadCallsConfiguredStreamableHTTPServer() throws {
        let temp = try TemporaryDirectory()
        try """
        [mcp_servers.docs]
        url = "https://mcp.example.test/mcp"
        bearer_token_env_var = "MCP_TOKEN"

        [mcp_servers.docs.http_headers]
        XStatic = "static-value"

        [mcp_servers.docs.env_http_headers]
        XEnv = "MCP_ENV"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let capture = MCPHTTPTransportCapture()
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "MCP_TOKEN": "token-value",
                "MCP_ENV": "env-value",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ],
            mcpHTTPTransport: { request in
                capture.append(request)
                let body = try XCTUnwrap(request.httpBody)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                switch object["method"] as? String {
                case "initialize":
                    return URLSessionTransportResponse(
                        statusCode: 200,
                        headers: ["mcp-session-id": "session-123"],
                        body: Data(#"{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"docs","version":"1.0.0"}}}"#.utf8)
                    )
                case "resources/read":
                    return URLSessionTransportResponse(
                        statusCode: 200,
                        body: Data(#"{"jsonrpc":"2.0","id":1,"result":{"contents":[{"uri":"test://codex/resource","mimeType":"text/markdown","text":"Resource body from the MCP server."},{"uri":"test://codex/resource.bin","mimeType":"application/octet-stream","blob":"YmluYXJ5LXJlc291cmNl"}]}}"#.utf8)
                    )
                default:
                    return URLSessionTransportResponse(
                        statusCode: 500,
                        body: Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"unexpected method"}}"#.utf8)
                    )
                }
            }
        )
        let processor = try initializedProcessor(configuration: configuration)
        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"mcpServer/resource/read","params":{"server":"docs","uri":"test://codex/resource"}}"#.utf8
        )))

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let contents = try XCTUnwrap(result["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 2)
        XCTAssertEqual(contents[0]["uri"] as? String, "test://codex/resource")
        XCTAssertEqual(contents[0]["mimeType"] as? String, "text/markdown")
        XCTAssertEqual(contents[0]["text"] as? String, "Resource body from the MCP server.")
        XCTAssertEqual(contents[1]["uri"] as? String, "test://codex/resource.bin")
        XCTAssertEqual(contents[1]["blob"] as? String, "YmluYXJ5LXJlc291cmNl")

        let requests = capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://mcp.example.test/mcp")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token-value")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "XStatic"), "static-value")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "XEnv"), "env-value")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Mcp-Session-Id"), "session-123")
        let readBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(readBody["method"] as? String, "resources/read")
        XCTAssertEqual((readBody["params"] as? [String: Any])?["uri"] as? String, "test://codex/resource")
    }

    func testMcpResourceReadWithoutThreadCallsConfiguredStdioServer() throws {
        let temp = try TemporaryDirectory()
        let script = temp.url.appendingPathComponent("stdio-mcp.sh", isDirectory: false)
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          case "$count" in
            1)
              printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stdio","version":"1.0.0"}}}'
              ;;
            2)
              printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"contents\\":[{\\"uri\\":\\"test://codex/stdio\\",\\"mimeType\\":\\"text/plain\\",\\"text\\":\\"$MCP_ENV:$INLINE\\"}]}}"
              exit 0
              ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try """
        [mcp_servers.stdio]
        command = "\(script.path)"
        env_vars = ["MCP_ENV"]
        tool_timeout_sec = 10

        [mcp_servers.stdio.env]
        INLINE = "inline-value"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "MCP_ENV": "passed-value",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )
        let processor = try initializedProcessor(configuration: configuration)
        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"mcpServer/resource/read","params":{"server":"stdio","uri":"test://codex/stdio"}}"#.utf8
        )))

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let contents = try XCTUnwrap(result["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents[0]["uri"] as? String, "test://codex/stdio")
        XCTAssertEqual(contents[0]["mimeType"] as? String, "text/plain")
        XCTAssertEqual(contents[0]["text"] as? String, "passed-value:inline-value")
    }

    func testMcpServerToolCallCallsConfiguredStreamableHTTPServer() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "call mcp",
            provider: nil
        )
        try """
        [mcp_servers.tools]
        url = "https://mcp.example.test/mcp"
        bearer_token_env_var = "MCP_TOKEN"

        [mcp_servers.tools.http_headers]
        XStatic = "static-value"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let capture = MCPHTTPTransportCapture()
        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "MCP_TOKEN": "token-value",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ],
            mcpHTTPTransport: { request in
                capture.append(request)
                let body = try XCTUnwrap(request.httpBody)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                switch object["method"] as? String {
                case "initialize":
                    return URLSessionTransportResponse(
                        statusCode: 200,
                        headers: ["mcp-session-id": "session-456"],
                        body: Data(#"{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"tools","version":"1.0.0"}}}"#.utf8)
                    )
                case "tools/call":
                    return URLSessionTransportResponse(
                        statusCode: 200,
                        body: Data(#"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"echo: hello from app"}],"structuredContent":{"echoed":"hello from app"},"isError":false,"_meta":{"calledBy":"mcp-app"}}}"#.utf8)
                    )
                default:
                    return URLSessionTransportResponse(
                        statusCode: 500,
                        body: Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"unexpected method"}}"#.utf8)
                    )
                }
            }
        )
        let processor = try initializedProcessor(configuration: configuration)
        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"mcpServer/tool/call","params":{"threadId":"\#(threadID)","server":"tools","tool":"echo_tool","arguments":{"message":"hello from app"},"_meta":{"source":"mcp-app"}}}"#.utf8
        )))

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "echo: hello from app")
        XCTAssertEqual((result["structuredContent"] as? [String: Any])?["echoed"] as? String, "hello from app")
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual((result["_meta"] as? [String: Any])?["calledBy"] as? String, "mcp-app")

        let requests = capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token-value")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "XStatic"), "static-value")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Mcp-Session-Id"), "session-456")
        let callBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(callBody["method"] as? String, "tools/call")
        let params = try XCTUnwrap(callBody["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "echo_tool")
        XCTAssertEqual((params["arguments"] as? [String: Any])?["message"] as? String, "hello from app")
        XCTAssertEqual((params["_meta"] as? [String: Any])?["source"] as? String, "mcp-app")
        XCTAssertEqual((params["_meta"] as? [String: Any])?["threadId"] as? String, threadID)
    }

    func testMcpServerToolCallCallsConfiguredStdioServer() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-06",
            timestamp: "2025-01-02T03:04:06Z",
            preview: "call stdio mcp",
            provider: nil
        )
        let script = temp.url.appendingPathComponent("stdio-tool-mcp.sh", isDirectory: false)
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          case "$count" in
            1)
              printf '%s\\n' '{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stdio","version":"1.0.0"}}}'
              ;;
            2)
              printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"content\\":[{\\"type\\":\\"text\\",\\"text\\":\\"$MCP_ENV:$INLINE\\"}],\\"structuredContent\\":{\\"transport\\":\\"stdio\\"},\\"isError\\":false,\\"_meta\\":{\\"calledBy\\":\\"stdio\\"}}}"
              exit 0
              ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try """
        [mcp_servers.stdio_tool]
        command = "\(script.path)"
        env_vars = ["MCP_ENV"]
        tool_timeout_sec = 10

        [mcp_servers.stdio_tool.env]
        INLINE = "inline-value"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            requiresOpenAIAuth: false,
            environment: [
                "MCP_ENV": "passed-value",
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )
        let processor = try initializedProcessor(configuration: configuration)
        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"mcpServer/tool/call","params":{"threadId":"\#(threadID)","server":"stdio_tool","tool":"echo_tool","arguments":{"message":"hello"}}}"#.utf8
        )))

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "passed-value:inline-value")
        XCTAssertEqual((result["structuredContent"] as? [String: Any])?["transport"] as? String, "stdio")
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual((result["_meta"] as? [String: Any])?["calledBy"] as? String, "stdio")
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let newerResult = try XCTUnwrap(newerPage["result"] as? [String: Any])
        let newerData = try XCTUnwrap(newerResult["data"] as? [[String: Any]])
        XCTAssertEqual(newerData.map(turnUserText), ["third", "fourth"])
    }

    func testThreadTurnsRoutesRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-10-00",
            timestamp: "2025-01-05T12:10:00Z",
            preview: "turns gate",
            provider: "mock_provider"
        )
        let cases = [
            (
                "thread/turns/list",
                #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)"}}"#
            ),
            (
                "thread/turns/items/list",
                #"{"id":2,"method":"thread/turns/items/list","params":{"threadId":"\#(threadID)","turnId":"turn-1"}}"#
            )
        ]

        for (method, request) in cases {
            let response = try appServerResponse(request, codexHome: temp.url)
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(method) requires experimentalApi capability")
        }
    }

    func testThreadRollbackPersistsMarkerAndReturnsPrunedThread() throws {
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
            .agentMessage(AgentMessageEvent(message: "first done")),
            .userMessage(UserMessageEvent(message: "second")),
            .agentMessage(AgentMessageEvent(message: "second done")),
            .userMessage(UserMessageEvent(message: "third"))
        ])

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/rollback","params":{"threadId":"\#(threadID)","numTurns":2}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.map(turnUserText), ["first"])
        XCTAssertEqual(turnAgentTexts(turns[0]), ["first done"])

        let rolloutText = try String(contentsOf: URL(fileURLWithPath: rolloutPath), encoding: .utf8)
        XCTAssertTrue(rolloutText.contains(#""type":"thread_rolled_back""#))
        XCTAssertTrue(rolloutText.contains(#""num_turns":2"#))

        let read = try appServerResponse(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)","includeTurns":true}}"#,
            codexHome: temp.url
        )
        let readThread = try XCTUnwrap((read["result"] as? [String: Any])?["thread"] as? [String: Any])
        let readTurns = try XCTUnwrap(readThread["turns"] as? [[String: Any]])
        XCTAssertEqual(readTurns.map(turnUserText), ["first"])
    }

    func testThreadTurnsListAppliesPersistedRollbackMarkers() throws {
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
            .userMessage(UserMessageEvent(message: "second")),
            .userMessage(UserMessageEvent(message: "third")),
            .threadRolledBack(ThreadRolledBackEvent(numTurns: 1))
        ])

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","limit":10}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map(turnUserText), ["second", "first"])
    }

    func testThreadRollbackRejectsNonU32NumTurnsLikeRustParams() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "first",
            provider: "mock_provider"
        )

        let zero = try appServerResponse(
            #"{"id":1,"method":"thread/rollback","params":{"threadId":"\#(threadID)","numTurns":0}}"#,
            codexHome: temp.url
        )
        let zeroError = try XCTUnwrap(zero["error"] as? [String: Any])
        XCTAssertEqual(zeroError["code"] as? Int, -32600)
        XCTAssertEqual(zeroError["message"] as? String, "numTurns must be >= 1")

        for (id, value) in [(2, "true"), (3, "1.5")] {
            let response = try appServerResponse(
                #"{"id":\#(id),"method":"thread/rollback","params":{"threadId":"\#(threadID)","numTurns":\#(value)}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "numTurns must be an integer")
        }
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let fullTurn = try XCTUnwrap(((full["result"] as? [String: Any])?["data"] as? [[String: Any]])?.first)
        XCTAssertEqual(fullTurn["itemsView"] as? String, "full")
        XCTAssertEqual(turnAgentTexts(fullTurn), ["draft", "final"])

        let notLoaded = try appServerResponse(
            #"{"id":2,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","itemsView":"notLoaded"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let notLoadedTurn = try XCTUnwrap(((notLoaded["result"] as? [String: Any])?["data"] as? [[String: Any]])?.first)
        XCTAssertEqual(notLoadedTurn["itemsView"] as? String, "notLoaded")
        XCTAssertEqual((notLoadedTurn["items"] as? [Any])?.count, 0)

        let unsupported = try appServerResponse(
            #"{"id":3,"method":"thread/turns/items/list","params":{"threadId":"\#(threadID)","turnId":"turn-1"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let error = try XCTUnwrap(unsupported["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertEqual(error["message"] as? String, "thread/turns/items/list is not supported yet")
    }

    func testThreadTurnsListRejectsUnknownEnumValuesLikeRustProtocol() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "first",
            provider: "mock_provider"
        )

        let badItemsView = try appServerResponse(
            #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","itemsView":"compact"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let badItemsViewError = try XCTUnwrap(badItemsView["error"] as? [String: Any])
        XCTAssertEqual(badItemsViewError["code"] as? Int, -32600)
        XCTAssertEqual(
            badItemsViewError["message"] as? String,
            "Invalid request: unknown variant `compact`, expected one of `notLoaded`, `summary`, `full`"
        )

        let badSortDirection = try appServerResponse(
            #"{"id":2,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","sortDirection":"sideways"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let badSortDirectionError = try XCTUnwrap(badSortDirection["error"] as? [String: Any])
        XCTAssertEqual(badSortDirectionError["code"] as? Int, -32600)
        XCTAssertEqual(
            badSortDirectionError["message"] as? String,
            "Invalid request: unknown variant `sideways`, expected `asc` or `desc`"
        )
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

    func testAccountLoginChatGPTAuthTokensPersistsExternalAuthAndNotifies() throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data("""
        {"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(accessToken)","chatgptAccountId":"org-embedded","chatgptPlanType":"pro"}}
        """.utf8)))
        XCTAssertEqual(messages.count, 3)

        let loginResult = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(loginResult["type"] as? String, "chatgptAuthTokens")

        XCTAssertEqual(messages[1]["method"] as? String, "account/login/completed")
        XCTAssertEqual(messages[2]["method"] as? String, "account/updated")
        let updatedParams = try XCTUnwrap(messages[2]["params"] as? [String: Any])
        XCTAssertEqual(updatedParams["authMode"] as? String, "chatgptAuthTokens")
        XCTAssertEqual(updatedParams["planType"] as? String, "pro")

        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertEqual(stored.authMode, .chatGPTAuthTokens)
        XCTAssertEqual(stored.tokens?.accessToken, accessToken)
        XCTAssertEqual(stored.tokens?.refreshToken, "")
        XCTAssertEqual(stored.tokens?.accountID, "org-embedded")

        let account = try decode(processor.processLine(Data(#"{"id":2,"method":"account/read","params":{"refreshToken":true}}"#.utf8)))
        let accountResult = try XCTUnwrap(account["result"] as? [String: Any])
        let accountPayload = try XCTUnwrap(accountResult["account"] as? [String: Any])
        XCTAssertEqual(accountPayload["type"] as? String, "chatgpt")
        XCTAssertEqual(accountPayload["email"] as? String, "embedded@example.com")
        XCTAssertEqual(accountPayload["planType"] as? String, "pro")
    }

    func testAccountLoginManagedAuthRejectedWhenExternalAuthActive() throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")
        try CodexAuthStorage.saveChatGPTAuthTokens(
            codexHome: temp.url,
            accessToken: accessToken,
            chatGPTAccountID: "org-embedded",
            chatGPTPlanType: "pro"
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let expectedMessage = "External auth is active. Use account/login/start (chatgptAuthTokens) to update it or account/logout to clear it."

        let apiKey = try decode(
            processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"apiKey","apiKey":"sk-test-key"}}"#.utf8))
        )
        let apiKeyError = try XCTUnwrap(apiKey["error"] as? [String: Any])
        XCTAssertEqual(apiKeyError["code"] as? Int, -32600)
        XCTAssertEqual(apiKeyError["message"] as? String, expectedMessage)

        let chatGPT = try decode(
            processor.processLine(Data(#"{"id":2,"method":"account/login/start","params":{"type":"chatgpt"}}"#.utf8))
        )
        let chatGPTError = try XCTUnwrap(chatGPT["error"] as? [String: Any])
        XCTAssertEqual(chatGPTError["code"] as? Int, -32600)
        XCTAssertEqual(chatGPTError["message"] as? String, expectedMessage)

        let deviceCode = try decode(
            processor.processLine(Data(#"{"id":3,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8))
        )
        let deviceCodeError = try XCTUnwrap(deviceCode["error"] as? [String: Any])
        XCTAssertEqual(deviceCodeError["code"] as? Int, -32600)
        XCTAssertEqual(deviceCodeError["message"] as? String, expectedMessage)

        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertEqual(stored.authMode, .chatGPTAuthTokens)
        XCTAssertNil(stored.openAIAPIKey)
    }

    func testAccountReadSkipsRefreshWhenExternalAuthActive() async throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        try CodexAuthStorage.saveChatGPTAuthTokens(
            codexHome: temp.url,
            accessToken: accessToken,
            chatGPTAccountID: "org-embedded",
            chatGPTPlanType: "pro",
            now: staleDate
        )
        let capture = AppServerRefreshCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            authRefreshTransport: { request in
                await capture.append(request)
                return AuthRefreshHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"unexpected-access-token","refresh_token":"unexpected-refresh-token"}"#.utf8)
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
        XCTAssertEqual(account["email"] as? String, "embedded@example.com")
        XCTAssertEqual(account["planType"] as? String, "pro")
        let refreshRequests = await capture.requests
        XCTAssertEqual(refreshRequests.count, 0)
        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertEqual(stored.authMode, .chatGPTAuthTokens)
        XCTAssertEqual(stored.tokens?.accessToken, accessToken)
    }

    func testAccountLoginChatGPTAuthTokensHonorsForcedWorkspaceAndForcedAPI() throws {
        let temp = try TemporaryDirectory()
        try """
        forced_login_method = "api"
        forced_chatgpt_workspace_id = "org-allowed"
        """.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-denied")

        let forcedAPI = try appServerResponse(
            """
            {"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(accessToken)","chatgptAccountId":"org-denied"}}
            """,
            codexHome: temp.url
        )
        let forcedAPIError = try XCTUnwrap(forcedAPI["error"] as? [String: Any])
        XCTAssertEqual(forcedAPIError["code"] as? Int, -32600)
        XCTAssertEqual(
            forcedAPIError["message"] as? String,
            "External ChatGPT auth is disabled. Use API key login instead."
        )

        try #"forced_chatgpt_workspace_id = "org-allowed""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let wrongWorkspace = try appServerResponse(
            """
            {"id":2,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(accessToken)","chatgptAccountId":"org-denied"}}
            """,
            codexHome: temp.url
        )
        let wrongWorkspaceError = try XCTUnwrap(wrongWorkspace["error"] as? [String: Any])
        XCTAssertEqual(wrongWorkspaceError["code"] as? Int, -32600)
        XCTAssertEqual(
            wrongWorkspaceError["message"] as? String,
            "External auth must use workspace org-allowed, but received \"org-denied\"."
        )
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

    func testAccountLoginChatGPTDeviceCodeSucceedsAndNotifies() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let idToken = try fakeJWT(email: "device@example.com", plan: "pro", accountID: "org-device")
        let probe = AppServerDeviceCodeProbe(scenario: .success(idToken: idToken))
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                authDeviceCodeTransport: { request in try await probe.handle(request) },
                environment: ["CODEX_APP_SERVER_LOGIN_ISSUER": "https://issuer.example/"]
            ),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        XCTAssertEqual(loginResult["type"] as? String, "chatgptDeviceCode")
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)
        XCTAssertNotNil(UUID(uuidString: loginID))
        XCTAssertEqual(loginResult["verificationUrl"] as? String, "https://issuer.example/codex/device")
        XCTAssertEqual(loginResult["userCode"] as? String, "CODE-12345")

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0]["method"] as? String, "account/login/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["loginId"] as? String, loginID)
        XCTAssertEqual(completedParams["success"] as? Bool, true)
        XCTAssertTrue(completedParams["error"] is NSNull)

        let updated = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0]["method"] as? String, "account/updated")
        let updatedParams = try XCTUnwrap(updated[0]["params"] as? [String: Any])
        XCTAssertEqual(updatedParams["authMode"] as? String, "chatgpt")
        XCTAssertEqual(updatedParams["planType"] as? String, "pro")

        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertEqual(stored.tokens?.accessToken, "access-token-123")
        XCTAssertEqual(stored.tokens?.refreshToken, "refresh-token-123")
        XCTAssertEqual(stored.tokens?.accountID, "org-device")
    }

    func testAccountLoginChatGPTDeviceCodeStartFailureDoesNotNotify() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let probe = AppServerDeviceCodeProbe(scenario: .userCodeFailure(statusCode: 404))
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                authDeviceCodeTransport: { request in try await probe.handle(request) },
                environment: ["CODEX_APP_SERVER_LOGIN_ISSUER": "https://issuer.example"]
            ),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let response = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8)))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "device code login is not enabled for this Codex server. Use the browser login or verify the server URL."
        )
        let capturedPayloads = await notificationCapture.payloadsData()
        XCTAssertTrue(capturedPayloads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testAccountLoginChatGPTDeviceCodeCanBeCanceled() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let probe = AppServerDeviceCodeProbe(scenario: .pending)
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                authDeviceCodeTransport: { request in try await probe.handle(request) },
                environment: ["CODEX_APP_SERVER_LOGIN_ISSUER": "https://issuer.example"]
            ),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)

        let cancel = try decode(processor.processLine(Data(#"{"id":2,"method":"account/login/cancel","params":{"loginId":"\#(loginID)"}}"#.utf8)))
        let cancelResult = try XCTUnwrap(cancel["result"] as? [String: Any])
        XCTAssertEqual(cancelResult["status"] as? String, "canceled")

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed[0]["method"] as? String, "account/login/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["loginId"] as? String, loginID)
        XCTAssertEqual(completedParams["success"] as? Bool, false)
        XCTAssertEqual(completedParams["error"] as? String, "Login was not completed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testAccountLoginAPIKeyCancelsActiveChatGPTDeviceCodeLogin() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let probe = AppServerDeviceCodeProbe(scenario: .pending)
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                authDeviceCodeTransport: { request in try await probe.handle(request) },
                environment: ["CODEX_APP_SERVER_LOGIN_ISSUER": "https://issuer.example"]
            ),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)

        let apiKeyMessages = try decodeMessages(
            processor.processLine(Data(#"{"id":2,"method":"account/login/start","params":{"type":"apiKey","apiKey":"sk-test-123"}}"#.utf8))
        )
        XCTAssertEqual(apiKeyMessages.count, 3)
        let apiKeyResult = try XCTUnwrap(apiKeyMessages[0]["result"] as? [String: Any])
        XCTAssertEqual(apiKeyResult["type"] as? String, "apiKey")
        XCTAssertEqual(apiKeyMessages[1]["method"] as? String, "account/login/completed")
        let loginCompletedParams = try XCTUnwrap(apiKeyMessages[1]["params"] as? [String: Any])
        XCTAssertTrue(loginCompletedParams["loginId"] is NSNull)
        XCTAssertEqual(loginCompletedParams["success"] as? Bool, true)
        XCTAssertEqual(apiKeyMessages[2]["method"] as? String, "account/updated")
        let updatedParams = try XCTUnwrap(apiKeyMessages[2]["params"] as? [String: Any])
        XCTAssertEqual(updatedParams["authMode"] as? String, "apikey")

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed[0]["method"] as? String, "account/login/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["loginId"] as? String, loginID)
        XCTAssertEqual(completedParams["success"] as? Bool, false)
        XCTAssertEqual(completedParams["error"] as? String, "Login was not completed")

        let cancelOldLogin = try decode(
            processor.processLine(Data(#"{"id":3,"method":"account/login/cancel","params":{"loginId":"\#(loginID)"}}"#.utf8))
        )
        let cancelResult = try XCTUnwrap(cancelOldLogin["result"] as? [String: Any])
        XCTAssertEqual(cancelResult["status"] as? String, "notFound")
    }

    func testAccountLogoutCancelsActiveChatGPTDeviceCodeLogin() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let probe = AppServerDeviceCodeProbe(scenario: .pending)
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                authDeviceCodeTransport: { request in try await probe.handle(request) },
                environment: ["CODEX_APP_SERVER_LOGIN_ISSUER": "https://issuer.example"]
            ),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let login = try decode(processor.processLine(Data(#"{"id":1,"method":"account/login/start","params":{"type":"chatgptDeviceCode"}}"#.utf8)))
        let loginResult = try XCTUnwrap(login["result"] as? [String: Any])
        let loginID = try XCTUnwrap(loginResult["loginId"] as? String)

        let logoutMessages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"account/logout"}"#.utf8)))
        XCTAssertEqual(logoutMessages.count, 2)
        XCTAssertNotNil(logoutMessages[0]["result"] as? [String: Any])
        XCTAssertEqual(logoutMessages[1]["method"] as? String, "account/updated")
        XCTAssertTrue(((logoutMessages[1]["params"] as? [String: Any])?["authMode"]) is NSNull)

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed[0]["method"] as? String, "account/login/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["loginId"] as? String, loginID)
        XCTAssertEqual(completedParams["success"] as? Bool, false)
        XCTAssertEqual(completedParams["error"] as? String, "Login was not completed")
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

    func testSendAddCreditsNudgeEmailRequiresAuthentication() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"account/sendAddCreditsNudgeEmail","params":{"creditType":"credits"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "codex account authentication required to notify workspace owner")
    }

    func testSendAddCreditsNudgeEmailRequiresChatGPTAuthentication() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-test")

        let response = try appServerResponse(
            #"{"id":1,"method":"account/sendAddCreditsNudgeEmail","params":{"creditType":"usage_limit"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "chatgpt authentication required to notify workspace owner")
    }

    func testSendAddCreditsNudgeEmailUsesSenderAndReturnsStatus() async throws {
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
        let sender = AppServerRecordingAddCreditsNudgeEmailSender(status: .cooldownActive)
        let configuration = testConfiguration(codexHome: temp.url, addCreditsNudgeEmailSender: sender)

        let response = try appServerResponse(
            #"{"id":1,"method":"account/sendAddCreditsNudgeEmail","params":{"creditType":"usage_limit"}}"#,
            configuration: configuration
        )

        let requests = await sender.requests
        XCTAssertEqual(requests, [
            AppServerRecordingAddCreditsNudgeEmailSender.Request(
                baseURL: "https://chatgpt.test/base/",
                accessToken: "access-token",
                accountID: "acct-test",
                creditType: .usageLimit
            )
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "cooldown_active")
    }

    func testSendAddCreditsNudgeEmailSurfacesBackendFailure() throws {
        let temp = try TemporaryDirectory()
        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: temp.url,
            apiKey: nil,
            idToken: fakeJWT(email: "user@example.com", plan: "pro"),
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )
        let sender = AppServerRecordingAddCreditsNudgeEmailSender(error: AddCreditsNudgeEmailTestError())
        let configuration = testConfiguration(codexHome: temp.url, addCreditsNudgeEmailSender: sender)

        let response = try appServerResponse(
            #"{"id":1,"method":"account/sendAddCreditsNudgeEmail","params":{"creditType":"credits"}}"#,
            configuration: configuration
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertEqual(error["message"] as? String, "failed to notify workspace owner: boom")
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
        let fetcher = AppServerRecordingAccountRateLimitsFetcher(result: AccountRateLimitsResult(
            rateLimits: RateLimitSnapshot(
                limitID: "codex",
                primary: RateLimitWindow(usedPercent: 42, windowMinutes: 60, resetsAt: 1_737_000_000),
                secondary: RateLimitWindow(usedPercent: 5, windowMinutes: 1_440, resetsAt: 1_737_043_200),
                credits: nil,
                planType: .pro
            ),
            rateLimitsByLimitID: [
                "codex": RateLimitSnapshot(
                    limitID: "codex",
                    primary: RateLimitWindow(usedPercent: 42, windowMinutes: 60, resetsAt: 1_737_000_000),
                    secondary: RateLimitWindow(usedPercent: 5, windowMinutes: 1_440, resetsAt: 1_737_043_200),
                    credits: nil,
                    planType: .pro
                ),
                "codex_other": RateLimitSnapshot(
                    limitID: "codex_other",
                    limitName: "codex_other",
                    primary: RateLimitWindow(usedPercent: 88, windowMinutes: 30, resetsAt: 1_735_693_200),
                    secondary: nil,
                    credits: nil,
                    planType: .pro
                )
            ]
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

        let byLimitID = try XCTUnwrap(result["rateLimitsByLimitId"] as? [String: Any])
        let codexOther = try XCTUnwrap(byLimitID["codex_other"] as? [String: Any])
        XCTAssertEqual(codexOther["limitId"] as? String, "codex_other")
        XCTAssertEqual(codexOther["limitName"] as? String, "codex_other")
        let codexOtherPrimary = try XCTUnwrap(codexOther["primary"] as? [String: Any])
        XCTAssertEqual(codexOtherPrimary["usedPercent"] as? Double, 88)
        XCTAssertEqual(codexOtherPrimary["windowDurationMins"] as? Int, 30)
        XCTAssertEqual(codexOtherPrimary["resetsAt"] as? Int, 1_735_693_200)
    }

    func testURLSessionAccountRateLimitsFetcherUsesCodexAPIUsagePath() async throws {
        let capture = AppServerRequestCapture()
        let fetcher = URLSessionAccountRateLimitsFetcher { request in
            await capture.append(request)
            return AccountRateLimitsHTTPResponse(statusCode: 200, body: Data(Self.rateLimitsUsageJSON.utf8))
        }

        let result = try await fetcher.fetchRateLimits(
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
        let snapshot = result.rateLimits
        XCTAssertEqual(snapshot.primary?.usedPercent, 42)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 60)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 1_440)
        XCTAssertEqual(snapshot.planType, .pro)
        XCTAssertEqual(snapshot.rateLimitReachedType, .workspaceMemberUsageLimitReached)
        XCTAssertEqual(result.rateLimitsByLimitID["codex"]?.primary?.usedPercent, 42)
        XCTAssertEqual(result.rateLimitsByLimitID["codex_other"]?.limitName, "codex_other")
        XCTAssertEqual(result.rateLimitsByLimitID["codex_other"]?.primary?.usedPercent, 88)
        XCTAssertEqual(result.rateLimitsByLimitID["codex_other"]?.primary?.windowMinutes, 30)
    }

    func testURLSessionAddCreditsNudgeEmailSenderPostsExpectedBody() async throws {
        let capture = AppServerRequestCapture()
        let sender = URLSessionAddCreditsNudgeEmailSender { request in
            await capture.append(request)
            return AccountRateLimitsHTTPResponse(statusCode: 200, body: Data())
        }

        let status = try await sender.send(
            baseURL: "https://api.example.test/",
            accessToken: "chatgpt-token",
            accountID: "account-123",
            creditType: .usageLimit
        )

        let requests = await capture.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, URL(string: "https://api.example.test/api/codex/accounts/send_add_credits_nudge_email"))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Authorization"] ?? nil, "Bearer chatgpt-token")
        XCTAssertEqual(request.headers["chatgpt-account-id"] ?? nil, "account-123")
        XCTAssertEqual(request.headers["Content-Type"] ?? nil, "application/json")
        XCTAssertEqual(request.body, #"{"credit_type":"usage_limit"}"#)
        XCTAssertEqual(status, .sent)
    }

    func testURLSessionAddCreditsNudgeEmailSenderMapsCooldown() async throws {
        let sender = URLSessionAddCreditsNudgeEmailSender { _ in
            AccountRateLimitsHTTPResponse(statusCode: 429, body: Data())
        }

        let status = try await sender.send(
            baseURL: "https://api.example.test/",
            accessToken: "chatgpt-token",
            accountID: "account-123",
            creditType: .credits
        )

        XCTAssertEqual(status, .cooldownActive)
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
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

    func testCollaborationModeListRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"collaborationMode/list","params":{}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "collaborationMode/list requires experimentalApi capability")
    }

    func testMockExperimentalMethodRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"mock/experimentalMethod","params":{"value":"hello"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "mock/experimentalMethod requires experimentalApi capability")
    }

    func testMockExperimentalMethodEchoesValue() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"mock/experimentalMethod","params":{"value":"hello"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["echoed"] as? String, "hello")

        let nullResponse = try appServerResponse(
            #"{"id":2,"method":"mock/experimentalMethod","params":{}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let nullResult = try XCTUnwrap(nullResponse["result"] as? [String: Any])
        XCTAssertTrue(nullResult["echoed"] is NSNull)
    }

    func testRealtimeRoutesRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        for (index, method) in [
            "thread/realtime/start",
            "thread/realtime/appendAudio",
            "thread/realtime/appendText",
            "thread/realtime/stop",
            "thread/realtime/listVoices"
        ].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(method) requires experimentalApi capability")
        }
    }

    func testRealtimeListVoicesReturnsRustBuiltinVoices() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/realtime/listVoices","params":{}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let voices = try XCTUnwrap(result["voices"] as? [String: Any])
        XCTAssertEqual(
            voices["v1"] as? [String],
            ["juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol", "cove"]
        )
        XCTAssertEqual(
            voices["v2"] as? [String],
            ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"]
        )
        XCTAssertEqual(voices["defaultV1"] as? String, "cove")
        XCTAssertEqual(voices["defaultV2"] as? String, "marin")
    }

    func testRealtimeConversationRoutesReturnRustDisabledThreadError() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        for (index, method) in [
            "thread/realtime/start",
            "thread/realtime/appendAudio",
            "thread/realtime/appendText",
            "thread/realtime/stop"
        ].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 2),"method":"\#(method)","params":{"threadId":"\#(threadID)"}}"#,
                codexHome: temp.url,
                experimentalAPIEnabled: true
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "thread \(threadID) does not support realtime conversation")
        }
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

    func testSkillsListDefaultsToConfiguredCwd() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"skills/list","params":{}}"#,
            configuration: testConfiguration(codexHome: codexHome.url, cwd: cwd.url)
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["cwd"] as? String, cwd.url.standardizedFileURL.path)
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

    func testHooksListReturnsEnabledPluginCommandHooks() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let pluginRoot = codexHome.url.appendingPathComponent("plugins/cache/test/demo/local", isDirectory: true)
        let manifestRoot = pluginRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        let hooksRoot = pluginRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        try #"{"name":"demo"}"#.write(
            to: manifestRoot.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo plugin hook",
                    "timeout": 7,
                    "statusMessage": "running plugin hook"
                  }
                ]
              }
            ]
          }
        }
        """.write(to: hooksRoot.appendingPathComponent("hooks.json", isDirectory: false), atomically: true, encoding: .utf8)
        try """
        [features]
        plugins = true
        plugin_hooks = true
        hooks = true

        [plugins."demo@test"]
        enabled = true
        """.write(to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let hooks = try XCTUnwrap(data[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, "demo@test:hooks/hooks.json:pre_tool_use:0:0")
        XCTAssertEqual(hooks[0]["eventName"] as? String, "preToolUse")
        XCTAssertEqual(hooks[0]["handlerType"] as? String, "command")
        XCTAssertEqual(hooks[0]["matcher"] as? String, "Bash")
        XCTAssertEqual(hooks[0]["command"] as? String, "echo plugin hook")
        XCTAssertEqual(hooks[0]["timeoutSec"] as? Int, 7)
        XCTAssertEqual(hooks[0]["statusMessage"] as? String, "running plugin hook")
        XCTAssertEqual(hooks[0]["sourcePath"] as? String, hooksRoot.appendingPathComponent("hooks.json").standardizedFileURL.path)
        XCTAssertEqual(hooks[0]["source"] as? String, "plugin")
        XCTAssertEqual(hooks[0]["pluginId"] as? String, "demo@test")
        XCTAssertEqual(hooks[0]["displayOrder"] as? Int, 0)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, true)
        XCTAssertEqual(hooks[0]["isManaged"] as? Bool, false)
        XCTAssertTrue((hooks[0]["currentHash"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "untrusted")
    }

    func testHooksListReportsPluginHookLoadWarnings() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let pluginRoot = codexHome.url.appendingPathComponent("plugins/cache/test/demo/local", isDirectory: true)
        let manifestRoot = pluginRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        let hooksRoot = pluginRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        try #"{"name":"demo"}"#.write(
            to: manifestRoot.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "{ not-json".write(
            to: hooksRoot.appendingPathComponent("hooks.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        [features]
        plugins = true
        plugin_hooks = true
        hooks = true

        [plugins."demo@test"]
        enabled = true
        """.write(to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["cwd"] as? String, cwd.url.path)
        XCTAssertEqual((data[0]["hooks"] as? [Any])?.count, 0)
        let warnings = try XCTUnwrap(data[0]["warnings"] as? [String])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("failed to parse plugin hooks config"))
        XCTAssertEqual((data[0]["errors"] as? [Any])?.count, 0)
    }

    func testHooksListUsesEachCwdEffectiveFeatureEnablement() throws {
        let codexHome = try TemporaryDirectory()
        let workspace = try TemporaryDirectory()
        try """
        [features]
        hooks = false
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: workspace.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workspace.url.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )
        let projectConfig = workspace.url.appendingPathComponent(".codex/config.toml", isDirectory: false)
        try """
        [features]
        hooks = true

        [hooks]

        [[hooks.PreToolUse]]
        matcher = "Bash"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "echo project hook"
        timeout = 5
        """.write(to: projectConfig, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(codexHome.url.path)","\#(workspace.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0]["cwd"] as? String, codexHome.url.path)
        XCTAssertEqual((data[0]["hooks"] as? [Any])?.count, 0)
        XCTAssertEqual((data[0]["warnings"] as? [Any])?.count, 0)
        XCTAssertEqual((data[0]["errors"] as? [Any])?.count, 0)

        XCTAssertEqual(data[1]["cwd"] as? String, workspace.url.path)
        XCTAssertEqual((data[1]["warnings"] as? [Any])?.count, 0)
        XCTAssertEqual((data[1]["errors"] as? [Any])?.count, 0)
        let hooks = try XCTUnwrap(data[1]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, "\(projectConfig.standardizedFileURL.path):pre_tool_use:0:0")
        XCTAssertEqual(hooks[0]["eventName"] as? String, "preToolUse")
        XCTAssertEqual(hooks[0]["handlerType"] as? String, "command")
        XCTAssertEqual(hooks[0]["matcher"] as? String, "Bash")
        XCTAssertEqual(hooks[0]["command"] as? String, "echo project hook")
        XCTAssertEqual(hooks[0]["timeoutSec"] as? Int, 5)
        XCTAssertTrue(hooks[0]["statusMessage"] is NSNull)
        XCTAssertEqual(hooks[0]["sourcePath"] as? String, projectConfig.standardizedFileURL.path)
        XCTAssertEqual(hooks[0]["source"] as? String, "project")
        XCTAssertTrue(hooks[0]["pluginId"] is NSNull)
        XCTAssertEqual(hooks[0]["displayOrder"] as? Int, 0)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, true)
        XCTAssertEqual(hooks[0]["isManaged"] as? Bool, false)
        XCTAssertTrue((hooks[0]["currentHash"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "untrusted")
    }

    func testConfigBatchWriteTogglesUserHook() throws {
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

        let initial = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let initialResult = try XCTUnwrap(initial["result"] as? [String: Any])
        let initialData = try XCTUnwrap(initialResult["data"] as? [[String: Any]])
        let initialHooks = try XCTUnwrap(initialData[0]["hooks"] as? [[String: Any]])
        let hookKey = try XCTUnwrap(initialHooks[0]["key"] as? String)
        XCTAssertEqual(initialHooks[0]["enabled"] as? Bool, true)

        let disable = try appServerResponse(
            #"{"id":2,"method":"config/batchWrite","params":{"edits":[{"keyPath":"hooks.state","value":{"\#(hookKey)":{"enabled":false}},"mergeStrategy":"upsert"}],"reloadUserConfig":true}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((disable["result"] as? [String: Any])?["status"] as? String, "ok")

        let disabled = try appServerResponse(
            #"{"id":3,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let disabledResult = try XCTUnwrap(disabled["result"] as? [String: Any])
        let disabledData = try XCTUnwrap(disabledResult["data"] as? [[String: Any]])
        let disabledHooks = try XCTUnwrap(disabledData[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(disabledHooks.count, 1)
        XCTAssertEqual(disabledHooks[0]["key"] as? String, hookKey)
        XCTAssertEqual(disabledHooks[0]["enabled"] as? Bool, false)

        let enable = try appServerResponse(
            #"{"id":4,"method":"config/batchWrite","params":{"edits":[{"keyPath":"hooks.state","value":{"\#(hookKey)":{"enabled":true}},"mergeStrategy":"upsert"}],"reloadUserConfig":true}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((enable["result"] as? [String: Any])?["status"] as? String, "ok")

        let enabled = try appServerResponse(
            #"{"id":5,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let enabledResult = try XCTUnwrap(enabled["result"] as? [String: Any])
        let enabledData = try XCTUnwrap(enabledResult["data"] as? [[String: Any]])
        let enabledHooks = try XCTUnwrap(enabledData[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(enabledHooks[0]["key"] as? String, hookKey)
        XCTAssertEqual(enabledHooks[0]["enabled"] as? Bool, true)
    }

    func testConfigBatchWriteUpdatesHookTrustStatus() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let configFile = codexHome.url.appendingPathComponent("config.toml", isDirectory: false)
        try """
        [hooks]

        [[hooks.UserPromptSubmit]]

        [[hooks.UserPromptSubmit.hooks]]
        type = "command"
        command = "python3 /tmp/listed-hook.py"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let initial = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let initialResult = try XCTUnwrap(initial["result"] as? [String: Any])
        let initialData = try XCTUnwrap(initialResult["data"] as? [[String: Any]])
        let initialHooks = try XCTUnwrap(initialData[0]["hooks"] as? [[String: Any]])
        let hookKey = try XCTUnwrap(initialHooks[0]["key"] as? String)
        let initialHash = try XCTUnwrap(initialHooks[0]["currentHash"] as? String)
        XCTAssertEqual(initialHooks[0]["trustStatus"] as? String, "untrusted")

        let trust = try appServerResponse(
            #"{"id":2,"method":"config/batchWrite","params":{"edits":[{"keyPath":"hooks.state","value":{"\#(hookKey)":{"trusted_hash":"\#(initialHash)"}},"mergeStrategy":"upsert"}],"reloadUserConfig":true}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((trust["result"] as? [String: Any])?["status"] as? String, "ok")

        let trusted = try appServerResponse(
            #"{"id":3,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let trustedResult = try XCTUnwrap(trusted["result"] as? [String: Any])
        let trustedData = try XCTUnwrap(trustedResult["data"] as? [[String: Any]])
        let trustedHooks = try XCTUnwrap(trustedData[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(trustedHooks[0]["key"] as? String, hookKey)
        XCTAssertEqual(trustedHooks[0]["currentHash"] as? String, initialHash)
        XCTAssertEqual(trustedHooks[0]["trustStatus"] as? String, "trusted")

        let modify = try appServerResponse(
            #"{"id":4,"method":"config/batchWrite","params":{"edits":[{"keyPath":"hooks.UserPromptSubmit","value":[{"hooks":[{"type":"command","command":"python3 /tmp/listed-hook.py","statusMessage":"modified hook"}]}],"mergeStrategy":"replace"}],"reloadUserConfig":true}}"#,
            codexHome: codexHome.url
        )
        XCTAssertEqual((modify["result"] as? [String: Any])?["status"] as? String, "ok")

        let modified = try appServerResponse(
            #"{"id":5,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let modifiedResult = try XCTUnwrap(modified["result"] as? [String: Any])
        let modifiedData = try XCTUnwrap(modifiedResult["data"] as? [[String: Any]])
        let modifiedHooks = try XCTUnwrap(modifiedData[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(modifiedHooks[0]["key"] as? String, hookKey)
        XCTAssertNotEqual(modifiedHooks[0]["currentHash"] as? String, initialHash)
        XCTAssertEqual(modifiedHooks[0]["trustStatus"] as? String, "modified")
    }

    func testHooksListReadsDottedHookStateToml() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let configFile = codexHome.url.appendingPathComponent("config.toml", isDirectory: false)
        let hookKey = "\(configFile.standardizedFileURL.path):pre_tool_use:0:0"
        try """
        [hooks.state."\(hookKey)"]
        enabled = false
        trusted_hash = "sha256:stale"

        [hooks]

        [[hooks.PreToolUse]]
        matcher = "Bash"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 /tmp/listed-hook.py"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let hooks = try XCTUnwrap(data[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, hookKey)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, false)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "modified")
    }

    func testHooksListReturnsManagedRequirementHooks() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let managedDir = try TemporaryDirectory()
        let requirementsPath = codexHome.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        [hooks]
        managed_dir = "\(managedDir.url.path)"

        [[hooks.PreToolUse]]
        matcher = "^Bash$"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 \(managedDir.url.appendingPathComponent("pre.py").path)"
        timeout = 10
        statusMessage = "checking"
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            configuration: testConfiguration(
                codexHome: codexHome.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let hooks = try XCTUnwrap(data[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, "\(managedDir.url.standardizedFileURL.path):pre_tool_use:0:0")
        XCTAssertEqual(hooks[0]["eventName"] as? String, "preToolUse")
        XCTAssertEqual(hooks[0]["handlerType"] as? String, "command")
        XCTAssertEqual(hooks[0]["matcher"] as? String, "^Bash$")
        XCTAssertEqual(hooks[0]["command"] as? String, "python3 \(managedDir.url.appendingPathComponent("pre.py").path)")
        XCTAssertEqual(hooks[0]["timeoutSec"] as? Int, 10)
        XCTAssertEqual(hooks[0]["statusMessage"] as? String, "checking")
        XCTAssertEqual(hooks[0]["sourcePath"] as? String, managedDir.url.standardizedFileURL.path)
        XCTAssertEqual(hooks[0]["source"] as? String, "system")
        XCTAssertTrue(hooks[0]["pluginId"] is NSNull)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, true)
        XCTAssertEqual(hooks[0]["isManaged"] as? Bool, true)
        XCTAssertTrue((hooks[0]["currentHash"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "managed")
        XCTAssertEqual(data[0]["warnings"] as? [String], [])
    }

    func testHooksListDoesNotDisableManagedRequirementHooksFromUserState() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let managedDir = try TemporaryDirectory()
        let requirementsPath = codexHome.url.appendingPathComponent("requirements.toml", isDirectory: false)
        let managedKey = "\(managedDir.url.standardizedFileURL.path):pre_tool_use:0:0"
        try """
        [hooks]
        managed_dir = "\(managedDir.url.path)"

        [[hooks.PreToolUse]]
        matcher = "^Bash$"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 \(managedDir.url.appendingPathComponent("pre.py").path)"
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        [hooks.state."\(managedKey)"]
        enabled = false
        trusted_hash = "sha256:user"
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            configuration: testConfiguration(
                codexHome: codexHome.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let hooks = try XCTUnwrap(data[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0]["key"] as? String, managedKey)
        XCTAssertEqual(hooks[0]["enabled"] as? Bool, true)
        XCTAssertEqual(hooks[0]["trustStatus"] as? String, "managed")
    }

    func testHooksListWarnsWhenManagedRequirementDirectoryIsMissing() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let missingDir = codexHome.url.appendingPathComponent("missing-managed-hooks", isDirectory: true)
        let requirementsPath = codexHome.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        [hooks]
        managed_dir = "\(missingDir.path)"

        [[hooks.PreToolUse]]
        matcher = "^Bash$"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 \(missingDir.appendingPathComponent("pre.py").path)"
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{"cwds":["\#(cwd.url.path)"]}}"#,
            configuration: testConfiguration(
                codexHome: codexHome.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual((data[0]["hooks"] as? [[String: Any]])?.count, 0)
        let warnings = try XCTUnwrap(data[0]["warnings"] as? [String])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("managed hook directory"))
        XCTAssertTrue(warnings[0].contains("does not exist"))
        XCTAssertTrue(warnings[0].contains(missingDir.path))
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

    func testHooksListDefaultsToConfiguredCwd() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"hooks/list","params":{}}"#,
            configuration: testConfiguration(codexHome: codexHome.url, cwd: cwd.url)
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["cwd"] as? String, cwd.url.standardizedFileURL.path)
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

    func testConfigReadAfterPipelinedWriteSeesWrittenValue() throws {
        let temp = try TemporaryDirectory()
        try #"model = "gpt-old""#.write(
            to: temp.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let write = try decode(processor.processLine(Data(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"model","value":"gpt-new","mergeStrategy":"replace"}}"#.utf8
        )))
        let writeResult = try XCTUnwrap(write["result"] as? [String: Any])
        XCTAssertEqual(writeResult["status"] as? String, "ok")

        let read = try decode(processor.processLine(Data(#"{"id":2,"method":"config/read","params":{}}"#.utf8)))
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(readResult["config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "gpt-new")
    }

    func testConfigValueWriteUpsertsNestedTableLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let base = """
        [mcp_servers.linear]
        bearer_token_env_var = "OLD_TOKEN"
        name = "linear"
        url = "https://linear.example"

        [mcp_servers.linear.env_http_headers]
        existing = "keep"

        [mcp_servers.linear.http_headers]
        alpha = "a"
        """
        try base.write(to: configFile, atomically: true, encoding: .utf8)
        let overlay = #"{"bearer_token_env_var":"NEW_TOKEN","http_headers":{"alpha":"updated","beta":"b"}}"#

        let upsert = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"mcp_servers.linear","value":\#(overlay),"mergeStrategy":"upsert"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((upsert["result"] as? [String: Any])?["status"] as? String, "ok")

        let upserted = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(upserted.contains(#"bearer_token_env_var = "NEW_TOKEN""#))
        XCTAssertTrue(upserted.contains(#"name = "linear""#))
        XCTAssertTrue(upserted.contains(#"url = "https://linear.example""#))
        XCTAssertTrue(upserted.contains(#"existing = "keep""#))
        XCTAssertTrue(upserted.contains(#"alpha = "updated""#))
        XCTAssertTrue(upserted.contains(#"beta = "b""#))

        try base.write(to: configFile, atomically: true, encoding: .utf8)
        let replace = try appServerResponse(
            #"{"id":2,"method":"config/value/write","params":{"keyPath":"mcp_servers.linear","value":\#(overlay),"mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((replace["result"] as? [String: Any])?["status"] as? String, "ok")

        let replaced = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(replaced.contains(#"bearer_token_env_var = "NEW_TOKEN""#))
        XCTAssertTrue(replaced.contains(#"alpha = "updated""#))
        XCTAssertTrue(replaced.contains(#"beta = "b""#))
        XCTAssertFalse(replaced.contains(#"name = "linear""#))
        XCTAssertFalse(replaced.contains(#"existing = "keep""#))
    }

    func testConfigValueWriteRejectsUnknownMergeStrategyLikeRustProtocol() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try #"model = "gpt-old""#.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"model","value":"gpt-new","mergeStrategy":"merge"}}"#,
            codexHome: temp.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "Invalid request: unknown variant `merge`, expected `replace` or `upsert`"
        )
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), #"model = "gpt-old""#)
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

    func testFuzzyFileSearchSessionRoutesRequireExperimentalAPI() throws {
        let codexHome = try TemporaryDirectory()

        for (index, method) in [
            "fuzzyFileSearch/sessionStart",
            "fuzzyFileSearch/sessionUpdate",
            "fuzzyFileSearch/sessionStop"
        ].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{}}"#,
                codexHome: codexHome.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(method) requires experimentalApi capability")
        }
    }

    func testFuzzyFileSearchSessionStreamsUpdatesAndCompletion() throws {
        let codexHome = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        try "x".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            experimentalAPIEnabled: true
        )

        let start = try decode(processor.processLine(Data(
            #"{"id":1,"method":"fuzzyFileSearch/sessionStart","params":{"sessionId":"session-1","roots":["\#(root.url.path)"]}}"#.utf8
        )))
        XCTAssertEqual((start["result"] as? [String: Any])?.isEmpty, true)

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"fuzzyFileSearch/sessionUpdate","params":{"sessionId":"session-1","query":"ALP"}}"#.utf8
        )))
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "fuzzyFileSearch/sessionUpdated")
        let updateParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(updateParams["sessionId"] as? String, "session-1")
        XCTAssertEqual(updateParams["query"] as? String, "ALP")
        let files = try XCTUnwrap(updateParams["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0]["root"] as? String, root.url.path)
        XCTAssertEqual(files[0]["path"] as? String, "alpha.txt")
        XCTAssertEqual(messages[2]["method"] as? String, "fuzzyFileSearch/sessionCompleted")
        let completedParams = try XCTUnwrap(messages[2]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["sessionId"] as? String, "session-1")
    }

    func testFuzzyFileSearchSessionStopRemovesSessionAndEmptyQuerySendsBlankSnapshot() throws {
        let codexHome = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        try "x".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            experimentalAPIEnabled: true
        )

        _ = try decode(processor.processLine(Data(
            #"{"id":1,"method":"fuzzyFileSearch/sessionStart","params":{"sessionId":"session-stop","roots":["\#(root.url.path)"]}}"#.utf8
        )))
        let emptyMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"fuzzyFileSearch/sessionUpdate","params":{"sessionId":"session-stop","query":""}}"#.utf8
        )))
        let emptyParams = try XCTUnwrap(emptyMessages[1]["params"] as? [String: Any])
        XCTAssertEqual((emptyParams["files"] as? [Any])?.count, 0)

        let stop = try decode(processor.processLine(Data(
            #"{"id":3,"method":"fuzzyFileSearch/sessionStop","params":{"sessionId":"session-stop"}}"#.utf8
        )))
        XCTAssertEqual((stop["result"] as? [String: Any])?.isEmpty, true)

        let missing = try decode(processor.processLine(Data(
            #"{"id":4,"method":"fuzzyFileSearch/sessionUpdate","params":{"sessionId":"session-stop","query":"alp"}}"#.utf8
        )))
        let error = try XCTUnwrap(missing["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "fuzzy file search session not found: session-stop")
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

    func testCommandExecResolvesRelativeCwdAgainstConfiguredServerCwd() throws {
        let codexHome = try TemporaryDirectory()
        let serverCwd = try TemporaryDirectory()
        let nested = serverCwd.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let configuration = testConfiguration(codexHome: codexHome.url, cwd: serverCwd.url)

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/pwd"],"cwd":"nested"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(
            (result["stdout"] as? String)?.replacingOccurrences(of: "/private/var/", with: "/var/"),
            nested.path.replacingOccurrences(of: "/private/var/", with: "/var/") + "\n"
        )
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecEnvironmentNullOverridesUnsetVariables() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let configuration = testConfiguration(
            codexHome: codexHome.url,
            environment: [
                "CODEX_SWIFT_COMMAND_KEEP": "server-value",
                "CODEX_SWIFT_COMMAND_UNSET": "server-value"
            ]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/usr/bin/env"],"cwd":"\#(cwd.url.path)","env":{"CODEX_SWIFT_COMMAND_KEEP":"override-value","CODEX_SWIFT_COMMAND_UNSET":null}}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        let environmentLines = Set((try XCTUnwrap(result["stdout"] as? String)).split(separator: "\n").map(String.init))
        XCTAssertTrue(environmentLines.contains("CODEX_SWIFT_COMMAND_KEEP=override-value"))
        XCTAssertFalse(environmentLines.contains { $0.hasPrefix("CODEX_SWIFT_COMMAND_UNSET=") })
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecBufferedOutputBytesCapAppliesPerStream() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf stdout; printf stderr >&2"],"cwd":"\#(cwd.url.path)","outputBytesCap":3}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "std")
        XCTAssertEqual(result["stderr"] as? String, "std")
    }

    func testCommandExecBufferedTimeoutReportsRustExitCode() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sleep","5"],"cwd":"\#(cwd.url.path)","timeoutMs":10}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 124)
        XCTAssertEqual(result["stdout"] as? String, "")
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecIgnoresSnakeCaseTimeoutAliasLikeRustProtocol() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","sleep 0.05; printf ok"],"cwd":"\#(cwd.url.path)","timeout_ms":1}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "ok")
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecPermissionProfileRequiresExperimentalAPI() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","permissionProfile":{"type":"disabled"}}}"#,
            codexHome: codexHome.url
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "command/exec.permissionProfile requires experimentalApi capability")

        let nullPermissionProfile = try appServerResponse(
            #"{"id":2,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","permissionProfile":null}}"#,
            codexHome: codexHome.url
        )
        let nullPermissionProfileResult = try XCTUnwrap(nullPermissionProfile["result"] as? [String: Any])
        XCTAssertEqual(nullPermissionProfileResult["exitCode"] as? Int, 0)
        XCTAssertEqual(nullPermissionProfileResult["stdout"] as? String, "hi\n")
    }

    func testCommandExecValidatesRustOptionConflicts() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let outputCap = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","outputBytesCap":10,"disableOutputCap":true}}"#,
            codexHome: codexHome.url
        )
        let outputCapError = try XCTUnwrap(outputCap["error"] as? [String: Any])
        XCTAssertEqual(outputCapError["code"] as? Int, -32602)
        XCTAssertEqual(
            outputCapError["message"] as? String,
            "command/exec cannot set both outputBytesCap and disableOutputCap"
        )

        let timeout = try appServerResponse(
            #"{"id":2,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","timeoutMs":10,"disableTimeout":true}}"#,
            codexHome: codexHome.url
        )
        let timeoutError = try XCTUnwrap(timeout["error"] as? [String: Any])
        XCTAssertEqual(timeoutError["code"] as? Int, -32602)
        XCTAssertEqual(
            timeoutError["message"] as? String,
            "command/exec cannot set both timeoutMs and disableTimeout"
        )

        let nullTimeoutWithDisable = try appServerResponse(
            #"{"id":4,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","timeoutMs":null,"disableTimeout":true}}"#,
            codexHome: codexHome.url
        )
        let nullTimeoutResult = try XCTUnwrap(nullTimeoutWithDisable["result"] as? [String: Any])
        XCTAssertEqual(nullTimeoutResult["exitCode"] as? Int, 0)
        XCTAssertEqual(nullTimeoutResult["stdout"] as? String, "hi\n")

        let nullOutputCapWithDisable = try appServerResponse(
            #"{"id":5,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","outputBytesCap":null,"disableOutputCap":true}}"#,
            codexHome: codexHome.url
        )
        let nullOutputCapResult = try XCTUnwrap(nullOutputCapWithDisable["result"] as? [String: Any])
        XCTAssertEqual(nullOutputCapResult["exitCode"] as? Int, 0)
        XCTAssertEqual(nullOutputCapResult["stdout"] as? String, "hi\n")

        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            experimentalAPIEnabled: true
        )
        let sandboxAndProfile = try decode(processor.processLine(Data(
            #"{"id":3,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{},"permissionProfile":"on-request"}}"#.utf8
        )))
        let sandboxAndProfileError = try XCTUnwrap(sandboxAndProfile["error"] as? [String: Any])
        XCTAssertEqual(sandboxAndProfileError["code"] as? Int, -32600)
        XCTAssertEqual(
            sandboxAndProfileError["message"] as? String,
            "`permissionProfile` cannot be combined with `sandboxPolicy`"
        )
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

    func testCommandExecProcessIDSessionAcceptsStdinAndSendsDeferredResponse() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        let started = processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/cat"],"processId":"cmd-stdin","cwd":"\#(cwd.url.path)","streamStdin":true}}"#.utf8
        ))
        XCTAssertNil(started)

        let write = try decode(processor.processLine(Data(
            #"{"id":2,"method":"command/exec/write","params":{"processId":"cmd-stdin","deltaBase64":"aGVsbG8=","closeStdin":true}}"#.utf8
        )))
        XCTAssertEqual((write["result"] as? [String: Any])?.isEmpty, true)

        let responseData = try await nextNotificationPayload(notificationCapture)
        let response = try XCTUnwrap(decodeMessages(responseData).first)
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "hello")
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecProcessIDSessionResolvesRelativeCwdAgainstConfiguredServerCwd() async throws {
        let codexHome = try TemporaryDirectory()
        let serverCwd = try TemporaryDirectory()
        let nested = serverCwd.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url, cwd: serverCwd.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/pwd"],"processId":"cmd-relative-cwd","cwd":"nested"}}"#.utf8
        )))

        let responseData = try await nextNotificationPayload(notificationCapture)
        let response = try XCTUnwrap(decodeMessages(responseData).first)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(
            (result["stdout"] as? String)?.replacingOccurrences(of: "/private/var/", with: "/var/"),
            nested.path.replacingOccurrences(of: "/private/var/", with: "/var/") + "\n"
        )
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecProcessIDSessionStreamsOutputAndDefersBufferedResponse() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        let started = processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf streamed"],"processId":"cmd-stream","cwd":"\#(cwd.url.path)","streamStdoutStderr":true}}"#.utf8
        ))
        XCTAssertNil(started)

        let firstData = try await nextNotificationPayload(notificationCapture)
        let secondData = try await nextNotificationPayload(notificationCapture)
        let messages = try decodeMessages(firstData) + decodeMessages(secondData)
        let output = try XCTUnwrap(messages.first { $0["method"] as? String == "command/exec/outputDelta" })
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processId"] as? String, "cmd-stream")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "streamed"
        )

        let response = try XCTUnwrap(messages.first { $0["id"] as? Int == 1 })
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "")
        XCTAssertEqual(result["stderr"] as? String, "")
    }

    func testCommandExecStreamsOutputBeforeProcessExit() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf live; sleep 5"],"processId":"cmd-live-stream","cwd":"\#(cwd.url.path)","streamStdoutStderr":true}}"#.utf8
        )))

        let outputData = try await nextNotificationPayload(notificationCapture, timeoutNanoseconds: 1_000_000_000)
        let output = try XCTUnwrap(decodeMessages(outputData).first)
        XCTAssertEqual(output["method"] as? String, "command/exec/outputDelta")
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processId"] as? String, "cmd-live-stream")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "live"
        )

        let terminate = try decode(processor.processLine(Data(
            #"{"id":2,"method":"command/exec/terminate","params":{"processId":"cmd-live-stream"}}"#.utf8
        )))
        XCTAssertEqual((terminate["result"] as? [String: Any])?.isEmpty, true)
    }

    func testCommandExecRejectsDuplicateProcessIDAndTerminateStopsActiveSession() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sleep","5"],"processId":"cmd-kill","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))

        let duplicate = try decode(processor.processLine(Data(
            #"{"id":2,"method":"command/exec","params":{"command":["/bin/sleep","5"],"processId":"cmd-kill","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        let duplicateError = try XCTUnwrap(duplicate["error"] as? [String: Any])
        XCTAssertEqual(duplicateError["code"] as? Int, -32600)
        XCTAssertEqual(duplicateError["message"] as? String, #"duplicate active command/exec process id: "cmd-kill""#)

        let terminate = try decode(processor.processLine(Data(
            #"{"id":3,"method":"command/exec/terminate","params":{"processId":"cmd-kill"}}"#.utf8
        )))
        XCTAssertEqual((terminate["result"] as? [String: Any])?.isEmpty, true)
    }

    func testCommandExecProcessIDSessionTimeoutReportsRustExitCode() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sleep","5"],"processId":"cmd-timeout","cwd":"\#(cwd.url.path)","timeoutMs":10}}"#.utf8
        )))

        let responseData = try await nextNotificationPayload(notificationCapture)
        let response = try XCTUnwrap(decodeMessages(responseData).first)
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 124)
    }

    func testCommandExecResizeActiveNonPtyReportsRustError() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sleep","5"],"processId":"cmd-resize","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))

        let resize = try decode(processor.processLine(Data(
            #"{"id":2,"method":"command/exec/resize","params":{"processId":"cmd-resize","size":{"rows":24,"cols":80}}}"#.utf8
        )))
        let resizeError = try XCTUnwrap(resize["error"] as? [String: Any])
        XCTAssertEqual(resizeError["code"] as? Int, -32600)
        XCTAssertEqual(resizeError["message"] as? String, "failed to resize PTY: process is not attached to a PTY")

        let terminate = try decode(processor.processLine(Data(
            #"{"id":3,"method":"command/exec/terminate","params":{"processId":"cmd-resize"}}"#.utf8
        )))
        XCTAssertEqual((terminate["result"] as? [String: Any])?.isEmpty, true)
    }

    func testCommandExecTtySessionResizesActiveTerminal() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sleep","5"],"processId":"cmd-pty","cwd":"\#(cwd.url.path)","tty":true,"size":{"rows":17,"cols":45}}}"#.utf8
        )))

        let resize = try decode(processor.processLine(Data(
            #"{"id":2,"method":"command/exec/resize","params":{"processId":"cmd-pty","size":{"rows":24,"cols":80}}}"#.utf8
        )))
        XCTAssertEqual((resize["result"] as? [String: Any])?.isEmpty, true)

        let terminate = try decode(processor.processLine(Data(
            #"{"id":3,"method":"command/exec/terminate","params":{"processId":"cmd-pty"}}"#.utf8
        )))
        XCTAssertEqual((terminate["result"] as? [String: Any])?.isEmpty, true)
    }

    func testCommandExecTtySessionReportsPtyOutput() async throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            }
        )

        XCTAssertNil(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf pty-out"],"processId":"cmd-pty-output","cwd":"\#(cwd.url.path)","tty":true,"size":{"rows":24,"cols":80}}}"#.utf8
        )))

        let firstData = try await nextNotificationPayload(notificationCapture)
        let secondData = try await nextNotificationPayload(notificationCapture)
        let messages = try decodeMessages(firstData) + decodeMessages(secondData)
        let output = try XCTUnwrap(messages.first { $0["method"] as? String == "command/exec/outputDelta" })
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processId"] as? String, "cmd-pty-output")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "pty-out"
        )

        let response = try XCTUnwrap(messages.first { $0["id"] as? Int == 1 })
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "")
        XCTAssertEqual(result["stderr"] as? String, "")
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

    func testProcessRoutesRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        for (index, method) in ["process/spawn", "process/writeStdin", "process/resizePty", "process/kill"].enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 1),"method":"\#(method)","params":{}}"#,
                codexHome: temp.url
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "\(method) requires experimentalApi capability")
        }
    }

    func testProcessFollowUpsReportNoActiveProcess() throws {
        let temp = try TemporaryDirectory()

        let write = try appServerResponse(
            #"{"id":1,"method":"process/writeStdin","params":{"processHandle":"proc-1","deltaBase64":"aGk="}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let writeError = try XCTUnwrap(write["error"] as? [String: Any])
        XCTAssertEqual(writeError["code"] as? Int, -32600)
        XCTAssertEqual(writeError["message"] as? String, #"no active process for process handle "proc-1""#)

        let resize = try appServerResponse(
            #"{"id":2,"method":"process/resizePty","params":{"processHandle":"proc-1","size":{"rows":24,"cols":80}}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let resizeError = try XCTUnwrap(resize["error"] as? [String: Any])
        XCTAssertEqual(resizeError["code"] as? Int, -32600)
        XCTAssertEqual(resizeError["message"] as? String, #"no active process for process handle "proc-1""#)

        let kill = try appServerResponse(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-1"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let killError = try XCTUnwrap(kill["error"] as? [String: Any])
        XCTAssertEqual(killError["code"] as? Int, -32600)
        XCTAssertEqual(killError["message"] as? String, #"no active process for process handle "proc-1""#)
    }

    func testProcessSpawnValidatesRustParamsBeforeLiveLifecycle() throws {
        let temp = try TemporaryDirectory()

        let emptyCommand = try appServerResponse(
            #"{"id":1,"method":"process/spawn","params":{"command":[],"processHandle":"proc-1","cwd":"\#(temp.url.path)"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let emptyCommandError = try XCTUnwrap(emptyCommand["error"] as? [String: Any])
        XCTAssertEqual(emptyCommandError["code"] as? Int, -32600)
        XCTAssertEqual(emptyCommandError["message"] as? String, "command must not be empty")

        let emptyHandle = try appServerResponse(
            #"{"id":2,"method":"process/spawn","params":{"command":["echo"],"processHandle":"","cwd":"\#(temp.url.path)"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let emptyHandleError = try XCTUnwrap(emptyHandle["error"] as? [String: Any])
        XCTAssertEqual(emptyHandleError["code"] as? Int, -32600)
        XCTAssertEqual(emptyHandleError["message"] as? String, "processHandle must not be empty")

        let relativeCwd = try appServerResponse(
            #"{"id":3,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"relative"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let relativeCwdError = try XCTUnwrap(relativeCwd["error"] as? [String: Any])
        XCTAssertEqual(relativeCwdError["code"] as? Int, -32600)
        XCTAssertEqual(
            relativeCwdError["message"] as? String,
            "Invalid request: AbsolutePathBuf deserialized without a base path"
        )

        let sizeWithoutTty = try appServerResponse(
            #"{"id":4,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","size":{"rows":24,"cols":80}}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let sizeWithoutTtyError = try XCTUnwrap(sizeWithoutTty["error"] as? [String: Any])
        XCTAssertEqual(sizeWithoutTtyError["code"] as? Int, -32602)
        XCTAssertEqual(sizeWithoutTtyError["message"] as? String, "process/spawn size requires tty: true")

        let negativeTimeout = try appServerResponse(
            #"{"id":5,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","timeoutMs":-1}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let negativeTimeoutError = try XCTUnwrap(negativeTimeout["error"] as? [String: Any])
        XCTAssertEqual(negativeTimeoutError["code"] as? Int, -32602)
        XCTAssertEqual(
            negativeTimeoutError["message"] as? String,
            "process/spawn timeoutMs must be non-negative, got -1"
        )

        let zeroSize = try appServerResponse(
            #"{"id":6,"method":"process/spawn","params":{"command":["echo"],"processHandle":"proc-1","cwd":"\#(temp.url.path)","tty":true,"size":{"rows":0,"cols":80}}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let zeroSizeError = try XCTUnwrap(zeroSize["error"] as? [String: Any])
        XCTAssertEqual(zeroSizeError["code"] as? Int, -32602)
        XCTAssertEqual(zeroSizeError["message"] as? String, "process size rows and cols must be greater than 0")
    }

    func testProcessSpawnRunsProcessAndEmitsExitNotification() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sh","-c","printf out; printf err >&2"],"processHandle":"proc-live","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)

        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        XCTAssertEqual(notification["method"] as? String, "process/exited")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-live")
        XCTAssertEqual(params["exitCode"] as? Int, 0)
        XCTAssertEqual(params["stdout"] as? String, "out")
        XCTAssertEqual(params["stderr"] as? String, "err")
        XCTAssertEqual(params["stdoutCapReached"] as? Bool, false)
        XCTAssertEqual(params["stderrCapReached"] as? Bool, false)

        let nullTimeoutMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"process/spawn","params":{"command":["/bin/echo","hi"],"processHandle":"proc-null-timeout","cwd":"\#(cwd.url.path)","timeoutMs":null}}"#.utf8
        )))
        XCTAssertEqual((nullTimeoutMessages[0]["result"] as? [String: Any])?.isEmpty, true)

        let nullTimeoutNotificationData = try await nextNotificationPayload(notificationCapture)
        let nullTimeoutNotification = try XCTUnwrap(decodeMessages(nullTimeoutNotificationData).first)
        let nullTimeoutParams = try XCTUnwrap(nullTimeoutNotification["params"] as? [String: Any])
        XCTAssertEqual(nullTimeoutParams["processHandle"] as? String, "proc-null-timeout")
        XCTAssertEqual(nullTimeoutParams["exitCode"] as? Int, 0)
        XCTAssertEqual(nullTimeoutParams["stdout"] as? String, "hi\n")
    }

    func testProcessSpawnInheritsServerEnvironmentAndAppliesOverrides() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(
                codexHome: temp.url,
                environment: [
                    "CODEX_SWIFT_PROCESS_TEST": "server-value",
                    "CODEX_SWIFT_PROCESS_UNSET": "server-value"
                ]
            ),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/usr/bin/env"],"processHandle":"proc-env","cwd":"\#(cwd.url.path)","env":{"CODEX_SWIFT_PROCESS_TEST":"override-value","CODEX_SWIFT_PROCESS_UNSET":null}}}"#.utf8
        )))
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)

        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-env")
        XCTAssertEqual(params["exitCode"] as? Int, 0)
        let stdout = try XCTUnwrap(params["stdout"] as? String)
        let environmentLines = Set(stdout.split(separator: "\n").map(String.init))
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            XCTAssertTrue(environmentLines.contains("HOME=\(home)"))
        }
        XCTAssertTrue(environmentLines.contains("CODEX_SWIFT_PROCESS_TEST=override-value"))
        XCTAssertFalse(environmentLines.contains { $0.hasPrefix("CODEX_SWIFT_PROCESS_UNSET=") })
        XCTAssertEqual(params["stderr"] as? String, "")
    }

    func testProcessSpawnCanStreamOutputDeltas() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sh","-c","printf streamed"],"processHandle":"proc-stream","cwd":"\#(cwd.url.path)","streamStdoutStderr":true}}"#.utf8
        )))

        let firstNotificationData = try await nextNotificationPayload(notificationCapture)
        let secondNotificationData = try await nextNotificationPayload(notificationCapture)
        let firstNotification = try XCTUnwrap(decodeMessages(firstNotificationData).first)
        let secondNotification = try XCTUnwrap(decodeMessages(secondNotificationData).first)
        let notifications = [firstNotification, secondNotification]
        let output = try XCTUnwrap(notifications.first { $0["method"] as? String == "process/outputDelta" })
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processHandle"] as? String, "proc-stream")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "streamed"
        )

        let exited = try XCTUnwrap(notifications.first { $0["method"] as? String == "process/exited" })
        let exitedParams = try XCTUnwrap(exited["params"] as? [String: Any])
        XCTAssertEqual(exitedParams["stdout"] as? String, "")
        XCTAssertEqual(exitedParams["stderr"] as? String, "")
    }

    func testProcessSpawnStreamsOutputBeforeProcessExit() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sh","-c","printf live-proc; sleep 5"],"processHandle":"proc-live-stream","cwd":"\#(cwd.url.path)","streamStdoutStderr":true}}"#.utf8
        )))

        let outputData = try await nextNotificationPayload(notificationCapture, timeoutNanoseconds: 1_000_000_000)
        let output = try XCTUnwrap(decodeMessages(outputData).first)
        XCTAssertEqual(output["method"] as? String, "process/outputDelta")
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processHandle"] as? String, "proc-live-stream")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "live-proc"
        )

        let kill = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/kill","params":{"processHandle":"proc-live-stream"}}"#.utf8
        )))
        XCTAssertEqual((kill["result"] as? [String: Any])?.isEmpty, true)
    }

    func testProcessWriteStdinFeedsStreamingProcessAndCanCloseStdin() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/cat"],"processHandle":"proc-stdin","cwd":"\#(cwd.url.path)","streamStdin":true}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let write = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/writeStdin","params":{"processHandle":"proc-stdin","deltaBase64":"aGVsbG8=","closeStdin":true}}"#.utf8
        )))
        XCTAssertEqual((write["result"] as? [String: Any])?.isEmpty, true)

        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        XCTAssertEqual(notification["method"] as? String, "process/exited")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-stdin")
        XCTAssertEqual(params["exitCode"] as? Int, 0)
        XCTAssertEqual(params["stdout"] as? String, "hello")
        XCTAssertEqual(params["stderr"] as? String, "")
    }

    func testProcessWriteStdinRejectsActiveProcessWithoutStdinStreaming() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-no-stdin","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let write = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/writeStdin","params":{"processHandle":"proc-no-stdin","deltaBase64":"aGk="}}"#.utf8
        )))
        let writeError = try XCTUnwrap(write["error"] as? [String: Any])
        XCTAssertEqual(writeError["code"] as? Int, -32600)
        XCTAssertEqual(writeError["message"] as? String, "stdin streaming is not enabled for this process")

        let kill = try decode(processor.processLine(Data(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-no-stdin"}}"#.utf8
        )))
        XCTAssertEqual((kill["result"] as? [String: Any])?.isEmpty, true)
    }

    func testProcessResizeActiveNonPtyReportsRustError() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-resize","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let resize = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/resizePty","params":{"processHandle":"proc-resize","size":{"rows":24,"cols":80}}}"#.utf8
        )))
        let resizeError = try XCTUnwrap(resize["error"] as? [String: Any])
        XCTAssertEqual(resizeError["code"] as? Int, -32600)
        XCTAssertEqual(resizeError["message"] as? String, "failed to resize PTY: process is not attached to a PTY")

        let kill = try decode(processor.processLine(Data(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-resize"}}"#.utf8
        )))
        XCTAssertEqual((kill["result"] as? [String: Any])?.isEmpty, true)
    }

    func testProcessSpawnTtyResizesActiveTerminal() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-pty","cwd":"\#(cwd.url.path)","tty":true,"size":{"rows":18,"cols":46}}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let resize = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/resizePty","params":{"processHandle":"proc-pty","size":{"rows":24,"cols":80}}}"#.utf8
        )))
        XCTAssertEqual((resize["result"] as? [String: Any])?.isEmpty, true)

        let kill = try decode(processor.processLine(Data(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-pty"}}"#.utf8
        )))
        XCTAssertEqual((kill["result"] as? [String: Any])?.isEmpty, true)
    }

    func testProcessSpawnTtyReportsPtyOutput() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sh","-c","printf pty-proc"],"processHandle":"proc-pty-output","cwd":"\#(cwd.url.path)","tty":true,"size":{"rows":24,"cols":80}}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let firstData = try await nextNotificationPayload(notificationCapture)
        let secondData = try await nextNotificationPayload(notificationCapture)
        let notifications = try decodeMessages(firstData) + decodeMessages(secondData)
        let output = try XCTUnwrap(notifications.first { $0["method"] as? String == "process/outputDelta" })
        let outputParams = try XCTUnwrap(output["params"] as? [String: Any])
        XCTAssertEqual(outputParams["processHandle"] as? String, "proc-pty-output")
        XCTAssertEqual(outputParams["stream"] as? String, "stdout")
        XCTAssertEqual(
            String(data: Data(base64Encoded: try XCTUnwrap(outputParams["deltaBase64"] as? String)) ?? Data(), encoding: .utf8),
            "pty-proc"
        )

        let exited = try XCTUnwrap(notifications.first { $0["method"] as? String == "process/exited" })
        let params = try XCTUnwrap(exited["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-pty-output")
        XCTAssertEqual(params["exitCode"] as? Int, 0)
        XCTAssertEqual(params["stdout"] as? String, "")
        XCTAssertEqual(params["stdoutCapReached"] as? Bool, false)
        XCTAssertEqual(params["stderr"] as? String, "")
        XCTAssertEqual(params["stderrCapReached"] as? Bool, false)
    }

    func testProcessSpawnTimeoutReportsRustExitCode() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decode(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-timeout","cwd":"\#(cwd.url.path)","timeoutMs":10}}"#.utf8
        )))
        XCTAssertEqual((spawn["result"] as? [String: Any])?.isEmpty, true)

        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        XCTAssertEqual(notification["method"] as? String, "process/exited")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-timeout")
        XCTAssertEqual(params["exitCode"] as? Int, 124)
    }

    func testProcessSpawnRejectsDuplicateHandleAndKillTerminatesActiveProcess() async throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in
                await notificationCapture.append(data)
            },
            experimentalAPIEnabled: true
        )

        let spawn = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-kill","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        XCTAssertEqual((spawn[0]["result"] as? [String: Any])?.isEmpty, true)

        let duplicate = try decode(processor.processLine(Data(
            #"{"id":2,"method":"process/spawn","params":{"command":["/bin/sleep","5"],"processHandle":"proc-kill","cwd":"\#(cwd.url.path)"}}"#.utf8
        )))
        let duplicateError = try XCTUnwrap(duplicate["error"] as? [String: Any])
        XCTAssertEqual(duplicateError["code"] as? Int, -32600)
        XCTAssertEqual(duplicateError["message"] as? String, #"duplicate active process handle: "proc-kill""#)

        let kill = try decode(processor.processLine(Data(
            #"{"id":3,"method":"process/kill","params":{"processHandle":"proc-kill"}}"#.utf8
        )))
        XCTAssertEqual((kill["result"] as? [String: Any])?.isEmpty, true)

        let notificationData = try await nextNotificationPayload(notificationCapture)
        let notification = try XCTUnwrap(decodeMessages(notificationData).first)
        XCTAssertEqual(notification["method"] as? String, "process/exited")
        let params = try XCTUnwrap(notification["params"] as? [String: Any])
        XCTAssertEqual(params["processHandle"] as? String, "proc-kill")
    }

    func testProcessFollowUpsValidateWriteAndResizeParams() throws {
        let temp = try TemporaryDirectory()

        let emptyWrite = try appServerResponse(
            #"{"id":1,"method":"process/writeStdin","params":{"processHandle":"proc-1"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let emptyWriteError = try XCTUnwrap(emptyWrite["error"] as? [String: Any])
        XCTAssertEqual(emptyWriteError["code"] as? Int, -32602)
        XCTAssertEqual(emptyWriteError["message"] as? String, "process/writeStdin requires deltaBase64 or closeStdin")

        let badBase64 = try appServerResponse(
            #"{"id":2,"method":"process/writeStdin","params":{"processHandle":"proc-1","deltaBase64":"%%%bad%%%"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )
        let badBase64Error = try XCTUnwrap(badBase64["error"] as? [String: Any])
        XCTAssertEqual(badBase64Error["code"] as? Int, -32602)
        XCTAssertEqual(badBase64Error["message"] as? String, "invalid deltaBase64: invalid base64 data")

        let zeroSize = try appServerResponse(
            #"{"id":3,"method":"process/resizePty","params":{"processHandle":"proc-1","size":{"rows":0,"cols":80}}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
        initializeFirst: Bool = true,
        experimentalAPIEnabled: Bool = false
    ) throws -> [String: Any] {
        try appServerResponse(
            line,
            configuration: testConfiguration(codexHome: codexHome),
            initializeFirst: initializeFirst,
            experimentalAPIEnabled: experimentalAPIEnabled
        )
    }

    private func appServerResponse(
        _ line: String,
        configuration: CodexAppServerConfiguration,
        initializeFirst: Bool = true,
        experimentalAPIEnabled: Bool = false
    ) throws -> [String: Any] {
        let processor = CodexAppServerMessageProcessor(configuration: configuration)
        if initializeFirst {
            let capabilities = experimentalAPIEnabled ? #","capabilities":{"experimentalApi":true}"# : ""
            _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}\#(capabilities)}}"#.utf8)))
        }
        return try decode(processor.processLine(Data(line.utf8)))
    }

    private func initializedProcessor(
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink? = nil,
        experimentalAPIEnabled: Bool = false
    ) throws -> CodexAppServerMessageProcessor {
        let processor = CodexAppServerMessageProcessor(configuration: configuration, notificationSink: notificationSink)
        let capabilities = experimentalAPIEnabled ? #","capabilities":{"experimentalApi":true}"# : ""
        _ = try decode(processor.processLine(Data(#"{"id":"init","method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}\#(capabilities)}}"#.utf8)))
        return processor
    }

    private func nextNotificationPayload(
        _ capture: AppServerNotificationCapture,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws -> Data {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if let payload = await capture.popPayload() {
                return payload
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw AppServerTestTimeout()
    }

    private func testConfiguration(
        codexHome: URL,
        cwd: URL? = nil,
        requiresOpenAIAuth: Bool = true,
        feedback: CodexFeedback = CodexFeedback(),
        feedbackUploadTransport: any FeedbackUploadTransport = URLSessionFeedbackUploadTransport(),
        acceptedLineAnalyticsUploader: any AcceptedLineAnalyticsUploading = DisabledAcceptedLineAnalyticsUploader(),
        accountRateLimitsFetcher: any AccountRateLimitsFetching = URLSessionAccountRateLimitsFetcher(),
        addCreditsNudgeEmailSender: any AddCreditsNudgeEmailSending = URLSessionAddCreditsNudgeEmailSender(),
        authRefreshTransport: AppServerAuthRefreshTransport? = nil,
        authDeviceCodeTransport: ChatGPTDeviceCodeLoginTransport? = nil,
        environment: [String: String] = [:],
        mcpHTTPTransport: @escaping AppServerMcpHTTPTransport = CodexAppServer.defaultMcpHTTPTransport,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter,
        configLayerOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides()
    ) -> CodexAppServerConfiguration {
        var mergedEnvironment = [
            CodexConfigLayerLoader.managedConfigEnvironmentVariable: codexHome
                .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                .path
        ]
        mergedEnvironment.merge(environment) { _, new in new }
        return CodexAppServerConfiguration(
            codexHome: codexHome,
            cwd: cwd ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            requiresOpenAIAuth: requiresOpenAIAuth,
            environment: mergedEnvironment,
            feedback: feedback,
            feedbackUploadTransport: feedbackUploadTransport,
            acceptedLineAnalyticsUploader: acceptedLineAnalyticsUploader,
            accountRateLimitsFetcher: accountRateLimitsFetcher,
            addCreditsNudgeEmailSender: addCreditsNudgeEmailSender,
            authRefreshTransport: authRefreshTransport,
            authDeviceCodeTransport: authDeviceCodeTransport,
            mcpHTTPTransport: mcpHTTPTransport,
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

    private func fakeJWT(email: String, plan: String, accountID: String = "acct-test") throws -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": plan,
                "chatgpt_account_id": accountID
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

    private func makeGitMarketplaceRemote(
        named name: String,
        marker: String,
        in parent: URL
    ) throws -> URL {
        try makeGitMarketplaceSourceAndRemote(named: name, marker: marker, in: parent).remote
    }

    private func makeGitMarketplaceSourceAndRemote(
        named name: String,
        marker: String,
        in parent: URL
    ) throws -> (source: URL, remote: URL, branch: String) {
        let source = try makeLocalMarketplaceRootWithPlugin(named: name, pluginName: "sample", in: parent)
        try marker.write(
            to: source.appendingPathComponent("plugins/sample/marker.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["init"], cwd: source)
        try runGit(["config", "user.name", "Test User"], cwd: source)
        try runGit(["config", "user.email", "test@example.com"], cwd: source)
        try runGit(["add", "."], cwd: source)
        try runGit(["commit", "-m", "Initial marketplace"], cwd: source)
        let remote = parent.appendingPathComponent("marketplace-remote.git", isDirectory: true)
        try runGit(["init", "--bare", remote.path], cwd: parent)
        try runGit(["remote", "add", "origin", remote.path], cwd: source)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: source)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["push", "-u", "origin", branch], cwd: source)
        return (source, remote, branch)
    }

    private func writePluginFixture(
        root: URL,
        relativePath: String,
        pluginName: String,
        version: String?,
        marker: String
    ) throws {
        let pluginRoot = root.appendingPathComponent(relativePath, isDirectory: true)
        let pluginManifestDirectory = pluginRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginManifestDirectory, withIntermediateDirectories: true)
        var manifest: [String: Any] = [
            "name": pluginName,
            "description": "Fixture plugin"
        ]
        if let version {
            manifest["version"] = version
        }
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: pluginManifestDirectory.appendingPathComponent("plugin.json", isDirectory: false))
        try marker.write(
            to: pluginRoot.appendingPathComponent("marker.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
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

private actor AppServerRecordingAcceptedLineAnalyticsUploader: AcceptedLineAnalyticsUploading {
    private(set) var requests: [AcceptedLineAnalyticsUploadRequest] = []

    func upload(_ request: AcceptedLineAnalyticsUploadRequest) async throws {
        requests.append(request)
    }
}

private actor AppServerRequestCapture {
    struct Request: Equatable {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let body: String?
    }

    private(set) var requests: [Request] = []

    func append(_ request: URLRequest) {
        requests.append(Request(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody.map { String(decoding: $0, as: UTF8.self) }
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

private final class MCPHTTPTransportCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func append(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private actor AppServerMcpOAuthLoginCapture {
    private(set) var requests: [AppServerMcpOAuthLoginStartRequest] = []

    func append(_ request: AppServerMcpOAuthLoginStartRequest) {
        requests.append(request)
    }
}

private struct AppServerTestTimeout: Error {}

private actor AppServerDeviceCodeProbe {
    enum Scenario {
        case success(idToken: String)
        case userCodeFailure(statusCode: Int)
        case pending
    }

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func handle(_ request: URLRequest) throws -> AuthRefreshHTTPResponse {
        let url = request.url?.absoluteString ?? ""
        switch url {
        case "https://issuer.example/api/accounts/deviceauth/usercode":
            if case let .userCodeFailure(statusCode) = scenario {
                return AuthRefreshHTTPResponse(statusCode: statusCode, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data(#"{"device_auth_id":"device-auth-123","user_code":"CODE-12345","interval":"60"}"#.utf8)
            )

        case "https://issuer.example/api/accounts/deviceauth/token":
            if case .pending = scenario {
                return AuthRefreshHTTPResponse(statusCode: 404, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data(#"{"authorization_code":"poll-code-321","code_challenge":"code-challenge-321","code_verifier":"code-verifier-321"}"#.utf8)
            )

        case "https://issuer.example/oauth/token":
            guard case let .success(idToken) = scenario else {
                return AuthRefreshHTTPResponse(statusCode: 500, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "id_token": "\(idToken)",
                  "access_token": "access-token-123",
                  "refresh_token": "refresh-token-123"
                }
                """.utf8)
            )

        default:
            return AuthRefreshHTTPResponse(statusCode: 404, body: Data())
        }
    }
}

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

    func popPayload() -> Data? {
        if !payloads.isEmpty {
            return payloads.removeFirst()
        }
        return nil
    }

    func nextPayload() async -> Data {
        if let payload = popPayload() {
            return payload
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

    private let result: AccountRateLimitsResult
    private(set) var requests: [Request] = []

    init(snapshot: RateLimitSnapshot) {
        self.result = AccountRateLimitsResult(rateLimits: snapshot)
    }

    init(result: AccountRateLimitsResult) {
        self.result = result
    }

    func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> AccountRateLimitsResult {
        requests.append(Request(baseURL: baseURL, accessToken: accessToken, accountID: accountID))
        return result
    }
}

private actor AppServerRecordingAddCreditsNudgeEmailSender: AddCreditsNudgeEmailSending {
    struct Request: Equatable {
        let baseURL: String
        let accessToken: String
        let accountID: String
        let creditType: AddCreditsNudgeCreditType
    }

    private let result: Result<AddCreditsNudgeEmailStatus, Error>
    private(set) var requests: [Request] = []

    init(status: AddCreditsNudgeEmailStatus) {
        self.result = .success(status)
    }

    init(error: Error) {
        self.result = .failure(error)
    }

    func send(
        baseURL: String,
        accessToken: String,
        accountID: String,
        creditType: AddCreditsNudgeCreditType
    ) async throws -> AddCreditsNudgeEmailStatus {
        requests.append(Request(
            baseURL: baseURL,
            accessToken: accessToken,
            accountID: accountID,
            creditType: creditType
        ))
        return try result.get()
    }
}

private struct AddCreditsNudgeEmailTestError: Error, CustomStringConvertible {
    var description: String { "boom" }
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
