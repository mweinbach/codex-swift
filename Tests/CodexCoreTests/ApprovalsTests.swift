import CodexCore
import XCTest

final class ApprovalsTests: XCTestCase {
    func testExecPolicyAmendmentIsTransparentArray() throws {
        let amendment = ExecPolicyAmendment(command: ["git", "status"])
        let encoded = try String(data: JSONEncoder().encode(amendment), encoding: .utf8)
        XCTAssertEqual(encoded, #"["git","status"]"#)
        XCTAssertEqual(try JSONDecoder().decode(ExecPolicyAmendment.self, from: Data(encoded!.utf8)), amendment)
    }
}
