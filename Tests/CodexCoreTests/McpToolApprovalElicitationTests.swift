import XCTest
@testable import CodexCore

final class McpToolApprovalElicitationTests: XCTestCase {
    private let questionID = "mcp_tool_call_approval_1"

    func testQuestionIDRecognitionRequiresRustPrefixUnderscoreBoundary() {
        XCTAssertTrue(isMcpToolApprovalQuestionID("mcp_tool_call_approval_call-1"))
        XCTAssertTrue(isMcpToolApprovalQuestionID("mcp_tool_call_approval_"))
        XCTAssertFalse(isMcpToolApprovalQuestionID("mcp_tool_call_approval"))
        XCTAssertFalse(isMcpToolApprovalQuestionID("mcp_tool_call_approvalExtra_call-1"))
        XCTAssertFalse(isMcpToolApprovalQuestionID("other_mcp_tool_call_approval_call-1"))
    }

    func testCustomServersSupportSessionAndPersistentApprovalKeysLikeRust() {
        let invocation = McpInvocation(server: "custom_server", tool: "run_action")
        let expected = McpToolApprovalKey(
            server: "custom_server",
            connectorID: nil,
            toolName: "run_action"
        )

        XCTAssertEqual(
            sessionMcpToolApprovalKey(invocation: invocation, metadata: nil, approvalMode: .auto),
            expected
        )
        XCTAssertEqual(
            persistentMcpToolApprovalKey(invocation: invocation, metadata: nil, approvalMode: .auto),
            expected
        )
    }

    func testCodexAppsConnectorsSupportPersistentApprovalKeysLikeRust() {
        let invocation = McpInvocation(
            server: codexAppsMCPServerName,
            tool: "calendar/list_events"
        )
        let metadata = McpToolApprovalMetadata(
            connectorID: "calendar",
            connectorName: "Calendar"
        )
        let expected = McpToolApprovalKey(
            server: codexAppsMCPServerName,
            connectorID: "calendar",
            toolName: "calendar/list_events"
        )

        XCTAssertEqual(
            sessionMcpToolApprovalKey(invocation: invocation, metadata: metadata, approvalMode: .auto),
            expected
        )
        XCTAssertEqual(
            persistentMcpToolApprovalKey(invocation: invocation, metadata: metadata, approvalMode: .auto),
            expected
        )
    }

    func testPromptApprovalModeAndMissingCodexAppsConnectorDoNotCreateApprovalKeysLikeRust() {
        let codexAppsInvocation = McpInvocation(
            server: codexAppsMCPServerName,
            tool: "calendar/list_events"
        )
        let customInvocation = McpInvocation(server: "custom_server", tool: "run_action")

        XCTAssertNil(sessionMcpToolApprovalKey(
            invocation: customInvocation,
            metadata: nil,
            approvalMode: .prompt
        ))
        XCTAssertNil(persistentMcpToolApprovalKey(
            invocation: customInvocation,
            metadata: nil,
            approvalMode: .approve
        ))
        XCTAssertNil(sessionMcpToolApprovalKey(
            invocation: codexAppsInvocation,
            metadata: nil,
            approvalMode: .auto
        ))
    }

