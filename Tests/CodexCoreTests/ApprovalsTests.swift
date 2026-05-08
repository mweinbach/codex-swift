import CodexCore
import XCTest

final class ApprovalsTests: XCTestCase {
    func testExecPolicyAmendmentIsTransparentArray() throws {
        let amendment = ExecPolicyAmendment(command: ["git", "status"])
        let encoded = try String(data: JSONEncoder().encode(amendment), encoding: .utf8)
        XCTAssertEqual(encoded, #"["git","status"]"#)
        XCTAssertEqual(try JSONDecoder().decode(ExecPolicyAmendment.self, from: Data(encoded!.utf8)), amendment)
    }

    func testReviewDecisionUnitVariantsUseRustSnakeCaseStrings() throws {
        let cases: [(ReviewDecision, String)] = [
            (.approved, #""approved""#),
            (.approvedForSession, #""approved_for_session""#),
            (.denied, #""denied""#),
            (.abort, #""abort""#)
        ]

        for (decision, json) in cases {
            let encoded = try String(data: JSONEncoder().encode(decision), encoding: .utf8)
            XCTAssertEqual(encoded, json)
            XCTAssertEqual(try JSONDecoder().decode(ReviewDecision.self, from: Data(json.utf8)), decision)
        }
    }

    func testReviewDecisionExecPolicyAmendmentUsesExternallyTaggedRustShape() throws {
        let decision = ReviewDecision.approvedExecpolicyAmendment(
            proposedExecpolicyAmendment: ExecPolicyAmendment(command: ["git", "status"])
        )
        let json = #"{"approved_execpolicy_amendment":{"proposed_execpolicy_amendment":["git","status"]}}"#

        let encoded = try String(data: JSONEncoder().encode(decision), encoding: .utf8)
        XCTAssertEqual(encoded, json)
        XCTAssertEqual(try JSONDecoder().decode(ReviewDecision.self, from: Data(json.utf8)), decision)
    }

    func testReviewDecisionDefaultIsDenied() {
        XCTAssertEqual(ReviewDecision.default, .denied)
    }
}
