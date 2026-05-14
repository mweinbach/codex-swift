import CodexCore
import XCTest

final class AppServerCollaborationModeProtocolTests: XCTestCase {
    func testCollaborationModeListParamsShapeMatchesRustProtocol() throws {
        try XCTAssertJSONObjectEqual(CollaborationModeListParams(), [:])
    }

    func testCollaborationModeMaskEncodesExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            AppServerCollaborationModeMask(
                name: "Default",
                mode: .defaultMode
            ),
            [
                "name": "Default",
                "mode": "default",
                "model": NSNull(),
                "reasoning_effort": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            AppServerCollaborationModeMask(
                name: "Plan",
                mode: .plan,
                model: "gpt-5.4",
                reasoningEffort: .medium
            ),
            [
                "name": "Plan",
                "mode": "plan",
                "model": "gpt-5.4",
                "reasoning_effort": "medium"
            ]
        )
    }

    func testCollaborationModeListResponseProjectsCoreMasksWithoutDeveloperInstructionsLikeRustProtocol() throws {
        let response = CollaborationModeListResponse(
            coreMasks: [
                CollaborationModeMask(
                    name: "Plan",
                    mode: .plan,
                    reasoningEffort: CollaborationModeOptionalSetting.set(.medium),
                    developerInstructions: CollaborationModeOptionalSetting.set("Plan before editing.")
                ),
                CollaborationModeMask(
                    name: "Default",
                    mode: .defaultMode,
                    reasoningEffort: .preserve,
                    developerInstructions: .clear
                )
            ]
        )

        try XCTAssertJSONObjectEqual(
            response,
            [
                "data": [
                    [
                        "name": "Plan",
                        "mode": "plan",
                        "model": NSNull(),
                        "reasoning_effort": "medium"
                    ],
                    [
                        "name": "Default",
                        "mode": "default",
                        "model": NSNull(),
                        "reasoning_effort": NSNull()
                    ]
                ]
            ]
        )
    }

    func testCollaborationModeMaskDecodesNullOptionalsLikeRustProtocol() throws {
        let decoded = try JSONDecoder().decode(
            AppServerCollaborationModeMask.self,
            from: Data(
                #"""
                {
                  "name": "Default",
                  "mode": null,
                  "model": null,
                  "reasoning_effort": null
                }
                """#.utf8
            )
        )

        XCTAssertEqual(decoded.name, "Default")
        XCTAssertNil(decoded.mode)
        XCTAssertNil(decoded.model)
        XCTAssertNil(decoded.reasoningEffort)
    }
}
