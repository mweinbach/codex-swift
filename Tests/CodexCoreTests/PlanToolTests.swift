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
}
