import CodexCLI
import CodexCore
import Foundation
import XCTest

final class ReviewCommandTargetTests: XCTestCase {
    func testResolvedReviewRequestUsesStructuredTargetWhenAvailable() throws {
        let request = try CodexCLI.ReviewCommandTarget
            .commit(sha: "abcdef1234567890", title: "Parser fix")
            .resolvedReviewRequest(
                stdinIsTerminal: true,
                readStdin: {
                    throw TestError("stdin should not be read")
                }
            )

        XCTAssertEqual(request, ReviewRequest(
            target: .commit(sha: "abcdef1234567890", title: "Parser fix")
        ))
    }

    func testResolvedReviewRequestReadsAndTrimsCustomStdinTarget() throws {
        let request = try CodexCLI.ReviewCommandTarget
            .customFromStdin
            .resolvedReviewRequest(
                stdinIsTerminal: true,
                readStdin: { Data("  focus the auth flow\n".utf8) }
            )

        XCTAssertEqual(request, ReviewRequest(target: .custom(instructions: "focus the auth flow")))
    }

    func testResolvedReviewRequestRejectsEmptyCustomStdinTarget() {
        XCTAssertThrowsError(try CodexCLI.ReviewCommandTarget
            .customFromStdin
            .resolvedReviewRequest(
                stdinIsTerminal: true,
                readStdin: { Data("\n\t ".utf8) }
            )) { error in
                XCTAssertEqual(error as? NonInteractiveInputError, .emptyStdinPrompt)
            }
    }

    private struct TestError: Error, Equatable, CustomStringConvertible, Sendable {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
