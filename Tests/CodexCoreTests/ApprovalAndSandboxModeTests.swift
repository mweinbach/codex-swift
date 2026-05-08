import CodexCore
import XCTest

final class ApprovalAndSandboxModeTests: XCTestCase {
    func testApprovalArgumentsMapToProtocolModes() {
        XCTAssertEqual(ApprovalModeCLIArgument.untrusted.approvalMode, .unlessTrusted)
        XCTAssertEqual(ApprovalModeCLIArgument.onFailure.approvalMode, .onFailure)
        XCTAssertEqual(ApprovalModeCLIArgument.onRequest.approvalMode, .onRequest)
        XCTAssertEqual(ApprovalModeCLIArgument.never.approvalMode, .never)
    }

    func testSandboxArgumentsMapToProtocolModes() {
        XCTAssertEqual(SandboxModeCLIArgument.readOnly.sandboxMode, .readOnly)
        XCTAssertEqual(SandboxModeCLIArgument.workspaceWrite.sandboxMode, .workspaceWrite)
        XCTAssertEqual(SandboxModeCLIArgument.dangerFullAccess.sandboxMode, .dangerFullAccess)
    }
}
