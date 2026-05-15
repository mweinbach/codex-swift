import CodexCore
import XCTest

final class ApprovalAndSandboxModeTests: XCTestCase {
    func testApprovalArgumentsMapToProtocolModes() {
        XCTAssertEqual(ApprovalModeCLIArgument.untrusted.approvalMode, .unlessTrusted)
        XCTAssertEqual(ApprovalModeCLIArgument.onFailure.approvalMode, .onFailure)
        XCTAssertEqual(ApprovalModeCLIArgument.onRequest.approvalMode, .onRequest)
        XCTAssertEqual(ApprovalModeCLIArgument.never.approvalMode, .never)
    }

    func testApprovalsReviewerSerializesAutoReviewAndAcceptsLegacyAliasLikeRust() throws {
        XCTAssertEqual(try jsonString(for: ApprovalsReviewer.user), #""user""#)
        XCTAssertEqual(try jsonString(for: ApprovalsReviewer.autoReview), #""guardian_subagent""#)

        XCTAssertEqual(try reviewer(from: #""user""#), .user)
        XCTAssertEqual(try reviewer(from: #""guardian_subagent""#), .autoReview)
        XCTAssertEqual(try reviewer(from: #""auto_review""#), .autoReview)
    }

    func testSandboxArgumentsMapToProtocolModes() {
        XCTAssertEqual(SandboxModeCLIArgument.readOnly.sandboxMode, .readOnly)
        XCTAssertEqual(SandboxModeCLIArgument.workspaceWrite.sandboxMode, .workspaceWrite)
        XCTAssertEqual(SandboxModeCLIArgument.dangerFullAccess.sandboxMode, .dangerFullAccess)
    }

    private func jsonString<T: Encodable>(for value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func reviewer(from json: String) throws -> ApprovalsReviewer {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(ApprovalsReviewer.self, from: data)
    }
}
