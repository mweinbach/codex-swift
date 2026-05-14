@testable import CodexCore
import XCTest

final class UserNotificationTests: XCTestCase {
    func testAgentTurnCompleteWireShapeMatchesRust() throws {
        let notification = UserNotification.agentTurnComplete(
            threadID: "b5f6c1c2-1111-2222-3333-444455556666",
            turnID: "12345",
            cwd: "/Users/example/project",
            client: "codex-tui",
            inputMessages: ["Rename `foo` to `bar` and update the callsites."],
            lastAssistantMessage: "Rename complete and verified `cargo build` succeeds."
        )

        let object = try JSONObject(notification)

        XCTAssertEqual(object["type"] as? String, "agent-turn-complete")
        XCTAssertEqual(object["thread-id"] as? String, "b5f6c1c2-1111-2222-3333-444455556666")
        XCTAssertEqual(object["turn-id"] as? String, "12345")
        XCTAssertEqual(object["cwd"] as? String, "/Users/example/project")
        XCTAssertEqual(object["client"] as? String, "codex-tui")
        XCTAssertEqual(
            object["input-messages"] as? [String],
            ["Rename `foo` to `bar` and update the callsites."]
        )
        XCTAssertEqual(
            object["last-assistant-message"] as? String,
            "Rename complete and verified `cargo build` succeeds."
        )

        let data = try JSONEncoder().encode(notification)
        XCTAssertEqual(try JSONDecoder().decode(UserNotification.self, from: data), notification)
    }

    func testAgentTurnCompleteEncodesNilAssistantMessageAsNull() throws {
        let notification = UserNotification.agentTurnComplete(
            threadID: "thread",
            turnID: "turn",
            cwd: "/tmp",
            inputMessages: [],
            lastAssistantMessage: nil
        )

        let object = try JSONObject(notification)

        XCTAssertFalse(object.keys.contains("client"))
        XCTAssertTrue(object.keys.contains("last-assistant-message"))
        XCTAssertTrue(object["last-assistant-message"] is NSNull)
    }

    func testNotifierBuildsCommandWithSerializedNotificationArgument() throws {
        let notifier = UserNotifier(notifyCommand: ["/bin/echo", "--flag"])
        let notification = UserNotification.agentTurnComplete(
            threadID: "thread",
            turnID: "turn",
            cwd: "/tmp",
            inputMessages: ["hello"],
            lastAssistantMessage: nil
        )

        let invocation = try XCTUnwrap(notifier.invocationArguments(for: notification))

        XCTAssertEqual(invocation[0], "/bin/echo")
        XCTAssertEqual(invocation[1], "--flag")
        let payload = try XCTUnwrap(invocation.last)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "agent-turn-complete")
        XCTAssertEqual(object["thread-id"] as? String, "thread")
    }

    func testNotifierIgnoresMissingOrEmptyCommands() {
        XCTAssertNil(UserNotifier().invocationArguments(for: sampleNotification()))
        XCTAssertNil(UserNotifier(notifyCommand: []).invocationArguments(for: sampleNotification()))
    }

    func testNotifyProcessUsesNullStandardIOLikeRustLegacyNotifyHook() throws {
        let process = try XCTUnwrap(UserNotifier(notifyCommand: ["echo"]).process(for: sampleNotification()))

        XCTAssertEqual(process.executableURL?.path, "/usr/bin/env")
        XCTAssertEqual(process.arguments?.first, "echo")
        XCTAssertNotNil(process.standardInput)
        XCTAssertNotNil(process.standardOutput)
        XCTAssertNotNil(process.standardError)
    }

    private func sampleNotification() -> UserNotification {
        .agentTurnComplete(
            threadID: "thread",
            turnID: "turn",
            cwd: "/tmp",
            inputMessages: [],
            lastAssistantMessage: nil
        )
    }
}
