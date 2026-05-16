import XCTest
@testable import CodexCore

final class McpToolApprovalTemplatesTests: XCTestCase {
    func testRendersExactMatchWithReadableParamLabelsFromRust() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "calendar",
                serverName: "codex_apps",
                toolTitle: "create_event",
                template: "Allow {connector_name} to create an event?",
                templateParams: [
                    ConsequentialToolTemplateParam(name: "calendar_id", label: "Calendar"),
                    ConsequentialToolTemplateParam(name: "title", label: "Title"),
                ]
            ),
        ]

        let rendered = McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "calendar",
            connectorName: "Calendar",
            toolTitle: "create_event",
            toolParams: .object([
                "title": .string("Roadmap review"),
                "calendar_id": .string("primary"),
                "timezone": .string("UTC"),
            ])
        )

        XCTAssertEqual(rendered, RenderedMcpToolApprovalTemplate(
            question: "Allow Calendar to create an event?",
            elicitationMessage: "Allow Calendar to create an event?",
            toolParams: .object([
                "title": .string("Roadmap review"),
                "calendar_id": .string("primary"),
                "timezone": .string("UTC"),
            ]),
            toolParamsDisplay: [
                RenderedMcpToolApprovalParam(
                    name: "calendar_id",
                    value: .string("primary"),
                    displayName: "Calendar"
                ),
                RenderedMcpToolApprovalParam(
                    name: "title",
                    value: .string("Roadmap review"),
                    displayName: "Title"
                ),
                RenderedMcpToolApprovalParam(
                    name: "timezone",
                    value: .string("UTC"),
                    displayName: "timezone"
                ),
            ]
        ))
    }

    func testReturnsNilWhenNoExactRustMatchExists() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "calendar",
                serverName: "codex_apps",
                toolTitle: "create_event",
                template: "Allow {connector_name} to create an event?",
                templateParams: []
            ),
        ]

        XCTAssertNil(McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "calendar",
            connectorName: "Calendar",
            toolTitle: "delete_event",
            toolParams: .object([:])
        ))
    }

    func testReturnsNilWhenRelabelingWouldCollideLikeRust() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "calendar",
                serverName: "codex_apps",
                toolTitle: "create_event",
                template: "Allow {connector_name} to create an event?",
                templateParams: [
                    ConsequentialToolTemplateParam(name: "calendar_id", label: "timezone"),
                ]
            ),
        ]

        XCTAssertNil(McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "calendar",
            connectorName: "Calendar",
            toolTitle: "create_event",
            toolParams: .object([
                "calendar_id": .string("primary"),
                "timezone": .string("UTC"),
            ])
        ))
    }

    func testBundledRustTemplatesLoad() {
        XCTAssertEqual(McpToolApprovalTemplates.bundledTemplates?.isEmpty, false)
    }

    func testRendersLiteralTemplateWithoutConnectorSubstitutionFromRust() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "github",
                serverName: "codex_apps",
                toolTitle: "add_comment",
                template: "Allow GitHub to add a comment to a pull request?",
                templateParams: []
            ),
        ]

        let rendered = McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "github",
            connectorName: nil,
            toolTitle: "add_comment",
            toolParams: .object([:])
        )

        XCTAssertEqual(rendered, RenderedMcpToolApprovalTemplate(
            question: "Allow GitHub to add a comment to a pull request?",
            elicitationMessage: "Allow GitHub to add a comment to a pull request?",
            toolParams: .object([:]),
            toolParamsDisplay: []
        ))
    }

    func testReturnsNilWhenConnectorPlaceholderHasNoValueLikeRust() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "calendar",
                serverName: "codex_apps",
                toolTitle: "create_event",
                template: "Allow {connector_name} to create an event?",
                templateParams: []
            ),
        ]

        XCTAssertNil(McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "calendar",
            connectorName: nil,
            toolTitle: "create_event",
            toolParams: .object([:])
        ))
    }

    func testRejectsNonObjectToolParamsLikeRust() {
        let templates = [
            ConsequentialToolMessageTemplate(
                connectorID: "github",
                serverName: "codex_apps",
                toolTitle: "add_comment",
                template: "Allow GitHub to add a comment to a pull request?",
                templateParams: []
            ),
        ]

        XCTAssertNil(McpToolApprovalTemplates.render(
            from: templates,
            serverName: "codex_apps",
            connectorID: "github",
            connectorName: nil,
            toolTitle: "add_comment",
            toolParams: .array([])
        ))
    }

    func testFallbackDisplayParamsSortObjectKeysLikeRust() {
        XCTAssertEqual(McpToolApprovalTemplates.buildDisplayParams(from: .object([
            "title": .string("Roadmap review"),
            "calendar_id": .string("primary"),
        ])), [
            RenderedMcpToolApprovalParam(
                name: "calendar_id",
                value: .string("primary"),
                displayName: "calendar_id"
            ),
            RenderedMcpToolApprovalParam(
                name: "title",
                value: .string("Roadmap review"),
                displayName: "title"
            ),
        ])
        XCTAssertNil(McpToolApprovalTemplates.buildDisplayParams(from: .array([])))
        XCTAssertNil(McpToolApprovalTemplates.buildDisplayParams(from: nil))
    }

    func testRenderedApprovalParamUsesRustSnakeCaseWireShape() throws {
        try XCTAssertJSONObjectEqual(RenderedMcpToolApprovalParam(
            name: "calendar_id",
            value: .string("primary"),
            displayName: "Calendar"
        ), [
            "name": "calendar_id",
            "value": "primary",
            "display_name": "Calendar",
        ])
    }

    func testApprovalElicitationMetaMarksToolApprovalsLikeRust() {
        XCTAssertEqual(buildMcpToolApprovalElicitationMeta(
            serverName: "custom_server",
            metadata: nil,
            toolParams: nil,
            toolParamsDisplay: nil,
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: false,
                allowPersistentApproval: false
            )
        ), .object([
            "codex_approval_kind": .string("mcp_tool_call"),
        ]))
    }

    func testApprovalElicitationMetaMergesSessionAndAlwaysPersistForCustomServersLikeRust() {
        XCTAssertEqual(buildMcpToolApprovalElicitationMeta(
            serverName: "custom_server",
            metadata: McpToolApprovalMetadata(
                toolTitle: "Run Action",
                toolDescription: "Runs the selected action."
            ),
            toolParams: .object(["id": .integer(1)]),
            toolParamsDisplay: nil,
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: true
            )
        ), .object([
            "codex_approval_kind": .string("mcp_tool_call"),
            "persist": .array([.string("session"), .string("always")]),
            "tool_title": .string("Run Action"),
            "tool_description": .string("Runs the selected action."),
            "tool_params": .object(["id": .integer(1)]),
        ]))
    }

    func testApprovalElicitationMetaIncludesConnectorSourceForCodexAppsLikeRust() {
        XCTAssertEqual(buildMcpToolApprovalElicitationMeta(
            serverName: codexAppsMCPServerName,
            metadata: McpToolApprovalMetadata(
                connectorID: "calendar",
                connectorName: "Calendar",
                connectorDescription: "Manage events and schedules.",
                toolTitle: "Run Action",
                toolDescription: "Runs the selected action."
            ),
            toolParams: .object(["calendar_id": .string("primary")]),
            toolParamsDisplay: nil,
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: false,
                allowPersistentApproval: false
            )
        ), .object([
            "codex_approval_kind": .string("mcp_tool_call"),
            "source": .string("connector"),
            "connector_id": .string("calendar"),
            "connector_name": .string("Calendar"),
            "connector_description": .string("Manage events and schedules."),
            "tool_title": .string("Run Action"),
            "tool_description": .string("Runs the selected action."),
            "tool_params": .object(["calendar_id": .string("primary")]),
        ]))
    }

    func testApprovalElicitationRequestUsesMessageOverrideAndPreservesToolParamsKeysLikeRust() throws {
        let request = buildMcpToolApprovalElicitationRequest(
            threadID: "thread-1",
            turnID: "turn-1",
            serverName: codexAppsMCPServerName,
            metadata: McpToolApprovalMetadata(
                connectorID: "calendar",
                connectorName: "Calendar",
                connectorDescription: "Manage events and schedules.",
                toolTitle: "Create Event",
                toolDescription: "Create a calendar event."
            ),
            toolParams: .object([
                "calendar_id": .string("primary"),
                "title": .string("Roadmap review"),
            ]),
            toolParamsDisplay: [
                RenderedMcpToolApprovalParam(
                    name: "calendar_id",
                    value: .string("primary"),
                    displayName: "Calendar"
                ),
                RenderedMcpToolApprovalParam(
                    name: "title",
                    value: .string("Roadmap review"),
                    displayName: "Title"
                ),
            ],
            message: "Allow Calendar to create an event?",
            promptOptions: McpToolApprovalPromptOptions(
                allowSessionRemember: true,
                allowPersistentApproval: true
            )
        )

        try XCTAssertJSONObjectEqual(request, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "serverName": "codex_apps",
            "mode": "form",
            "_meta": [
                "codex_approval_kind": "mcp_tool_call",
                "persist": ["session", "always"],
                "source": "connector",
                "connector_id": "calendar",
                "connector_name": "Calendar",
                "connector_description": "Manage events and schedules.",
                "tool_title": "Create Event",
                "tool_description": "Create a calendar event.",
                "tool_params": [
                    "calendar_id": "primary",
                    "title": "Roadmap review",
                ],
                "tool_params_display": [
                    [
                        "name": "calendar_id",
                        "value": "primary",
                        "display_name": "Calendar",
                    ],
                    [
                        "name": "title",
                        "value": "Roadmap review",
                        "display_name": "Title",
                    ],
                ],
            ],
            "message": "Allow Calendar to create an event?",
            "requestedSchema": [
                "type": "object",
                "properties": [:],
            ],
        ])
    }
}
