import CodexCore
import XCTest

final class ApprovalPresetsTests: XCTestCase {
    func testBuiltInApprovalPresetsMatchRustOrderAndPolicies() {
        let presets = ApprovalPresets.builtIn()
        XCTAssertEqual(presets.map(\.id), ["read-only", "auto", "full-access"])
        XCTAssertEqual(presets[0].approval, .onRequest)
        XCTAssertEqual(presets[0].sandbox, .readOnly)
        XCTAssertEqual(presets[1].sandbox, .newWorkspaceWritePolicy())
        XCTAssertEqual(presets[2].approval, .never)
        XCTAssertEqual(presets[2].sandbox, .dangerFullAccess)
    }
}
