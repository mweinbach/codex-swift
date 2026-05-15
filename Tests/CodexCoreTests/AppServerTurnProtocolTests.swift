import CodexCore
import XCTest

final class AppServerTurnProtocolTests: XCTestCase {
    func testUserInputEncodesRustAppServerV2Shape() throws {
        try XCTAssertJSONObjectEqual(
            AppServerUserInput.text(
                "hello",
                textElements: [AppServerTextElement(
                    byteRange: AppServerByteRange(start: 0, end: 5),
                    placeholder: nil
                )]
            ),
            [
                "type": "text",
                "text": "hello",
                "textElements": [[
                    "byteRange": [
                        "start": 0,
                        "end": 5
                    ],
                    "placeholder": NSNull()
                ]]
            ]
        )

        try XCTAssertJSONObjectEqual(AppServerUserInput.image(url: "https://example.com/image.png"), [
            "type": "image",
            "url": "https://example.com/image.png"
        ])
        try XCTAssertJSONObjectEqual(AppServerUserInput.localImage(path: "/tmp/image.png"), [
            "type": "localImage",
            "path": "/tmp/image.png"
        ])
        try XCTAssertJSONObjectEqual(AppServerUserInput.skill(name: "plan", path: "/skills/plan/SKILL.md"), [
            "type": "skill",
            "name": "plan",
            "path": "/skills/plan/SKILL.md"
        ])
        try XCTAssertJSONObjectEqual(AppServerUserInput.mention(name: "docs", path: "app://google_drive"), [
            "type": "mention",
            "name": "docs",
            "path": "app://google_drive"
        ])
    }

    func testUserInputConvertsCoreRolloutShapeToAppServerShape() throws {
        let core = UserInput.text(
            "hello",
            textElements: [TextElement(byteRange: ByteRange(start: 0, end: 5), placeholder: "hello")]
        )
        let appServer = AppServerUserInput(core: core)

        XCTAssertEqual(appServer.coreValue, core)
        XCTAssertEqual(appServer.textCharacterCount, 5)
        try XCTAssertJSONObjectEqual(appServer, [
            "type": "text",
            "text": "hello",
            "textElements": [[
                "byteRange": [
                    "start": 0,
                    "end": 5
                ],
                "placeholder": "hello"
            ]]
        ])

        try XCTAssertJSONObjectEqual(AppServerUserInput(core: .image(imageURL: "data:image/png;base64,abc")), [
            "type": "image",
            "url": "data:image/png;base64,abc"
        ])
        XCTAssertEqual(AppServerUserInput(core: .image(imageURL: "data:image/png;base64,abc")).textCharacterCount, 0)
        try XCTAssertJSONObjectEqual(AppServerUserInput(core: .localImage(path: "/tmp/a.png")), [
            "type": "localImage",
            "path": "/tmp/a.png"
        ])
    }

    func testUserInputRejectsExplicitNullForRustDefaultedTextElements() throws {
        let omitted = try JSONDecoder().decode(
            AppServerUserInput.self,
            from: Data(#"{"type":"text","text":"hello"}"#.utf8)
        )
        XCTAssertEqual(omitted, .text("hello"))

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerUserInput.self,
                from: Data(#"{"type":"text","text":"hello","textElements":null}"#.utf8)
            )
        )
    }

