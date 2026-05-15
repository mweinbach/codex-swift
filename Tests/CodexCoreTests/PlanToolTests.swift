import CodexCore
import XCTest

final class PlanToolTests: XCTestCase {
    func testUpdatePlanArgsMatchRustWireShape() throws {
        let args = UpdatePlanArguments(
            explanation: "Tighten parity",
            plan: [
                PlanItemArgument(step: "Inspect Rust", status: .completed),
                PlanItemArgument(step: "Port Swift", status: .inProgress),
                PlanItemArgument(step: "Verify", status: .pending)
            ]
        )

        try XCTAssertJSONObjectEqual(args, [
            "explanation": "Tighten parity",
            "plan": [
                ["step": "Inspect Rust", "status": "completed"],
                ["step": "Port Swift", "status": "in_progress"],
                ["step": "Verify", "status": "pending"]
            ]
        ])
    }

    func testUpdatePlanArgsDefaultOptionalExplanationLikeRust() throws {
        try XCTAssertJSONObjectEqual(UpdatePlanArguments(explanation: nil, plan: []), [
            "explanation": NSNull(),
            "plan": [] as [Any]
        ])

        let omitted = try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "plan": [
            { "step": "Verify", "status": "pending" }
          ]
        }
        """#.utf8))
        XCTAssertNil(omitted.explanation)
        XCTAssertEqual(omitted.plan, [PlanItemArgument(step: "Verify", status: .pending)])

        let explicitNull = try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "explanation": null,
          "plan": [
            { "step": "Verify", "status": "completed" }
          ]
        }
        """#.utf8))
        XCTAssertNil(explicitNull.explanation)
        XCTAssertEqual(explicitNull.plan, [PlanItemArgument(step: "Verify", status: .completed)])
    }

    func testUpdatePlanArgsRejectUnknownFieldsLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "plan": [
            { "step": "Verify", "status": "pending" }
          ],
          "extra": true
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "plan": [
            { "step": "Verify", "status": "pending", "extra": true }
          ]
        }
        """#.utf8)))
    }

    func testUpdatePlanArgsRequirePlanAndKnownStatusesLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "explanation": "missing plan"
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(UpdatePlanArguments.self, from: Data(#"""
        {
          "plan": [
            { "step": "Verify", "status": "running" }
          ]
        }
        """#.utf8)))
    }
}
