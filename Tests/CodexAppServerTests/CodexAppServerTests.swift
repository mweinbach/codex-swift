@testable import CodexAppServer
import CodexCore
import Foundation
import SQLite3
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

    func testThreadStartEphemeralRemainsPathlessLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        retainedTemporaryDirectories.append(cwd)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"model":"gpt-test","modelProvider":"mock_provider","cwd":"\#(cwd.url.path)","ephemeral":true}}"#.utf8)))

        XCTAssertEqual(messages.count, 2)
        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        XCTAssertEqual(thread["sessionId"] as? String, threadID)
        XCTAssertEqual(thread["ephemeral"] as? Bool, true)
        XCTAssertEqual(thread["path"] as? NSNull, NSNull())
        XCTAssertEqual(thread["preview"] as? String, "")
        XCTAssertEqual(thread["modelProvider"] as? String, "mock_provider")
        XCTAssertEqual(thread["cwd"] as? String, cwd.url.path)
        XCTAssertEqual(thread["source"] as? String, "appServer")
        XCTAssertEqual((thread["turns"] as? [Any])?.count, 0)

        XCTAssertEqual(messages[1]["method"] as? String, "thread/started")
        let notificationParams = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        let notificationThread = try XCTUnwrap(notificationParams["thread"] as? [String: Any])
        XCTAssertEqual(notificationThread["id"] as? String, threadID)
        XCTAssertEqual(notificationThread["ephemeral"] as? Bool, true)
        XCTAssertEqual(notificationThread["path"] as? NSNull, NSNull())
        XCTAssertNil(try RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
    }

    func testThreadStartWithWorkspaceWritePersistsTrustedProjectLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        retainedTemporaryDirectories.append(cwd)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        _ = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"cwd":"\#(cwd.url.path)","sandbox":"workspace-write"}}"#.utf8)))

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[projects.\"\(cwd.url.resolvingSymlinksInPath().standardizedFileURL.path)\"]"))
        XCTAssertTrue(config.contains(#"trust_level = "trusted""#))
    }

    func testThreadStartWithNestedGitCwdTrustsRepoRootLikeRust() throws {
        let temp = try TemporaryDirectory()
        let repoRoot = try TemporaryDirectory()
        retainedTemporaryDirectories.append(repoRoot)
        try runGit(["init"], cwd: repoRoot.url)
        let nested = repoRoot.url.appendingPathComponent("nested/project", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        _ = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"cwd":"\#(nested.path)","sandbox":"workspace-write"}}"#.utf8)))

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        let trustedRoot = repoRoot.url.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(config.contains("[projects.\"\(trustedRoot)\"]"))
        XCTAssertFalse(config.contains("[projects.\"\(nested.resolvingSymlinksInPath().standardizedFileURL.path)\"]"))
        XCTAssertTrue(config.contains(#"trust_level = "trusted""#))
    }

    func testThreadStartWithReadOnlySandboxDoesNotPersistProjectTrustLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        retainedTemporaryDirectories.append(cwd)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        _ = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"cwd":"\#(cwd.url.path)","sandbox":"read-only"}}"#.utf8)))

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("config.toml").path))
    }

    func testThreadStartWithExplicitUntrustedProjectDoesNotPromoteTrustLikeRust() throws {
        let temp = try TemporaryDirectory()
        let repoRoot = try TemporaryDirectory()
        retainedTemporaryDirectories.append(repoRoot)
        try runGit(["init"], cwd: repoRoot.url)
        let nested = repoRoot.url.appendingPathComponent("nested/project", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let trustedRoot = repoRoot.url.resolvingSymlinksInPath().standardizedFileURL.path
        try """
        [projects."\(trustedRoot)"]
        trust_level = "untrusted"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        _ = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"cwd":"\#(nested.path)","sandbox":"workspace-write"}}"#.utf8)))

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[projects.\"\(trustedRoot)\"]"))
        XCTAssertTrue(config.contains(#"trust_level = "untrusted""#))
        XCTAssertFalse(config.contains(#"trust_level = "trusted""#))
    }

    func testThreadStartFailsWhenRequiredMCPServerCommandCannotInitializeLikeRust() throws {
        let temp = try TemporaryDirectory()
        try writeRequiredBrokenMCPConfig(codexHome: temp.url)
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            environment: ["PATH": ""]
        ))

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 1)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        let message = try XCTUnwrap(error["message"] as? String)
        XCTAssertTrue(message.contains("required MCP servers failed to initialize: required_broken"))
        XCTAssertTrue(message.contains("codex-definitely-not-a-real-binary"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent("sessions", isDirectory: true).path
        ))
    }

    func testThreadResumeFailsWhenRequiredMCPServerCommandCannotInitializeLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            environment: ["PATH": ""]
        ))
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let startedThread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(startedThread["id"] as? String)
        try writeRequiredBrokenMCPConfig(codexHome: temp.url)

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))

        try assertRequiredBrokenMCPStartupError(messages)
    }

    func testThreadForkFailsWhenRequiredMCPServerCommandCannotInitializeLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            environment: ["PATH": ""]
        ))
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let startedThread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(startedThread["id"] as? String)
        try writeRequiredBrokenMCPConfig(codexHome: temp.url)

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"thread/fork","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))

        try assertRequiredBrokenMCPStartupError(messages)
    }

    func testThreadPersistExtendedHistoryEmitsDeprecationNoticeLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"persistExtendedHistory":true}}"#.utf8
        )))

        XCTAssertEqual(startMessages.count, 3)
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let startedThread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(startedThread["id"] as? String)
        try assertPersistExtendedHistoryDeprecationNotice(startMessages[1])
        XCTAssertEqual(startMessages[2]["method"] as? String, "thread/started")

        let resumeMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"thread/resume","params":{"threadId":"\#(threadID)","persistExtendedHistory":true}}"#.utf8
        )))

        XCTAssertEqual(resumeMessages.count, 2)
        XCTAssertNotNil(resumeMessages[0]["result"] as? [String: Any])
        try assertPersistExtendedHistoryDeprecationNotice(resumeMessages[1])

        let forkMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":3,"method":"thread/fork","params":{"threadId":"\#(threadID)","persistExtendedHistory":true}}"#.utf8
        )))

        XCTAssertEqual(forkMessages.count, 3)
        XCTAssertNotNil(forkMessages[0]["result"] as? [String: Any])
        try assertPersistExtendedHistoryDeprecationNotice(forkMessages[1])
        XCTAssertEqual(forkMessages[2]["method"] as? String, "thread/started")
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
            (#"{"persistFullHistory":true}"#, "thread/start.persistFullHistory"),
            (#"{"persistExtendedHistory":true}"#, "thread/start.persistFullHistory")
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

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"experimentalRawEvents":false,"persistFullHistory":false,"persistExtendedHistory":false}}"#.utf8)))

        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertNil(messages[0]["error"])
    }

    func testThreadStartRejectsUnknownEnvironmentBeforeCreatingThreadLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"environments":[{"environment_id":"missing","cwd":"\#(temp.url.path)"}]}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 1)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "unknown turn environment id `missing`")
        let page = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            defaultProvider: "openai"
        )
        XCTAssertEqual(page.items.count, 0)
    }

    func testThreadStartRejectsDuplicateEnvironmentBeforeCreatingThreadLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"environments":[{"environment_id":"local","cwd":"\#(temp.url.path)"},{"environment_id":"local","cwd":"\#(temp.url.path)"}]}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 1)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "duplicate turn environment id `local`")
        let page = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            defaultProvider: "openai"
        )
        XCTAssertEqual(page.items.count, 0)
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

    func testGetConversationSummaryResolvesRelativeRolloutPathFromCodexHome() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))

        let newConversation = try decode(processor.processLine(Data(#"{"id":1,"method":"newConversation","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let newResult = try XCTUnwrap(newConversation["result"] as? [String: Any])
        let conversationID = try XCTUnwrap(newResult["conversationId"] as? String)
        let rolloutPath = URL(fileURLWithPath: try XCTUnwrap(newResult["rolloutPath"] as? String)).standardizedFileURL.path
        let codexHomePath = temp.url.standardizedFileURL.path
        XCTAssertTrue(rolloutPath.hasPrefix(codexHomePath + "/"))
        let relativePath = String(rolloutPath.dropFirst(codexHomePath.count + 1))

        let send = try decode(processor.processLine(Data(#"{"id":2,"method":"sendUserMessage","params":{"conversationId":"\#(conversationID)","items":[{"type":"text","data":{"text":"Relative summary"}}]}}"#.utf8)))
        XCTAssertTrue(try XCTUnwrap(send["result"] as? [String: Any]).isEmpty)

        let response = try decode(processor.processLine(Data(#"{"id":3,"method":"getConversationSummary","params":{"rolloutPath":"\#(relativePath)"}}"#.utf8)))
        let summary = try XCTUnwrap((response["result"] as? [String: Any])?["summary"] as? [String: Any])
        XCTAssertEqual(summary["conversationId"] as? String, conversationID)
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(summary["path"] as? String)).standardizedFileURL.path,
            rolloutPath
        )
        XCTAssertEqual(summary["preview"] as? String, "Relative summary")
        XCTAssertEqual(summary["modelProvider"] as? String, "mock_provider")
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

        XCTAssertEqual(messages.count, 3)
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
        XCTAssertEqual(messages[2]["method"] as? String, "thread/status/changed")
        let statusParams = try XCTUnwrap(messages[2]["params"] as? [String: Any])
        XCTAssertEqual(statusParams["threadId"] as? String, threadID)
        let status = try XCTUnwrap(statusParams["status"] as? [String: Any])
        XCTAssertEqual(status["type"] as? String, "active")
        XCTAssertEqual(status["activeFlags"] as? [String], [])

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

    func testTurnStartRejectsUnknownEnvironmentBeforeStartingTurnLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Hello"}],"environments":[{"environment_id":"missing","cwd":"\#(temp.url.path)"}]}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 1)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "unknown turn environment id `missing`")
    }

    func testTurnStartRejectsDuplicateEnvironmentBeforeStartingTurnLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Hello"}],"environments":[{"environment_id":"local","cwd":"\#(temp.url.path)"},{"environment_id":"local","cwd":"\#(temp.url.path)"}]}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 1)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "duplicate turn environment id `local`")
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

    func testTurnStartRejectsOversizedV2TextInputLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let oversized = String(repeating: "x", count: (1 << 20) + 1)
        let request: [String: Any] = [
            "id": 2,
            "method": "turn/start",
            "params": [
                "threadId": threadID,
                "input": [
                    ["type": "text", "text": oversized]
                ]
            ]
        ]

        let response = try decode(processor.processLine(try JSONSerialization.data(withJSONObject: request)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual(error["message"] as? String, "Input exceeds the maximum length of 1048576 characters.")
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["input_error_code"] as? String, "input_too_large")
        XCTAssertEqual(data["max_chars"] as? Int, 1 << 20)
        XCTAssertEqual(data["actual_chars"] as? Int, (1 << 20) + 1)
    }

    func testTurnStartRejectsOversizedV2TextInputBeforeThreadLookupLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let oversized = String(repeating: "x", count: (1 << 20) + 1)
        let request: [String: Any] = [
            "id": 1,
            "method": "turn/start",
            "params": [
                "threadId": "not-a-thread-id",
                "input": [
                    ["type": "text", "text": oversized]
                ]
            ]
        ]

        let response = try decode(processor.processLine(try JSONSerialization.data(withJSONObject: request)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual(error["message"] as? String, "Input exceeds the maximum length of 1048576 characters.")
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["input_error_code"] as? String, "input_too_large")
        XCTAssertEqual(data["max_chars"] as? Int, 1 << 20)
        XCTAssertEqual(data["actual_chars"] as? Int, (1 << 20) + 1)
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

    func testTurnSteerRejectsOversizedV2TextInputLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let turnMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Start"}]}}"#.utf8
        )))
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)
        let first = String(repeating: "x", count: 1 << 19)
        let second = String(repeating: "y", count: (1 << 19) + 1)
        let request: [String: Any] = [
            "id": 3,
            "method": "turn/steer",
            "params": [
                "threadId": threadID,
                "expectedTurnId": turnID,
                "input": [
                    ["type": "text", "text": first],
                    ["type": "image", "url": "https://example.test/ignored-for-limit.png"],
                    ["type": "text", "text": second]
                ]
            ]
        ]

        let response = try decode(processor.processLine(try JSONSerialization.data(withJSONObject: request)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual(error["message"] as? String, "Input exceeds the maximum length of 1048576 characters.")
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["input_error_code"] as? String, "input_too_large")
        XCTAssertEqual(data["max_chars"] as? Int, 1 << 20)
        XCTAssertEqual(data["actual_chars"] as? Int, (1 << 20) + 1)
    }

    func testTurnSteerRejectsOversizedV2TextInputBeforeActiveTurnLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let oversized = String(repeating: "x", count: (1 << 20) + 1)
        let request: [String: Any] = [
            "id": 2,
            "method": "turn/steer",
            "params": [
                "threadId": threadID,
                "expectedTurnId": "turn-does-not-exist",
                "input": [
                    ["type": "text", "text": oversized]
                ]
            ]
        ]

        let response = try decode(processor.processLine(try JSONSerialization.data(withJSONObject: request)))

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual(error["message"] as? String, "Input exceeds the maximum length of 1048576 characters.")
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["input_error_code"] as? String, "input_too_large")
        XCTAssertEqual(data["max_chars"] as? Int, 1 << 20)
        XCTAssertEqual(data["actual_chars"] as? Int, (1 << 20) + 1)
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

        XCTAssertEqual(messages.count, 3)
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
        XCTAssertEqual(messages[2]["method"] as? String, "thread/status/changed")
        let statusParams = try XCTUnwrap(messages[2]["params"] as? [String: Any])
        XCTAssertEqual(statusParams["threadId"] as? String, threadID)
        let status = try XCTUnwrap(statusParams["status"] as? [String: Any])
        XCTAssertEqual(status["type"] as? String, "idle")

        let resume = try decode(processor.processLine(Data(#"{"id":4,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8)))
        let resumeResult = try XCTUnwrap(resume["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        let turns = try XCTUnwrap(resumedThread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0]["status"] as? String, "interrupted")
    }

    func testThreadStatusChangedCanBeOptedOut() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            optOutNotificationMethods: ["thread/status/changed"]
        )
        let startMessages = try decodeMessages(processor.processLine(Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)
        let turnMessages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"turn/start","params":{"threadId":"\#(threadID)","input":[{"type":"text","text":"Interrupt me"}]}}"#.utf8)))
        XCTAssertEqual(turnMessages.count, 2)
        XCTAssertEqual(turnMessages[1]["method"] as? String, "turn/started")
        XCTAssertFalse(turnMessages.contains { $0["method"] as? String == "thread/status/changed" })
        let turnResult = try XCTUnwrap(turnMessages[0]["result"] as? [String: Any])
        let turn = try XCTUnwrap(turnResult["turn"] as? [String: Any])
        let turnID = try XCTUnwrap(turn["id"] as? String)

        let interruptMessages = try decodeMessages(processor.processLine(Data(#"{"id":3,"method":"turn/interrupt","params":{"threadId":"\#(threadID)","turnId":"\#(turnID)"}}"#.utf8)))

        XCTAssertEqual(interruptMessages.count, 2)
        XCTAssertEqual(interruptMessages[1]["method"] as? String, "turn/completed")
        XCTAssertFalse(interruptMessages.contains { $0["method"] as? String == "thread/status/changed" })
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

    func testRuntimePlanUpdateEventEmitsRustPlanNotification() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .planUpdate(UpdatePlanArguments(
                explanation: "working the checklist",
                plan: [
                    PlanItemArgument(step: "inspect Rust", status: .completed),
                    PlanItemArgument(step: "port Swift", status: .inProgress),
                    PlanItemArgument(step: "verify", status: .pending)
                ]
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-2",
            event: .planUpdate(UpdatePlanArguments(explanation: nil, plan: []))
        )

        let messages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["method"] as? String, "turn/plan/updated")
        let params = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["turnId"] as? String, "turn-1")
        XCTAssertEqual(params["explanation"] as? String, "working the checklist")
        let plan = try XCTUnwrap(params["plan"] as? [[String: Any]])
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan[0]["step"] as? String, "inspect Rust")
        XCTAssertEqual(plan[0]["status"] as? String, "completed")
        XCTAssertEqual(plan[1]["step"] as? String, "port Swift")
        XCTAssertEqual(plan[1]["status"] as? String, "inProgress")
        XCTAssertEqual(plan[2]["step"] as? String, "verify")
        XCTAssertEqual(plan[2]["status"] as? String, "pending")

        let empty = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(empty[0]["method"] as? String, "turn/plan/updated")
        let emptyParams = try XCTUnwrap(empty[0]["params"] as? [String: Any])
        XCTAssertEqual(emptyParams["turnId"] as? String, "turn-2")
        XCTAssertTrue(emptyParams["explanation"] is NSNull)
        let emptyPlan = try XCTUnwrap(emptyParams["plan"] as? [[String: Any]])
        XCTAssertTrue(emptyPlan.isEmpty)
    }

    func testRuntimeThreadGoalUpdatedEventEmitsRustNotification() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )
        let eventThreadID = try ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")

        await processor.handleRuntimeEvent(
            threadID: "subscribed-thread",
            turnID: "runtime-turn",
            event: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                threadID: eventThreadID,
                turnID: "goal-turn",
                goal: ThreadGoal(
                    threadID: eventThreadID,
                    objective: "finish the port",
                    status: .active,
                    tokenBudget: 10_000,
                    tokensUsed: 123,
                    timeUsedSeconds: 45,
                    createdAt: 1_700_000_000,
                    updatedAt: 1_700_000_123
                )
            ))
        )

        let messages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["method"] as? String, "thread/goal/updated")
        let params = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, eventThreadID.description)
        XCTAssertEqual(params["turnId"] as? String, "goal-turn")
        let goal = try XCTUnwrap(params["goal"] as? [String: Any])
        XCTAssertEqual(goal["threadId"] as? String, eventThreadID.description)
        XCTAssertEqual(goal["objective"] as? String, "finish the port")
        XCTAssertEqual(goal["status"] as? String, "active")
        XCTAssertEqual(goal["tokenBudget"] as? Int, 10_000)
        XCTAssertEqual(goal["tokensUsed"] as? Int, 123)
        XCTAssertEqual(goal["timeUsedSeconds"] as? Int, 45)
        XCTAssertEqual(goal["createdAt"] as? Int, 1_700_000_000)
        XCTAssertEqual(goal["updatedAt"] as? Int, 1_700_000_123)
    }

    func testRuntimeTokenCountEventEmitsUsageAndRateLimitNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .tokenCount(TokenCountEvent(
                info: TokenUsageInfo(
                    totalTokenUsage: TokenUsage(
                        inputTokens: 100,
                        cachedInputTokens: 25,
                        outputTokens: 40,
                        reasoningOutputTokens: 7,
                        totalTokens: 140
                    ),
                    lastTokenUsage: TokenUsage(
                        inputTokens: 10,
                        cachedInputTokens: 5,
                        outputTokens: 4,
                        reasoningOutputTokens: 1,
                        totalTokens: 14
                    ),
                    modelContextWindow: 200_000
                ),
                rateLimits: RateLimitSnapshot(
                    limitID: "codex",
                    limitName: "codex",
                    primary: RateLimitWindow(usedPercent: 42.4, windowMinutes: 300, resetsAt: 1_700_000_000),
                    secondary: nil,
                    credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "12.50"),
                    planType: .pro,
                    rateLimitReachedType: .workspaceOwnerUsageLimitReached
                )
            ))
        )

        let usageMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(usageMessages.count, 1)
        XCTAssertEqual(usageMessages[0]["method"] as? String, "thread/tokenUsage/updated")
        let usageParams = try XCTUnwrap(usageMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(usageParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(usageParams["turnId"] as? String, "turn-1")
        let tokenUsage = try XCTUnwrap(usageParams["tokenUsage"] as? [String: Any])
        XCTAssertEqual(tokenUsage["modelContextWindow"] as? Int, 200_000)
        let total = try XCTUnwrap(tokenUsage["total"] as? [String: Any])
        XCTAssertEqual(total["totalTokens"] as? Int, 140)
        XCTAssertEqual(total["inputTokens"] as? Int, 100)
        XCTAssertEqual(total["cachedInputTokens"] as? Int, 25)
        XCTAssertEqual(total["outputTokens"] as? Int, 40)
        XCTAssertEqual(total["reasoningOutputTokens"] as? Int, 7)
        let last = try XCTUnwrap(tokenUsage["last"] as? [String: Any])
        XCTAssertEqual(last["totalTokens"] as? Int, 14)
        XCTAssertEqual(last["inputTokens"] as? Int, 10)
        XCTAssertEqual(last["cachedInputTokens"] as? Int, 5)
        XCTAssertEqual(last["outputTokens"] as? Int, 4)
        XCTAssertEqual(last["reasoningOutputTokens"] as? Int, 1)

        let rateLimitMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(rateLimitMessages.count, 1)
        XCTAssertEqual(rateLimitMessages[0]["method"] as? String, "account/rateLimits/updated")
        let rateLimitParams = try XCTUnwrap(rateLimitMessages[0]["params"] as? [String: Any])
        let rateLimits = try XCTUnwrap(rateLimitParams["rateLimits"] as? [String: Any])
        XCTAssertEqual(rateLimits["limitId"] as? String, "codex")
        XCTAssertEqual(rateLimits["limitName"] as? String, "codex")
        XCTAssertEqual(rateLimits["planType"] as? String, "pro")
        XCTAssertEqual(rateLimits["rateLimitReachedType"] as? String, "workspace_owner_usage_limit_reached")
        let primary = try XCTUnwrap(rateLimits["primary"] as? [String: Any])
        XCTAssertEqual(primary["usedPercent"] as? Int, 42)
        XCTAssertEqual(primary["windowDurationMins"] as? Int, 300)
        XCTAssertEqual(primary["resetsAt"] as? Int, 1_700_000_000)
        XCTAssertTrue(rateLimits["secondary"] is NSNull)
        let credits = try XCTUnwrap(rateLimits["credits"] as? [String: Any])
        XCTAssertEqual(credits["hasCredits"] as? Bool, true)
        XCTAssertEqual(credits["unlimited"] as? Bool, false)
        XCTAssertEqual(credits["balance"] as? String, "12.50")
    }

    func testRuntimeItemDeltaEventsEmitRustProgressNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let cases: [(EventMessage, String, [String: Any])] = [
            (
                .agentMessageContentDelta(AgentMessageContentDeltaEvent(
                    threadID: "event-thread",
                    turnID: "event-turn",
                    itemID: "agent-1",
                    delta: "hello"
                )),
                "item/agentMessage/delta",
                ["itemId": "agent-1", "delta": "hello"]
            ),
            (
                .planDelta(PlanDeltaEvent(
                    threadID: "event-thread",
                    turnID: "event-turn",
                    itemID: "plan-1",
                    delta: "next"
                )),
                "item/plan/delta",
                ["itemId": "plan-1", "delta": "next"]
            ),
            (
                .reasoningContentDelta(ReasoningContentDeltaEvent(
                    threadID: "event-thread",
                    turnID: "event-turn",
                    itemID: "reason-1",
                    delta: "summary",
                    summaryIndex: 2
                )),
                "item/reasoning/summaryTextDelta",
                ["itemId": "reason-1", "delta": "summary", "summaryIndex": Int64(2)]
            ),
            (
                .reasoningRawContentDelta(ReasoningRawContentDeltaEvent(
                    threadID: "event-thread",
                    turnID: "event-turn",
                    itemID: "reason-raw-1",
                    delta: "raw",
                    contentIndex: 3
                )),
                "item/reasoning/textDelta",
                ["itemId": "reason-raw-1", "delta": "raw", "contentIndex": Int64(3)]
            ),
            (
                .agentReasoningSectionBreak(AgentReasoningSectionBreakEvent(
                    itemID: "reason-1",
                    summaryIndex: 4
                )),
                "item/reasoning/summaryPartAdded",
                ["itemId": "reason-1", "summaryIndex": Int64(4)]
            )
        ]

        for (event, _, _) in cases {
            await processor.handleRuntimeEvent(threadID: "thread-1", turnID: "turn-1", event: event)
        }

        for (_, method, expected) in cases {
            let messages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["method"] as? String, method)
            let params = try XCTUnwrap(messages[0]["params"] as? [String: Any])
            XCTAssertEqual(params["threadId"] as? String, "thread-1")
            XCTAssertEqual(params["turnId"] as? String, "turn-1")
            for (key, value) in expected {
                switch value {
                case let intValue as Int64:
                    XCTAssertEqual(params[key] as? Int, Int(intValue))
                case let stringValue as String:
                    XCTAssertEqual(params[key] as? String, stringValue)
                default:
                    XCTFail("unsupported expected value for \(key)")
                }
            }
        }
    }

    func testRuntimeCommandAndPatchProgressEventsEmitRustNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .execCommandOutputDelta(ExecCommandOutputDeltaEvent(
                callID: "cmd-1",
                stream: .stdout,
                chunk: [0x48, 0x69, 0x20, 0xFF]
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .terminalInteraction(TerminalInteractionEvent(
                callID: "cmd-1",
                processID: "proc-1",
                stdin: "q\n"
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .patchApplyUpdated(PatchApplyUpdatedEvent(
                callID: "patch-1",
                changes: [
                    "b.swift": .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new", movePath: "Sources/B.swift"),
                    "a.swift": .add(content: "let a = 1\n"),
                    "c.swift": .delete(content: "let c = 1\n")
                ]
            ))
        )

        let outputMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(outputMessages[0]["method"] as? String, "item/commandExecution/outputDelta")
        let outputParams = try XCTUnwrap(outputMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(outputParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(outputParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(outputParams["itemId"] as? String, "cmd-1")
        XCTAssertEqual(outputParams["delta"] as? String, "Hi \u{FFFD}")

        let terminalMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(terminalMessages[0]["method"] as? String, "item/commandExecution/terminalInteraction")
        let terminalParams = try XCTUnwrap(terminalMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(terminalParams["itemId"] as? String, "cmd-1")
        XCTAssertEqual(terminalParams["processId"] as? String, "proc-1")
        XCTAssertEqual(terminalParams["stdin"] as? String, "q\n")

        let patchMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(patchMessages[0]["method"] as? String, "item/fileChange/patchUpdated")
        let patchParams = try XCTUnwrap(patchMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(patchParams["itemId"] as? String, "patch-1")
        let changes = try XCTUnwrap(patchParams["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["path"] as? String }, ["a.swift", "b.swift", "c.swift"])
        XCTAssertEqual(changes[0]["diff"] as? String, "let a = 1\n")
        XCTAssertEqual((changes[0]["kind"] as? [String: Any])?["type"] as? String, "add")
        XCTAssertEqual(changes[1]["diff"] as? String, "@@ -1 +1 @@\n-old\n+new\n\nMoved to: Sources/B.swift")
        let updateKind = try XCTUnwrap(changes[1]["kind"] as? [String: Any])
        XCTAssertEqual(updateKind["type"] as? String, "update")
        XCTAssertEqual(updateKind["movePath"] as? String, "Sources/B.swift")
        XCTAssertEqual((changes[2]["kind"] as? [String: Any])?["type"] as? String, "delete")
    }

    func testRuntimeItemLifecycleEventsEmitRustNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )
        let eventThreadID = try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .itemStarted(ItemStartedEvent(
                threadID: eventThreadID,
                turnID: "event-turn",
                item: .agentMessage(AgentMessageItem(
                    id: "agent-1",
                    content: [.text("Hello "), .text("world")],
                    phase: .finalAnswer,
                    memoryCitation: MemoryCitation(
                        entries: [
                            MemoryCitationEntry(
                                path: "MEMORY.md",
                                lineStart: 1,
                                lineEnd: 2,
                                note: "summary"
                            )
                        ],
                        rolloutIDs: ["rollout-1"]
                    )
                )),
                startedAtMilliseconds: 111
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .itemCompleted(ItemCompletedEvent(
                threadID: eventThreadID,
                turnID: "event-turn",
                item: .reasoning(ReasoningItem(
                    id: "reason-1",
                    summaryText: ["line one"],
                    rawContent: ["raw"]
                )),
                completedAtMilliseconds: 222
            ))
        )

        let startedMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(startedMessages[0]["method"] as? String, "item/started")
        let startedParams = try XCTUnwrap(startedMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(startedParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(startedParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(startedParams["startedAtMs"] as? Int, 111)
        let agentItem = try XCTUnwrap(startedParams["item"] as? [String: Any])
        XCTAssertEqual(agentItem["type"] as? String, "agentMessage")
        XCTAssertEqual(agentItem["id"] as? String, "agent-1")
        XCTAssertEqual(agentItem["text"] as? String, "Hello world")
        XCTAssertEqual(agentItem["phase"] as? String, "FinalAnswer")
        let memoryCitation = try XCTUnwrap(agentItem["memoryCitation"] as? [String: Any])
        XCTAssertEqual(memoryCitation["threadIds"] as? [String], ["rollout-1"])
        let citationEntries = try XCTUnwrap(memoryCitation["entries"] as? [[String: Any]])
        XCTAssertEqual(citationEntries[0]["path"] as? String, "MEMORY.md")
        XCTAssertEqual(citationEntries[0]["lineStart"] as? Int, 1)
        XCTAssertEqual(citationEntries[0]["lineEnd"] as? Int, 2)
        XCTAssertEqual(citationEntries[0]["note"] as? String, "summary")

        let completedMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completedMessages[0]["method"] as? String, "item/completed")
        let completedParams = try XCTUnwrap(completedMessages[0]["params"] as? [String: Any])
        XCTAssertEqual(completedParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(completedParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(completedParams["completedAtMs"] as? Int, 222)
        let reasoningItem = try XCTUnwrap(completedParams["item"] as? [String: Any])
        XCTAssertEqual(reasoningItem["type"] as? String, "reasoning")
        XCTAssertEqual(reasoningItem["id"] as? String, "reason-1")
        XCTAssertEqual(reasoningItem["summary"] as? [String], ["line one"])
        XCTAssertEqual(reasoningItem["content"] as? [String], ["raw"])
    }

    func testRuntimeItemLifecycleSerializesUserFileAndMcpItems() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )
        let eventThreadID = try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .itemStarted(ItemStartedEvent(
                threadID: eventThreadID,
                turnID: "event-turn",
                item: .userMessage(UserMessageItem(
                    id: "user-1",
                    content: [
                        .text(
                            "hello",
                            textElements: [TextElement(byteRange: ByteRange(start: 0, end: 5), placeholder: "hello")]
                        ),
                        .image(imageURL: "https://example.test/image.png"),
                        .localImage(path: "local/image.png"),
                        .skill(name: "skill-creator", path: "/repo/.codex/skills/skill-creator/SKILL.md")
                    ]
                )),
                startedAtMilliseconds: 10
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .itemCompleted(ItemCompletedEvent(
                threadID: eventThreadID,
                turnID: "event-turn",
                item: .fileChange(FileChangeItem(
                    id: "patch-1",
                    changes: [
                        "b.swift": .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new", movePath: nil),
                        "a.swift": .add(content: "let a = 1\n")
                    ],
                    status: .completed
                )),
                completedAtMilliseconds: 20
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .itemCompleted(ItemCompletedEvent(
                threadID: eventThreadID,
                turnID: "event-turn",
                item: .mcpToolCall(McpToolCallItem(
                    id: "mcp-1",
                    server: "docs",
                    tool: "lookup",
                    arguments: .object(["query": .string("swift")]),
                    mcpAppResourceURI: "app://docs",
                    status: .failed,
                    error: McpToolCallError(message: "boom"),
                    duration: ProtocolDuration(secs: 1, nanos: 250_000_000)
                )),
                completedAtMilliseconds: 30
            ))
        )

        let userMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let userParams = try XCTUnwrap(userMessages[0]["params"] as? [String: Any])
        let userItem = try XCTUnwrap(userParams["item"] as? [String: Any])
        XCTAssertEqual(userItem["type"] as? String, "userMessage")
        let content = try XCTUnwrap(userItem["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["text", "image", "localImage", "skill"])
        XCTAssertEqual(content[0]["text"] as? String, "hello")
        let textElements = try XCTUnwrap(content[0]["textElements"] as? [[String: Any]])
        XCTAssertEqual((textElements[0]["byteRange"] as? [String: Any])?["start"] as? Int, 0)
        XCTAssertEqual((textElements[0]["byteRange"] as? [String: Any])?["end"] as? Int, 5)
        XCTAssertEqual(textElements[0]["placeholder"] as? String, "hello")
        XCTAssertEqual(content[1]["url"] as? String, "https://example.test/image.png")
        XCTAssertEqual(content[2]["path"] as? String, "local/image.png")
        XCTAssertEqual(content[3]["name"] as? String, "skill-creator")

        let fileMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let fileParams = try XCTUnwrap(fileMessages[0]["params"] as? [String: Any])
        let fileItem = try XCTUnwrap(fileParams["item"] as? [String: Any])
        XCTAssertEqual(fileItem["type"] as? String, "fileChange")
        XCTAssertEqual(fileItem["status"] as? String, "completed")
        let changes = try XCTUnwrap(fileItem["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["path"] as? String }, ["a.swift", "b.swift"])
        XCTAssertEqual((changes[1]["kind"] as? [String: Any])?["type"] as? String, "update")
        XCTAssertTrue(((changes[1]["kind"] as? [String: Any])?["movePath"]) is NSNull)

        let mcpMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let mcpParams = try XCTUnwrap(mcpMessages[0]["params"] as? [String: Any])
        let mcpItem = try XCTUnwrap(mcpParams["item"] as? [String: Any])
        XCTAssertEqual(mcpItem["type"] as? String, "mcpToolCall")
        XCTAssertEqual(mcpItem["server"] as? String, "docs")
        XCTAssertEqual(mcpItem["tool"] as? String, "lookup")
        XCTAssertEqual(mcpItem["status"] as? String, "failed")
        XCTAssertEqual(mcpItem["mcpAppResourceUri"] as? String, "app://docs")
        XCTAssertEqual((mcpItem["arguments"] as? [String: Any])?["query"] as? String, "swift")
        XCTAssertTrue(mcpItem["result"] is NSNull)
        XCTAssertEqual((mcpItem["error"] as? [String: Any])?["message"] as? String, "boom")
        XCTAssertEqual(mcpItem["durationMs"] as? Int, 1250)
    }

    func testRuntimeRawResponseItemEmitsRustNotification() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .rawResponseItem(RawResponseItemEvent(item: .message(
                id: "response-item-1",
                role: "assistant",
                content: [.outputText(text: "done")],
                phase: .finalAnswer
            )))
        )

        let messages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["method"] as? String, "rawResponseItem/completed")
        let params = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["turnId"] as? String, "turn-1")
        let item = try XCTUnwrap(params["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "message")
        XCTAssertNil(item["id"])
        XCTAssertEqual(item["role"] as? String, "assistant")
        XCTAssertEqual(item["phase"] as? String, "final_answer")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "output_text")
        XCTAssertEqual(content[0]["text"] as? String, "done")
    }

    func testRuntimeRawHookPromptAlsoEmitsHookPromptItemCompleted() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let before = Int(Date().timeIntervalSince1970 * 1000)
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .rawResponseItem(RawResponseItemEvent(item: .message(
                id: "hook-1",
                role: "user",
                content: [.inputText(text: #"<hook_prompt hook_run_id="run-1">Continue</hook_prompt>"#)]
            )))
        )
        let after = Int(Date().timeIntervalSince1970 * 1000)

        let itemMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(itemMessages.count, 1)
        let itemMessage = try XCTUnwrap(itemMessages.first)
        XCTAssertEqual(itemMessage["method"] as? String, "item/completed")
        let itemParams = try XCTUnwrap(itemMessage["params"] as? [String: Any])
        XCTAssertEqual(itemParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(itemParams["turnId"] as? String, "turn-1")
        let completedAtMilliseconds = try XCTUnwrap(itemParams["completedAtMs"] as? Int)
        XCTAssertGreaterThanOrEqual(completedAtMilliseconds, before)
        XCTAssertLessThanOrEqual(completedAtMilliseconds, after)
        let hookItem = try XCTUnwrap(itemParams["item"] as? [String: Any])
        XCTAssertEqual(hookItem["type"] as? String, "hookPrompt")
        XCTAssertEqual(hookItem["id"] as? String, "hook-1")
        let fragments = try XCTUnwrap(hookItem["fragments"] as? [[String: Any]])
        let fragment = try XCTUnwrap(fragments.first)
        XCTAssertEqual(fragment["text"] as? String, "Continue")
        XCTAssertEqual(fragment["hookRunId"] as? String, "run-1")

        let rawMessages = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(rawMessages.count, 1)
        let rawMessage = try XCTUnwrap(rawMessages.first)
        XCTAssertEqual(rawMessage["method"] as? String, "rawResponseItem/completed")
        let rawParams = try XCTUnwrap(rawMessage["params"] as? [String: Any])
        let rawItem = try XCTUnwrap(rawParams["item"] as? [String: Any])
        XCTAssertEqual(rawItem["type"] as? String, "message")
        XCTAssertEqual(rawItem["role"] as? String, "user")
        let rawContent = try XCTUnwrap(rawItem["content"] as? [[String: Any]])
        let rawText = try XCTUnwrap(rawContent.first)
        XCTAssertEqual(rawText["type"] as? String, "input_text")
        XCTAssertEqual(rawText["text"] as? String, #"<hook_prompt hook_run_id="run-1">Continue</hook_prompt>"#)
    }

    func testRuntimeMcpStartupUpdateEmitsStatusNotification() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .mcpStartupUpdate(McpStartupUpdateEvent(server: "docs", status: .starting))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .mcpStartupUpdate(McpStartupUpdateEvent(server: "docs", status: .ready))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .mcpStartupUpdate(McpStartupUpdateEvent(server: "broken", status: .failed(error: "boom")))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .mcpStartupUpdate(McpStartupUpdateEvent(server: "slow", status: .cancelled))
        )

        let starting = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(starting.count, 1)
        XCTAssertEqual(starting[0]["method"] as? String, "mcpServer/startupStatus/updated")
        let startingParams = try XCTUnwrap(starting[0]["params"] as? [String: Any])
        XCTAssertEqual(startingParams["name"] as? String, "docs")
        XCTAssertEqual(startingParams["status"] as? String, "starting")
        XCTAssertTrue(startingParams["error"] is NSNull)

        let ready = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let readyParams = try XCTUnwrap(ready[0]["params"] as? [String: Any])
        XCTAssertEqual(readyParams["name"] as? String, "docs")
        XCTAssertEqual(readyParams["status"] as? String, "ready")
        XCTAssertTrue(readyParams["error"] is NSNull)

        let failed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let failedParams = try XCTUnwrap(failed[0]["params"] as? [String: Any])
        XCTAssertEqual(failedParams["name"] as? String, "broken")
        XCTAssertEqual(failedParams["status"] as? String, "failed")
        XCTAssertEqual(failedParams["error"] as? String, "boom")

        let cancelled = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let cancelledParams = try XCTUnwrap(cancelled[0]["params"] as? [String: Any])
        XCTAssertEqual(cancelledParams["name"] as? String, "slow")
        XCTAssertEqual(cancelledParams["status"] as? String, "cancelled")
        XCTAssertTrue(cancelledParams["error"] is NSNull)
    }

    func testRuntimeErrorEventsEmitRustErrorNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .error(ErrorEvent(
                message: "too many attempts",
                codexErrorInfo: .responseTooManyFailedAttempts(httpStatusCode: 429)
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .streamError(StreamErrorEvent(
                message: "stream dropped",
                codexErrorInfo: .responseStreamDisconnected(httpStatusCode: nil),
                additionalDetails: "retrying"
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .error(ErrorEvent(
                message: "cannot steer",
                codexErrorInfo: .activeTurnNotSteerable(turnKind: .review)
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .warning(WarningEvent(message: "after suppressed error"))
        )

        let systemError = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(systemError[0]["method"] as? String, "thread/status/changed")
        let systemErrorParams = try XCTUnwrap(systemError[0]["params"] as? [String: Any])
        XCTAssertEqual(systemErrorParams["threadId"] as? String, "thread-1")
        let systemErrorStatus = try XCTUnwrap(systemErrorParams["status"] as? [String: Any])
        XCTAssertEqual(systemErrorStatus["type"] as? String, "systemError")

        let error = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(error[0]["method"] as? String, "error")
        let errorParams = try XCTUnwrap(error[0]["params"] as? [String: Any])
        XCTAssertEqual(errorParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(errorParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(errorParams["willRetry"] as? Bool, false)
        let errorObject = try XCTUnwrap(errorParams["error"] as? [String: Any])
        XCTAssertEqual(errorObject["message"] as? String, "too many attempts")
        XCTAssertTrue(errorObject["additionalDetails"] is NSNull)
        let errorInfo = try XCTUnwrap(errorObject["codexErrorInfo"] as? [String: Any])
        let tooManyAttempts = try XCTUnwrap(errorInfo["responseTooManyFailedAttempts"] as? [String: Any])
        XCTAssertEqual(tooManyAttempts["httpStatusCode"] as? Int, 429)

        let streamError = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(streamError[0]["method"] as? String, "error")
        let streamErrorParams = try XCTUnwrap(streamError[0]["params"] as? [String: Any])
        XCTAssertEqual(streamErrorParams["willRetry"] as? Bool, true)
        let streamErrorObject = try XCTUnwrap(streamErrorParams["error"] as? [String: Any])
        XCTAssertEqual(streamErrorObject["message"] as? String, "stream dropped")
        XCTAssertEqual(streamErrorObject["additionalDetails"] as? String, "retrying")
        let streamErrorInfo = try XCTUnwrap(streamErrorObject["codexErrorInfo"] as? [String: Any])
        let disconnected = try XCTUnwrap(streamErrorInfo["responseStreamDisconnected"] as? [String: Any])
        XCTAssertTrue(disconnected["httpStatusCode"] is NSNull)

        let suppressedSystemError = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(suppressedSystemError[0]["method"] as? String, "thread/status/changed")
        let suppressedSystemErrorParams = try XCTUnwrap(suppressedSystemError[0]["params"] as? [String: Any])
        XCTAssertEqual(suppressedSystemErrorParams["threadId"] as? String, "thread-1")
        let suppressedSystemErrorStatus = try XCTUnwrap(suppressedSystemErrorParams["status"] as? [String: Any])
        XCTAssertEqual(suppressedSystemErrorStatus["type"] as? String, "systemError")

        let warning = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(warning[0]["method"] as? String, "warning")
        let warningParams = try XCTUnwrap(warning[0]["params"] as? [String: Any])
        XCTAssertEqual(warningParams["message"] as? String, "after suppressed error")
    }

    func testRuntimeTurnLifecycleEmitsRustNotificationsAndFailureError() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "fallback-turn",
            event: .taskStarted(TaskStartedEvent(
                turnID: "turn-1",
                startedAt: 1_778_320_000,
                modelContextWindow: 128_000,
                collaborationModeKind: .defaultMode
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .error(ErrorEvent(message: "boom", codexErrorInfo: .badRequest))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "fallback-turn",
            event: .taskComplete(TaskCompleteEvent(
                turnID: "turn-1",
                lastAgentMessage: nil,
                completedAt: 1_778_320_010,
                durationMilliseconds: 10_000
            ))
        )

        let active = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(active[0]["method"] as? String, "thread/status/changed")
        let activeParams = try XCTUnwrap(active[0]["params"] as? [String: Any])
        let activeStatus = try XCTUnwrap(activeParams["status"] as? [String: Any])
        XCTAssertEqual(activeStatus["type"] as? String, "active")

        let started = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(started[0]["method"] as? String, "turn/started")
        let startedParams = try XCTUnwrap(started[0]["params"] as? [String: Any])
        let startedTurn = try XCTUnwrap(startedParams["turn"] as? [String: Any])
        XCTAssertEqual(startedTurn["id"] as? String, "turn-1")
        XCTAssertEqual(startedTurn["itemsView"] as? String, "notLoaded")
        XCTAssertEqual(startedTurn["status"] as? String, "inProgress")
        XCTAssertEqual(startedTurn["startedAt"] as? Int, 1_778_320_000)
        XCTAssertTrue(startedTurn["completedAt"] is NSNull)
        XCTAssertTrue(startedTurn["durationMs"] is NSNull)

        let systemError = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(systemError[0]["method"] as? String, "thread/status/changed")
        let systemErrorParams = try XCTUnwrap(systemError[0]["params"] as? [String: Any])
        let systemErrorStatus = try XCTUnwrap(systemErrorParams["status"] as? [String: Any])
        XCTAssertEqual(systemErrorStatus["type"] as? String, "systemError")

        let error = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(error[0]["method"] as? String, "error")

        let idle = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(idle[0]["method"] as? String, "thread/status/changed")
        let idleParams = try XCTUnwrap(idle[0]["params"] as? [String: Any])
        let idleStatus = try XCTUnwrap(idleParams["status"] as? [String: Any])
        XCTAssertEqual(idleStatus["type"] as? String, "idle")

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed[0]["method"] as? String, "turn/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        let completedTurn = try XCTUnwrap(completedParams["turn"] as? [String: Any])
        XCTAssertEqual(completedTurn["id"] as? String, "turn-1")
        XCTAssertEqual(completedTurn["itemsView"] as? String, "notLoaded")
        XCTAssertEqual(completedTurn["status"] as? String, "failed")
        XCTAssertEqual(completedTurn["startedAt"] as? Int, 1_778_320_000)
        XCTAssertEqual(completedTurn["completedAt"] as? Int, 1_778_320_010)
        XCTAssertEqual(completedTurn["durationMs"] as? Int, 10_000)
        let completedError = try XCTUnwrap(completedTurn["error"] as? [String: Any])
        XCTAssertEqual(completedError["message"] as? String, "boom")
        XCTAssertEqual(completedError["codexErrorInfo"] as? String, "badRequest")
        XCTAssertTrue(completedError["additionalDetails"] is NSNull)
    }

    func testRuntimeApprovalAndUserInputEventsUpdateActiveFlags() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .taskStarted(TaskStartedEvent(
                turnID: "turn-1",
                modelContextWindow: nil
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .applyPatchApprovalRequest(ApplyPatchApprovalRequestEvent(
                callID: "patch-1",
                turnID: "turn-1",
                changes: [:]
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .execApprovalRequest(ExecApprovalRequestEvent(
                callID: "exec-1",
                turnID: "turn-1",
                command: ["git", "status"],
                cwd: "/repo",
                parsedCmd: []
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .requestUserInput(RequestUserInputEvent(
                callID: "input-1",
                turnID: "turn-1",
                questions: [RequestUserInputQuestion(id: "choice", header: "Choice", question: "Pick")]
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .taskComplete(TaskCompleteEvent(
                turnID: "turn-1",
                lastAgentMessage: nil
            ))
        )

        let active = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(active[0]["method"] as? String, "thread/status/changed")
        let activeParams = try XCTUnwrap(active[0]["params"] as? [String: Any])
        let activeStatus = try XCTUnwrap(activeParams["status"] as? [String: Any])
        XCTAssertEqual(activeStatus["activeFlags"] as? [String], [])

        _ = try await nextNotificationPayload(notificationCapture)

        let waitingOnApproval = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(waitingOnApproval[0]["method"] as? String, "thread/status/changed")
        let waitingOnApprovalParams = try XCTUnwrap(waitingOnApproval[0]["params"] as? [String: Any])
        let waitingOnApprovalStatus = try XCTUnwrap(waitingOnApprovalParams["status"] as? [String: Any])
        XCTAssertEqual(waitingOnApprovalStatus["activeFlags"] as? [String], ["waitingOnApproval"])

        let waitingOnBoth = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(waitingOnBoth[0]["method"] as? String, "thread/status/changed")
        let waitingOnBothParams = try XCTUnwrap(waitingOnBoth[0]["params"] as? [String: Any])
        let waitingOnBothStatus = try XCTUnwrap(waitingOnBothParams["status"] as? [String: Any])
        XCTAssertEqual(waitingOnBothStatus["activeFlags"] as? [String], ["waitingOnApproval", "waitingOnUserInput"])

        let idle = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(idle[0]["method"] as? String, "thread/status/changed")
        let idleParams = try XCTUnwrap(idle[0]["params"] as? [String: Any])
        let idleStatus = try XCTUnwrap(idleParams["status"] as? [String: Any])
        XCTAssertEqual(idleStatus["type"] as? String, "idle")
    }

    func testRuntimeTurnAbortedEmitsInterruptedCompletionWithTiming() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .taskStarted(TaskStartedEvent(
                turnID: "turn-1",
                startedAt: 1_778_320_000,
                modelContextWindow: nil
            ))
        )
        _ = try await nextNotificationPayload(notificationCapture)
        _ = try await nextNotificationPayload(notificationCapture)

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "fallback-turn",
            event: .turnAborted(TurnAbortedEvent(
                turnID: "turn-1",
                reason: .interrupted,
                completedAt: 1_778_320_005,
                durationMilliseconds: 5_000
            ))
        )

        let idle = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(idle[0]["method"] as? String, "thread/status/changed")
        let idleParams = try XCTUnwrap(idle[0]["params"] as? [String: Any])
        let idleStatus = try XCTUnwrap(idleParams["status"] as? [String: Any])
        XCTAssertEqual(idleStatus["type"] as? String, "idle")

        let completed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(completed[0]["method"] as? String, "turn/completed")
        let completedParams = try XCTUnwrap(completed[0]["params"] as? [String: Any])
        let completedTurn = try XCTUnwrap(completedParams["turn"] as? [String: Any])
        XCTAssertEqual(completedTurn["id"] as? String, "turn-1")
        XCTAssertEqual(completedTurn["status"] as? String, "interrupted")
        XCTAssertTrue(completedTurn["error"] is NSNull)
        XCTAssertEqual(completedTurn["startedAt"] as? Int, 1_778_320_000)
        XCTAssertEqual(completedTurn["completedAt"] as? Int, 1_778_320_005)
        XCTAssertEqual(completedTurn["durationMs"] as? Int, 5_000)
    }

    func testRuntimeNoticeAndModelEventsEmitRustNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .warning(WarningEvent(message: "heads up"))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .guardianWarning(WarningEvent(message: "approval needed"))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .skillsUpdateAvailable
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .deprecationNotice(DeprecationNoticeEvent(summary: "old flag", details: nil))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .modelReroute(ModelRerouteEvent(
                fromModel: "gpt-5.4",
                toModel: "gpt-5.4-cyber",
                reason: .highRiskCyberActivity
            ))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .modelVerification(ModelVerificationEvent(verifications: [.trustedAccessForCyber]))
        )

        let warning = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(warning[0]["method"] as? String, "warning")
        let warningParams = try XCTUnwrap(warning[0]["params"] as? [String: Any])
        XCTAssertEqual(warningParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(warningParams["message"] as? String, "heads up")

        let guardian = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(guardian[0]["method"] as? String, "guardianWarning")
        let guardianParams = try XCTUnwrap(guardian[0]["params"] as? [String: Any])
        XCTAssertEqual(guardianParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(guardianParams["message"] as? String, "approval needed")

        let skills = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(skills[0]["method"] as? String, "skills/changed")
        let skillsParams = try XCTUnwrap(skills[0]["params"] as? [String: Any])
        XCTAssertTrue(skillsParams.isEmpty)

        let deprecation = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(deprecation[0]["method"] as? String, "deprecationNotice")
        let deprecationParams = try XCTUnwrap(deprecation[0]["params"] as? [String: Any])
        XCTAssertEqual(deprecationParams["summary"] as? String, "old flag")
        XCTAssertTrue(deprecationParams["details"] is NSNull)

        let rerouted = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(rerouted[0]["method"] as? String, "model/rerouted")
        let reroutedParams = try XCTUnwrap(rerouted[0]["params"] as? [String: Any])
        XCTAssertEqual(reroutedParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(reroutedParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(reroutedParams["fromModel"] as? String, "gpt-5.4")
        XCTAssertEqual(reroutedParams["toModel"] as? String, "gpt-5.4-cyber")
        XCTAssertEqual(reroutedParams["reason"] as? String, "highRiskCyberActivity")

        let verification = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(verification[0]["method"] as? String, "model/verification")
        let verificationParams = try XCTUnwrap(verification[0]["params"] as? [String: Any])
        XCTAssertEqual(verificationParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(verificationParams["turnId"] as? String, "turn-1")
        XCTAssertEqual(verificationParams["verifications"] as? [String], ["trustedAccessForCyber"])
    }

    func testRuntimeRealtimeLifecycleEventsEmitNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .realtimeConversationStarted(
                RealtimeConversationStartedEvent(realtimeSessionID: "rt-123", version: .v2)
            )
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .realtimeConversationSdp(RealtimeConversationSdpEvent(sdp: "v=0\r\n"))
        )
        await processor.handleRuntimeEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            event: .realtimeConversationClosed(RealtimeConversationClosedEvent(reason: nil))
        )

        let started = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started[0]["method"] as? String, "thread/realtime/started")
        let startedParams = try XCTUnwrap(started[0]["params"] as? [String: Any])
        XCTAssertEqual(startedParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(startedParams["realtimeSessionId"] as? String, "rt-123")
        XCTAssertEqual(startedParams["version"] as? String, "v2")

        let sdp = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(sdp[0]["method"] as? String, "thread/realtime/sdp")
        let sdpParams = try XCTUnwrap(sdp[0]["params"] as? [String: Any])
        XCTAssertEqual(sdpParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(sdpParams["sdp"] as? String, "v=0\r\n")

        let closed = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(closed[0]["method"] as? String, "thread/realtime/closed")
        let closedParams = try XCTUnwrap(closed[0]["params"] as? [String: Any])
        XCTAssertEqual(closedParams["threadId"] as? String, "thread-1")
        XCTAssertTrue(closedParams["reason"] is NSNull)
    }

    func testRuntimeRealtimePayloadEventsEmitRustNotifications() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            notificationSink: { data in await notificationCapture.append(data) }
        )

        let events: [RealtimeEvent] = [
            .inputAudioSpeechStarted(RealtimeInputAudioSpeechStarted(itemID: nil)),
            .inputTranscriptDelta(RealtimeTranscriptDelta(delta: "hel")),
            .inputTranscriptDone(RealtimeTranscriptDone(text: "hello")),
            .outputTranscriptDelta(RealtimeTranscriptDelta(delta: "hi")),
            .outputTranscriptDone(RealtimeTranscriptDone(text: "hi there")),
            .audioOut(
                RealtimeAudioFrame(
                    data: "AAAA",
                    sampleRate: 24_000,
                    numChannels: 1,
                    samplesPerChannel: nil,
                    itemID: "out-1"
                )
            ),
            .responseCancelled(RealtimeResponseCancelled(responseID: nil)),
            .conversationItemAdded(.object(["type": .string("message"), "id": .string("item-1")])),
            .handoffRequested(
                RealtimeHandoffRequested(
                    handoffID: "handoff-1",
                    itemID: "item-2",
                    inputTranscript: "transfer me",
                    activeTranscript: [RealtimeTranscriptEntry(role: "assistant", text: "working")]
                )
            ),
            .error("realtime failed")
        ]

        for event in events {
            await processor.handleRuntimeEvent(
                threadID: "thread-1",
                turnID: "turn-1",
                event: .realtimeConversationRealtime(RealtimeConversationRealtimeEvent(payload: event))
            )
        }

        let speech = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(speech[0]["method"] as? String, "thread/realtime/itemAdded")
        let speechParams = try XCTUnwrap(speech[0]["params"] as? [String: Any])
        let speechItem = try XCTUnwrap(speechParams["item"] as? [String: Any])
        XCTAssertEqual(speechItem["type"] as? String, "input_audio_buffer.speech_started")
        XCTAssertTrue(speechItem["item_id"] is NSNull)

        let inputDelta = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(inputDelta[0]["method"] as? String, "thread/realtime/transcript/delta")
        let inputDeltaParams = try XCTUnwrap(inputDelta[0]["params"] as? [String: Any])
        XCTAssertEqual(inputDeltaParams["role"] as? String, "user")
        XCTAssertEqual(inputDeltaParams["delta"] as? String, "hel")

        let inputDone = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(inputDone[0]["method"] as? String, "thread/realtime/transcript/done")
        let inputDoneParams = try XCTUnwrap(inputDone[0]["params"] as? [String: Any])
        XCTAssertEqual(inputDoneParams["role"] as? String, "user")
        XCTAssertEqual(inputDoneParams["text"] as? String, "hello")

        let outputDelta = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let outputDeltaParams = try XCTUnwrap(outputDelta[0]["params"] as? [String: Any])
        XCTAssertEqual(outputDelta[0]["method"] as? String, "thread/realtime/transcript/delta")
        XCTAssertEqual(outputDeltaParams["role"] as? String, "assistant")
        XCTAssertEqual(outputDeltaParams["delta"] as? String, "hi")

        let outputDone = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let outputDoneParams = try XCTUnwrap(outputDone[0]["params"] as? [String: Any])
        XCTAssertEqual(outputDone[0]["method"] as? String, "thread/realtime/transcript/done")
        XCTAssertEqual(outputDoneParams["role"] as? String, "assistant")
        XCTAssertEqual(outputDoneParams["text"] as? String, "hi there")

        let audio = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(audio[0]["method"] as? String, "thread/realtime/outputAudio/delta")
        let audioParams = try XCTUnwrap(audio[0]["params"] as? [String: Any])
        let audioChunk = try XCTUnwrap(audioParams["audio"] as? [String: Any])
        XCTAssertEqual(audioChunk["data"] as? String, "AAAA")
        XCTAssertEqual(audioChunk["sampleRate"] as? Int, 24_000)
        XCTAssertEqual(audioChunk["numChannels"] as? Int, 1)
        XCTAssertTrue(audioChunk["samplesPerChannel"] is NSNull)
        XCTAssertEqual(audioChunk["itemId"] as? String, "out-1")

        let cancelled = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let cancelledParams = try XCTUnwrap(cancelled[0]["params"] as? [String: Any])
        let cancelledItem = try XCTUnwrap(cancelledParams["item"] as? [String: Any])
        XCTAssertEqual(cancelled[0]["method"] as? String, "thread/realtime/itemAdded")
        XCTAssertEqual(cancelledItem["type"] as? String, "response.cancelled")
        XCTAssertTrue(cancelledItem["response_id"] is NSNull)

        let conversationItem = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let conversationItemParams = try XCTUnwrap(conversationItem[0]["params"] as? [String: Any])
        let item = try XCTUnwrap(conversationItemParams["item"] as? [String: Any])
        XCTAssertEqual(conversationItem[0]["method"] as? String, "thread/realtime/itemAdded")
        XCTAssertEqual(item["type"] as? String, "message")
        XCTAssertEqual(item["id"] as? String, "item-1")

        let handoff = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        let handoffParams = try XCTUnwrap(handoff[0]["params"] as? [String: Any])
        let handoffItem = try XCTUnwrap(handoffParams["item"] as? [String: Any])
        XCTAssertEqual(handoff[0]["method"] as? String, "thread/realtime/itemAdded")
        XCTAssertEqual(handoffItem["type"] as? String, "handoff_request")
        XCTAssertEqual(handoffItem["handoff_id"] as? String, "handoff-1")
        XCTAssertEqual(handoffItem["item_id"] as? String, "item-2")
        XCTAssertEqual(handoffItem["input_transcript"] as? String, "transfer me")
        let activeTranscript = try XCTUnwrap(handoffItem["active_transcript"] as? [[String: Any]])
        XCTAssertEqual(activeTranscript.first?["role"] as? String, "assistant")
        XCTAssertEqual(activeTranscript.first?["text"] as? String, "working")

        let error = try decodeMessages(try await nextNotificationPayload(notificationCapture))
        XCTAssertEqual(error[0]["method"] as? String, "thread/realtime/error")
        let errorParams = try XCTUnwrap(error[0]["params"] as? [String: Any])
        XCTAssertEqual(errorParams["threadId"] as? String, "thread-1")
        XCTAssertEqual(errorParams["message"] as? String, "realtime failed")
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
            (#""persistFullHistory":true"#, "thread/resume.persistFullHistory"),
            (#""persistExtendedHistory":true"#, "thread/resume.persistFullHistory")
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

    func testThreadResumeUsesLatestTurnContextCwd() throws {
        let temp = try TemporaryDirectory()
        let staleCwd = temp.url.appendingPathComponent("stale", isDirectory: true)
        let latestCwd = temp.url.appendingPathComponent("latest", isDirectory: true)
        try FileManager.default.createDirectory(at: staleCwd, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestCwd, withIntermediateDirectories: true)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T13-00-00",
            timestamp: "2025-01-05T13:00:00Z",
            preview: "Saved user message",
            provider: "mock_provider",
            cwd: staleCwd.path
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        try appendRolloutItems(
            to: rolloutPath,
            timestamp: "2025-01-05T13:00:01Z",
            items: [
                .turnContext(TurnContextItem(
                    turnID: "turn-1",
                    cwd: latestCwd.path,
                    approvalPolicy: .never,
                    sandboxPolicy: .readOnly,
                    model: "test-model",
                    summary: .auto
                ))
            ]
        )

        let resumeResponse = try appServerResponse(
            #"{"id":1,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let resumeResult = try XCTUnwrap(resumeResponse["result"] as? [String: Any])
        let resumedThread = try XCTUnwrap(resumeResult["thread"] as? [String: Any])
        XCTAssertEqual(resumeResult["cwd"] as? String, latestCwd.path)
        XCTAssertEqual(resumedThread["cwd"] as? String, latestCwd.path)

        let readResponse = try appServerResponse(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let readResult = try XCTUnwrap(readResponse["result"] as? [String: Any])
        let readThread = try XCTUnwrap(readResult["thread"] as? [String: Any])
        XCTAssertEqual(readThread["cwd"] as? String, latestCwd.path)
    }

    func testThreadForkExperimentalFieldsRequireExperimentalAPI() throws {
        let temp = try TemporaryDirectory()

        let cases: [(String, String)] = [
            (#""path":"/tmp/source.jsonl""#, "thread/fork.path"),
            (#""approvalPolicy":{"type":"granular","sandboxApproval":true}"#, "askForApproval.granular"),
            (#""permissions":{"profile":"readOnly"}"#, "thread/fork.permissions"),
            (#""excludeTurns":true"#, "thread/fork.excludeTurns"),
            (#""persistFullHistory":true"#, "thread/fork.persistFullHistory"),
            (#""persistExtendedHistory":true"#, "thread/fork.persistFullHistory")
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

    func testThreadReadCanReturnArchivedThreadsByIDLikeRust() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "Archived user message",
            provider: "mock_provider",
            archived: true
        )
        let archivedPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID,
            includeArchived: true
        ))
        try appendRolloutEvents(
            to: archivedPath,
            timestamp: "2025-01-05T12:00:01Z",
            events: [.agentMessage(AgentMessageEvent(message: "Archived answer"))]
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/read","params":{"threadId":"\#(threadID)","includeTurns":true}}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        XCTAssertEqual(thread["id"] as? String, threadID)
        XCTAssertEqual(thread["path"] as? String, archivedPath)
        let turns = try XCTUnwrap(thread["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turnUserText(turns[0]), "Archived user message")
        XCTAssertEqual(turnAgentTexts(turns[0]), ["Archived answer"])
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

    func testThreadMetadataUpdateRepairsArchivedThreadLikeRust() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T08-30-00",
            timestamp: "2025-01-06T08:30:00Z",
            preview: "Archived thread preview",
            provider: "mock_provider",
            archived: true
        )

        let update = try appServerResponse(
            #"{"id":1,"method":"thread/metadata/update","params":{"threadId":"\#(threadID)","gitInfo":{"branch":"feature/archived-thread"}}}"#,
            codexHome: temp.url
        )

        let updateResult = try XCTUnwrap(update["result"] as? [String: Any])
        let updatedThread = try XCTUnwrap(updateResult["thread"] as? [String: Any])
        let gitInfo = try XCTUnwrap(updatedThread["gitInfo"] as? [String: Any])
        XCTAssertEqual(updatedThread["id"] as? String, threadID)
        XCTAssertEqual(updatedThread["preview"] as? String, "Archived thread preview")
        XCTAssertEqual(updatedThread["createdAt"] as? Int, 1_736_152_200)
        XCTAssertNil(gitInfo["sha"] as? String)
        XCTAssertEqual(gitInfo["branch"] as? String, "feature/archived-thread")
        XCTAssertNil(gitInfo["originUrl"] as? String)

        let read = try appServerResponse(
            #"{"id":2,"method":"thread/read","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url
        )
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let readThread = try XCTUnwrap(readResult["thread"] as? [String: Any])
        let readGitInfo = try XCTUnwrap(readThread["gitInfo"] as? [String: Any])
        XCTAssertEqual(readGitInfo["branch"] as? String, "feature/archived-thread")
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

    func testThreadGoalMethodsRequireStateDbWhenFeatureEnabled() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        goals = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T07-20-00",
            timestamp: "2025-01-06T07:20:00Z",
            preview: "goal missing state",
            provider: "mock_provider"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/goal/get","params":{"threadId":"\#(threadID)"}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertEqual(error["message"] as? String, "sqlite state db unavailable for thread goals")
    }

    func testThreadGoalMethodsPersistAndNotifyWhenFeatureEnabled() async throws {
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
        let stateStore = try await createAppServerGoalStateStore(
            codexHome: temp.url,
            threadID: threadID,
            title: "goal thread"
        )
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url, stateStore: stateStore),
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
        let persistedGoal = try await stateStore.getThreadGoal(threadID: try ThreadId(string: threadID))
        XCTAssertNil(persistedGoal)
    }

    func testThreadResumeEmitsGoalSnapshotWhenFeatureEnabled() async throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        goals = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-06T07-22-00",
            timestamp: "2025-01-06T07:22:00Z",
            preview: "goal snapshot",
            provider: "mock_provider"
        )
        let stateStore = try await createAppServerGoalStateStore(
            codexHome: temp.url,
            threadID: threadID,
            title: "goal snapshot"
        )
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url, stateStore: stateStore),
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"keep polishing","status":"paused"}}"#.utf8
        )))

        let resume = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual(resume.count, 2)
        let resumeThread = try XCTUnwrap((resume[0]["result"] as? [String: Any])?["thread"] as? [String: Any])
        XCTAssertEqual(resumeThread["id"] as? String, threadID)
        XCTAssertEqual(resume[1]["method"] as? String, "thread/goal/updated")
        let updateParams = try XCTUnwrap(resume[1]["params"] as? [String: Any])
        XCTAssertEqual(updateParams["threadId"] as? String, threadID)
        XCTAssertEqual(updateParams["turnId"] as? NSNull, NSNull())
        let goal = try XCTUnwrap(updateParams["goal"] as? [String: Any])
        XCTAssertEqual(goal["objective"] as? String, "keep polishing")
        XCTAssertEqual(goal["status"] as? String, "paused")

        _ = try decodeMessages(processor.processLine(Data(
            #"{"id":3,"method":"thread/goal/clear","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))

        let clearedResume = try decodeMessages(processor.processLine(Data(
            #"{"id":4,"method":"thread/resume","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        XCTAssertEqual(clearedResume.count, 2)
        XCTAssertEqual(clearedResume[1]["method"] as? String, "thread/goal/cleared")
        let clearedParams = try XCTUnwrap(clearedResume[1]["params"] as? [String: Any])
        XCTAssertEqual(clearedParams["threadId"] as? String, threadID)
    }

    func testThreadGoalMethodsValidateEnabledInputs() async throws {
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
        let stateStore = try await createAppServerGoalStateStore(
            codexHome: temp.url,
            threadID: threadID,
            title: "goal validation"
        )
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let emptyObjective = try appServerResponse(
            #"{"id":1,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"   "}}"#,
            configuration: configuration,
            experimentalAPIEnabled: true
        )
        let emptyObjectiveError = try XCTUnwrap(emptyObjective["error"] as? [String: Any])
        XCTAssertEqual(emptyObjectiveError["code"] as? Int, -32600)
        XCTAssertEqual(emptyObjectiveError["message"] as? String, "goal objective must not be empty")

        let zeroBudget = try appServerResponse(
            #"{"id":2,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","objective":"keep polishing","tokenBudget":0}}"#,
            configuration: configuration,
            experimentalAPIEnabled: true
        )
        let zeroBudgetError = try XCTUnwrap(zeroBudget["error"] as? [String: Any])
        XCTAssertEqual(zeroBudgetError["code"] as? Int, -32600)
        XCTAssertEqual(zeroBudgetError["message"] as? String, "goal budgets must be positive when provided")

        let missingGoal = try appServerResponse(
            #"{"id":3,"method":"thread/goal/set","params":{"threadId":"\#(threadID)","status":"paused"}}"#,
            configuration: configuration,
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
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerMemoryTables(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
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
            configuration: testConfiguration(codexHome: temp.url, stateStore: stateStore),
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

    func testMemoryResetRequiresStateDbWhenExperimentalAPIEnabled() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertEqual(error["message"] as? String, "sqlite state db unavailable for memory reset")
    }

    func testMemoryResetClearsStateRowsAndPreservesThreadMemoryModes() async throws {
        let temp = try TemporaryDirectory()
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        try createAppServerMemoryTables(databaseURL: stateDatabaseURL)
        try insertAppServerMemoryRows(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let threadID = try ThreadId(string: "00000000-0000-0000-0000-000000009020")
        try await stateStore.upsertThread(ThreadMetadata(
            id: threadID,
            rolloutPath: temp.url.appendingPathComponent("sessions/test.jsonl", isDirectory: false).path,
            createdAt: try appServerDate("2025-01-05T13:00:00Z"),
            updatedAt: try appServerDate("2025-01-05T13:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: temp.url.path,
            cliVersion: "0.0.0",
            title: "memory thread",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "memory thread"
        ))
        _ = try await stateStore.setThreadMemoryMode(threadID: threadID, memoryMode: "disabled")

        let response = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            configuration: testConfiguration(codexHome: temp.url, stateStore: stateStore),
            experimentalAPIEnabled: true
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)

        XCTAssertEqual(try sqliteCount(databaseURL: stateDatabaseURL, query: "SELECT COUNT(*) FROM stage1_outputs"), 0)
        XCTAssertEqual(try sqliteCount(databaseURL: stateDatabaseURL, query: "SELECT COUNT(*) FROM jobs"), 1)
        XCTAssertEqual(
            try sqliteCount(
                databaseURL: stateDatabaseURL,
                query: "SELECT COUNT(*) FROM jobs WHERE kind = 'not_memory'"
            ),
            1
        )
        let memoryMode = try await stateStore.getThreadMemoryMode(threadID: threadID)
        XCTAssertEqual(memoryMode, "disabled")
    }

    func testMemoryResetCreatesMissingRootsAndRejectsSymlinkedRoot() throws {
        let temp = try TemporaryDirectory()
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerMemoryTables(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let missingRoots = try appServerResponse(
            #"{"id":1,"method":"memory/reset","params":{}}"#,
            configuration: testConfiguration(codexHome: temp.url, stateStore: stateStore),
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
            configuration: testConfiguration(codexHome: symlink.deletingLastPathComponent(), stateStore: stateStore),
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

    func testAppListUsesLoadedThreadAppsFeatureWhenThreadIDIsProvided() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let directoryPage = """
        {
          "apps": [
            {
              "id": "beta",
              "name": "Beta",
              "description": "Beta connector"
            }
          ],
          "next_token": null
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/backend-api/connectors/directory/list")
                return URLSessionTransportResponse(statusCode: 200, body: Data(directoryPage.utf8))
            }
        )
        let processor = try initializedProcessor(configuration: configuration)
        let startMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8
        )))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let global = try decode(processor.processLine(Data(
            #"{"id":2,"method":"app/list","params":{}}"#.utf8
        )))
        let globalResult = try XCTUnwrap(global["result"] as? [String: Any])
        XCTAssertEqual((globalResult["data"] as? [Any])?.count, 0)
        XCTAssertTrue(globalResult["nextCursor"] is NSNull)

        let scoped = try decode(processor.processLine(Data(
            #"{"id":3,"method":"app/list","params":{"threadId":"\#(threadID)"}}"#.utf8
        )))
        let scopedResult = try XCTUnwrap(scoped["result"] as? [String: Any])
        let scopedData = try XCTUnwrap(scopedResult["data"] as? [[String: Any]])
        XCTAssertEqual(scopedData.map { $0["id"] as? String }, ["beta"])
        XCTAssertEqual(scopedData[0]["description"] as? String, "Beta connector")
        XCTAssertTrue(scopedResult["nextCursor"] is NSNull)
    }

    func testAppListRejectsUnknownLoadedThreadID() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let missingThreadID = "00000000-0000-0000-0000-000000000000"

        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"app/list","params":{"threadId":"\#(missingThreadID)"}}"#.utf8
        )))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "thread not found: \(missingThreadID)")
    }

    func testAppListForceRefetchPreservesPreviousCacheOnFailure() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let transport = AppListDirectoryTransport(
            successBody: """
            {
              "apps": [
                {
                  "id": "beta",
                  "name": "Beta App",
                  "description": "Beta connector"
                }
              ],
              "next_token": null
            }
            """
        )
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                transport.response(for: request)
            }
        ))

        let initial = try decode(processor.processLine(Data(
            #"{"id":1,"method":"app/list","params":{"forceRefetch":false}}"#.utf8
        )))
        let initialResult = try XCTUnwrap(initial["result"] as? [String: Any])
        let initialData = try XCTUnwrap(initialResult["data"] as? [[String: Any]])
        XCTAssertEqual(initialData.map { $0["id"] as? String }, ["beta"])
        XCTAssertEqual(initialData[0]["description"] as? String, "Beta connector")
        XCTAssertTrue(initialResult["nextCursor"] is NSNull)

        transport.setFailing(true)
        let refetch = try decode(processor.processLine(Data(
            #"{"id":2,"method":"app/list","params":{"forceRefetch":true}}"#.utf8
        )))
        let refetchError = try XCTUnwrap(refetch["error"] as? [String: Any])
        XCTAssertEqual(refetchError["code"] as? Int, -32603)
        XCTAssertEqual(refetchError["message"] as? String, "failed to list apps")

        let cached = try decode(processor.processLine(Data(
            #"{"id":3,"method":"app/list","params":{"forceRefetch":false}}"#.utf8
        )))
        let cachedResult = try XCTUnwrap(cached["result"] as? [String: Any])
        let cachedData = try XCTUnwrap(cachedResult["data"] as? [[String: Any]])
        XCTAssertEqual(cachedData.map { $0["id"] as? String }, ["beta"])
        XCTAssertEqual(cachedData[0]["description"] as? String, "Beta connector")
        XCTAssertTrue(cachedResult["nextCursor"] is NSNull)
        XCTAssertEqual(transport.requestCount, 2)
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

    func testAppListReturnsConfiguredLocalPluginAppsAndPaginates() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let sourcePath = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        try """
        [marketplaces.debug]
        source_type = "local"
        source = "\(sourcePath)"

        [plugins."weather@debug"]
        enabled = true

        [apps.connector_weather]
        enabled = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let first = try appServerResponse(
            #"{"id":1,"method":"app/list","params":{"limit":1}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.count, 1)
        XCTAssertEqual(firstData[0]["id"] as? String, "connector_weather")
        XCTAssertEqual(firstData[0]["name"] as? String, "Weather")
        XCTAssertEqual(firstData[0]["installUrl"] as? String, "https://chatgpt.com/apps/weather/connector_weather")
        XCTAssertEqual(firstData[0]["isAccessible"] as? Bool, false)
        XCTAssertEqual(firstData[0]["isEnabled"] as? Bool, false)
        XCTAssertEqual(firstData[0]["pluginDisplayNames"] as? [String], [])
        XCTAssertTrue(firstResult["nextCursor"] is NSNull)

        let beyond = try appServerResponse(
            #"{"id":2,"method":"app/list","params":{"cursor":"2"}}"#,
            codexHome: temp.url
        )
        let beyondError = try XCTUnwrap(beyond["error"] as? [String: Any])
        XCTAssertEqual(beyondError["code"] as? Int, -32600)
        XCTAssertEqual(beyondError["message"] as? String, "cursor 2 exceeds total apps 1")
    }

    func testAppListLoadsRemoteDirectoryAndWorkspaceConnectorsForWorkspaceAuth() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true

        [apps._default]
        enabled = false

        [apps.connector_alpha]
        enabled = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        [apps.connector_beta]
        enabled = false
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "business", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let firstPage = """
        {
          "apps": [
            {
              "id": "connector_beta",
              "name": "  ",
              "description": "   "
            },
            {
              "id": "connector_hidden",
              "name": "Hidden",
              "visibility": "HIDDEN"
            }
          ],
          "next_token": "page two"
        }
        """
        let secondPage = """
        {
          "apps": [
            {
              "id": "connector_beta",
              "name": "Beta",
              "description": "Beta connector",
              "logoUrl": "https://cdn.example/beta.png",
              "distributionChannel": "official"
            }
          ],
          "next_token": ""
        }
        """
        let workspacePage = """
        {
          "apps": [
            {
              "id": "connector_alpha",
              "name": "Alpha",
              "description": "Workspace connector"
            }
          ],
          "next_token": null
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/connectors/directory/list", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(firstPage.utf8))
                case ("GET", "/backend-api/connectors/directory/list", "token=page%20two&external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(secondPage.utf8))
                case ("GET", "/backend-api/connectors/directory/list_workspace", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(workspacePage.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            },
            configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
        )

        let response = try appServerResponse(#"{"id":1,"method":"app/list","params":{}}"#, configuration: configuration)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["id"] as? String }, ["connector_alpha", "connector_beta"])
        XCTAssertEqual(data.map { $0["name"] as? String }, ["Alpha", "Beta"])
        XCTAssertEqual(data[0]["description"] as? String, "Workspace connector")
        XCTAssertEqual(data[1]["description"] as? String, "Beta connector")
        XCTAssertEqual(data[1]["logoUrl"] as? String, "https://cdn.example/beta.png")
        XCTAssertEqual(data[1]["distributionChannel"] as? String, "official")
        XCTAssertEqual(data.map { $0["installUrl"] as? String }, [
            "https://chatgpt.com/apps/alpha/connector_alpha",
            "https://chatgpt.com/apps/beta/connector_beta"
        ])
        XCTAssertEqual(data.map { $0["isAccessible"] as? Bool }, [false, false])
        XCTAssertEqual(data.map { $0["isEnabled"] as? Bool }, [true, false])
        XCTAssertTrue(result["nextCursor"] is NSNull)
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer chatgpt-token",
            "Bearer chatgpt-token",
            "Bearer chatgpt-token"
        ])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") }, [
            "account-123",
            "account-123",
            "account-123"
        ])
    }

    func testAppListMergesAccessibleConnectorsWithDirectoryMetadata() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let directoryPage = """
        {
          "apps": [
            {
              "id": "calendar",
              "name": "  "
            }
          ],
          "next_token": null
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/connectors/directory/list", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(directoryPage.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            },
            accessibleConnectorProvider: { _, _ in
                return [
                    DiscoverableConnectorInfo(
                        id: "calendar",
                        name: "Google Calendar",
                        description: "Plan events",
                        isAccessible: true,
                        isEnabled: true,
                        pluginDisplayNames: ["sample", "alpha", "sample"]
                    )
                ]
            }
        )

        let response = try appServerResponse(#"{"id":1,"method":"app/list","params":{}}"#, configuration: configuration)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["id"] as? String, "calendar")
        XCTAssertEqual(data[0]["name"] as? String, "Google Calendar")
        XCTAssertEqual(data[0]["description"] as? String, "Plan events")
        XCTAssertEqual(data[0]["installUrl"] as? String, "https://chatgpt.com/apps/calendar/calendar")
        XCTAssertEqual(data[0]["isAccessible"] as? Bool, true)
        XCTAssertEqual(data[0]["isEnabled"] as? Bool, true)
        XCTAssertEqual(data[0]["pluginDisplayNames"] as? [String], ["alpha", "sample"])
        XCTAssertTrue(result["nextCursor"] is NSNull)
    }

    func testAppListUsesRustConnectorInstallURLSlugs() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        apps = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let configuration = testConfiguration(
            codexHome: temp.url,
            accessibleConnectorProvider: { _, _ in
                [
                    DiscoverableConnectorInfo(
                        id: "connector_symbol",
                        name: "$$$",
                        isAccessible: true,
                        isEnabled: true
                    ),
                    DiscoverableConnectorInfo(
                        id: "connector_punctuation",
                        name: "A + B",
                        isAccessible: true,
                        isEnabled: true
                    )
                ]
            }
        )

        let response = try appServerResponse(#"{"id":1,"method":"app/list","params":{}}"#, configuration: configuration)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["installUrl"] as? String }, [
            "https://chatgpt.com/apps/app/connector_symbol",
            "https://chatgpt.com/apps/a---b/connector_punctuation"
        ])
    }

    func testAppListFiltersDisallowedDirectoryAndAccessibleConnectors() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let directoryPage = """
        {
          "apps": [
            {
              "id": "connector_alpha",
              "name": "Alpha"
            },
            {
              "id": "connector_openai_hidden",
              "name": "OpenAI Hidden"
            }
          ],
          "next_token": null
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/connectors/directory/list", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(directoryPage.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            },
            accessibleConnectorProvider: { _, _ in
                [
                    DiscoverableConnectorInfo(
                        id: "connector_accessible",
                        name: "Accessible",
                        isAccessible: true,
                        isEnabled: true
                    ),
                    DiscoverableConnectorInfo(
                        id: "asdk_app_6938a94a61d881918ef32cb999ff937c",
                        name: "Default Hidden",
                        isAccessible: true,
                        isEnabled: true
                    )
                ]
            }
        )

        let response = try appServerResponse(#"{"id":1,"method":"app/list","params":{}}"#, configuration: configuration)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["id"] as? String }, ["connector_accessible", "connector_alpha"])
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

    func testPluginListFetchesFeaturedPluginIdsForOpenAICuratedMarketplaceWithoutAuth() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(
            named: "openai-curated",
            pluginName: "linear",
            in: temp.url
        )
        let sourcePath = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [marketplaces.openai-curated]
        source_type = "local"
        source = "\(sourcePath)"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                return URLSessionTransportResponse(
                    statusCode: 200,
                    body: Data(#"["linear@openai-curated"]"#.utf8)
                )
            }
        )
        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{}}"#,
            configuration: configuration
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["featuredPluginIds"] as? [String], ["linear@openai-curated"])
        let request = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.example/backend-api/plugins/featured?platform=codex")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "chatgpt-account-id"))
    }

    func testPluginListIncludesRemoteGlobalMarketplaceWhenRemotePluginEnabled() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let directoryBody = """
        {
          "plugins": [
            {
              "id": "plugins~Plugin_00000000000000000000000000000000",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "app_ids": [],
                "keywords": ["issue-tracking", "project management"],
                "interface": {
                  "short_description": "Plan and track work",
                  "capabilities": ["Read", "Write"],
                  "logo_url": "https://example.com/linear.png",
                  "screenshot_urls": ["https://example.com/linear-shot.png"]
                },
                "skills": []
              }
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let installedBody = """
        {
          "plugins": [
            {
              "id": "plugins~Plugin_00000000000000000000000000000000",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "app_ids": [],
                "keywords": ["issue-tracking", "project management"],
                "interface": {
                  "short_description": "Plan and track work",
                  "capabilities": ["Read", "Write"],
                  "logo_url": "https://example.com/linear.png",
                  "screenshot_urls": ["https://example.com/linear-shot.png"]
                },
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """

        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/list", "scope=GLOBAL&limit=200"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(directoryBody.utf8))
                case ("/backend-api/ps/plugins/installed", "scope=GLOBAL"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404)
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let marketplaces = try XCTUnwrap(result["marketplaces"] as? [[String: Any]])
        XCTAssertEqual(marketplaces.count, 1)
        XCTAssertEqual(marketplaces[0]["name"] as? String, "chatgpt-global")
        XCTAssertTrue(marketplaces[0]["path"] is NSNull)
        let marketplaceInterface = try XCTUnwrap(marketplaces[0]["interface"] as? [String: Any])
        XCTAssertEqual(marketplaceInterface["displayName"] as? String, "ChatGPT Plugins")

        let plugins = try XCTUnwrap(marketplaces[0]["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["id"] as? String, "plugins~Plugin_00000000000000000000000000000000")
        XCTAssertEqual(plugins[0]["name"] as? String, "linear")
        XCTAssertEqual(plugins[0]["installed"] as? Bool, true)
        XCTAssertEqual(plugins[0]["enabled"] as? Bool, true)
        XCTAssertEqual(plugins[0]["installPolicy"] as? String, "AVAILABLE")
        XCTAssertEqual(plugins[0]["authPolicy"] as? String, "ON_USE")
        XCTAssertEqual(plugins[0]["availability"] as? String, "AVAILABLE")
        let source = try XCTUnwrap(plugins[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "remote")
        let interface = try XCTUnwrap(plugins[0]["interface"] as? [String: Any])
        XCTAssertEqual(interface["displayName"] as? String, "Linear")
        XCTAssertEqual(interface["shortDescription"] as? String, "Plan and track work")
        XCTAssertEqual(interface["capabilities"] as? [String], ["Read", "Write"])
        XCTAssertEqual(interface["logoUrl"] as? String, "https://example.com/linear.png")
        XCTAssertEqual(interface["screenshotUrls"] as? [String], ["https://example.com/linear-shot.png"])
        XCTAssertEqual(plugins[0]["keywords"] as? [String], ["issue-tracking", "project management"])
        XCTAssertEqual(result["featuredPluginIds"] as? [String], [])

        let requests = capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer chatgpt-token" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "chatgpt-account-id") == "account-123" })
    }

    func testPluginListFetchesWorkspaceDirectoryKindWithoutRemotePluginFlag() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let directoryBody = workspaceRemotePluginPageBody(
            id: "plugins~Plugin_11111111111111111111111111111111",
            name: "workspace-linear",
            displayName: "Workspace Linear"
        )
        let installedBody = workspaceRemotePluginPageBody(
            id: "plugins~Plugin_11111111111111111111111111111111",
            name: "workspace-linear",
            displayName: "Workspace Linear",
            enabled: false
        )
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/list", "scope=WORKSPACE&limit=200"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(directoryBody.utf8))
                case ("/backend-api/ps/plugins/installed", "scope=WORKSPACE"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404)
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{"marketplaceKinds":["workspace-directory"]}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let marketplaces = try XCTUnwrap(result["marketplaces"] as? [[String: Any]])
        XCTAssertEqual(marketplaces.count, 1)
        XCTAssertEqual(marketplaces[0]["name"] as? String, "workspace-directory")
        let marketplaceInterface = try XCTUnwrap(marketplaces[0]["interface"] as? [String: Any])
        XCTAssertEqual(marketplaceInterface["displayName"] as? String, "Workspace Directory")
        let plugins = try XCTUnwrap(marketplaces[0]["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["name"] as? String, "workspace-linear")
        XCTAssertEqual(plugins[0]["installed"] as? Bool, true)
        XCTAssertEqual(plugins[0]["enabled"] as? Bool, false)
        let shareContext = try XCTUnwrap(plugins[0]["shareContext"] as? [String: Any])
        XCTAssertEqual(shareContext["remotePluginId"] as? String, "plugins~Plugin_11111111111111111111111111111111")
        XCTAssertEqual(shareContext["creatorName"] as? String, "Gavin")

        let requests = capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains { $0.url?.query?.contains("scope=GLOBAL") == true })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer chatgpt-token" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "chatgpt-account-id") == "account-123" })
    }

    func testPluginListFetchesSharedWithMeKindAndShareContext() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let sharedBody = workspaceRemotePluginPageBody(
            id: "plugins~Plugin_22222222222222222222222222222222",
            name: "shared-linear",
            displayName: "Shared Linear"
        )
        let installedBody = workspaceRemotePluginPageBody(
            id: "plugins~Plugin_22222222222222222222222222222222",
            name: "shared-linear",
            displayName: "Shared Linear",
            enabled: true
        )
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/workspace/shared", "limit=200"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(sharedBody.utf8))
                case ("/backend-api/ps/plugins/installed", "scope=WORKSPACE"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404)
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/list","params":{"marketplaceKinds":["shared-with-me"]}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let marketplaces = try XCTUnwrap(result["marketplaces"] as? [[String: Any]])
        XCTAssertEqual(marketplaces.count, 1)
        XCTAssertEqual(marketplaces[0]["name"] as? String, "shared-with-me")
        let marketplaceInterface = try XCTUnwrap(marketplaces[0]["interface"] as? [String: Any])
        XCTAssertEqual(marketplaceInterface["displayName"] as? String, "Shared with me")
        let plugins = try XCTUnwrap(marketplaces[0]["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["name"] as? String, "shared-linear")
        XCTAssertEqual(plugins[0]["installed"] as? Bool, true)
        XCTAssertEqual(plugins[0]["enabled"] as? Bool, true)
        let shareContext = try XCTUnwrap(plugins[0]["shareContext"] as? [String: Any])
        XCTAssertEqual(shareContext["remotePluginId"] as? String, "plugins~Plugin_22222222222222222222222222222222")
        XCTAssertEqual(shareContext["creatorAccountUserId"] as? String, "user-gavin__account-123")
        XCTAssertEqual(shareContext["creatorName"] as? String, "Gavin")
        XCTAssertEqual(shareContext["shareUrl"] as? String, "https://chatgpt.example/plugins/share/share-key-1")
        let shareTargets = try XCTUnwrap(shareContext["shareTargets"] as? [[String: Any]])
        XCTAssertEqual(shareTargets.count, 1)
        XCTAssertEqual(shareTargets[0]["principalType"] as? String, "user")
        XCTAssertEqual(shareTargets[0]["principalId"] as? String, "user-ada__account-123")
        XCTAssertEqual(shareTargets[0]["name"] as? String, "Ada")
        XCTAssertEqual(result["featuredPluginIds"] as? [String], [])

        let requests = capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains { $0.url?.path == "/backend-api/ps/plugins/list" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer chatgpt-token" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "chatgpt-account-id") == "account-123" })
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

    func testPluginReadValidatesSourceAndReportsRemoteDisabledWhenPluginsDisabled() throws {
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

        try """
        [features]
        plugins = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
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

    func testPluginReadReadsRemotePluginDetailsAndSkills() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let pluginID = "plugins~Plugin_00000000000000000000000000000000"
        let detailBody = remotePluginDetailBody(id: pluginID, scope: "GLOBAL")
        let installedBody = """
        {
          "plugins": [
            {
              "id": "\(pluginID)",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "app_ids": [],
                "interface": {
                  "short_description": "Plan and track work",
                  "capabilities": ["Read", "Write"]
                },
                "skills": []
              },
              "enabled": false,
              "disabled_skill_names": ["plan-work"]
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/\(pluginID)", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("/backend-api/ps/plugins/installed", "scope=GLOBAL"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let plugin = try XCTUnwrap(result["plugin"] as? [String: Any])
        XCTAssertEqual(plugin["marketplaceName"] as? String, "chatgpt-global")
        XCTAssertTrue(plugin["marketplacePath"] is NSNull)
        XCTAssertEqual(plugin["description"] as? String, "Track work in Linear")
        let summary = try XCTUnwrap(plugin["summary"] as? [String: Any])
        XCTAssertEqual(summary["id"] as? String, pluginID)
        XCTAssertEqual(summary["name"] as? String, "linear")
        XCTAssertEqual(summary["installed"] as? Bool, true)
        XCTAssertEqual(summary["enabled"] as? Bool, false)
        let source = try XCTUnwrap(summary["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "remote")
        XCTAssertEqual(summary["keywords"] as? [String], ["issue-tracking", "project management"])
        let interface = try XCTUnwrap(summary["interface"] as? [String: Any])
        XCTAssertEqual(interface["displayName"] as? String, "Linear")
        XCTAssertEqual(interface["shortDescription"] as? String, "Plan and track work")
        let skills = try XCTUnwrap(plugin["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0]["name"] as? String, "plan-work")
        XCTAssertEqual(skills[0]["description"] as? String, "Plan work from Linear issues")
        XCTAssertEqual(skills[0]["shortDescription"] as? String, "Create a plan from issues")
        XCTAssertTrue(skills[0]["path"] is NSNull)
        XCTAssertEqual(skills[0]["enabled"] as? Bool, false)
        XCTAssertEqual((plugin["apps"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((plugin["hooks"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(plugin["mcpServers"] as? [String], [])
        XCTAssertTrue(capture.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer chatgpt-token" })
    }

    func testPluginReadReturnsShareContextForWorkspaceRemotePlugin() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins~Plugin_11111111111111111111111111111111"
        let detailBody = remotePluginDetailBody(id: pluginID, name: "shared-linear", displayName: "Shared Linear", scope: "WORKSPACE")
        let installedBody = """
        {
          "plugins": [],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/\(pluginID)", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("/backend-api/ps/plugins/installed", "scope=WORKSPACE"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/read","params":{"remoteMarketplaceName":"shared-with-me","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let plugin = try XCTUnwrap(result["plugin"] as? [String: Any])
        XCTAssertEqual(plugin["marketplaceName"] as? String, "workspace-directory")
        let summary = try XCTUnwrap(plugin["summary"] as? [String: Any])
        let shareContext = try XCTUnwrap(summary["shareContext"] as? [String: Any])
        XCTAssertEqual(shareContext["remotePluginId"] as? String, pluginID)
        XCTAssertEqual(shareContext["creatorAccountUserId"] as? String, "user-gavin__account-123")
        XCTAssertEqual(shareContext["creatorName"] as? String, "Gavin")
        XCTAssertEqual(shareContext["shareUrl"] as? String, "https://chatgpt.example/plugins/share/share-key-1")
        let shareTargets = try XCTUnwrap(shareContext["shareTargets"] as? [[String: Any]])
        XCTAssertEqual(shareTargets.count, 1)
        XCTAssertEqual(shareTargets[0]["principalType"] as? String, "user")
        XCTAssertEqual(shareTargets[0]["principalId"] as? String, "user-ada__account-123")
        XCTAssertEqual(shareTargets[0]["name"] as? String, "Ada")
    }

    func testPluginSkillReadReadsRemoteSkillContents() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins~Plugin_00000000000000000000000000000000"
        let skillBody = """
        {
          "plugin_id": "\(pluginID)",
          "name": "plan-work",
          "skill_md_contents": "# Plan Work\\n\\nUse Linear issues to create a plan."
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                switch (request.url?.path, request.url?.query) {
                case ("/backend-api/ps/plugins/\(pluginID)/skills/plan-work", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(skillBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/skill/read","params":{"remoteMarketplaceName":"chatgpt-global","remotePluginId":"\#(pluginID)","skillName":"plan-work"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(
            result["contents"] as? String,
            "# Plan Work\n\nUse Linear issues to create a plan."
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

    func testPluginShareSaveUploadsLocalPluginAndRecordsLocalPath() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginSource = temp.url.appendingPathComponent("share-source", isDirectory: true)
        try writePluginFixture(
            root: pluginSource,
            relativePath: "demo-plugin",
            pluginName: "demo-plugin",
            version: "0.1.0",
            marker: "from-share-upload"
        )
        let pluginPath = pluginSource.appendingPathComponent("demo-plugin", isDirectory: true)
        let pluginID = "plugins_123"
        let uploadURLBody = """
        {
          "file_id": "file_123",
          "upload_url": "https://uploads.example/upload/file_123",
          "etag": "\\"upload_etag_123\\""
        }
        """
        let createBody = """
        {
          "plugin_id": "\(pluginID)",
          "share_url": "https://chatgpt.example/plugins/share/share-key-1"
        }
        """
        let createdBody = """
        {
          "plugins": [
            \(remotePluginDetailBody(id: pluginID, name: "demo-plugin", displayName: "Demo Plugin", scope: "WORKSPACE"))
          ],
          "pagination": {
            "limit": 200,
            "next_page_token": null
          }
        }
        """
        let installedBody = """
        {
          "plugins": [],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.host, request.url?.query) {
                case ("POST", "/backend-api/public/plugins/workspace/upload-url", "chatgpt.example", nil):
                    return URLSessionTransportResponse(statusCode: 201, body: Data(uploadURLBody.utf8))
                case ("PUT", "/upload/file_123", "uploads.example", nil):
                    return URLSessionTransportResponse(statusCode: 201, headers: ["etag": "\"blob_etag_123\""])
                case ("POST", "/backend-api/public/plugins/workspace", "chatgpt.example", nil):
                    return URLSessionTransportResponse(statusCode: 201, body: Data(createBody.utf8))
                case ("GET", "/backend-api/ps/plugins/workspace/created", "chatgpt.example", "limit=200"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(createdBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "chatgpt.example", "scope=WORKSPACE"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath.path)","discoverability":"UNLISTED","shareTargets":[{"principalType":"user","principalId":"user-1"}]}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["remotePluginId"] as? String, pluginID)
        XCTAssertEqual(result["shareUrl"] as? String, "https://chatgpt.example/plugins/share/share-key-1")

        let requests = capture.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["POST", "PUT", "POST"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer chatgpt-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "chatgpt-account-id"), "account-123")
        let uploadURLRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(uploadURLRequest["filename"] as? String, "demo-plugin.tar.gz")
        XCTAssertEqual(uploadURLRequest["mime_type"] as? String, "application/gzip")
        XCTAssertNil(uploadURLRequest["plugin_id"])
        XCTAssertGreaterThan(uploadURLRequest["size_bytes"] as? Int ?? 0, 0)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-ms-blob-type"), "BlockBlob")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/gzip")
        let uploadedArchive = try XCTUnwrap(requests[1].httpBody)
        XCTAssertTrue(try archiveContains(uploadedArchive, "marker.txt", in: temp.url))
        let finalizeRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[2].httpBody)) as? [String: Any])
        XCTAssertEqual(finalizeRequest["file_id"] as? String, "file_123")
        XCTAssertEqual(finalizeRequest["etag"] as? String, "\"upload_etag_123\"")
        XCTAssertEqual(finalizeRequest["discoverability"] as? String, "UNLISTED")
        let targets = try XCTUnwrap(finalizeRequest["share_targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0]["principal_type"] as? String, "user")
        XCTAssertEqual(targets[0]["principal_id"] as? String, "user-1")
        XCTAssertEqual(targets[1]["principal_type"] as? String, "workspace")
        XCTAssertEqual(targets[1]["principal_id"] as? String, "account-123")

        let listResponse = try appServerResponse(
            #"{"id":2,"method":"plugin/share/list","params":{}}"#,
            configuration: configuration
        )
        let listResult = try XCTUnwrap(listResponse["result"] as? [String: Any])
        let data = try XCTUnwrap(listResult["data"] as? [[String: Any]])
        XCTAssertEqual(data.first?["localPluginPath"] as? String, pluginPath.path)
    }

    func testPluginShareSaveUpdatesExistingWorkspacePlugin() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginSource = temp.url.appendingPathComponent("share-source", isDirectory: true)
        try writePluginFixture(
            root: pluginSource,
            relativePath: "demo-plugin",
            pluginName: "demo-plugin",
            version: "0.1.0",
            marker: "from-share-update"
        )
        let pluginPath = pluginSource.appendingPathComponent("demo-plugin", isDirectory: true)
        let pluginID = "plugins_456"
        let uploadURLBody = """
        {
          "file_id": "file_456",
          "upload_url": "https://uploads.example/upload/file_456",
          "etag": "\\"upload_etag_456\\""
        }
        """
        let updateBody = """
        {
          "plugin_id": "\(pluginID)",
          "share_url": null
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.host) {
                case ("POST", "/backend-api/public/plugins/workspace/upload-url", "chatgpt.example"):
                    return URLSessionTransportResponse(statusCode: 201, body: Data(uploadURLBody.utf8))
                case ("PUT", "/upload/file_456", "uploads.example"):
                    return URLSessionTransportResponse(statusCode: 200)
                case ("POST", "/backend-api/public/plugins/workspace/\(pluginID)", "chatgpt.example"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(updateBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/share/save","params":{"pluginPath":"\#(pluginPath.path)","remotePluginId":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["remotePluginId"] as? String, pluginID)
        XCTAssertEqual(result["shareUrl"] as? String, "")
        let requests = capture.requests
        XCTAssertEqual(requests.map { $0.url?.path ?? "" }, [
            "/backend-api/public/plugins/workspace/upload-url",
            "/upload/file_456",
            "/backend-api/public/plugins/workspace/\(pluginID)"
        ])
        let uploadURLRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(uploadURLRequest["plugin_id"] as? String, pluginID)
        let finalizeRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[2].httpBody)) as? [String: Any])
        XCTAssertEqual(finalizeRequest["file_id"] as? String, "file_456")
        XCTAssertEqual(finalizeRequest["etag"] as? String, "\"upload_etag_456\"")
        XCTAssertNil(finalizeRequest["discoverability"])
        XCTAssertNil(finalizeRequest["share_targets"])
    }

    func testPluginShareListReturnsCreatedWorkspacePlugins() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins_123"
        let createdBody = """
        {
          "plugins": [
            \(remotePluginDetailBody(id: pluginID, name: "demo-plugin", displayName: "Demo Plugin", scope: "WORKSPACE"))
          ],
          "pagination": {
            "limit": 200,
            "next_page_token": null
          }
        }
        """
        let installedBody = """
        {
          "plugins": [
            {
              "id": "\(pluginID)",
              "name": "demo-plugin",
              "scope": "WORKSPACE",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Demo Plugin",
                "description": "Demo plugin description",
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/workspace/created", "limit=200"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(createdBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=WORKSPACE"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/share/list","params":{}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0]["shareUrl"] as? String, "https://chatgpt.example/plugins/share/share-key-1")
        XCTAssertTrue(data[0]["localPluginPath"] is NSNull)
        let plugin = try XCTUnwrap(data[0]["plugin"] as? [String: Any])
        XCTAssertEqual(plugin["id"] as? String, pluginID)
        XCTAssertEqual(plugin["source"] as? [String: String], ["type": "remote"])
        XCTAssertEqual(plugin["installed"] as? Bool, true)
        XCTAssertEqual(plugin["enabled"] as? Bool, true)
        let shareContext = try XCTUnwrap(plugin["shareContext"] as? [String: Any])
        XCTAssertEqual(shareContext["remotePluginId"] as? String, pluginID)
        let shareTargets = try XCTUnwrap(shareContext["shareTargets"] as? [[String: Any]])
        XCTAssertEqual(shareTargets.map { $0["principalId"] as? String }, ["user-ada__account-123"])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer chatgpt-token", "Bearer chatgpt-token"])
    }

    func testPluginShareUpdateTargetsForwardsWorkspaceTargetAndFiltersResponse() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let capture = MCPHTTPTransportCapture()
        let responseBody = """
        {
          "principals": [
            {
              "principal_type": "user",
              "principal_id": "owner-1",
              "name": "Owner"
            },
            {
              "principal_type": "user",
              "principal_id": "user-1",
              "name": "Gavin"
            },
            {
              "principal_type": "workspace",
              "principal_id": "account-123",
              "name": "Workspace"
            }
          ]
        }
        """
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path) {
                case ("PUT", "/backend-api/ps/plugins/plugins_123/shares"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(responseBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/share/updateTargets","params":{"remotePluginId":"plugins_123","discoverability":"UNLISTED","shareTargets":[{"principalType":"user","principalId":"user-1"}]}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["discoverability"] as? String, "UNLISTED")
        let principals = try XCTUnwrap(result["principals"] as? [[String: Any]])
        XCTAssertEqual(principals.count, 1)
        XCTAssertEqual(principals[0]["principalType"] as? String, "user")
        XCTAssertEqual(principals[0]["principalId"] as? String, "user-1")
        XCTAssertEqual(principals[0]["name"] as? String, "Gavin")
        let request = try XCTUnwrap(capture.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["discoverability"] as? String, "UNLISTED")
        let targets = try XCTUnwrap(body["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0]["principal_type"] as? String, "user")
        XCTAssertEqual(targets[0]["principal_id"] as? String, "user-1")
        XCTAssertEqual(targets[1]["principal_type"] as? String, "workspace")
        XCTAssertEqual(targets[1]["principal_id"] as? String, "account-123")
    }

    func testPluginShareDeleteRemovesCreatedWorkspacePlugin() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path) {
                case ("DELETE", "/backend-api/public/plugins/workspace/plugins_123"):
                    return URLSessionTransportResponse(statusCode: 204, body: Data())
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/share/delete","params":{"remotePluginId":"plugins_123"}}"#,
            configuration: configuration
        )
        XCTAssertNotNil(response["result"] as? [String: Any])
        XCTAssertEqual(capture.requests.map { $0.httpMethod ?? "" }, ["DELETE"])
        XCTAssertEqual(capture.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer chatgpt-token")
        XCTAssertEqual(capture.requests.first?.value(forHTTPHeaderField: "chatgpt-account-id"), "account-123")
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
            "install remote plugin: chatgpt authentication required for remote plugin catalog"
        )
    }

    func testPluginInstallRemoteCallsInstallMutation() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins_123"
        let bundleSource = temp.url.appendingPathComponent("remote-bundle-source", isDirectory: true)
        try writePluginFixture(
            root: bundleSource,
            relativePath: "linear",
            pluginName: "linear",
            version: "0.0.1-local-ignored",
            marker: "from-remote-bundle"
        )
        let bundleBytes = try remotePluginBundleTarGzBytes(
            pluginRoot: bundleSource.appendingPathComponent("linear", isDirectory: true),
            in: temp.url
        )
        let installedManifest = temp.url
            .appendingPathComponent("plugins/cache/chatgpt-global/linear/1.2.3/.codex-plugin/plugin.json", isDirectory: false)
        let installedMarker = temp.url
            .appendingPathComponent("plugins/cache/chatgpt-global/linear/1.2.3/marker.txt", isDirectory: false)
        let detailBody = remotePluginDetailBody(
            id: pluginID,
            name: "linear",
            displayName: "Linear",
            scope: "GLOBAL",
            releaseVersion: "1.2.3",
            bundleDownloadURL: "https://bundles.example/linear.tar.gz"
        )
        let installBody = """
        {
          "id": "\(pluginID)",
          "enabled": true
        }
        """
        let installedBody = """
        {
          "plugins": [
            {
              "id": "\(pluginID)",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "version": "1.2.3",
                "bundle_download_url": "https://bundles.example/linear.tar.gz",
                "app_ids": [],
                "interface": {},
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let emptyInstalledBody = """
        {
          "plugins": [],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)", "includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("GET", "/linear.tar.gz", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: bundleBytes)
                case ("POST", "/backend-api/ps/plugins/\(pluginID)/install", nil):
                    guard FileManager.default.fileExists(atPath: installedManifest.path) else {
                        return URLSessionTransportResponse(statusCode: 409, body: Data("cache missing before mutation".utf8))
                    }
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=GLOBAL&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=WORKSPACE&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(emptyInstalledBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["authPolicy"] as? String, "ON_USE")
        XCTAssertEqual((result["appsNeedingAuth"] as? [Any])?.count, 0)
        XCTAssertEqual(capture.requests.map { $0.httpMethod ?? "" }, ["GET", "GET", "POST", "GET", "GET"])
        XCTAssertEqual(
            try String(contentsOf: installedMarker, encoding: .utf8),
            "from-remote-bundle"
        )
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer chatgpt-token",
            nil,
            "Bearer chatgpt-token",
            "Bearer chatgpt-token",
            "Bearer chatgpt-token"
        ])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") }, [
            "account-123",
            nil,
            "account-123",
            "account-123",
            "account-123"
        ])
    }

    func testPluginInstallRemoteRefreshesInstalledBundleCacheAfterMutation() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let pluginID = "plugins_123"
        let linearSource = temp.url.appendingPathComponent("linear-source", isDirectory: true)
        try writePluginFixture(
            root: linearSource,
            relativePath: "linear",
            pluginName: "linear",
            version: "0.0.1-local-ignored",
            marker: "from-linear-bundle"
        )
        let linearBundleBytes = try remotePluginBundleTarGzBytes(
            pluginRoot: linearSource.appendingPathComponent("linear", isDirectory: true),
            in: temp.url
        )
        let notionSource = temp.url.appendingPathComponent("notion-source", isDirectory: true)
        try writePluginFixture(
            root: notionSource,
            relativePath: "notion",
            pluginName: "notion",
            version: "0.0.1-local-ignored",
            marker: "from-installed-sync"
        )
        let notionBundleBytes = try remotePluginBundleTarGzBytes(
            pluginRoot: notionSource.appendingPathComponent("notion", isDirectory: true),
            in: temp.url
        )
        let staleCacheRoot = temp.url.appendingPathComponent("plugins/cache/chatgpt-global/stale", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staleCacheRoot.appendingPathComponent("old/.codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )

        let detailBody = remotePluginDetailBody(
            id: pluginID,
            name: "linear",
            displayName: "Linear",
            scope: "GLOBAL",
            releaseVersion: "1.2.3",
            bundleDownloadURL: "https://bundles.example/linear.tar.gz"
        )
        let installBody = """
        {
          "id": "\(pluginID)",
          "enabled": true
        }
        """
        let installedBody = """
        {
          "plugins": [
            {
              "id": "\(pluginID)",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "version": "1.2.3",
                "bundle_download_url": "https://bundles.example/linear.tar.gz",
                "app_ids": [],
                "interface": {},
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            },
            {
              "id": "plugins_456",
              "name": "notion",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Notion",
                "description": "Track notes in Notion",
                "version": "9.9.9",
                "bundle_download_url": "https://bundles.example/notion.tar.gz",
                "app_ids": [],
                "interface": {},
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let emptyInstalledBody = """
        {
          "plugins": [],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)", "includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("GET", "/linear.tar.gz", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: linearBundleBytes)
                case ("POST", "/backend-api/ps/plugins/\(pluginID)/install", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=GLOBAL&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                case ("GET", "/notion.tar.gz", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: notionBundleBytes)
                case ("GET", "/backend-api/ps/plugins/installed", "scope=WORKSPACE&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(emptyInstalledBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        XCTAssertNotNil(response["result"] as? [String: Any])
        let syncedMarker = temp.url.appendingPathComponent(
            "plugins/cache/chatgpt-global/notion/9.9.9/marker.txt",
            isDirectory: false
        )
        XCTAssertEqual(try String(contentsOf: syncedMarker, encoding: .utf8), "from-installed-sync")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleCacheRoot.path))
        XCTAssertEqual(capture.requests.map { $0.url?.path ?? "" }, [
            "/backend-api/ps/plugins/\(pluginID)",
            "/linear.tar.gz",
            "/backend-api/ps/plugins/\(pluginID)/install",
            "/backend-api/ps/plugins/installed",
            "/notion.tar.gz",
            "/backend-api/ps/plugins/installed"
        ])
    }

    func testPluginInstallRemoteRejectsUnavailablePluginsBeforeMutation() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins_123"
        let detailBody = remotePluginDetailBody(
            id: pluginID,
            name: "linear",
            displayName: "Linear",
            scope: "GLOBAL",
            installationPolicy: "NOT_AVAILABLE",
            releaseVersion: "1.2.3",
            bundleDownloadURL: "https://bundles.example/linear.tar.gz"
        )
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)", "includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "remote plugin \(pluginID) is not available for install")
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testPluginInstallRemoteRejectsBundleLinksBeforeExtraction() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins_123"
        let bundleSource = temp.url.appendingPathComponent("remote-bundle-with-link", isDirectory: true)
        try writePluginFixture(
            root: bundleSource,
            relativePath: "linear",
            pluginName: "linear",
            version: "0.0.1-local-ignored",
            marker: "from-remote-bundle"
        )
        try FileManager.default.createSymbolicLink(
            atPath: bundleSource.appendingPathComponent("linear/link-to-marker", isDirectory: false).path,
            withDestinationPath: "marker.txt"
        )
        let bundleBytes = try remotePluginBundleTarGzBytes(
            pluginRoot: bundleSource.appendingPathComponent("linear", isDirectory: true),
            in: temp.url
        )
        let detailBody = remotePluginDetailBody(
            id: pluginID,
            name: "linear",
            displayName: "Linear",
            scope: "GLOBAL",
            releaseVersion: "1.2.3",
            bundleDownloadURL: "https://bundles.example/linear.tar.gz"
        )
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)", "includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("GET", "/linear.tar.gz", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: bundleBytes)
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertTrue((error["message"] as? String)?.contains("remote plugin bundle tar entry `./link-to-marker` is a link") == true)
        XCTAssertEqual(capture.requests.map { $0.httpMethod ?? "" }, ["GET", "GET"])
        let cacheRoot = temp.url.appendingPathComponent("plugins/cache/chatgpt-global/linear", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheRoot.path))
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

    func testPluginInstallReturnsDirectoryAppsNeedingAuth() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try makeLocalMarketplaceRootWithPlugin(named: "debug", pluginName: "weather", in: temp.url)
        let marketplacePath = sourceRoot.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        try """
        {
          "apps": {
            "weather": {
              "id": "connector_weather",
              "name": "Weather"
            },
            "disallowed": {
              "id": "asdk_app_6938a94a61d881918ef32cb999ff937c",
              "name": "Disallowed app"
            },
            "hidden": {
              "id": "connector_hidden",
              "name": "Hidden app"
            }
          }
        }
        """.write(
            to: sourceRoot.appendingPathComponent("plugins/weather/.app.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml", isDirectory: false), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json", isDirectory: false), atomically: true, encoding: .utf8)
        let connectorBody = """
        {
          "apps": [
            {
              "id": "connector_weather",
              "name": "Weather",
              "description": "Weather connector"
            },
            {
              "id": "asdk_app_6938a94a61d881918ef32cb999ff937c",
              "name": "Disallowed app",
              "description": "Filtered app"
            },
            {
              "id": "connector_hidden",
              "name": "Hidden app",
              "description": "Hidden connector",
              "visibility": "HIDDEN"
            }
          ],
          "next_token": null
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/connectors/directory/list", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(connectorBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let install = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"marketplacePath":\#(jsonString(marketplacePath)),"pluginName":"weather"}}"#,
            configuration: configuration
        )
        let installResult = try XCTUnwrap(install["result"] as? [String: Any])
        let appsNeedingAuth = try XCTUnwrap(installResult["appsNeedingAuth"] as? [[String: Any]])
        XCTAssertEqual(appsNeedingAuth.count, 1)
        XCTAssertEqual(appsNeedingAuth[0]["id"] as? String, "connector_weather")
        XCTAssertEqual(appsNeedingAuth[0]["name"] as? String, "Weather")
        XCTAssertEqual(appsNeedingAuth[0]["description"] as? String, "Weather connector")
        XCTAssertEqual(appsNeedingAuth[0]["installUrl"] as? String, "https://chatgpt.com/apps/weather/connector_weather")
        XCTAssertEqual(appsNeedingAuth[0]["needsAuth"] as? Bool, true)
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer chatgpt-token"])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") }, ["account-123"])
    }

    func testPluginInstallRemoteReturnsDirectoryAppsNeedingAuth() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        apps = true
        plugins = true
        remote_plugin = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let pluginID = "plugins_123"
        let bundleSource = temp.url.appendingPathComponent("remote-bundle-source", isDirectory: true)
        try writePluginFixture(
            root: bundleSource,
            relativePath: "linear",
            pluginName: "linear",
            version: "0.0.1-local-ignored",
            marker: "from-remote-bundle"
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
            to: bundleSource.appendingPathComponent("linear/.app.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bundleBytes = try remotePluginBundleTarGzBytes(
            pluginRoot: bundleSource.appendingPathComponent("linear", isDirectory: true),
            in: temp.url
        )
        let detailBody = remotePluginDetailBody(
            id: pluginID,
            name: "linear",
            displayName: "Linear",
            scope: "GLOBAL",
            releaseVersion: "1.2.3",
            bundleDownloadURL: "https://bundles.example/linear.tar.gz"
        )
        let installBody = """
        {
          "id": "\(pluginID)",
          "enabled": true
        }
        """
        let installedBody = """
        {
          "plugins": [
            {
              "id": "\(pluginID)",
              "name": "linear",
              "scope": "GLOBAL",
              "installation_policy": "AVAILABLE",
              "authentication_policy": "ON_USE",
              "status": "ENABLED",
              "release": {
                "display_name": "Linear",
                "description": "Track work in Linear",
                "version": "1.2.3",
                "bundle_download_url": "https://bundles.example/linear.tar.gz",
                "app_ids": [],
                "interface": {},
                "skills": []
              },
              "enabled": true,
              "disabled_skill_names": []
            }
          ],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let emptyInstalledBody = """
        {
          "plugins": [],
          "pagination": {
            "limit": 50,
            "next_page_token": null
          }
        }
        """
        let connectorBody = """
        {
          "apps": [
            {
              "id": "connector_weather",
              "name": "Weather",
              "description": "Weather connector"
            }
          ],
          "next_token": null
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path, request.url?.query) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)", "includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("GET", "/linear.tar.gz", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: bundleBytes)
                case ("POST", "/backend-api/ps/plugins/\(pluginID)/install", nil):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=GLOBAL&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(installedBody.utf8))
                case ("GET", "/backend-api/ps/plugins/installed", "scope=WORKSPACE&includeDownloadUrls=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(emptyInstalledBody.utf8))
                case ("GET", "/backend-api/connectors/directory/list", "external_logos=true"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(connectorBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let install = try appServerResponse(
            #"{"id":1,"method":"plugin/install","params":{"remoteMarketplaceName":"chatgpt-global","pluginName":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        let installResult = try XCTUnwrap(install["result"] as? [String: Any])
        let appsNeedingAuth = try XCTUnwrap(installResult["appsNeedingAuth"] as? [[String: Any]])
        XCTAssertEqual(appsNeedingAuth.count, 1)
        XCTAssertEqual(appsNeedingAuth[0]["id"] as? String, "connector_weather")
        XCTAssertEqual(appsNeedingAuth[0]["name"] as? String, "Weather")
        XCTAssertEqual(appsNeedingAuth[0]["description"] as? String, "Weather connector")
        XCTAssertEqual(appsNeedingAuth[0]["installUrl"] as? String, "https://chatgpt.com/apps/weather/connector_weather")
        XCTAssertEqual(appsNeedingAuth[0]["needsAuth"] as? Bool, true)
        XCTAssertEqual(capture.requests.map { $0.httpMethod }, ["GET", "GET", "POST", "GET", "GET", "GET"])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer chatgpt-token",
            nil,
            "Bearer chatgpt-token",
            "Bearer chatgpt-token",
            "Bearer chatgpt-token",
            "Bearer chatgpt-token"
        ])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") }, [
            "account-123",
            nil,
            "account-123",
            "account-123",
            "account-123",
            "account-123"
        ])
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

    func testPluginUninstallValidatesIdsAndReportsRemoteDisabledWhenPluginsDisabled() throws {
        let temp = try TemporaryDirectory()

        let invalid = try appServerResponse(
            #"{"id":1,"method":"plugin/uninstall","params":{"pluginId":"bad id","forceRemoteSync":true}}"#,
            codexHome: temp.url
        )
        let invalidError = try XCTUnwrap(invalid["error"] as? [String: Any])
        XCTAssertEqual(invalidError["code"] as? Int, -32600)
        XCTAssertEqual(invalidError["message"] as? String, "invalid remote plugin id")

        try """
        [features]
        plugins = false
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let remoteDisabled = try appServerResponse(
            #"{"id":2,"method":"plugin/uninstall","params":{"pluginId":"plugins~Plugin_gmail","forceRemoteSync":true}}"#,
            codexHome: temp.url
        )
        let remoteDisabledError = try XCTUnwrap(remoteDisabled["error"] as? [String: Any])
        XCTAssertEqual(remoteDisabledError["code"] as? Int, -32600)
        XCTAssertEqual(remoteDisabledError["message"] as? String, "remote plugin uninstall is not enabled")
    }

    func testPluginUninstallRemovesRemotePluginCacheAfterCloudMutation() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let pluginID = "plugins~Plugin_linear"
        let detailBody = remotePluginDetailBody(id: pluginID, name: "linear", displayName: "Linear", scope: "GLOBAL")
        let uninstallBody = #"{"id":"plugins~Plugin_linear","enabled":false}"#
        let cacheRoot = temp.url.appendingPathComponent("plugins/cache/chatgpt-global/linear", isDirectory: true)
        let legacyCacheRoot = temp.url.appendingPathComponent("plugins/cache/chatgpt-global/\(pluginID)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheRoot.appendingPathComponent("1.0.0/.codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyCacheRoot.appendingPathComponent("local/.codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("POST", "/backend-api/plugins/\(pluginID)/uninstall"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(uninstallBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/uninstall","params":{"pluginId":"\#(pluginID)","forceRemoteSync":true}}"#,
            configuration: configuration
        )
        XCTAssertNotNil(response["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCacheRoot.path))
        XCTAssertEqual(capture.requests.map { $0.httpMethod ?? "" }, ["GET", "POST"])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer chatgpt-token", "Bearer chatgpt-token"])
        XCTAssertEqual(capture.requests.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") }, ["account-123", "account-123"])
    }

    func testPluginUninstallUsesRemoteDetailScopeForWorkspaceCache() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"

        [features]
        plugins = true
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let pluginID = "plugins_69f27c3e67848191a45cbaa5f2adb39d"
        let detailBody = remotePluginDetailBody(id: pluginID, name: "skill-improver", displayName: "Skill Improver", scope: "WORKSPACE")
        let uninstallBody = #"{"id":"plugins_69f27c3e67848191a45cbaa5f2adb39d","enabled":false}"#
        let workspaceCacheRoot = temp.url.appendingPathComponent("plugins/cache/workspace-directory/skill-improver", isDirectory: true)
        let globalCacheRoot = temp.url.appendingPathComponent("plugins/cache/chatgpt-global/skill-improver", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspaceCacheRoot.appendingPathComponent("1.0.0/.codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: globalCacheRoot.appendingPathComponent("1.0.0/.codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/backend-api/ps/plugins/\(pluginID)"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(detailBody.utf8))
                case ("POST", "/backend-api/plugins/\(pluginID)/uninstall"):
                    return URLSessionTransportResponse(statusCode: 200, body: Data(uninstallBody.utf8))
                default:
                    return URLSessionTransportResponse(statusCode: 404, body: Data("missing".utf8))
                }
            }
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"plugin/uninstall","params":{"pluginId":"\#(pluginID)"}}"#,
            configuration: configuration
        )
        XCTAssertNotNil(response["result"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceCacheRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: globalCacheRoot.path))
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

    func testExternalAgentConfigImportSessionsWithoutDetailsIsNoopLikeRust() throws {
        let temp = try TemporaryDirectory()
        let processor = try initializedProcessor(configuration: CodexAppServerConfiguration(codexHome: temp.url))

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"externalAgentConfig/import","params":{"migrationItems":[{"itemType":"SESSIONS","description":"Sessions","cwd":null}]}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["id"] as? Int, 1)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?.isEmpty, true)
        XCTAssertEqual(messages[1]["method"] as? String, "externalAgentConfig/import/completed")

        let list = try decode(processor.processLine(Data(
            #"{"id":2,"method":"thread/list","params":{}}"#.utf8
        )))
        let threads = try XCTUnwrap((list["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertTrue(threads.isEmpty)
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

    func testExternalAgentConfigDetectPluginsReportsRemoteMarketplaceSources() throws {
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
          "enabledPlugins": {
            "formatter@acme-tools": true
          },
          "extraKnownMarketplaces": {
            "acme-tools": {
              "source": "acme-corp/external-agent-plugins"
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
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        let plugins = try XCTUnwrap(details["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["marketplaceName"] as? String, "acme-tools")
        XCTAssertEqual(plugins[0]["pluginNames"] as? [String], ["formatter"])
    }

    func testExternalAgentConfigDetectPluginsInfersExternalOfficialMarketplace() throws {
        let temp = try TemporaryDirectory()
        let codexHome = temp.url.appendingPathComponent("codex-home", isDirectory: true)
        let home = temp.url.appendingPathComponent("home", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try """
        {
          "enabledPlugins": {
            "sample@claude-plugins-official": true
          }
        }
        """.write(
            to: claude.appendingPathComponent("settings.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let detect = try appServerResponse(
            #"{"id":1,"method":"externalAgentConfig/detect","params":{"includeHome":true}}"#,
            configuration: testConfiguration(codexHome: codexHome, environment: ["HOME": home.path])
        )
        let items = try XCTUnwrap((detect["result"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["itemType"] as? String }, ["PLUGINS"])
        let details = try XCTUnwrap(items[0]["details"] as? [String: Any])
        let plugins = try XCTUnwrap(details["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins[0]["marketplaceName"] as? String, "claude-plugins-official")
        XCTAssertEqual(plugins[0]["pluginNames"] as? [String], ["sample"])
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

    func testMcpResourceReadStdioUsesThreadOrServerCwdFallback() throws {
        let temp = try TemporaryDirectory()
        let threadCwd = temp.url.appendingPathComponent("thread-cwd", isDirectory: true)
        let serverCwd = temp.url.appendingPathComponent("server-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: threadCwd, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: serverCwd, withIntermediateDirectories: true)
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T05-04-05",
            timestamp: "2025-01-02T05:04:05Z",
            preview: "MCP thread cwd",
            provider: "openai",
            cwd: threadCwd.path
        )
        let script = temp.url.appendingPathComponent("stdio-mcp-cwd.sh", isDirectory: false)
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
              cwd=$(pwd)
              printf '%s\\n' "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"contents\\":[{\\"uri\\":\\"test://codex/cwd\\",\\"mimeType\\":\\"text/plain\\",\\"text\\":\\"$cwd\\"}]}}"
              exit 0
              ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try """
        [mcp_servers.stdio]
        command = "\(script.path)"
        tool_timeout_sec = 10
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let configuration = CodexAppServerConfiguration(
            codexHome: temp.url,
            cwd: serverCwd,
            requiresOpenAIAuth: false,
            environment: [
                CodexConfigLayerLoader.managedConfigEnvironmentVariable: temp.url
                    .appendingPathComponent("missing-managed-config.toml", isDirectory: false)
                    .path
            ]
        )
        let processor = try initializedProcessor(configuration: configuration)
        let threadResponse = try decode(processor.processLine(Data(
            #"{"id":1,"method":"mcpServer/resource/read","params":{"threadId":"\#(threadID)","server":"stdio","uri":"test://codex/cwd"}}"#.utf8
        )))
        let noThreadResponse = try decode(processor.processLine(Data(
            #"{"id":2,"method":"mcpServer/resource/read","params":{"server":"stdio","uri":"test://codex/cwd"}}"#.utf8
        )))

        let threadResult = try XCTUnwrap(threadResponse["result"] as? [String: Any])
        let threadContents = try XCTUnwrap(threadResult["contents"] as? [[String: Any]])
        let noThreadResult = try XCTUnwrap(noThreadResponse["result"] as? [String: Any])
        let noThreadContents = try XCTUnwrap(noThreadResult["contents"] as? [[String: Any]])
        func normalizedPath(_ path: String?) -> String? {
            path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        }
        XCTAssertEqual(
            normalizedPath(threadContents.first?["text"] as? String),
            normalizedPath(threadCwd.path)
        )
        XCTAssertEqual(
            normalizedPath(noThreadContents.first?["text"] as? String),
            normalizedPath(serverCwd.path)
        )
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

    func testThreadTurnsListCanReturnArchivedThreadsByIDLikeRust() throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "archived first",
            provider: "mock_provider",
            archived: true
        )
        let archivedPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID,
            includeArchived: true
        ))
        try appendRolloutEvents(to: archivedPath, timestamp: "2025-01-05T12:00:01Z", events: [
            .agentMessage(AgentMessageEvent(message: "archived final"))
        ])

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/turns/list","params":{"threadId":"\#(threadID)","limit":10}}"#,
            codexHome: temp.url,
            experimentalAPIEnabled: true
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(turnUserText(data[0]), "archived first")
        XCTAssertEqual(turnAgentTexts(data[0]), ["archived final"])
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

    func testThreadListSupportsRustSourceCwdSearchAndArchiveFilters() throws {
        let temp = try TemporaryDirectory()
        let repoA = temp.url.appendingPathComponent("repo-a", isDirectory: true).path
        let repoB = temp.url.appendingPathComponent("repo-b", isDirectory: true).path
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-05T12-00-00",
            timestamp: "2025-01-05T12:00:00Z",
            preview: "exec target match",
            provider: "openai",
            source: .exec,
            cwd: repoA
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-04T12-00-00",
            timestamp: "2025-01-04T12:00:00Z",
            preview: "exec other cwd",
            provider: "openai",
            source: .exec,
            cwd: repoB
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "archived target match",
            provider: "openai",
            archived: true,
            cwd: repoA
        )

        let execResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"sourceKinds":["exec"],"cwd":"\#(repoA)","searchTerm":"target"}}"#,
            codexHome: temp.url
        )
        let execData = try XCTUnwrap((execResponse["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertEqual(execData.map { $0["preview"] as? String }, ["exec target match"])

        let archivedResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"archived":true,"cwd":["\#(repoA)"],"searchTerm":"target"}}"#,
            codexHome: temp.url
        )
        let archivedData = try XCTUnwrap((archivedResponse["result"] as? [String: Any])?["data"] as? [[String: Any]])
        XCTAssertEqual(archivedData.map { $0["preview"] as? String }, ["archived target match"])
    }

    func testThreadListSupportsRustSortAndBackwardsCursor() throws {
        let temp = try TemporaryDirectory()
        let oldestID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T12-00-00",
            timestamp: "2025-01-01T12:00:00Z",
            preview: "oldest",
            provider: "openai"
        )
        let middleID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "middle",
            provider: "openai"
        )
        let newestID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "newest",
            provider: "openai"
        )
        try setModificationDate("2025-02-03T12:00:00Z", for: oldestID, codexHome: temp.url)
        try setModificationDate("2025-02-01T12:00:00Z", for: middleID, codexHome: temp.url)
        try setModificationDate("2025-02-02T12:00:00Z", for: newestID, codexHome: temp.url)

        let firstResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":2,"sortDirection":"asc"}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(firstResponse["result"] as? [String: Any])
        let firstData = try XCTUnwrap(firstResult["data"] as? [[String: Any]])
        XCTAssertEqual(firstData.map { $0["preview"] as? String }, ["oldest", "middle"])
        XCTAssertEqual(firstResult["nextCursor"] as? String, "2025-01-02T12:00:00Z")
        XCTAssertEqual(firstResult["backwardsCursor"] as? String, "2025-01-01T12:00:00.001Z")

        let cursor = try XCTUnwrap(firstResult["nextCursor"] as? String)
        let secondResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"limit":2,"sortDirection":"asc","cursor":"\#(cursor)"}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(secondResponse["result"] as? [String: Any])
        let secondData = try XCTUnwrap(secondResult["data"] as? [[String: Any]])
        XCTAssertEqual(secondData.map { $0["preview"] as? String }, ["newest"])
        XCTAssertTrue(secondResult["nextCursor"] is NSNull)
        XCTAssertEqual(secondResult["backwardsCursor"] as? String, "2025-01-03T12:00:00.001Z")

        let updatedResponse = try appServerResponse(
            #"{"id":3,"method":"thread/list","params":{"sortKey":"updated_at"}}"#,
            codexHome: temp.url
        )
        let updatedResult = try XCTUnwrap(updatedResponse["result"] as? [String: Any])
        let updatedData = try XCTUnwrap(updatedResult["data"] as? [[String: Any]])
        XCTAssertEqual(updatedData.map { $0["preview"] as? String }, ["oldest", "newest", "middle"])
    }

    func testThreadListRejectsInvalidCursorWithRustErrorCode() throws {
        let temp = try TemporaryDirectory()

        let invalidTimestampResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"cursor":"not-a-cursor","limit":2}}"#,
            codexHome: temp.url
        )
        let invalidTimestampError = try XCTUnwrap(invalidTimestampResponse["error"] as? [String: Any])
        XCTAssertEqual(invalidTimestampError["code"] as? Int, -32600)
        XCTAssertEqual(invalidTimestampError["message"] as? String, "invalid cursor: not-a-cursor")

        let legacySwiftCursorResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"cursor":"2025-01-01T12-00-00|01234567-89ab-cdef-0123-456789abcdef"}}"#,
            codexHome: temp.url
        )
        let legacySwiftCursorError = try XCTUnwrap(legacySwiftCursorResponse["error"] as? [String: Any])
        XCTAssertEqual(legacySwiftCursorError["code"] as? Int, -32600)
        XCTAssertEqual(
            legacySwiftCursorError["message"] as? String,
            "invalid cursor: 2025-01-01T12-00-00|01234567-89ab-cdef-0123-456789abcdef"
        )
    }

    func testThreadListStateDbOnlyReturnsSQLiteWithoutRolloutScan() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T10-00-00",
            timestamp: "2025-01-02T10:00:00Z",
            preview: "rollout cwd should not match stale sqlite cwd",
            provider: "openai",
            cwd: temp.url.appendingPathComponent("rollout-cwd", isDirectory: true).path
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let staleCwd = temp.url.appendingPathComponent("stale-cwd", isDirectory: true)
        try await stateStore.upsertThread(ThreadMetadata(
            id: ThreadId(string: threadID),
            rolloutPath: rolloutPath,
            createdAt: try appServerDate("2025-01-02T10:00:00Z"),
            updatedAt: try appServerDate("2025-01-03T10:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: staleCwd.path,
            cliVersion: "0.0.0",
            title: "stale sqlite title",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "state db only stale cwd"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let stateOnlyResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"cwd":"\#(staleCwd.path)","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let stateOnlyResult = try XCTUnwrap(stateOnlyResponse["result"] as? [String: Any])
        let stateOnlyData = try XCTUnwrap(stateOnlyResult["data"] as? [[String: Any]])
        XCTAssertEqual(stateOnlyData.map { $0["id"] as? String }, [threadID])
        XCTAssertEqual(stateOnlyData.map { $0["preview"] as? String }, ["state db only stale cwd"])
        XCTAssertEqual(stateOnlyData.map { $0["cwd"] as? String }, [staleCwd.path])

        let scannedResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"limit":10,"cwd":"\#(staleCwd.path)","useStateDbOnly":false}}"#,
            configuration: configuration
        )
        let scannedResult = try XCTUnwrap(scannedResponse["result"] as? [String: Any])
        let scannedData = try XCTUnwrap(scannedResult["data"] as? [[String: Any]])
        XCTAssertTrue(scannedData.isEmpty)
    }

    func testThreadListCwdFilterRepairsStaleStateDbHitsBeforeReturning() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T13-00-00",
            timestamp: "2025-01-03T13:00:00Z",
            preview: "Hello from user",
            provider: "openai",
            cwd: temp.url.path
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let staleCwd = temp.url.appendingPathComponent("stale-cwd", isDirectory: true)
        try await stateStore.upsertThread(ThreadMetadata(
            id: ThreadId(string: threadID),
            rolloutPath: rolloutPath,
            createdAt: try appServerDate("2025-01-03T13:00:00Z"),
            updatedAt: try appServerDate("2025-01-03T13:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: staleCwd.path,
            cliVersion: "0.0.0",
            title: "Hello from user",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "Hello from user"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let staleStateOnlyResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"cwd":"\#(staleCwd.path)","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let staleStateOnlyResult = try XCTUnwrap(staleStateOnlyResponse["result"] as? [String: Any])
        let staleStateOnlyData = try XCTUnwrap(staleStateOnlyResult["data"] as? [[String: Any]])
        XCTAssertEqual(staleStateOnlyData.map { $0["id"] as? String }, [threadID])

        let scannedResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"limit":10,"cwd":"\#(staleCwd.path)","useStateDbOnly":false}}"#,
            configuration: configuration
        )
        let scannedResult = try XCTUnwrap(scannedResponse["result"] as? [String: Any])
        let scannedData = try XCTUnwrap(scannedResult["data"] as? [[String: Any]])
        XCTAssertTrue(scannedData.isEmpty)

        let repairedStateOnlyResponse = try appServerResponse(
            #"{"id":3,"method":"thread/list","params":{"limit":10,"cwd":"\#(staleCwd.path)","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let repairedStateOnlyResult = try XCTUnwrap(repairedStateOnlyResponse["result"] as? [String: Any])
        let repairedStateOnlyData = try XCTUnwrap(repairedStateOnlyResult["data"] as? [[String: Any]])
        XCTAssertTrue(repairedStateOnlyData.isEmpty)
    }

    func testThreadListRepairsStateDbForLaterStateDbOnlyListing() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T14-00-00",
            timestamp: "2025-01-03T14:00:00Z",
            preview: "Hello from user",
            provider: "openai",
            cwd: temp.url.path
        )
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let stateOnlyBeforeRepairResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"cwd":"\#(temp.url.path)","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let stateOnlyBeforeRepairResult = try XCTUnwrap(stateOnlyBeforeRepairResponse["result"] as? [String: Any])
        let stateOnlyBeforeRepairData = try XCTUnwrap(stateOnlyBeforeRepairResult["data"] as? [[String: Any]])
        XCTAssertTrue(stateOnlyBeforeRepairData.isEmpty)

        let repairedResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"limit":10,"cwd":"\#(temp.url.path)","useStateDbOnly":false}}"#,
            configuration: configuration
        )
        let repairedResult = try XCTUnwrap(repairedResponse["result"] as? [String: Any])
        let repairedData = try XCTUnwrap(repairedResult["data"] as? [[String: Any]])
        XCTAssertEqual(repairedData.map { $0["id"] as? String }, [threadID])

        let stateOnlyAfterRepairResponse = try appServerResponse(
            #"{"id":3,"method":"thread/list","params":{"limit":10,"cwd":"\#(temp.url.path)","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let stateOnlyAfterRepairResult = try XCTUnwrap(stateOnlyAfterRepairResponse["result"] as? [String: Any])
        let stateOnlyAfterRepairData = try XCTUnwrap(stateOnlyAfterRepairResult["data"] as? [[String: Any]])
        XCTAssertEqual(stateOnlyAfterRepairData.map { $0["id"] as? String }, [threadID])
        XCTAssertEqual(stateOnlyAfterRepairData.map { $0["preview"] as? String }, ["Hello from user"])
        XCTAssertEqual(stateOnlyAfterRepairData.map { $0["modelProvider"] as? String }, ["openai"])
    }

    func testThreadListReturnsStateDbPageAfterUnfilteredRepair() async throws {
        let temp = try TemporaryDirectory()
        let sqliteFirstThreadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T15-00-00",
            timestamp: "2025-01-03T15:00:00Z",
            preview: "SQLite updated first",
            provider: "openai",
            cwd: temp.url.path
        )
        let filesystemFirstThreadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T16-00-00",
            timestamp: "2025-01-03T16:00:00Z",
            preview: "Filesystem updated first",
            provider: "openai",
            cwd: temp.url.path
        )
        try setModificationDate("2025-01-03T15:00:00Z", for: sqliteFirstThreadID, codexHome: temp.url)
        try setModificationDate("2025-01-03T16:00:00Z", for: filesystemFirstThreadID, codexHome: temp.url)
        let sqliteFirstPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: sqliteFirstThreadID
        ))
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        try await stateStore.upsertThread(ThreadMetadata(
            id: ThreadId(string: sqliteFirstThreadID),
            rolloutPath: sqliteFirstPath,
            createdAt: try appServerDate("2025-01-03T15:00:00Z"),
            updatedAt: try appServerDate("2025-01-04T15:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: temp.url.path,
            cliVersion: "0.0.0",
            title: "SQLite updated first",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "SQLite updated first"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":1,"sortKey":"updated_at"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])

        XCTAssertEqual(data.map { $0["id"] as? String }, [sqliteFirstThreadID])
        XCTAssertNotEqual(data.map { $0["id"] as? String }, [filesystemFirstThreadID])
    }

    func testThreadListOverlaysStateDbGitMetadataForFilteredListing() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T16-00-00",
            timestamp: "2025-01-03T16:00:00Z",
            preview: "Hello from user",
            provider: "openai",
            cwd: temp.url.path
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        try await stateStore.upsertThread(ThreadMetadata(
            id: ThreadId(string: threadID),
            rolloutPath: rolloutPath,
            createdAt: try appServerDate("2025-01-03T16:00:00Z"),
            updatedAt: try appServerDate("2025-01-03T16:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: temp.url.path,
            cliVersion: "0.0.0",
            title: "Hello from user",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "Hello from user",
            gitSHA: "sqlite-sha",
            gitBranch: "sqlite-branch",
            gitOriginURL: "https://example.com/repo.git"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"sourceKinds":["cli"]}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let thread = try XCTUnwrap(data.first)
        let gitInfo = try XCTUnwrap(thread["gitInfo"] as? [String: Any])

        XCTAssertEqual(thread["id"] as? String, threadID)
        XCTAssertEqual(gitInfo["sha"] as? String, "sqlite-sha")
        XCTAssertEqual(gitInfo["branch"] as? String, "sqlite-branch")
        XCTAssertEqual(gitInfo["originUrl"] as? String, "https://example.com/repo.git")
    }

    func testThreadListSearchRepairsStaleStateDbHitsBeforeReturning() async throws {
        let temp = try TemporaryDirectory()
        let threadID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T15-00-00",
            timestamp: "2025-01-03T15:00:00Z",
            preview: "Hello from user",
            provider: "openai",
            cwd: temp.url.path
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: threadID
        ))
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        try await stateStore.upsertThread(ThreadMetadata(
            id: ThreadId(string: threadID),
            rolloutPath: rolloutPath,
            createdAt: try appServerDate("2025-01-03T15:00:00Z"),
            updatedAt: try appServerDate("2025-01-03T15:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: temp.url.path,
            cliVersion: "0.0.0",
            title: "needle stale title",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "stale first user"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let staleStateOnlyResponse = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"searchTerm":"needle","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let staleStateOnlyResult = try XCTUnwrap(staleStateOnlyResponse["result"] as? [String: Any])
        let staleStateOnlyData = try XCTUnwrap(staleStateOnlyResult["data"] as? [[String: Any]])
        XCTAssertEqual(staleStateOnlyData.map { $0["id"] as? String }, [threadID])

        let scannedResponse = try appServerResponse(
            #"{"id":2,"method":"thread/list","params":{"limit":10,"searchTerm":"needle","useStateDbOnly":false}}"#,
            configuration: configuration
        )
        let scannedResult = try XCTUnwrap(scannedResponse["result"] as? [String: Any])
        let scannedData = try XCTUnwrap(scannedResult["data"] as? [[String: Any]])
        XCTAssertTrue(scannedData.isEmpty)

        let repairedStateOnlyResponse = try appServerResponse(
            #"{"id":3,"method":"thread/list","params":{"limit":10,"searchTerm":"needle","useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let repairedStateOnlyResult = try XCTUnwrap(repairedStateOnlyResponse["result"] as? [String: Any])
        let repairedStateOnlyData = try XCTUnwrap(repairedStateOnlyResult["data"] as? [[String: Any]])
        XCTAssertTrue(repairedStateOnlyData.isEmpty)
    }

    func testThreadListStateDbOnlyDropsMissingRolloutPaths() async throws {
        let temp = try TemporaryDirectory()
        let stateDatabaseURL = temp.url.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let staleThreadID = try ThreadId(string: "00000000-0000-0000-0000-000000009010")
        let staleRolloutPath = temp.url
            .appendingPathComponent("sessions/2099/01/01/rollout-2099-01-01T00-00-00-\(staleThreadID).jsonl")
            .path
        try await stateStore.upsertThread(ThreadMetadata(
            id: staleThreadID,
            rolloutPath: staleRolloutPath,
            createdAt: try appServerDate("2025-01-03T13:00:00Z"),
            updatedAt: try appServerDate("2025-01-03T13:00:00Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: temp.url.path,
            cliVersion: "0.0.0",
            title: "stale state db path",
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: "stale row should be dropped"
        ))
        let configuration = testConfiguration(codexHome: temp.url, stateStore: stateStore)

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":10,"useStateDbOnly":true}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        let storedPath = try await stateStore.findRolloutPath(threadID: staleThreadID, archiveFilter: .all)

        XCTAssertTrue(data.isEmpty)
        XCTAssertNil(storedPath)
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

    func testThreadArchiveMarksSQLiteThreadArchivedLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let id = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "archive state",
            provider: "openai"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: id
        ))
        let stateStore = try createAppServerStateStore(codexHome: temp.url)
        let threadID = try ThreadId(string: id)
        try await upsertAppServerStateThread(
            stateStore,
            threadID: threadID,
            rolloutPath: rolloutPath,
            codexHome: temp.url,
            title: "archive state"
        )

        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            stateStore: stateStore
        ))
        _ = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/archive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        let archivedPath = try await stateStore.findRolloutPath(
            threadID: threadID,
            archiveFilter: .archivedOnly
        )
        let activePath = try await stateStore.findRolloutPath(
            threadID: threadID,
            archiveFilter: .unarchivedOnly
        )
        XCTAssertNil(activePath)
        XCTAssertEqual(
            archivedPath.map(canonicalPath),
            try archivedRolloutPath(codexHome: temp.url, threadID: id).map(canonicalPath)
        )
    }

    func testThreadArchiveArchivesSpawnedDescendantsLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let parentID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-00-00",
            timestamp: "2025-01-01T00:00:00Z",
            preview: "parent",
            provider: "openai"
        )
        let childID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-01-00",
            timestamp: "2025-01-01T00:01:00Z",
            preview: "child",
            provider: "openai"
        )
        let grandchildID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-02-00",
            timestamp: "2025-01-01T00:02:00Z",
            preview: "grandchild",
            provider: "openai"
        )
        let stateStore = try createAppServerStateStore(codexHome: temp.url)
        let parentThreadID = try ThreadId(string: parentID)
        let childThreadID = try ThreadId(string: childID)
        let grandchildThreadID = try ThreadId(string: grandchildID)
        try await stateStore.upsertThreadSpawnEdge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: .closed
        )
        try await stateStore.upsertThreadSpawnEdge(
            parentThreadID: childThreadID,
            childThreadID: grandchildThreadID,
            status: .open
        )

        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            stateStore: stateStore
        ))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/archive","params":{"threadId":"\#(parentID)"}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 4)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(try archivedThreadIDs(from: Array(messages.dropFirst())), [
            parentID,
            grandchildID,
            childID
        ])
        for threadID in [parentID, childID, grandchildID] {
            XCTAssertNil(try RolloutListing.findConversationPathByIDString(
                codexHome: temp.url,
                idString: threadID
            ))
            XCTAssertNotNil(try archivedRolloutPath(codexHome: temp.url, threadID: threadID))
        }
    }

    func testThreadArchiveSkipsFailedSpawnedDescendantLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let parentID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-00-00",
            timestamp: "2025-01-01T00:00:00Z",
            preview: "parent",
            provider: "openai"
        )
        let childID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-01-00",
            timestamp: "2025-01-01T00:01:00Z",
            preview: "child",
            provider: "openai"
        )
        let grandchildID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T00-02-00",
            timestamp: "2025-01-01T00:02:00Z",
            preview: "grandchild",
            provider: "openai"
        )
        let childRolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: childID
        ))
        let childArchiveConflict = temp.url
            .appendingPathComponent("archived_sessions", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: childRolloutPath).lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: childArchiveConflict, withIntermediateDirectories: true)
        let stateStore = try createAppServerStateStore(codexHome: temp.url)
        let parentThreadID = try ThreadId(string: parentID)
        let childThreadID = try ThreadId(string: childID)
        let grandchildThreadID = try ThreadId(string: grandchildID)
        try await stateStore.upsertThreadSpawnEdge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: .closed
        )
        try await stateStore.upsertThreadSpawnEdge(
            parentThreadID: childThreadID,
            childThreadID: grandchildThreadID,
            status: .open
        )

        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            stateStore: stateStore
        ))
        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"thread/archive","params":{"threadId":"\#(parentID)"}}"#.utf8
        )))

        XCTAssertEqual(messages.count, 3)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(try archivedThreadIDs(from: Array(messages.dropFirst())), [
            parentID,
            grandchildID
        ])
        XCTAssertNotNil(try RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: childID
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: childArchiveConflict.path))
        for threadID in [parentID, grandchildID] {
            XCTAssertNil(try RolloutListing.findConversationPathByIDString(
                codexHome: temp.url,
                idString: threadID
            ))
            XCTAssertNotNil(try archivedRolloutPath(codexHome: temp.url, threadID: threadID))
        }
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
        let oldRestoredThreshold = try appServerDate("2026-01-01T00:00:00Z")
        let archivedPath = try XCTUnwrap(archivedRolloutPath(codexHome: temp.url, threadID: id))
        try FileManager.default.setAttributes(
            [.modificationDate: oldRestoredThreshold],
            ofItemAtPath: archivedPath
        )
        let messages = try decodeMessages(processor.processLine(
            Data(#"{"id":2,"method":"thread/unarchive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        let result = try XCTUnwrap(messages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(result["thread"] as? [String: Any])
        XCTAssertEqual(thread["id"] as? String, id)
        XCTAssertEqual(thread["preview"] as? String, "restore me")
        XCTAssertEqual(thread["status"].flatMap { ($0 as? [String: Any])?["type"] as? String }, "notLoaded")
        XCTAssertGreaterThan(
            try XCTUnwrap(thread["updatedAt"] as? Int),
            Int(oldRestoredThreshold.timeIntervalSince1970)
        )
        XCTAssertEqual(messages[1]["method"] as? String, "thread/unarchived")
        let params = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolloutPath))
        XCTAssertNotNil(try RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: id))
    }

    func testThreadUnarchiveMarksSQLiteThreadUnarchivedLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let id = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T03-04-05",
            timestamp: "2025-01-02T03:04:05Z",
            preview: "restore state",
            provider: "openai"
        )
        let rolloutPath = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: temp.url,
            idString: id
        ))
        let stateStore = try createAppServerStateStore(codexHome: temp.url)
        let threadID = try ThreadId(string: id)
        try await upsertAppServerStateThread(
            stateStore,
            threadID: threadID,
            rolloutPath: rolloutPath,
            codexHome: temp.url,
            title: "restore state"
        )
        let processor = try initializedProcessor(configuration: testConfiguration(
            codexHome: temp.url,
            stateStore: stateStore
        ))
        _ = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/archive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        _ = try decodeMessages(processor.processLine(
            Data(#"{"id":2,"method":"thread/unarchive","params":{"threadId":"\#(id)"}}"#.utf8)
        ))

        let activePath = try await stateStore.findRolloutPath(
            threadID: threadID,
            archiveFilter: .unarchivedOnly
        )
        let archivedPath = try await stateStore.findRolloutPath(
            threadID: threadID,
            archiveFilter: .archivedOnly
        )
        XCTAssertEqual(activePath.map(canonicalPath), canonicalPath(rolloutPath))
        XCTAssertNil(archivedPath)
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

    func testAccountLoginChatGPTAuthTokensRequiresExperimentalAPI() throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")

        let response = try appServerResponse(
            #"{"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\#(accessToken)","chatgptAccountId":"org-embedded","chatgptPlanType":"pro"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(error["message"] as? String, "account/login/start.chatgptAuthTokens requires experimentalApi capability")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
    }

    func testAccountLoginChatGPTAuthTokensStoresEphemeralAuthAndNotifies() throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

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

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))
        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
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
            chatGPTPlanType: "pro",
            mode: .ephemeral
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

        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
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
            mode: .ephemeral,
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
        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
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
            codexHome: temp.url,
            experimentalAPIEnabled: true
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

    func testAccountLogoutClearsExternalEphemeralAuthAndEmitsV2Notification() throws {
        let temp = try TemporaryDirectory()
        let accessToken = try fakeJWT(email: "embedded@example.com", plan: "pro", accountID: "org-embedded")
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url),
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data("""
        {"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(accessToken)","chatgptAccountId":"org-embedded","chatgptPlanType":"pro"}}
        """.utf8)))

        let messages = try decodeMessages(processor.processLine(Data(#"{"id":2,"method":"account/logout"}"#.utf8)))
        XCTAssertEqual(messages.count, 2)
        XCTAssertNotNil(messages[0]["result"] as? [String: Any])
        XCTAssertEqual(messages[1]["method"] as? String, "account/updated")
        XCTAssertTrue((messages[1]["params"] as? [String: Any])?["authMode"] is NSNull)
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("auth.json").path))

        let account = try decode(processor.processLine(Data(#"{"id":3,"method":"account/read","params":{}}"#.utf8)))
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

    func testAccountRateLimitsRefreshesExternalAuthOnUnauthorized() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let initialAccessToken = try fakeJWT(email: "initial@example.com", plan: "pro", accountID: "org-initial")
        let refreshedAccessToken = try fakeJWT(email: "refreshed@example.com", plan: "pro", accountID: "org-refreshed")
        let backend = AppServerSequentialAccountBackend(responses: [
            AccountRateLimitsHTTPResponse(statusCode: 401, body: Data(#"{"error":{"message":"unauthorized"}}"#.utf8)),
            AccountRateLimitsHTTPResponse(statusCode: 200, body: Data(Self.rateLimitsUsageJSON.utf8))
        ])
        let fetcher = URLSessionAccountRateLimitsFetcher { request in
            await backend.respond(to: request)
        }
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url, accountRateLimitsFetcher: fetcher),
            notificationSink: { data in await notificationCapture.append(data) },
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data("""
        {"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(initialAccessToken)","chatgptAccountId":"org-initial","chatgptPlanType":"pro"}}
        """.utf8)))

        let processorBox = AppServerUncheckedSendableBox(processor)
        let rateLimitsTask = Task {
            processorBox.value.processLine(Data(#"{"id":2,"method":"account/rateLimits/read","params":{}}"#.utf8))
        }

        let refreshRequestData = try await nextNotificationPayload(notificationCapture)
        let refreshRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: refreshRequestData) as? [String: Any])
        XCTAssertEqual(refreshRequest["method"] as? String, "account/chatgptAuthTokens/refresh")
        let refreshParams = try XCTUnwrap(refreshRequest["params"] as? [String: Any])
        XCTAssertEqual(refreshParams["reason"] as? String, "unauthorized")
        XCTAssertEqual(refreshParams["previousAccountId"] as? String, "org-initial")
        let refreshRequestID = try XCTUnwrap(refreshRequest["id"])

        let refreshResponse = try JSONSerialization.data(withJSONObject: [
            "id": refreshRequestID,
            "result": [
                "accessToken": refreshedAccessToken,
                "chatgptAccountId": "org-refreshed",
                "chatgptPlanType": "pro"
            ]
        ])
        XCTAssertNil(processor.processLine(refreshResponse))

        let response = try decode(await rateLimitsTask.value)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let rateLimits = try XCTUnwrap(result["rateLimits"] as? [String: Any])
        XCTAssertEqual(rateLimits["planType"] as? String, "pro")

        let requests = await backend.requests
        XCTAssertEqual(requests.map { $0.headers["Authorization"] }, [
            "Bearer \(initialAccessToken)",
            "Bearer \(refreshedAccessToken)"
        ])
        XCTAssertEqual(requests.map { $0.headers["chatgpt-account-id"] }, ["org-initial", "org-refreshed"])
        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
        XCTAssertEqual(stored.tokens?.accessToken, refreshedAccessToken)
        XCTAssertEqual(stored.tokens?.accountID, "org-refreshed")
    }

    func testSendAddCreditsNudgeEmailRefreshesExternalAuthOnUnauthorized() async throws {
        let temp = try TemporaryDirectory()
        let notificationCapture = AppServerNotificationCapture()
        let initialAccessToken = try fakeJWT(email: "initial@example.com", plan: "pro", accountID: "org-initial")
        let refreshedAccessToken = try fakeJWT(email: "refreshed@example.com", plan: "pro", accountID: "org-refreshed")
        let backend = AppServerSequentialAccountBackend(responses: [
            AccountRateLimitsHTTPResponse(statusCode: 401, body: Data()),
            AccountRateLimitsHTTPResponse(statusCode: 200, body: Data())
        ])
        let sender = URLSessionAddCreditsNudgeEmailSender { request in
            await backend.respond(to: request)
        }
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: temp.url, addCreditsNudgeEmailSender: sender),
            notificationSink: { data in await notificationCapture.append(data) },
            experimentalAPIEnabled: true
        )

        _ = try decodeMessages(processor.processLine(Data("""
        {"id":1,"method":"account/login/start","params":{"type":"chatgptAuthTokens","accessToken":"\(initialAccessToken)","chatgptAccountId":"org-initial","chatgptPlanType":"pro"}}
        """.utf8)))

        let processorBox = AppServerUncheckedSendableBox(processor)
        let nudgeTask = Task {
            processorBox.value.processLine(Data(#"{"id":2,"method":"account/sendAddCreditsNudgeEmail","params":{"creditType":"usage_limit"}}"#.utf8))
        }

        let refreshRequestData = try await nextNotificationPayload(notificationCapture)
        let refreshRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: refreshRequestData) as? [String: Any])
        XCTAssertEqual(refreshRequest["method"] as? String, "account/chatgptAuthTokens/refresh")
        let refreshParams = try XCTUnwrap(refreshRequest["params"] as? [String: Any])
        XCTAssertEqual(refreshParams["reason"] as? String, "unauthorized")
        XCTAssertEqual(refreshParams["previousAccountId"] as? String, "org-initial")
        let refreshRequestID = try XCTUnwrap(refreshRequest["id"])

        let refreshResponse = try JSONSerialization.data(withJSONObject: [
            "id": refreshRequestID,
            "result": [
                "accessToken": refreshedAccessToken,
                "chatgptAccountId": "org-refreshed",
                "chatgptPlanType": "pro"
            ]
        ])
        XCTAssertNil(processor.processLine(refreshResponse))

        let response = try decode(await nudgeTask.value)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "sent")

        let requests = await backend.requests
        XCTAssertEqual(requests.map { $0.headers["Authorization"] }, [
            "Bearer \(initialAccessToken)",
            "Bearer \(refreshedAccessToken)"
        ])
        XCTAssertEqual(requests.map { $0.headers["chatgpt-account-id"] }, ["org-initial", "org-refreshed"])
        XCTAssertEqual(requests.map(\.body), [
            #"{"credit_type":"usage_limit"}"#,
            #"{"credit_type":"usage_limit"}"#
        ])
        let stored = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .ephemeral))
        XCTAssertEqual(stored.tokens?.accessToken, refreshedAccessToken)
        XCTAssertEqual(stored.tokens?.accountID, "org-refreshed")
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

    func testExperimentalFeatureEnablementSetRefreshesAppListWhenAppsTurnOn() throws {
        let temp = try TemporaryDirectory()
        try """
        chatgpt_base_url = "https://chatgpt.example/backend-api/"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let idToken = try fakeJWT(email: "user@example.com", plan: "plus", accountID: "account-123")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "chatgpt-token",
            "refresh_token": "refresh-token",
            "account_id": "account-123"
          }
        }
        """.write(to: temp.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let directoryPage = """
        {
          "apps": [
            {
              "id": "alpha",
              "name": "Alpha",
              "description": "Alpha v2"
            }
          ],
          "next_token": null
        }
        """
        let capture = MCPHTTPTransportCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            pluginHTTPTransport: { request in
                capture.append(request)
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/backend-api/connectors/directory/list")
                XCTAssertEqual(request.url?.query, "external_logos=true")
                return URLSessionTransportResponse(statusCode: 200, body: Data(directoryPage.utf8))
            }
        )
        let processor = try initializedProcessor(configuration: configuration)

        let disableMessages = try decodeMessages(processor.processLine(Data(
            #"{"id":1,"method":"experimentalFeature/enablement/set","params":{"enablement":{"apps":false}}}"#.utf8
        )))
        XCTAssertEqual(disableMessages.count, 1)
        XCTAssertEqual((disableMessages[0]["result"] as? [String: Any])?["enablement"] as? [String: Bool], ["apps": false])

        let messages = try decodeMessages(processor.processLine(Data(
            #"{"id":2,"method":"experimentalFeature/enablement/set","params":{"enablement":{"apps":true}}}"#.utf8
        )))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["id"] as? Int, 2)
        XCTAssertEqual((messages[0]["result"] as? [String: Any])?["enablement"] as? [String: Bool], ["apps": true])
        XCTAssertEqual(messages[1]["method"] as? String, "app/list/updated")
        let params = try XCTUnwrap(messages[1]["params"] as? [String: Any])
        let data = try XCTUnwrap(params["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["id"] as? String }, ["alpha"])
        XCTAssertEqual(data[0]["name"] as? String, "Alpha")
        XCTAssertEqual(data[0]["description"] as? String, "Alpha v2")
        XCTAssertEqual(data[0]["installUrl"] as? String, "https://chatgpt.com/apps/alpha/alpha")
        XCTAssertEqual(data[0]["isAccessible"] as? Bool, false)
        XCTAssertEqual(data[0]["isEnabled"] as? Bool, true)
        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(capture.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer chatgpt-token")
        XCTAssertEqual(capture.requests[0].value(forHTTPHeaderField: "chatgpt-account-id"), "account-123")
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

        let requests = [
            #"{"method":"thread/realtime/start","params":{"threadId":"\#(threadID)","outputModality":"text"}}"#,
            #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"data":"AA==","sampleRate":24000,"numChannels":1}}}"#,
            #"{"method":"thread/realtime/appendText","params":{"threadId":"\#(threadID)","text":"hello"}}"#,
            #"{"method":"thread/realtime/stop","params":{"threadId":"\#(threadID)"}}"#
        ]

        for (index, request) in requests.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 2),\#(request.dropFirst())"#,
                codexHome: temp.url,
                experimentalAPIEnabled: true
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32600)
            XCTAssertEqual(error["message"] as? String, "thread \(threadID) does not support realtime conversation")
        }
    }

    func testRealtimeConversationRoutesSucceedWhenFeatureEnabled() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        realtime_conversation = true
        """.write(
            to: temp.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)
        ))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let requests = [
            #"{"method":"thread/realtime/start","params":{"threadId":"\#(threadID)","outputModality":"text"}}"#,
            #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"data":"AA==","sampleRate":24000,"numChannels":1}}}"#,
            #"{"method":"thread/realtime/appendText","params":{"threadId":"\#(threadID)","text":"hello"}}"#,
            #"{"method":"thread/realtime/stop","params":{"threadId":"\#(threadID)"}}"#
        ]

        for (index, request) in requests.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 2),\#(request.dropFirst())"#,
                codexHome: temp.url,
                experimentalAPIEnabled: true
            )
            XCTAssertNil(response["error"], "\(response)")
            let result = try XCTUnwrap(response["result"] as? [String: Any])
            XCTAssertEqual(result.isEmpty, true)
        }
    }

    func testRealtimeConversationRoutesValidateRustParamsWhenFeatureEnabled() throws {
        let temp = try TemporaryDirectory()
        try """
        [features]
        realtime_conversation = true
        """.write(
            to: temp.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let processor = try initializedProcessor(configuration: testConfiguration(codexHome: temp.url))
        let startMessages = try decodeMessages(processor.processLine(
            Data(#"{"id":1,"method":"thread/start","params":{"modelProvider":"mock_provider"}}"#.utf8)
        ))
        let startResult = try XCTUnwrap(startMessages[0]["result"] as? [String: Any])
        let thread = try XCTUnwrap(startResult["thread"] as? [String: Any])
        let threadID = try XCTUnwrap(thread["id"] as? String)

        let cases = [
            (
                #"{"method":"thread/realtime/start","params":{"threadId":"\#(threadID)"}}"#,
                "missing field `outputModality`"
            ),
            (
                #"{"method":"thread/realtime/start","params":{"threadId":"\#(threadID)","outputModality":"video"}}"#,
                "unknown variant `video`, expected `text` or `audio`"
            ),
            (
                #"{"method":"thread/realtime/start","params":{"threadId":"\#(threadID)","outputModality":"audio","transport":{"type":"webrtc"}}}"#,
                "missing field `sdp`"
            ),
            (
                #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)"}}"#,
                "missing field `audio`"
            ),
            (
                #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"sampleRate":24000,"numChannels":1}}}"#,
                "missing field `data`"
            ),
            (
                #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"data":"AA==","numChannels":1}}}"#,
                "missing field `sampleRate`"
            ),
            (
                #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"data":"AA==","sampleRate":24000.5,"numChannels":1}}}"#,
                "invalid value for field `sampleRate`"
            ),
            (
                #"{"method":"thread/realtime/appendAudio","params":{"threadId":"\#(threadID)","audio":{"data":"AA==","sampleRate":24000,"numChannels":70000}}}"#,
                "invalid value for field `numChannels`"
            ),
            (
                #"{"method":"thread/realtime/appendText","params":{"threadId":"\#(threadID)"}}"#,
                "missing field `text`"
            )
        ]

        for (index, testCase) in cases.enumerated() {
            let response = try appServerResponse(
                #"{"id":\#(index + 2),\#(testCase.0.dropFirst())"#,
                codexHome: temp.url,
                experimentalAPIEnabled: true
            )
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual(error["code"] as? Int, -32602)
            XCTAssertEqual(error["message"] as? String, testCase.1)
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

        let toolsOnly = try appServerResponse(
            #"{"id":3,"method":"mcpServerStatus/list","params":{"detail":"toolsAndAuthOnly"}}"#,
            codexHome: temp.url
        )
        let toolsOnlyResult = try XCTUnwrap(toolsOnly["result"] as? [String: Any])
        let toolsOnlyData = try XCTUnwrap(toolsOnlyResult["data"] as? [[String: Any]])
        XCTAssertEqual(toolsOnlyData.map { $0["name"] as? String }, ["docs", "github"])
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

    func testMcpServerStatusListRejectsUnknownDetailLikeRustProtocol() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"mcpServerStatus/list","params":{"detail":"lite"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "Invalid request: unknown variant `lite`, expected `full` or `toolsAndAuthOnly`"
        )
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

    func testMcpServerReloadAcceptsNullParams() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"config/mcpServer/reload","params":null}"#,
            codexHome: temp.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
    }

    func testMcpServerReloadRejectsObjectParams() throws {
        let temp = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"config/mcpServer/reload","params":{}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual(error["message"] as? String, "invalid params for config/mcpServer/reload")
    }

    func testMcpServerReloadReportsConfigLoadFailures() throws {
        let temp = try TemporaryDirectory()
        try """
        [mcp_servers.docs]
        command = "docs"
        bearer_token = "token"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/mcpServer/reload"}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32603)
        XCTAssertEqual(
            error["message"] as? String,
            "failed to refresh MCP servers: failed to reload config: mcp_servers.docs uses unsupported `bearer_token`; set `bearer_token_env_var`."
        )
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
        scopes = ["configured"]
        oauth_resource = "https://api.github.test"
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
        XCTAssertEqual(requests[0].oauthResource, "https://api.github.test")
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

    func testMcpServerOAuthLoginUsesConfiguredScopesWhenParamsOmitScopes() async throws {
        let temp = try TemporaryDirectory()
        try """
        [mcp_servers.github]
        url = "https://mcp.github.test/mcp"
        scopes = ["repo", "workflow"]
        oauth_resource = "https://api.github.test"
        """.write(to: temp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let loginCapture = AppServerMcpOAuthLoginCapture()
        let configuration = testConfiguration(
            codexHome: temp.url,
            mcpOAuthLoginStarter: { request, completion in
                await loginCapture.append(request)
                await completion(true, nil)
                return AppServerMcpOAuthLoginStarted(authorizationURL: "https://auth.github.test/authorize")
            }
        )
        let processor = try initializedProcessor(configuration: configuration)

        _ = try decode(processor.processLine(Data(#"{"id":1,"method":"mcpServer/oauth/login","params":{"name":"github"}}"#.utf8)))

        let requests = await loginCapture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].scopes, ["repo", "workflow"])
        XCTAssertEqual(requests[0].oauthResource, "https://api.github.test")
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

    func testConfigReadReportsManagedOverrideOverSessionFlagsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let managedConfigFile = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try #"model = "user""#.write(to: configFile, atomically: true, encoding: .utf8)
        try #"model = "system""#.write(to: managedConfigFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/read","params":{"includeLayers":true}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                cliConfigOverrides: CliConfigOverrides(rawOverrides: [#"model="session""#]),
                configLayerOverrides: ConfigLayerLoaderOverrides(managedConfigPath: managedConfigFile)
            )
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "system")
        let origins = try XCTUnwrap(result["origins"] as? [String: Any])
        let modelOrigin = try XCTUnwrap(origins["model"] as? [String: Any])
        let modelOriginName = try XCTUnwrap(modelOrigin["name"] as? [String: Any])
        XCTAssertEqual(modelOriginName["type"] as? String, "legacyManagedConfigTomlFromFile")
        XCTAssertEqual(modelOriginName["file"] as? String, managedConfigFile.standardizedFileURL.path)

        let layers = try XCTUnwrap(result["layers"] as? [[String: Any]])
        XCTAssertEqual((layers[0]["name"] as? [String: Any])?["type"] as? String, "legacyManagedConfigTomlFromFile")
        XCTAssertEqual((layers[1]["name"] as? [String: Any])?["type"] as? String, "sessionFlags")
        XCTAssertEqual((layers[2]["name"] as? [String: Any])?["type"] as? String, "user")
        XCTAssertEqual(((layers[1]["config"] as? [String: Any])?["model"]) as? String, "session")
        XCTAssertEqual(((layers[2]["config"] as? [String: Any])?["model"]) as? String, "user")
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

    func testConfigReadUsesCwdProjectLayers() throws {
        let codexHome = try TemporaryDirectory()
        try #"model = "gpt-user""#.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let repo = codexHome.url.appendingPathComponent("repo", isDirectory: true)
        let nested = repo.appendingPathComponent("Sources/App", isDirectory: true)
        let dotCodex = repo.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try "gitdir: .git\n".write(to: repo.appendingPathComponent(".git", isDirectory: false), atomically: true, encoding: .utf8)
        try #"model = "gpt-project""#.write(
            to: dotCodex.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"config/read","params":{"cwd":"\#(nested.path)","includeLayers":true}}"#,
            codexHome: codexHome.url
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "gpt-project")
        let origins = try XCTUnwrap(result["origins"] as? [String: Any])
        let modelOrigin = try XCTUnwrap(origins["model"] as? [String: Any])
        let modelOriginName = try XCTUnwrap(modelOrigin["name"] as? [String: Any])
        XCTAssertEqual(modelOriginName["type"] as? String, "project")
        XCTAssertEqual(modelOriginName["dotCodexFolder"] as? String, dotCodex.standardizedFileURL.path)
        let layers = try XCTUnwrap(result["layers"] as? [[String: Any]])
        XCTAssertTrue(layers.contains { layer in
            (layer["name"] as? [String: Any])?["type"] as? String == "project"
                && (layer["config"] as? [String: Any])?["model"] as? String == "gpt-project"
        })
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

    func testConfigRequirementsReadIncludesLegacyManagedConfigRequirementsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let missingRequirements = temp.url.appendingPathComponent("missing-requirements.toml", isDirectory: false)
        let managedConfig = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try """
        approval_policy = "on-request"
        sandbox_mode = "read-only"
        """.write(to: managedConfig, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"configRequirements/read","params":{}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(
                    managedConfigPath: managedConfig,
                    requirementsPath: missingRequirements
                )
            )
        )

        XCTAssertNil(response["error"], "\(response)")
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let requirements = try XCTUnwrap(result["requirements"] as? [String: Any])
        XCTAssertEqual(requirements["allowedApprovalPolicies"] as? [String], ["on-request"])
        XCTAssertEqual(requirements["allowedSandboxModes"] as? [String], ["read-only"])
    }

    func testConfigRequirementsReadMergesFileAndLegacyManagedConfigLikeRust() throws {
        let temp = try TemporaryDirectory()
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        let managedConfig = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try #"allowed_approval_policies = ["untrusted"]"#.write(
            to: requirementsPath,
            atomically: true,
            encoding: .utf8
        )
        try #"sandbox_mode = "read-only""#.write(to: managedConfig, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"configRequirements/read","params":{}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(
                    managedConfigPath: managedConfig,
                    requirementsPath: requirementsPath
                )
            )
        )

        XCTAssertNil(response["error"], "\(response)")
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let requirements = try XCTUnwrap(result["requirements"] as? [String: Any])
        XCTAssertEqual(requirements["allowedApprovalPolicies"] as? [String], ["untrusted"])
        XCTAssertEqual(requirements["allowedSandboxModes"] as? [String], ["read-only"])
    }

    func testConfigRequirementsReadReturnsRustShapeForAllowedPoliciesAndSandboxes() throws {
        let temp = try TemporaryDirectory()
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        allowed_approval_policies = ["untrusted", "on-request"]
        allowed_approvals_reviewers = ["user", "guardian_subagent"]
        allowed_sandbox_modes = ["read-only", "workspace-write", "external-sandbox"]
        allowed_web_search_modes = ["cached"]
        enforce_residency = "us"

        [features]
        tool_search = true
        plugins = false

        [experimental_network]
        enabled = true
        http_port = 8123
        socks_port = 9123
        allow_upstream_proxy = false
        dangerously_allow_non_loopback_proxy = true
        dangerously_allow_all_unix_sockets = false
        managed_allowed_domains_only = true
        allow_local_binding = true

        [experimental_network.domains]
        "api.openai.com" = "allow"
        "blocked.example.com" = "deny"

        [experimental_network.unix_sockets]
        "/tmp/codex.sock" = "allow"
        "/tmp/disabled.sock" = "none"
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
        XCTAssertEqual(requirements["allowedApprovalsReviewers"] as? [String], ["user", "guardian_subagent"])
        XCTAssertEqual(requirements["allowedWebSearchModes"] as? [String], ["cached", "disabled"])
        XCTAssertEqual(requirements["featureRequirements"] as? [String: Bool], ["tool_search": true, "plugins": false])
        XCTAssertTrue(requirements["hooks"] is NSNull)
        XCTAssertEqual(requirements["enforceResidency"] as? String, "us")
        let network = try XCTUnwrap(requirements["network"] as? [String: Any])
        XCTAssertEqual(network["enabled"] as? Bool, true)
        XCTAssertEqual(network["httpPort"] as? Int, 8123)
        XCTAssertEqual(network["socksPort"] as? Int, 9123)
        XCTAssertEqual(network["allowUpstreamProxy"] as? Bool, false)
        XCTAssertEqual(network["dangerouslyAllowNonLoopbackProxy"] as? Bool, true)
        XCTAssertEqual(network["dangerouslyAllowAllUnixSockets"] as? Bool, false)
        XCTAssertEqual(network["domains"] as? [String: String], [
            "api.openai.com": "allow",
            "blocked.example.com": "deny"
        ])
        XCTAssertEqual(network["managedAllowedDomainsOnly"] as? Bool, true)
        XCTAssertEqual(network["allowedDomains"] as? [String], ["api.openai.com"])
        XCTAssertEqual(network["deniedDomains"] as? [String], ["blocked.example.com"])
        XCTAssertEqual(network["unixSockets"] as? [String: String], [
            "/tmp/codex.sock": "allow",
            "/tmp/disabled.sock": "none"
        ])
        XCTAssertEqual(network["allowUnixSockets"] as? [String], ["/tmp/codex.sock"])
        XCTAssertEqual(network["allowLocalBinding"] as? Bool, true)
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

    func testConfigValueWritePreservesCommentsAndOrderLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let original = """
        # Codex user configuration
        model = "gpt-5.2"
        approval_policy = "on-request"

        [notice]
        # Preserve this comment
        hide_full_access_warning = true

        [features]
        unified_exec = true

        """
        try original.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"features.personality","value":true,"mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")

        let expected = """
        # Codex user configuration
        model = "gpt-5.2"
        approval_policy = "on-request"

        [notice]
        # Preserve this comment
        hide_full_access_warning = true

        [features]
        unified_exec = true
        personality = true

        """
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), expected)
    }

    func testConfigValueWriteSupportsNestedAppPathsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)

        let appsValue = #"{"app1":{"enabled":false}}"#
        let writeApps = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"apps","value":\#(appsValue),"mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((writeApps["result"] as? [String: Any])?["status"] as? String, "ok")

        let writeNested = try appServerResponse(
            #"{"id":2,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"apps.app1.default_tools_approval_mode","value":"prompt","mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((writeNested["result"] as? [String: Any])?["status"] as? String, "ok")

        let read = try appServerResponse(
            #"{"id":3,"method":"config/read","params":{"includeLayers":false}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        let apps = try XCTUnwrap(config["apps"] as? [String: Any])
        let app1 = try XCTUnwrap(apps["app1"] as? [String: Any])
        XCTAssertEqual(app1["enabled"] as? Bool, false)
        XCTAssertEqual(app1["default_tools_approval_mode"] as? String, "prompt")
    }

    func testConfigValueWriteSupportsCustomMCPServerApprovalModeLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try """
        [mcp_servers.docs]
        command = "docs-server"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let write = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"mcp_servers.docs.default_tools_approval_mode","value":"approve","mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual((write["result"] as? [String: Any])?["status"] as? String, "ok")
        XCTAssertTrue(try String(contentsOf: configFile, encoding: .utf8).contains(#"default_tools_approval_mode = "approve""#))

        let read = try appServerResponse(
            #"{"id":2,"method":"config/read","params":{"includeLayers":false}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(result["config"] as? [String: Any])
        let servers = try XCTUnwrap(config["mcp_servers"] as? [String: Any])
        let docs = try XCTUnwrap(servers["docs"] as? [String: Any])
        XCTAssertEqual(docs["command"] as? String, "docs-server")
        XCTAssertEqual(docs["default_tools_approval_mode"] as? String, "approve")
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

    func testConfigValueWriteClearsMissingPathAsNoOpLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"features.personality","value":null,"mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(result["filePath"] as? String, configFile.standardizedFileURL.path)
        XCTAssertTrue((result["version"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertTrue(result["overriddenMetadata"] is NSNull)
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "")
    }

    func testConfigValueWriteRejectsInvalidUserValueEvenWhenManagedOverridesLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let managedConfigFile = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try #"model = "user""#.write(to: configFile, atomically: true, encoding: .utf8)
        try #"approval_policy = "never""#.write(to: managedConfigFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"approval_policy","value":"bogus","mergeStrategy":"replace"}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(managedConfigPath: managedConfigFile)
            )
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.contains("Invalid configuration:") == true)
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["config_write_error_code"] as? String, "configValidationError")
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), #"model = "user""#)
    }

    func testConfigValueWriteRejectsReservedBuiltinProviderOverrideLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try #"model = "user""#.write(to: configFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"model_providers.openai.name","value":"OpenAI Override","mergeStrategy":"replace"}}"#,
            codexHome: temp.url
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        let message = try XCTUnwrap(error["message"] as? String)
        XCTAssertTrue(message.contains("Invalid configuration:"))
        XCTAssertTrue(message.contains("reserved built-in provider IDs"))
        XCTAssertTrue(message.contains("`openai`"))
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["config_write_error_code"] as? String, "configValidationError")
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), #"model = "user""#)
    }

    func testConfigValueWriteRejectsManagedFeatureRequirementConflictLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)
        try """
        [features]
        personality = true
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"features.personality","value":false,"mergeStrategy":"replace"}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.contains("Invalid configuration: invalid value for `features`: `features.personality=false`") == true)
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["config_write_error_code"] as? String, "configValidationError")
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "")
    }

    func testConfigValueWriteRejectsManagedProfileFeatureRequirementConflictLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let requirementsPath = temp.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)
        try """
        [features]
        personality = true
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"profiles.enterprise.features.personality","value":false,"mergeStrategy":"replace"}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(requirementsPath: requirementsPath)
            )
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertTrue((error["message"] as? String)?.contains("Invalid configuration: invalid value for `features`: `profiles.enterprise.features.personality=false`") == true)
        let data = try XCTUnwrap(error["data"] as? [String: Any])
        XCTAssertEqual(data["config_write_error_code"] as? String, "configValidationError")
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "")
    }

    func testConfigValueWriteReportsManagedOverrideLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let managedConfigFile = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try "".write(to: configFile, atomically: true, encoding: .utf8)
        try #"approval_policy = "never""#.write(to: managedConfigFile, atomically: true, encoding: .utf8)

        let response = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"keyPath":"approval_policy","value":"on-request","mergeStrategy":"replace"}}"#,
            configuration: testConfiguration(
                codexHome: temp.url,
                configLayerOverrides: ConfigLayerLoaderOverrides(managedConfigPath: managedConfigFile)
            )
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "okOverridden")
        let overridden = try XCTUnwrap(result["overriddenMetadata"] as? [String: Any])
        XCTAssertEqual(
            overridden["message"] as? String,
            "Overridden by legacy managed_config.toml: \(managedConfigFile.standardizedFileURL.path)"
        )
        XCTAssertEqual(overridden["effectiveValue"] as? String, "never")
        let layer = try XCTUnwrap(overridden["overridingLayer"] as? [String: Any])
        let layerName = try XCTUnwrap(layer["name"] as? [String: Any])
        XCTAssertEqual(layerName["type"] as? String, "legacyManagedConfigTomlFromFile")
        XCTAssertEqual(layerName["file"] as? String, managedConfigFile.standardizedFileURL.path)
    }

    func testConfigValueWriteReportsOkWhenWriteMatchesManagedEffectiveValueLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        let managedConfigFile = temp.url.appendingPathComponent("managed_config.toml", isDirectory: false)
        try #"approval_policy = "on-request""#.write(to: configFile, atomically: true, encoding: .utf8)
        try #"approval_policy = "never""#.write(to: managedConfigFile, atomically: true, encoding: .utf8)

        let configuration = testConfiguration(
            codexHome: temp.url,
            configLayerOverrides: ConfigLayerLoaderOverrides(managedConfigPath: managedConfigFile)
        )
        let write = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"approval_policy","value":"never","mergeStrategy":"replace"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(write["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertTrue(result["overriddenMetadata"] is NSNull)

        let read = try appServerResponse(
            #"{"id":2,"method":"config/read","params":{"includeLayers":true}}"#,
            configuration: configuration
        )
        let readResult = try XCTUnwrap(read["result"] as? [String: Any])
        let config = try XCTUnwrap(readResult["config"] as? [String: Any])
        XCTAssertEqual(config["approval_policy"] as? String, "never")
        let origins = try XCTUnwrap(readResult["origins"] as? [String: Any])
        let approvalOrigin = try XCTUnwrap(origins["approval_policy"] as? [String: Any])
        let approvalOriginName = try XCTUnwrap(approvalOrigin["name"] as? [String: Any])
        XCTAssertEqual(approvalOriginName["type"] as? String, "legacyManagedConfigTomlFromFile")
        XCTAssertEqual(approvalOriginName["file"] as? String, managedConfigFile.standardizedFileURL.path)
    }

    func testConfigValueWriteSucceedsWhenManagedPreferencesExpandHomeDirectoryPathsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try "model = \"user\"\n".write(to: configFile, atomically: true, encoding: .utf8)

        let managedPreferences = Data("""
        sandbox_mode = "workspace-write"
        [sandbox_workspace_write]
        writable_roots = ["~/code"]
        """.utf8)
            .base64EncodedString()
        let configuration = testConfiguration(
            codexHome: temp.url,
            configLayerOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: temp.url.appendingPathComponent("missing-managed-config.toml", isDirectory: false),
                managedPreferencesBase64: managedPreferences
            )
        )
        let write = try appServerResponse(
            #"{"id":1,"method":"config/value/write","params":{"filePath":"\#(configFile.path)","keyPath":"model","value":"updated","mergeStrategy":"replace"}}"#,
            configuration: configuration
        )
        let result = try XCTUnwrap(write["result"] as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "model = \"updated\"\n")
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

    func testCommandExecUsesConfiguredReadOnlySandboxLikeRust() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let blockedFile = cwd.url.appendingPathComponent("blocked.txt", isDirectory: false)

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf nope > blocked.txt"],"cwd":"\#(cwd.url.path)"}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertNotEqual(result["exitCode"] as? Int, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedFile.path))
    }

    func testCommandExecSandboxPolicyCanOverrideConfiguredReadOnlyLikeRust() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let allowedFile = cwd.url.appendingPathComponent("allowed.txt", isDirectory: false)

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf yep > allowed.txt"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"dangerFullAccess"}}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(try String(contentsOf: allowedFile, encoding: .utf8), "yep")
    }

    func testCommandExecReadOnlySandboxPolicyCanOverrideNetworkAccessLikeRust() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()

        let response = try appServerResponse(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","if [ -z \"${CODEX_SANDBOX_NETWORK_DISABLED+x}\" ]; then printf enabled; else printf disabled; fi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"readOnly","networkAccess":true}}}"#,
            codexHome: codexHome.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "enabled")
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

    func testCommandExecPermissionProfileDisabledOverridesConfiguredSandboxLikeRust() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let allowedFile = cwd.url.appendingPathComponent("permission-profile.txt", isDirectory: false)
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/sh","-c","printf profile > permission-profile.txt"],"cwd":"\#(cwd.url.path)","permissionProfile":{"type":"disabled"}}}"#.utf8
        )))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(try String(contentsOf: allowedFile, encoding: .utf8), "profile")
    }

    func testCommandExecPermissionProfileRejectsUnbridgeableWritesLikeRust() throws {
        let codexHome = try TemporaryDirectory()
        let cwd = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let processor = try initializedProcessor(
            configuration: testConfiguration(codexHome: codexHome.url),
            experimentalAPIEnabled: true
        )

        let response = try decode(processor.processLine(Data(
            #"{"id":1,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","permissionProfile":{"type":"managed","network":{"enabled":false},"fileSystem":{"type":"restricted","entries":[{"path":{"type":"path","path":"\#(outside.url.path)"},"access":"write"}]}}}}"#.utf8
        )))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32600)
        XCTAssertEqual(
            error["message"] as? String,
            "invalid permission profile: permissions profile requests filesystem writes outside the workspace root, which is not supported until the runtime enforces FileSystemSandboxPolicy directly"
        )
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

        let negativeTimeout = try appServerResponse(
            #"{"id":6,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","timeoutMs":-1}}"#,
            codexHome: codexHome.url
        )
        let negativeTimeoutError = try XCTUnwrap(negativeTimeout["error"] as? [String: Any])
        XCTAssertEqual(negativeTimeoutError["code"] as? Int, -32602)
        XCTAssertEqual(
            negativeTimeoutError["message"] as? String,
            "command/exec timeoutMs must be non-negative, got -1"
        )

        let streamingWithoutProcessID = try appServerResponse(
            #"{"id":7,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","streamStdoutStderr":true}}"#,
            codexHome: codexHome.url
        )
        let streamingWithoutProcessIDError = try XCTUnwrap(streamingWithoutProcessID["error"] as? [String: Any])
        XCTAssertEqual(streamingWithoutProcessIDError["code"] as? Int, -32600)
        XCTAssertEqual(
            streamingWithoutProcessIDError["message"] as? String,
            "command/exec tty or streaming requires a client-supplied processId"
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
            #"{"id":3,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"dangerFullAccess"},"permissionProfile":"on-request"}}"#.utf8
        )))
        let sandboxAndProfileError = try XCTUnwrap(sandboxAndProfile["error"] as? [String: Any])
        XCTAssertEqual(sandboxAndProfileError["code"] as? Int, -32600)
        XCTAssertEqual(
            sandboxAndProfileError["message"] as? String,
            "`permissionProfile` cannot be combined with `sandboxPolicy`"
        )

        let legacyReadOnly = try appServerResponse(
            #"{"id":8,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"readOnly","access":{"type":"restricted"}}}}"#,
            codexHome: codexHome.url
        )
        let legacyReadOnlyError = try XCTUnwrap(legacyReadOnly["error"] as? [String: Any])
        XCTAssertEqual(legacyReadOnlyError["code"] as? Int, -32600)
        XCTAssertEqual(
            legacyReadOnlyError["message"] as? String,
            "readOnly.access is no longer supported; use permissionProfile for restricted reads"
        )

        let legacyWorkspaceWrite = try appServerResponse(
            #"{"id":9,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"workspaceWrite","readOnlyAccess":{"type":"restricted"}}}}"#,
            codexHome: codexHome.url
        )
        let legacyWorkspaceWriteError = try XCTUnwrap(legacyWorkspaceWrite["error"] as? [String: Any])
        XCTAssertEqual(legacyWorkspaceWriteError["code"] as? Int, -32600)
        XCTAssertEqual(
            legacyWorkspaceWriteError["message"] as? String,
            "workspaceWrite.readOnlyAccess is no longer supported; use permissionProfile for restricted reads"
        )

        let invalidNetworkAccess = try appServerResponse(
            #"{"id":10,"method":"command/exec","params":{"command":["/bin/echo","hi"],"cwd":"\#(cwd.url.path)","sandboxPolicy":{"type":"externalSandbox","networkAccess":"bogus"}}}"#,
            codexHome: codexHome.url
        )
        let invalidNetworkAccessError = try XCTUnwrap(invalidNetworkAccess["error"] as? [String: Any])
        XCTAssertEqual(invalidNetworkAccessError["code"] as? Int, -32600)
        XCTAssertEqual(invalidNetworkAccessError["message"] as? String, "invalid sandbox policy")
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

        let responseData = try await nextNotificationPayload(notificationCapture)
        let response = try XCTUnwrap(decodeMessages(responseData).first { $0["id"] as? Int == 1 })
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertNotEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["stdout"] as? String, "")
        XCTAssertEqual(result["stderr"] as? String, "")
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
        experimentalAPIEnabled: Bool = false,
        optOutNotificationMethods: [String] = []
    ) throws -> CodexAppServerMessageProcessor {
        let processor = CodexAppServerMessageProcessor(configuration: configuration, notificationSink: notificationSink)
        var capabilities: [String: Any] = [:]
        if experimentalAPIEnabled {
            capabilities["experimentalApi"] = true
        }
        if !optOutNotificationMethods.isEmpty {
            capabilities["optOutNotificationMethods"] = optOutNotificationMethods
        }
        var params: [String: Any] = [
            "clientInfo": [
                "name": "test",
                "version": "0"
            ]
        ]
        if !capabilities.isEmpty {
            params["capabilities"] = capabilities
        }
        let request: [String: Any] = [
            "id": "init",
            "method": "initialize",
            "params": params
        ]
        _ = try decode(processor.processLine(try JSONSerialization.data(withJSONObject: request)))
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

    private func archivedThreadIDs(from messages: [[String: Any]]) throws -> [String] {
        try messages.map { message in
            XCTAssertEqual(message["method"] as? String, "thread/archived")
            let params = try XCTUnwrap(message["params"] as? [String: Any])
            return try XCTUnwrap(params["threadId"] as? String)
        }
    }

    private func archivedRolloutPath(codexHome: URL, threadID: String) throws -> String? {
        try RolloutListing.getConversations(
            codexHome: codexHome,
            pageSize: 100,
            archivedOnly: true,
            defaultProvider: "openai"
        )
        .items
        .first(where: { $0.path.hasSuffix("\(threadID).jsonl") })?
        .path
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func createAppServerStateStore(codexHome: URL) throws -> SQLiteAgentGraphStore {
        let stateDatabaseURL = codexHome.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        return try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
    }

    private func upsertAppServerStateThread(
        _ stateStore: SQLiteAgentGraphStore,
        threadID: ThreadId,
        rolloutPath: String,
        codexHome: URL,
        title: String
    ) async throws {
        try await stateStore.upsertThread(ThreadMetadata(
            id: threadID,
            rolloutPath: rolloutPath,
            createdAt: try appServerDate("2025-01-02T03:04:05Z"),
            updatedAt: try appServerDate("2025-01-02T03:04:05Z"),
            source: "cli",
            modelProvider: "openai",
            cwd: codexHome.path,
            cliVersion: "0.0.0",
            title: title,
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: title
        ))
    }

    private func assertPersistExtendedHistoryDeprecationNotice(
        _ message: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(message["method"] as? String, "deprecationNotice", file: file, line: line)
        let params = try XCTUnwrap(message["params"] as? [String: Any], file: file, line: line)
        XCTAssertEqual(
            params["summary"] as? String,
            "persistExtendedHistory is deprecated and ignored",
            file: file,
            line: line
        )
        XCTAssertEqual(
            params["details"] as? String,
            "Remove this parameter. App-server always uses limited history persistence.",
            file: file,
            line: line
        )
    }

    private func writeRequiredBrokenMCPConfig(codexHome: URL) throws {
        try """
        [mcp_servers.required_broken]
        command = "codex-definitely-not-a-real-binary"
        required = true
        """.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    }

    private func assertRequiredBrokenMCPStartupError(
        _ messages: [[String: Any]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(messages.count, 1, file: file, line: line)
        let error = try XCTUnwrap(messages[0]["error"] as? [String: Any], file: file, line: line)
        XCTAssertEqual(error["code"] as? Int, -32603, file: file, line: line)
        let message = try XCTUnwrap(error["message"] as? String, file: file, line: line)
        XCTAssertTrue(
            message.contains("required MCP servers failed to initialize: required_broken"),
            file: file,
            line: line
        )
        XCTAssertTrue(message.contains("codex-definitely-not-a-real-binary"), file: file, line: line)
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
        pluginHTTPTransport: @escaping AppServerPluginHTTPTransport = CodexAppServer.defaultPluginHTTPTransport,
        accessibleConnectorProvider: @escaping AppServerAccessibleConnectorProvider = CodexAppServer.defaultAccessibleConnectorProvider,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter,
        cliConfigOverrides: CliConfigOverrides = CliConfigOverrides(),
        configLayerOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        stateStore: SQLiteAgentGraphStore? = nil
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
            pluginHTTPTransport: pluginHTTPTransport,
            accessibleConnectorProvider: accessibleConnectorProvider,
            mcpOAuthLoginStarter: mcpOAuthLoginStarter,
            cliConfigOverrides: cliConfigOverrides,
            configLayerOverrides: configLayerOverrides,
            stateStore: stateStore
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
        gitInfo: GitInfo? = nil,
        archived: Bool = false,
        cwd: String = "/"
    ) throws -> String {
        let id = UUID().uuidString.lowercased()
        let path = codexHome
            .appendingPathComponent(archived ? "archived_sessions" : "sessions/2025/01/02", isDirectory: true)
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
                cwd: cwd,
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
        try appendRolloutItems(to: path, timestamp: timestamp, items: events.map(RolloutRecordItem.eventMsg))
    }

    private func appendRolloutItems(to path: String, timestamp: String, items: [RolloutRecordItem]) throws {
        let encoder = JSONEncoder()
        let lines = try items.map { item in
            let line = RolloutLine(timestamp: timestamp, item: item)
            return String(data: try encoder.encode(line), encoding: .utf8)!
        }.joined(separator: "\n")
        let url = URL(fileURLWithPath: path)
        let existing = try String(contentsOf: url, encoding: .utf8)
        try (existing + "\n" + lines).write(to: url, atomically: true, encoding: .utf8)
    }

    private func setModificationDate(_ timestamp: String, for threadID: String, codexHome: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = try XCTUnwrap(formatter.date(from: timestamp))
        let path = try XCTUnwrap(RolloutListing.findConversationPathByIDString(
            codexHome: codexHome,
            idString: threadID
        ))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    private func appServerDate(_ timestamp: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = timestamp.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: timestamp))
    }

    private func createAppServerGoalStateStore(
        codexHome: URL,
        threadID: String,
        title: String
    ) async throws -> SQLiteAgentGraphStore {
        let stateDatabaseURL = codexHome.appendingPathComponent("state.sqlite3", isDirectory: false)
        try createAppServerThreadsTable(databaseURL: stateDatabaseURL)
        let stateStore = try SQLiteAgentGraphStore(databaseURL: stateDatabaseURL, defaultProvider: "openai")
        let parsedThreadID = try ThreadId(string: threadID)
        try await stateStore.upsertThread(ThreadMetadata(
            id: parsedThreadID,
            rolloutPath: codexHome
                .appendingPathComponent("sessions/test-\(threadID).jsonl", isDirectory: false)
                .path,
            createdAt: try appServerDate("2025-01-06T07:30:00Z"),
            updatedAt: try appServerDate("2025-01-06T07:30:00Z"),
            source: "cli",
            modelProvider: "mock_provider",
            cwd: codexHome.path,
            cliVersion: "0.0.0",
            title: title,
            sandboxPolicy: "read-only",
            approvalMode: "never",
            tokensUsed: 0,
            firstUserMessage: title
        ))
        return stateStore
    }

    private func createAppServerThreadsTable(databaseURL: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }
        let query =
            """
            CREATE TABLE threads (
                id TEXT NOT NULL PRIMARY KEY,
                agent_path TEXT,
                memory_mode TEXT,
                rollout_path TEXT,
                created_at INTEGER,
                created_at_ms INTEGER,
                archived INTEGER NOT NULL DEFAULT 0,
                archived_at INTEGER,
                source TEXT NOT NULL DEFAULT 'cli',
                thread_source TEXT,
                agent_nickname TEXT,
                agent_role TEXT,
                model_provider TEXT NOT NULL DEFAULT 'openai',
                model TEXT,
                reasoning_effort TEXT,
                cwd TEXT NOT NULL DEFAULT '',
                cli_version TEXT NOT NULL DEFAULT '',
                first_user_message TEXT NOT NULL DEFAULT '',
                sandbox_policy TEXT NOT NULL DEFAULT '',
                approval_mode TEXT NOT NULL DEFAULT '',
                tokens_used INTEGER NOT NULL DEFAULT 0,
                title TEXT,
                updated_at INTEGER,
                updated_at_ms INTEGER,
                git_sha TEXT,
                git_branch TEXT,
                git_origin_url TEXT
            )
            """
        XCTAssertEqual(sqlite3_exec(openedDatabase, query, nil, nil, nil), SQLITE_OK)
    }

    private func createAppServerMemoryTables(databaseURL: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }
        let query =
            """
            CREATE TABLE IF NOT EXISTS stage1_outputs (
                thread_id TEXT NOT NULL PRIMARY KEY,
                source_updated_at INTEGER NOT NULL,
                raw_memory TEXT NOT NULL,
                rollout_summary TEXT NOT NULL,
                generated_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS jobs (
                kind TEXT NOT NULL,
                job_key TEXT NOT NULL,
                status TEXT NOT NULL,
                PRIMARY KEY(kind, job_key)
            );
            """
        XCTAssertEqual(sqlite3_exec(openedDatabase, query, nil, nil, nil), SQLITE_OK)
    }

    private func insertAppServerMemoryRows(databaseURL: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }
        let query =
            """
            INSERT INTO stage1_outputs (
                thread_id,
                source_updated_at,
                raw_memory,
                rollout_summary,
                generated_at
            ) VALUES
                ('00000000-0000-0000-0000-000000009020', 1, 'raw', 'summary', 2);
            INSERT INTO jobs (kind, job_key, status) VALUES
                ('memory_stage1', 'stage1', 'running'),
                ('memory_consolidate_global', 'global', 'running'),
                ('not_memory', 'other', 'running');
            """
        XCTAssertEqual(sqlite3_exec(openedDatabase, query, nil, nil, nil), SQLITE_OK)
    }

    private func sqliteCount(databaseURL: URL, query: String) throws -> Int {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(openedDatabase, query, -1, &statement, nil), SQLITE_OK)
        let preparedStatement = try XCTUnwrap(statement)
        defer {
            sqlite3_finalize(preparedStatement)
        }
        XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_ROW)
        return Int(sqlite3_column_int64(preparedStatement, 0))
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

    private func remotePluginBundleTarGzBytes(pluginRoot: URL, in tempRoot: URL) throws -> Data {
        let archive = tempRoot.appendingPathComponent("remote-plugin-bundle-\(UUID().uuidString).tar.gz", isDirectory: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archive.path, "-C", pluginRoot.path, "."]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "tar remote plugin bundle failed: \(stderr)\(stdout)")
        return try Data(contentsOf: archive)
    }

    private func archiveContains(_ archiveBytes: Data, _ expectedPath: String, in tempRoot: URL) throws -> Bool {
        let archive = tempRoot.appendingPathComponent("share-upload-\(UUID().uuidString).tar.gz", isDirectory: false)
        try archiveBytes.write(to: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", archive.path]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "tar share upload listing failed: \(stderr)\(stdout)")
        try? FileManager.default.removeItem(at: archive)
        return stdout
            .split(separator: "\n")
            .map(String.init)
            .contains { $0 == expectedPath || $0 == "./\(expectedPath)" }
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

private actor AppServerSequentialAccountBackend {
    private(set) var requests: [AppServerRequestCapture.Request] = []
    private var responses: [AccountRateLimitsHTTPResponse]

    init(responses: [AccountRateLimitsHTTPResponse]) {
        self.responses = responses
    }

    func respond(to request: URLRequest) -> AccountRateLimitsHTTPResponse {
        requests.append(AppServerRequestCapture.Request(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody.map { String(decoding: $0, as: UTF8.self) }
        ))
        guard !responses.isEmpty else {
            return AccountRateLimitsHTTPResponse(statusCode: 500, body: Data())
        }
        return responses.removeFirst()
    }
}

// Test-only box for running the synchronous processor on a task while the test answers its outgoing request.
private final class AppServerUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
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

private final class AppListDirectoryTransport: @unchecked Sendable {
    private let lock = NSLock()
    private let successBody: String
    private var failing = false
    private var requests = 0

    init(successBody: String) {
        self.successBody = successBody
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func setFailing(_ failing: Bool) {
        lock.lock()
        self.failing = failing
        lock.unlock()
    }

    func response(for request: URLRequest) -> URLSessionTransportResponse {
        lock.lock()
        requests += 1
        let shouldFail = failing
        lock.unlock()

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/backend-api/connectors/directory/list")
        if shouldFail {
            return URLSessionTransportResponse(statusCode: 401, body: Data("unauthorized".utf8))
        }
        return URLSessionTransportResponse(statusCode: 200, body: Data(successBody.utf8))
    }
}

private func workspaceRemotePluginPageBody(
    id: String,
    name: String,
    displayName: String,
    enabled: Bool? = nil
) -> String {
    let enabledField = enabled.map { #", "enabled": \#($0), "disabled_skill_names": []"# } ?? ""
    return """
    {
      "plugins": [
        {
          "id": "\(id)",
          "name": "\(name)",
          "scope": "WORKSPACE",
          "creator_account_user_id": "user-gavin__account-123",
          "share_url": "https://chatgpt.example/plugins/share/share-key-1",
          "installation_policy": "AVAILABLE",
          "authentication_policy": "ON_USE",
          "status": "ENABLED",
          "creator_name": "Gavin",
          "share_principals": [
            {
              "principal_type": "user",
              "principal_id": "user-gavin__account-123",
              "role": "owner",
              "name": "Gavin"
            },
            {
              "principal_type": "user",
              "principal_id": "user-ada__account-123",
              "role": "reader",
              "name": "Ada"
            }
          ],
          "release": {
            "display_name": "\(displayName)",
            "description": "Track work",
            "app_ids": [],
            "interface": {},
            "skills": []
          }\(enabledField)
        }
      ],
      "pagination": {
        "limit": 50,
        "next_page_token": null
      }
    }
    """
}

private func remotePluginDetailBody(
    id: String,
    name: String = "linear",
    displayName: String = "Linear",
    scope: String,
    status: String = "ENABLED",
    installationPolicy: String = "AVAILABLE",
    releaseVersion: String? = nil,
    bundleDownloadURL: String? = nil
) -> String {
    let workspaceFields = scope == "WORKSPACE" ? """
    ,
      "creator_account_user_id": "user-gavin__account-123",
      "creator_name": "Gavin",
      "share_url": "https://chatgpt.example/plugins/share/share-key-1",
      "share_principals": [
        {
          "principal_type": "user",
          "principal_id": "user-gavin__account-123",
          "role": "owner",
          "name": "Gavin"
        },
        {
          "principal_type": "user",
          "principal_id": "user-ada__account-123",
          "role": "reader",
          "name": "Ada"
        }
      ]
    """ : ""
    return """
    {
      "id": "\(id)",
      "name": "\(name)",
      "scope": "\(scope)"\(workspaceFields),
      "installation_policy": "\(installationPolicy)",
      "authentication_policy": "ON_USE",
      "status": "\(status)",
      "release": {
        "display_name": "\(displayName)",
        "description": "Track work in Linear",
        \(releaseVersion.map { #""version": "\#($0)","# } ?? "")
        \(bundleDownloadURL.map { #""bundle_download_url": "\#($0)","# } ?? "")
        "app_ids": [],
        "keywords": ["issue-tracking", "project management"],
        "interface": {
          "short_description": "Plan and track work",
          "capabilities": ["Read", "Write"],
          "logo_url": "https://example.com/linear.png",
          "screenshot_urls": ["https://example.com/linear-shot.png"]
        },
        "skills": [
          {
            "name": "plan-work",
            "description": "Plan work from Linear issues",
            "plugin_release_skill_id": "skill-1",
            "interface": {
              "display_name": "Plan Work",
              "short_description": "Create a plan from issues"
            }
          }
        ]
      }
    }
    """
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
