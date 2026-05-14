import CodexCore
import XCTest

final class AppServerHookProtocolTests: XCTestCase {
    func testHookRunSummaryEncodesRustCamelCaseShapeWithExplicitNullOptionals() throws {
        let run = try appServerHookRunSummary()

        try XCTAssertJSONObjectEqual(run, [
            "id": "run-1",
            "eventName": "preToolUse",
            "handlerType": "command",
            "executionMode": "sync",
            "scope": "turn",
            "sourcePath": "/tmp/codex-hooks/hooks.json",
            "source": "project",
            "displayOrder": 7,
            "status": "running",
            "statusMessage": NSNull(),
            "startedAt": 1_778_320_000,
            "completedAt": NSNull(),
            "durationMs": NSNull(),
            "entries": [
                [
                    "kind": "warning",
                    "text": "careful"
                ],
                [
                    "kind": "context",
                    "text": "extra context"
                ]
            ]
        ])
    }

    func testHookRunSummaryDefaultsMissingRustSourceToUnknown() throws {
        let decoded = try JSONDecoder().decode(
            AppServerHookRunSummary.self,
            from: Data(
                """
                {
                  "id": "run-1",
                  "eventName": "postToolUse",
                  "handlerType": "agent",
                  "executionMode": "async",
                  "scope": "thread",
                  "sourcePath": "/tmp/codex-hooks/hooks.json",
                  "displayOrder": 8,
                  "status": "completed",
                  "statusMessage": null,
                  "startedAt": 1778320000,
                  "completedAt": 1778320002,
                  "durationMs": 2000,
                  "entries": []
                }
                """.utf8
            )
        )

        XCTAssertEqual(decoded.source, .unknown)
        XCTAssertEqual(decoded.eventName, .postToolUse)
        XCTAssertEqual(decoded.handlerType, .agent)
        XCTAssertEqual(decoded.executionMode, .async)
        XCTAssertEqual(decoded.scope, .thread)
        XCTAssertEqual(decoded.status, .completed)
        XCTAssertEqual(decoded.completedAt, 1_778_320_002)
        XCTAssertEqual(decoded.durationMs, 2_000)
    }

    func testHookNotificationsEncodeRustWireShape() throws {
        let run = try appServerHookRunSummary()

        try XCTAssertJSONObjectEqual(
            HookStartedNotification(threadID: "thread-1", turnID: nil, run: run),
            [
                "threadId": "thread-1",
                "turnId": NSNull(),
                "run": [
                    "id": "run-1",
                    "eventName": "preToolUse",
                    "handlerType": "command",
                    "executionMode": "sync",
                    "scope": "turn",
                    "sourcePath": "/tmp/codex-hooks/hooks.json",
                    "source": "project",
                    "displayOrder": 7,
                    "status": "running",
                    "statusMessage": NSNull(),
                    "startedAt": 1_778_320_000,
                    "completedAt": NSNull(),
                    "durationMs": NSNull(),
                    "entries": [
                        [
                            "kind": "warning",
                            "text": "careful"
                        ],
                        [
                            "kind": "context",
                            "text": "extra context"
                        ]
                    ]
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            HookCompletedNotification(threadID: "thread-1", turnID: "turn-1", run: run),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "run": [
                    "id": "run-1",
                    "eventName": "preToolUse",
                    "handlerType": "command",
                    "executionMode": "sync",
                    "scope": "turn",
                    "sourcePath": "/tmp/codex-hooks/hooks.json",
                    "source": "project",
                    "displayOrder": 7,
                    "status": "running",
                    "statusMessage": NSNull(),
                    "startedAt": 1_778_320_000,
                    "completedAt": NSNull(),
                    "durationMs": NSNull(),
                    "entries": [
                        [
                            "kind": "warning",
                            "text": "careful"
                        ],
                        [
                            "kind": "context",
                            "text": "extra context"
                        ]
                    ]
                ]
            ]
        )
    }

    func testAppServerHookRunSummaryConvertsCoreSnakeCaseRun() throws {
        let core = HookRunSummary(
            id: "run-core",
            eventName: .userPromptSubmit,
            handlerType: .prompt,
            executionMode: .async,
            scope: .thread,
            sourcePath: try AbsolutePath(absolutePath: "/tmp/codex-hooks/project.toml"),
            source: .cloudRequirements,
            displayOrder: 2,
            status: .blocked,
            statusMessage: "blocked",
            startedAt: 10,
            completedAt: 20,
            durationMs: 10,
            entries: [
                HookOutputEntry(kind: .feedback, text: "feedback"),
                HookOutputEntry(kind: .error, text: "bad")
            ]
        )

        try XCTAssertJSONObjectEqual(AppServerHookRunSummary(core: core), [
            "id": "run-core",
            "eventName": "userPromptSubmit",
            "handlerType": "prompt",
            "executionMode": "async",
            "scope": "thread",
            "sourcePath": "/tmp/codex-hooks/project.toml",
            "source": "cloudRequirements",
            "displayOrder": 2,
            "status": "blocked",
            "statusMessage": "blocked",
            "startedAt": 10,
            "completedAt": 20,
            "durationMs": 10,
            "entries": [
                [
                    "kind": "feedback",
                    "text": "feedback"
                ],
                [
                    "kind": "error",
                    "text": "bad"
                ]
            ]
        ])
    }

    private func appServerHookRunSummary() throws -> AppServerHookRunSummary {
        AppServerHookRunSummary(
            id: "run-1",
            eventName: .preToolUse,
            handlerType: .command,
            executionMode: .sync,
            scope: .turn,
            sourcePath: try AbsolutePath(absolutePath: "/tmp/codex-hooks/hooks.json"),
            source: .project,
            displayOrder: 7,
            status: .running,
            statusMessage: nil,
            startedAt: 1_778_320_000,
            completedAt: nil,
            durationMs: nil,
            entries: [
                AppServerHookOutputEntry(kind: .warning, text: "careful"),
                AppServerHookOutputEntry(kind: .context, text: "extra context")
            ]
        )
    }
}
