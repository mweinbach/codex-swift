import XCTest
@testable import CodexCore

final class ReviewOutputTests: XCTestCase {
    func testReviewOutputWireShapeUsesRustFieldNames() throws {
        let output = ReviewOutputEvent(
            findings: [finding(title: "Bug", body: "Details", confidenceScore: 0.75, priority: 1)],
            overallCorrectness: "patch is incorrect",
            overallExplanation: "The patch drops data.",
            overallConfidenceScore: 0.5
        )

        try XCTAssertJSONObjectEqual(output, [
            "findings": [[
                "title": "Bug",
                "body": "Details",
                "confidence_score": 0.75,
                "priority": 1,
                "code_location": [
                    "absolute_file_path": "/repo/File.swift",
                    "line_range": [
                        "start": 10,
                        "end": 12
                    ]
                ]
            ]],
            "overall_correctness": "patch is incorrect",
            "overall_explanation": "The patch drops data.",
            "overall_confidence_score": 0.5
        ])
    }

    func testReviewOutputDecodesWireShape() throws {
        let output = try JSONDecoder().decode(ReviewOutputEvent.self, from: Data("""
        {
          "findings": [{
            "title": "Leak",
            "body": "The file handle is not closed.",
            "confidence_score": 0.9,
            "priority": 0,
            "code_location": {
              "absolute_file_path": "/repo/File.swift",
              "line_range": { "start": 4, "end": 5 }
            }
          }],
          "overall_correctness": "patch is incorrect",
          "overall_explanation": "Needs a close call.",
          "overall_confidence_score": 0.8
        }
        """.utf8))

        XCTAssertEqual(output.findings.count, 1)
        XCTAssertEqual(output.findings[0].title, "Leak")
        XCTAssertEqual(output.findings[0].codeLocation.absoluteFilePath, "/repo/File.swift")
        XCTAssertEqual(output.findings[0].codeLocation.lineRange, ReviewLineRange(start: 4, end: 5))
        XCTAssertEqual(output.overallCorrectness, "patch is incorrect")
        XCTAssertEqual(output.overallExplanation, "Needs a close call.")
        XCTAssertEqual(output.overallConfidenceScore, 0.8, accuracy: 0.0001)
    }

    func testExitedReviewModeEventUsesReviewOutputKey() throws {
        try XCTAssertJSONObjectEqual(
            ExitedReviewModeEvent(reviewOutput: ReviewOutputEvent(overallExplanation: "Done")),
            [
                "review_output": [
                    "findings": [],
                    "overall_correctness": "",
                    "overall_explanation": "Done",
                    "overall_confidence_score": 0
                ]
            ]
        )
    }

    func testReviewDeliveryWireValues() throws {
        XCTAssertEqual(try JSONEncoder().encode(ReviewDelivery.inline), Data(#""inline""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(ReviewDelivery.detached), Data(#""detached""#.utf8))
    }

    func testFormatReviewFindingsBlockWithoutSelection() {
        let text = ReviewFormat.formatReviewFindingsBlock(findings: [
            finding(title: "First", body: "line one\nline two\n", start: 3, end: 4)
        ])

        XCTAssertEqual(
            text,
            "\nReview comment:\n\n- First — /repo/File.swift:3-4\n  line one\n  line two"
        )
    }

    func testFormatReviewFindingsBlockWithSelectionAndMissingFlagsDefaultSelected() {
        let text = ReviewFormat.formatReviewFindingsBlock(
            findings: [
                finding(title: "First", body: "alpha", path: "/repo/a.swift", start: 1, end: 1),
                finding(title: "Second", body: "beta\r\ngamma", path: "/repo/b.swift", start: 2, end: 4),
                finding(title: "Third", body: "", path: "/repo/c.swift", start: 5, end: 5)
            ],
            selection: [true, false]
        )

        XCTAssertEqual(
            text,
            "\nFull review comments:\n\n- [x] First — /repo/a.swift:1-1\n  alpha\n\n- [ ] Second — /repo/b.swift:2-4\n  beta\n  gamma\n\n- [x] Third — /repo/c.swift:5-5"
        )
    }

    func testRenderReviewOutputUsesExplanationAndFindings() {
        let output = ReviewOutputEvent(
            findings: [finding(title: "Bug", body: "body", start: 7, end: 8)],
            overallExplanation: "  Summary text. \n"
        )

        XCTAssertEqual(
            ReviewFormat.renderReviewOutputText(output),
            "Summary text.\n\nReview comment:\n\n- Bug — /repo/File.swift:7-8\n  body"
        )
    }

    func testRenderReviewOutputFallsBackWhenEmpty() {
        XCTAssertEqual(
            ReviewFormat.renderReviewOutputText(ReviewOutputEvent(overallExplanation: " \n\t ")),
            "Reviewer failed to output a response."
        )
    }

    private func finding(
        title: String = "Title",
        body: String = "Body",
        confidenceScore: Float = 0.5,
        priority: Int32 = 2,
        path: String = "/repo/File.swift",
        start: UInt32 = 10,
        end: UInt32 = 12
    ) -> ReviewFinding {
        ReviewFinding(
            title: title,
            body: body,
            confidenceScore: confidenceScore,
            priority: priority,
            codeLocation: ReviewCodeLocation(
                absoluteFilePath: path,
                lineRange: ReviewLineRange(start: start, end: end)
            )
        )
    }
}
