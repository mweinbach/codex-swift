import XCTest
@testable import CodexCore

final class McpToolApprovalElicitationTests: XCTestCase {
    private let questionID = "mcp_tool_call_approval_1"

    func testDeclinedElicitationResponseStaysDeclineLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .decline,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistAlways),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testSyntheticDeclineRequestUserInputResponseStaysDeclineLikeRust() {
        let response = RequestUserInputResponse(answers: [
            questionID: RequestUserInputAnswer(answers: [
                McpToolApprovalAnswer.accept,
                McpToolApprovalAnswer.declineSynthetic,
            ]),
        ])

        XCTAssertEqual(
            parseMcpToolApprovalResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testAcceptedElicitationResponseUsesAlwaysPersistMetaLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistAlways),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptAndRemember
        )
    }

    func testAcceptedElicitationResponseUsesSessionPersistMetaLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: .object([
                McpToolApprovalMetaKey.persist: .string(McpToolApprovalMetaKey.persistSession),
            ])
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptForSession
        )
    }

    func testAcceptedElicitationWithoutContentDefaultsToAcceptLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: nil,
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationWithNonObjectContentDefaultsToAcceptLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .array([]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationResponseReadsStringContentAnswerLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .string(McpToolApprovalAnswer.accept),
            ]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .accept
        )
    }

    func testAcceptedElicitationResponseReadsArrayContentAnswerLikeRust() {
        let response = AppServerProtocol.McpServerElicitationRequestResponse(
            action: .accept,
            content: .object([
                questionID: .array([
                    .integer(1),
                    .string(McpToolApprovalAnswer.acceptForSession),
                ]),
            ]),
            meta: nil
        )

        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(response, questionID: questionID),
            .acceptForSession
        )
    }

    func testRequestUserInputAnswerPriorityMatchesRust() {
        let response = RequestUserInputResponse(answers: [
            questionID: RequestUserInputAnswer(answers: [
                McpToolApprovalAnswer.accept,
                McpToolApprovalAnswer.acceptAndRemember,
                McpToolApprovalAnswer.acceptForSession,
                McpToolApprovalAnswer.declineSynthetic,
            ]),
        ])

        XCTAssertEqual(
            parseMcpToolApprovalResponse(response, questionID: questionID),
            .decline(message: nil)
        )
    }

    func testMissingResponseOrQuestionCancelsLikeRust() {
        XCTAssertEqual(
            parseMcpToolApprovalElicitationResponse(nil, questionID: questionID),
            .cancel
        )
        XCTAssertEqual(
            parseMcpToolApprovalResponse(RequestUserInputResponse(answers: [:]), questionID: questionID),
            .cancel
        )
    }

    func testPromptModeNormalizesSessionAndPersistentApprovalsLikeRust() {
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptForSession, for: .prompt),
            .accept
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptAndRemember, for: .prompt),
            .accept
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptForSession, for: .approve),
            .acceptForSession
        )
        XCTAssertEqual(
            normalizeMcpToolApprovalDecision(.acceptAndRemember, for: .auto),
            .acceptAndRemember
        )
    }
}