    func testPromptOptionsFollowKeyAvailabilityAndElicitationFeatureLikeRust() {
        let key = McpToolApprovalKey(server: "custom_server", connectorID: nil, toolName: "run_action")

        XCTAssertEqual(
            mcpToolApprovalPromptOptions(
                sessionApprovalKey: key,
                persistentApprovalKey: key,
                toolCallMcpElicitationEnabled: false
            ),
            McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: false
            )
        )
        XCTAssertEqual(
            mcpToolApprovalPromptOptions(
                sessionApprovalKey: key,
                persistentApprovalKey: key,
                toolCallMcpElicitationEnabled: true
            ),
            McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: true
            )
        )
        XCTAssertEqual(
            mcpToolApprovalPromptOptions(
                sessionApprovalKey: nil,
                persistentApprovalKey: key,
                toolCallMcpElicitationEnabled: true
            ),
            McpToolApprovalPromptOptions(
                allowSessionRemember: false,
                allowPersistentApproval: true
            )
        )
    }

    func testGuardianElicitationReviewBuildsMcpToolCallFromOptInMetaLikeRust() {
        let review = guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
            serverName: "browser-use",
            requestID: "7",
            request: .form(
                meta: .object(Self.guardianMeta(toolParams: .object([
                    "origin": .string("https://example.com"),
                ]))),
                message: "Allow origin?",
                requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
            )
        ))

        XCTAssertEqual(review, .approvalRequest(GuardianMcpToolApprovalRequest(
            id: "mcp_elicitation:browser-use:7",
            server: "browser-use",
            toolName: "access_browser_origin",
            arguments: .object(["origin": .string("https://example.com")]),
            connectorID: "browser-use",
            connectorName: "Browser Use",
            connectorDescription: nil,
            toolTitle: "Access browser origin",
            toolDescription: nil
        )))
    }

    func testGuardianElicitationReviewDefaultsMissingToolParamsLikeRust() {
        let review = guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
            serverName: "browser-use",
            requestID: "7",
            request: .form(
                meta: .object(Self.guardianMeta(toolParams: nil)),
                message: "Allow origin?",
                requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
            )
        ))

        guard case let .approvalRequest(request) = review else {
            return XCTFail("expected Guardian MCP tool call request")
        }
        XCTAssertEqual(request.arguments, .object([:]))
    }

    func testGuardianElicitationReviewRequiresExplicitApprovalRequestOptInLikeRust() {
        let review = guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
            serverName: "browser-use",
            requestID: "7",
            request: .form(
                meta: .object([
                    McpToolApprovalMetaKey.approvalKind: .string(McpToolApprovalMetaKey.approvalKindMcpToolCall),
                    McpToolApprovalMetaKey.toolName: .string("access_browser_origin"),
                ]),
                message: "Allow origin?",
                requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
            )
        ))

        XCTAssertEqual(review, .notRequested)
    }

    func testGuardianElicitationReviewDeclinesUnsupportedOptInShapesLikeRust() {
        XCTAssertEqual(
            guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
                serverName: "browser-use",
                requestID: "8",
                request: .url(
                    meta: .object(Self.guardianMeta(toolParams: .object([:]))),
                    message: "Open URL",
                    url: "https://example.com",
                    elicitationID: "elicit-1"
                )
            )),
            .decline("guardian MCP elicitation review only supports form elicitations")
        )
        XCTAssertEqual(
            guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
                serverName: "browser-use",
                requestID: "9",
                request: .form(
                    meta: .object(Self.guardianMeta(toolParams: .object([:]))),
                    message: "Allow origin?",
                    requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [
                        "confirmed": .string(AppServerProtocol.McpElicitationStringSchema())
                    ])
                )
            )),
            .decline("guardian MCP elicitation review only supports empty form schemas")
        )
        XCTAssertEqual(
            guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
                serverName: "browser-use",
                requestID: "10",
                request: .form(
                    meta: .object([
                        McpToolApprovalMetaKey.approvalKind: .string(McpToolApprovalMetaKey.approvalKindMcpToolCall),
                        McpToolApprovalMetaKey.requestType: .string(McpToolApprovalMetaKey.requestTypeApprovalRequest),
                    ]),
                    message: "Allow origin?",
                    requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
                )
            )),
            .decline("guardian MCP elicitation metadata must include a non-empty tool_name")
        )
        XCTAssertEqual(
            guardianMcpElicitationReview(request: GuardianMcpElicitationReviewRequest(
                serverName: "browser-use",
                requestID: "11",
                request: .form(
                    meta: .object(Self.guardianMeta(toolParams: .array([]))),
                    message: "Allow origin?",
                    requestedSchema: AppServerProtocol.McpElicitationSchema(properties: [:])
                )
            )),
            .decline("guardian MCP elicitation tool_params must be an object")
        )
    }

    func testGuardianDecisionsMapToMcpElicitationResponsesLikeRust() throws {
        try XCTAssertJSONObjectEqual(
            mcpElicitationResponseFromGuardianDecision(.approved),
            [
                "action": "accept",
                "content": [:],
                "_meta": ["approvals_reviewer": "auto_review"],
            ]
        )
        try XCTAssertJSONObjectEqual(
            mcpElicitationResponseFromGuardianDecision(.denied(message: "Denied by Guardian")),
            [
                "action": "decline",
                "content": NSNull(),
                "_meta": [
                    "approvals_reviewer": "auto_review",
                    "message": "Denied by Guardian",
                ],
            ]
        )
        try XCTAssertJSONObjectEqual(
            mcpElicitationResponseFromGuardianDecision(.timedOut(message: "Guardian review timed out.")),
            [
                "action": "decline",
                "content": NSNull(),
                "_meta": [
                    "approvals_reviewer": "auto_review",
                    "message": "Guardian review timed out.",
                ],
            ]
        )
        try XCTAssertJSONObjectEqual(
            mcpElicitationResponseFromGuardianDecision(.abort),
            [
                "action": "cancel",
                "content": NSNull(),
                "_meta": ["approvals_reviewer": "auto_review"],
            ]
        )
    }

    func testApprovalQuestionOptionsOmitAlwaysAllowWhenElicitationDisabledLikeRust() {
        let question = buildMcpToolApprovalQuestion(
            id: "q",
            serverName: codexAppsMCPServerName,
            toolName: "run_action",
            connectorName: "Calendar",
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: false
            )
        )

        XCTAssertEqual(question.header, "Approve app tool call?")
        XCTAssertEqual(question.question, "Allow Calendar to run tool \"run_action\"?")
        XCTAssertEqual(question.isOther, false)
        XCTAssertEqual(question.isSecret, false)
        XCTAssertEqual(question.options?.map(\.label), [
            McpToolApprovalAnswer.accept,
            McpToolApprovalAnswer.acceptForSession,
            McpToolApprovalAnswer.cancel,
        ])
    }

    func testCustomMcpToolQuestionOffersSessionAndPersistentApprovalLikeRust() {
        let question = buildMcpToolApprovalQuestion(
            id: "q",
            serverName: "custom_server",
            toolName: "run_action",
            connectorName: nil,
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: true
            )
        )

        XCTAssertEqual(question.question, "Allow the custom_server MCP server to run tool \"run_action\"?")
        XCTAssertEqual(question.options?.map(\.label), [
            McpToolApprovalAnswer.accept,
            McpToolApprovalAnswer.acceptForSession,
            McpToolApprovalAnswer.acceptAndRemember,
            McpToolApprovalAnswer.cancel,
        ])
        XCTAssertEqual(question.options?.map(\.description), [
            "Run the tool and continue.",
            "Run the tool and remember this choice for this session.",
            "Run the tool and remember this choice for future tool calls.",
            "Cancel this tool call.",
        ])
    }

    func testQuestionOverrideTrimsTrailingQuestionMarksLikeRust() {
        let question = buildMcpToolApprovalQuestion(
            id: "q",
            serverName: "custom_server",
            toolName: "run_action",
            connectorName: nil,
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: false,
                allowPersistentApproval: false
            ),
            questionOverride: "Allow this??"
        )

        XCTAssertEqual(question.question, "Allow this?")
    }

    func testFallbackMessageUsesThisAppWhenCodexAppsConnectorNameIsMissingLikeRust() {
        XCTAssertEqual(
            buildMcpToolApprovalFallbackMessage(
                serverName: codexAppsMCPServerName,
                toolName: "run_action",
                connectorName: "   "
            ),
            "Allow this app to run tool \"run_action\"?"
        )
    }

    func testQuestionTextUsesTrimmedMonitorReasonLikeRust() {
        XCTAssertEqual(
            mcpToolApprovalQuestionText(
                question: "Allow this app?",
                monitorReason: "  elevated risk  "
            ),
            "Tool call needs your approval. Reason: elevated risk"
        )
        XCTAssertEqual(
            mcpToolApprovalQuestionText(question: "Allow this app?", monitorReason: "  "),
            "Allow this app?"
        )
    }

    func testDeclinedElicitationResponseStaysDeclineLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .decline,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistAlways),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testSyntheticDeclineRequestUserInputResponseStaysDeclineLikeRust() {
        let response = RequestUserInputResponse(answers: [
            questionID: RequestUserInputAnswer(answers: [
                McpToolApprovalAnswer.accept,
                McpToolApprovalAnswer.declineSynthetic,
            ]),
        ])

        XCTAssertEqual(
            parseMcpToolApprovalResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testAcceptedElicitationResponseUsesAlwaysPersistMetaLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistAlways),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptAndRemember
        )
    }

    func testAcceptedElicitationResponseUsesSessionPersistMetaLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistSession),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptForSession
        )
    }

    func testAcceptedElicitationWithoutContentDefaultsToAcceptLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: nil,
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationWithNonObjectContentDefaultsToAcceptLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .array([]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationResponseReadsStringContentAnswerLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationResponseReadsArrayContentAnswerLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .array([
                    .integer(1),
                    .string(McpToolApprovalAnswer.acceptForSession),
                ]),
            ]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptForSession
        )
    }

    func testRequestUserInputAnswerPriorityMatchesRust() {
        let response = RequestUserInputResponse(answers: [
            questionID: RequestUserInputAnswer(answers: [
                McpToolApprovalAnswer.accept,
                McpToolApprovalAnswer.acceptAndRemember,
                McpToolApprovalAnswer.acceptForSession,
                McpToolApprovalAnswer.declineSynthetic,
            ]),
        ])

        XCTAssertEqual(
            parseMcpToolApprovalResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testMissingResponseOrQuestionCancelsLikeRust() {
        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(nil, questionID: questionID),
            .cancel
        )
        XCTAssertEqual(
            parseMcpToolApprovalResponse(RequestUserInputResponse(answers: [:]), questionID: questionID),
            .cancel
        )
    }

    func testPromptModeNormalizesSessionAndPersistentApprovalsLikeRust() {
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptForSession, for: .prompt),
            .accept
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptAndRemember, for: .prompt),
            .accept
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptForSession, for: .approve),
            .acceptForSession
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptAndRemember, for: .auto),
            .acceptAndRemember
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.blockedBySafetyMonitor("risk"), for: .prompt),
            .blockedBySafetyMonitor("risk")
        )
    }

    private static func guardianMeta(toolParams: JSONValue?) -> [String: JSONValue] {
        var meta: [String: JSONValue] = [
            McpToolApprovalMetaKey.approvalKind: .string(McpToolApprovalMetaKey.approvalKindMcpToolCall),
            McpToolApprovalMetaKey.requestType: .string(McpToolApprovalMetaKey.requestTypeApprovalRequest),
            McpToolApprovalMetaKey.connectorID: .string("browser-use"),
            McpToolApprovalMetaKey.connectorName: .string("Browser Use"),
            McpToolApprovalMetaKey.toolName: .string("access_browser_origin"),
            McpToolApprovalMetaKey.toolTitle: .string("Access browser origin"),
        ]
        if let toolParams {
            meta[McpToolApprovalMetaKey.toolParams] = toolParams
        }
        return meta
    }
}