    func testTurnStartParamsPreserveServiceTierOverrideSemantics() throws {
        let params = AppServerTurnStartParams(
            threadID: "thread_123",
            input: [],
            serviceTier: .clear
        )

        try XCTAssertJSONObjectEqual(params, [
            "threadId": "thread_123",
            "input": [],
            "responsesapiClientMetadata": NSNull(),
            "environments": NSNull(),
            "cwd": NSNull(),
            "approvalPolicy": NSNull(),
            "approvalsReviewer": NSNull(),
            "sandboxPolicy": NSNull(),
            "permissions": NSNull(),
            "model": NSNull(),
            "serviceTier": NSNull(),
            "effort": NSNull(),
            "summary": NSNull(),
            "personality": NSNull(),
            "outputSchema": NSNull(),
            "collaborationMode": NSNull()
        ])

        let withoutOverride = try JSONObject(AppServerTurnStartParams(threadID: "thread_123", input: []))
        XCTAssertNil(withoutOverride["serviceTier"])
        XCTAssertEqual(withoutOverride["responsesapiClientMetadata"] as? NSNull, NSNull())

        try XCTAssertJSONObjectEqual(
            AppServerTurnStartParams(threadID: "thread_123", input: [], serviceTier: .set("priority")),
            [
                "threadId": "thread_123",
                "input": [],
                "responsesapiClientMetadata": NSNull(),
                "environments": NSNull(),
                "cwd": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissions": NSNull(),
                "model": NSNull(),
                "serviceTier": "priority",
                "effort": NSNull(),
                "summary": NSNull(),
                "personality": NSNull(),
                "outputSchema": NSNull(),
                "collaborationMode": NSNull()
            ]
        )

        let nullOverride = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"serviceTier":null}"#.utf8)
        )
        XCTAssertEqual(nullOverride.serviceTier, .clear)

        let omittedOverride = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[]}"#.utf8)
        )
        XCTAssertNil(omittedOverride.serviceTier)
    }

    func testTurnStartParamsUseRustAppServerSandboxPolicyShape() throws {
        let params = AppServerTurnStartParams(
            threadID: "thread_123",
            input: [],
            sandboxPolicy: .workspaceWrite(
                writableRoots: ["/repo"],
                networkAccess: true,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: false
            )
        )

        let object = try JSONObject(params)
        XCTAssertEqual(
            NSDictionary(dictionary: object["sandboxPolicy"] as? [String: Any] ?? [:]),
            NSDictionary(dictionary: [
                "type": "workspaceWrite",
                "writableRoots": ["/repo"],
                "networkAccess": true,
                "excludeTmpdirEnvVar": true,
                "excludeSlashTmp": false
            ])
        )

        let decoded = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"""
            {
              "threadId": "thread_123",
              "input": [],
              "sandboxPolicy": {
                "type": "readOnly",
                "networkAccess": true
              }
            }
            """#.utf8)
        )
        XCTAssertEqual(decoded.sandboxPolicy, .readOnly(networkAccess: true))
    }

    func testTurnStartParamsRoundTripEnvironmentsLikeRustProtocol() throws {
        let cwd = try AbsolutePath(absolutePath: "/tmp/codex-turn")
        let params = AppServerTurnStartParams(
            threadID: "thread_123",
            input: [],
            environments: [AppServerTurnEnvironmentParams(environmentID: "local", cwd: cwd)]
        )

        let object = try JSONObject(params)
        XCTAssertEqual(
            NSArray(array: object["environments"] as? [Any] ?? []),
            NSArray(array: [[
                "environmentId": "local",
                "cwd": "/tmp/codex-turn"
            ]])
        )

        let decoded = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"environments":[]}"#.utf8)
        )
        XCTAssertEqual(decoded.environments, [])
        try XCTAssertJSONObjectEqual(decoded, [
            "threadId": "thread_123",
            "input": [],
            "responsesapiClientMetadata": NSNull(),
            "environments": [],
            "cwd": NSNull(),
            "approvalPolicy": NSNull(),
            "approvalsReviewer": NSNull(),
            "sandboxPolicy": NSNull(),
            "permissions": NSNull(),
            "model": NSNull(),
            "effort": NSNull(),
            "summary": NSNull(),
            "personality": NSNull(),
            "outputSchema": NSNull(),
            "collaborationMode": NSNull()
        ])

        let nullEnvironments = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"environments":null}"#.utf8)
        )
        XCTAssertNil(nullEnvironments.environments)

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerTurnStartParams.self,
                from: Data(#"{"threadId":"thread_123","input":[],"environments":[{"environmentId":"local","cwd":"relative"}]}"#.utf8)
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("decoded relative path without a base path"))
        }
    }

    func testTurnSteerInterruptAndResponsesEncodeRustShapes() throws {
        try XCTAssertJSONObjectEqual(
            AppServerTurnSteerParams(
                threadID: "thread-1",
                input: [.text("continue")],
                expectedTurnID: "turn-1"
            ),
            [
                "threadId": "thread-1",
                "input": [[
                    "type": "text",
                    "text": "continue",
                    "textElements": []
                ]],
                "responsesapiClientMetadata": NSNull(),
                "expectedTurnId": "turn-1"
            ]
        )
        try XCTAssertJSONObjectEqual(AppServerTurnSteerResponse(turnID: "turn-2"), [
            "turnId": "turn-2"
        ])
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerTurnSteerParams.self,
                from: Data(#"{"threadId":"thread-1","input":[]}"#.utf8)
            )
        )
        try XCTAssertJSONObjectEqual(AppServerTurnInterruptParams(threadID: "thread-1", turnID: "turn-2"), [
            "threadId": "thread-1",
            "turnId": "turn-2"
        ])
        try XCTAssertJSONObjectEqual(AppServerTurnInterruptResponse(), [:])

        let turn = AppServerTurn(id: "turn-1", items: [], status: .inProgress)
        try XCTAssertJSONObjectEqual(AppServerTurnStartResponse(turn: turn), [
            "turn": expectedTurnObject(status: "inProgress")
        ])
    }

    func testTurnStartAndSteerParamsExperimentalReasonsMatchRustClientRequestInspection() {
        let granular = AskForApproval.granular(
            GranularApprovalConfig(
                sandboxApproval: false,
                rules: true,
                skillApproval: false,
                requestPermissions: false,
                mcpElicitations: true
            )
        )

        XCTAssertEqual(
            AppServerTurnStartParams(threadID: "thr_123", input: [], approvalPolicy: granular)
                .appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            AppServerTurnStartParams(
                threadID: "thr_123",
                input: [],
                responsesapiClientMetadata: ["source": "test"],
                approvalPolicy: granular
            ).appServerExperimentalReason,
            "turn/start.responsesapiClientMetadata"
        )
        XCTAssertEqual(
            AppServerTurnStartParams(threadID: "thr_123", input: [], environments: [])
                .appServerExperimentalReason,
            "turn/start.environments"
        )
        XCTAssertEqual(
            AppServerTurnStartParams(
                threadID: "thr_123",
                input: [],
                permissions: AppServerPermissionProfileSelectionParams.profile(id: "workspace")
            ).appServerExperimentalReason,
            "turn/start.permissions"
        )
        XCTAssertEqual(
            AppServerTurnStartParams(
                threadID: "thr_123",
                input: [],
                collaborationMode: CollaborationMode(
                    mode: .plan,
                    settings: CollaborationModeSettings(model: "gpt-5")
                )
            ).appServerExperimentalReason,
            "turn/start.collaborationMode"
        )
        XCTAssertEqual(
            AppServerTurnSteerParams(
                threadID: "thr_123",
                input: [],
                responsesapiClientMetadata: ["source": "test"],
                expectedTurnID: "turn_123"
            ).appServerExperimentalReason,
            "turn/steer.responsesapiClientMetadata"
        )
        XCTAssertNil(AppServerTurnStartParams(threadID: "thr_123", input: []).appServerExperimentalReason)
        XCTAssertNil(
            AppServerTurnSteerParams(threadID: "thr_123", input: [], expectedTurnID: "turn_123")
                .appServerExperimentalReason
        )
    }

    func testTurnNotificationsAndPlanUseRustCamelCaseShape() throws {
        let turn = AppServerTurn(id: "turn-1", items: [], status: .inProgress)

        try XCTAssertJSONObjectEqual(TurnStartedNotification(threadID: "thread-1", turn: turn), [
            "threadId": "thread-1",
            "turn": expectedTurnObject(status: "inProgress")
        ])
        try XCTAssertJSONObjectEqual(TurnCompletedNotification(threadID: "thread-1", turn: turn), [
            "threadId": "thread-1",
            "turn": expectedTurnObject(status: "inProgress")
        ])
        try XCTAssertJSONObjectEqual(TurnUsage(inputTokens: 1, cachedInputTokens: 2, outputTokens: 3), [
            "inputTokens": 1,
            "cachedInputTokens": 2,
            "outputTokens": 3
        ])
        try XCTAssertJSONObjectEqual(
            TurnDiffUpdatedNotification(threadID: "thread-1", turnID: "turn-1", diff: "diff --git a/a b/a\n"),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "diff": "diff --git a/a b/a\n"
            ]
        )
        try XCTAssertJSONObjectEqual(
            TurnPlanUpdatedNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                plan: [TurnPlanStep(core: PlanItemArgument(step: "Port turn", status: .inProgress))]
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "explanation": NSNull(),
                "plan": [[
                    "step": "Port turn",
                    "status": "inProgress"
                ]]
            ]
        )
    }

    private func expectedTurnObject(status: String) -> [String: Any] {
        [
            "id": "turn-1",
            "items": [],
            "itemsView": "full",
            "status": status,
            "error": NSNull(),
            "startedAt": NSNull(),
            "completedAt": NSNull(),
            "durationMs": NSNull()
        ]
    }
}
