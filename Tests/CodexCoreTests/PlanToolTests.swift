import CodexCore
import XCTest

final class PlanToolTests: XCTestCase {
    func testUpdatePlanArgsWireShape() throws {
        let args = UpdatePlanArguments(
            explanation: "doing work",
            plan: [PlanItemArgument(step: "Port models", status: .inProgress)]
        )
        try XCTAssertJSONObjectEqual(args, [
            "explanation": "doing work",
            "plan": [
                [
                    "step": "Port models",
                    "status": "in_progress"
                ]
            ]
        ])
    }

    func testUpdatePlanArgsEncodeNilExplanationAsExplicitNullLikeRustOption() throws {
        try XCTAssertJSONObjectEqual(UpdatePlanArguments(explanation: nil, plan: []), [
            "explanation": NSNull(),
            "plan": [] as [Any]
        ])
    }

    func testUpdatePlanArgsDecodeMissingExplanationAsNilLikeRustDefault() throws {
        let decoded = try JSONDecoder().decode(
            UpdatePlanArguments.self,
            from: Data(#"{"plan":[{"step":"Port models","status":"completed"}]}"#.utf8)
        )

        XCTAssertNil(decoded.explanation)
        XCTAssertEqual(decoded.plan, [PlanItemArgument(step: "Port models", status: .completed)])
    }

    func testUpdatePlanArgsRejectUnknownFieldsLikeRustDenyUnknownFields() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UpdatePlanArguments.self,
                from: Data(#"{"explanation":null,"plan":[],"extra":true}"#.utf8)
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("unknown field `extra`"),
                "unexpected error: \(error)"
            )
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UpdatePlanArguments.self,
                from: Data(#"{"plan":[{"step":"Port models","status":"pending","extra":true}]}"#.utf8)
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("unknown field `extra`"),
                "unexpected error: \(error)"
            )
        }
    }
}
