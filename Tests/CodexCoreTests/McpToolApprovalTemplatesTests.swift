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
}
