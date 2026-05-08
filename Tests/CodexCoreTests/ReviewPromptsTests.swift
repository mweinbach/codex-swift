import XCTest
@testable import CodexCore

final class ReviewPromptsTests: XCTestCase {
    func testReviewTargetWireShapeUsesCamelCaseTags() throws {
        try XCTAssertJSONObjectEqual(ReviewTarget.uncommittedChanges, [
            "type": "uncommittedChanges"
        ])
        try XCTAssertJSONObjectEqual(ReviewTarget.baseBranch(branch: "main"), [
            "type": "baseBranch",
            "branch": "main"
        ])
        try XCTAssertJSONObjectEqual(ReviewTarget.commit(sha: "abcdef123", title: nil), [
            "type": "commit",
            "sha": "abcdef123",
            "title": NSNull()
        ])
        try XCTAssertJSONObjectEqual(ReviewTarget.custom(instructions: "check this"), [
            "type": "custom",
            "instructions": "check this"
        ])
    }

    func testReviewRequestOmitsMissingHint() throws {
        try XCTAssertJSONObjectEqual(ReviewRequest(target: .uncommittedChanges), [
            "target": [
                "type": "uncommittedChanges"
            ]
        ])

        try XCTAssertJSONObjectEqual(
            ReviewRequest(target: .baseBranch(branch: "main"), userFacingHint: "against main"),
            [
                "target": [
                    "type": "baseBranch",
                    "branch": "main"
                ],
                "user_facing_hint": "against main"
            ]
        )
    }

    func testReviewTargetDecodesWireShape() throws {
        let target = try JSONDecoder().decode(ReviewTarget.self, from: Data("""
        {"type":"commit","sha":"abcdef123","title":"subject"}
        """.utf8))

        XCTAssertEqual(target, .commit(sha: "abcdef123", title: "subject"))
    }

    func testUncommittedPrompt() throws {
        XCTAssertEqual(
            try ReviewPrompts.reviewPrompt(target: .uncommittedChanges, cwd: "/repo"),
            "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."
        )
    }

    func testBaseBranchPromptUsesMergeBaseWhenAvailable() throws {
        var calls: [(cwd: String, branch: String)] = []

        let prompt = try ReviewPrompts.reviewPrompt(
            target: .baseBranch(branch: "main"),
            cwd: "/repo",
            mergeBaseWithHead: { cwd, branch in
                calls.append((cwd, branch))
                return "abc123"
            }
        )

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].cwd, "/repo")
        XCTAssertEqual(calls[0].branch, "main")
        XCTAssertEqual(
            prompt,
            "Review the code changes against the base branch 'main'. The merge base commit for this comparison is abc123. Run `git diff abc123` to inspect the changes relative to main. Provide prioritized, actionable findings."
        )
    }

    func testBaseBranchPromptFallsBackWhenMergeBaseIsMissing() throws {
        let prompt = try ReviewPrompts.reviewPrompt(
            target: .baseBranch(branch: "develop"),
            cwd: "/repo",
            mergeBaseWithHead: { _, _ in nil }
        )

        XCTAssertEqual(
            prompt,
            "Review the code changes against the base branch 'develop'. Start by finding the merge diff between the current branch and develop's upstream e.g. (`git merge-base HEAD \"$(git rev-parse --abbrev-ref \"develop@{upstream}\")\"`), then run `git diff` against that SHA to see what changes we would merge into the develop branch. Provide prioritized, actionable findings."
        )
    }

    func testCommitPrompts() throws {
        XCTAssertEqual(
            try ReviewPrompts.reviewPrompt(
                target: .commit(sha: "abcdef123", title: "subject"),
                cwd: "/repo"
            ),
            "Review the code changes introduced by commit abcdef123 (\"subject\"). Provide prioritized, actionable findings."
        )
        XCTAssertEqual(
            try ReviewPrompts.reviewPrompt(
                target: .commit(sha: "abcdef123", title: nil),
                cwd: "/repo"
            ),
            "Review the code changes introduced by commit abcdef123. Provide prioritized, actionable findings."
        )
    }

    func testCustomPromptTrimsAndRejectsEmpty() throws {
        XCTAssertEqual(
            try ReviewPrompts.reviewPrompt(target: .custom(instructions: "  focus auth  \n"), cwd: "/repo"),
            "focus auth"
        )

        XCTAssertThrowsError(
            try ReviewPrompts.reviewPrompt(target: .custom(instructions: " \n\t "), cwd: "/repo")
        ) { error in
            XCTAssertEqual(error as? ReviewPromptError, .emptyPrompt)
        }
    }

    func testUserFacingHints() {
        XCTAssertEqual(ReviewPrompts.userFacingHint(target: .uncommittedChanges), "current changes")
        XCTAssertEqual(
            ReviewPrompts.userFacingHint(target: .baseBranch(branch: "main")),
            "changes against 'main'"
        )
        XCTAssertEqual(
            ReviewPrompts.userFacingHint(target: .commit(sha: "abcdef1234567890", title: "subject")),
            "commit abcdef1: subject"
        )
        XCTAssertEqual(
            ReviewPrompts.userFacingHint(target: .commit(sha: "abc", title: nil)),
            "commit abc"
        )
        XCTAssertEqual(
            ReviewPrompts.userFacingHint(target: .custom(instructions: "  inspect parser  ")),
            "inspect parser"
        )
    }

    func testResolveReviewRequestHonorsProvidedHint() throws {
        let resolved = try ReviewPrompts.resolveReviewRequest(
            ReviewRequest(target: .custom(instructions: "check runtime"), userFacingHint: "runtime"),
            cwd: "/repo"
        )

        XCTAssertEqual(resolved, ResolvedReviewRequest(
            target: .custom(instructions: "check runtime"),
            prompt: "check runtime",
            userFacingHint: "runtime"
        ))
        XCTAssertEqual(resolved.reviewRequest, ReviewRequest(
            target: .custom(instructions: "check runtime"),
            userFacingHint: "runtime"
        ))
    }
}
