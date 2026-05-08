import CodexCore
import XCTest

final class TruncationTests: XCTestCase {
    func testSplitStringWorks() {
        XCTAssertEqual(
            Truncation.splitString("hello world", beginningBytes: 5, endBytes: 5).removedScalars,
            1
        )
        XCTAssertEqual(Truncation.splitString("hello world", beginningBytes: 5, endBytes: 5).prefix, "hello")
        XCTAssertEqual(Truncation.splitString("hello world", beginningBytes: 5, endBytes: 5).suffix, "world")

        let emptyBudgets = Truncation.splitString("abc", beginningBytes: 0, endBytes: 0)
        XCTAssertEqual(emptyBudgets.removedScalars, 3)
        XCTAssertEqual(emptyBudgets.prefix, "")
        XCTAssertEqual(emptyBudgets.suffix, "")
    }

    func testSplitStringHandlesEmptyString() {
        let split = Truncation.splitString("", beginningBytes: 4, endBytes: 4)

        XCTAssertEqual(split.removedScalars, 0)
        XCTAssertEqual(split.prefix, "")
        XCTAssertEqual(split.suffix, "")
    }

    func testSplitStringOnlyKeepsPrefixWhenTailBudgetIsZero() {
        let split = Truncation.splitString("abcdef", beginningBytes: 3, endBytes: 0)

        XCTAssertEqual(split.removedScalars, 3)
        XCTAssertEqual(split.prefix, "abc")
        XCTAssertEqual(split.suffix, "")
    }

    func testSplitStringOnlyKeepsSuffixWhenPrefixBudgetIsZero() {
        let split = Truncation.splitString("abcdef", beginningBytes: 0, endBytes: 3)

        XCTAssertEqual(split.removedScalars, 3)
        XCTAssertEqual(split.prefix, "")
        XCTAssertEqual(split.suffix, "def")
    }

    func testSplitStringHandlesOverlappingBudgetsWithoutRemoval() {
        let split = Truncation.splitString("abcdef", beginningBytes: 4, endBytes: 4)

        XCTAssertEqual(split.removedScalars, 0)
        XCTAssertEqual(split.prefix, "abcd")
        XCTAssertEqual(split.suffix, "ef")
    }

    func testSplitStringRespectsUTF8Boundaries() {
        let mixed = Truncation.splitString("😀abc😀", beginningBytes: 5, endBytes: 5)
        XCTAssertEqual(mixed.removedScalars, 1)
        XCTAssertEqual(mixed.prefix, "😀a")
        XCTAssertEqual(mixed.suffix, "c😀")

        let noBudget = Truncation.splitString("😀😀😀😀😀", beginningBytes: 1, endBytes: 1)
        XCTAssertEqual(noBudget.removedScalars, 5)
        XCTAssertEqual(noBudget.prefix, "")
        XCTAssertEqual(noBudget.suffix, "")

        let smallBudget = Truncation.splitString("😀😀😀😀😀", beginningBytes: 7, endBytes: 7)
        XCTAssertEqual(smallBudget.removedScalars, 3)
        XCTAssertEqual(smallBudget.prefix, "😀")
        XCTAssertEqual(smallBudget.suffix, "😀")

        let exactScalarBudgets = Truncation.splitString("😀😀😀😀😀", beginningBytes: 8, endBytes: 8)
        XCTAssertEqual(exactScalarBudgets.removedScalars, 1)
        XCTAssertEqual(exactScalarBudgets.prefix, "😀😀")
        XCTAssertEqual(exactScalarBudgets.suffix, "😀😀")
    }

    func testTruncateBytesLessThanPlaceholderReturnsPlaceholder() {
        XCTAssertEqual(
            Truncation.formattedTruncateText("example output", policy: .bytes(1)),
            "Total output lines: 1\n\n…13 chars truncated…t"
        )
    }

    func testTruncateTokensLessThanPlaceholderReturnsPlaceholder() {
        XCTAssertEqual(
            Truncation.formattedTruncateText("example output", policy: .tokens(1)),
            "Total output lines: 1\n\nex…3 tokens truncated…ut"
        )
    }

    func testUnderLimitReturnsOriginal() {
        let content = "example output"

        XCTAssertEqual(Truncation.formattedTruncateText(content, policy: .tokens(10)), content)
        XCTAssertEqual(Truncation.formattedTruncateText(content, policy: .bytes(20)), content)
    }

    func testOverLimitReturnsTruncated() {
        let content = "this is an example of a long output that should be truncated"

        XCTAssertEqual(
            Truncation.formattedTruncateText(content, policy: .tokens(5)),
            "Total output lines: 1\n\nthis is an…10 tokens truncated… truncated"
        )
        XCTAssertEqual(
            Truncation.formattedTruncateText(content, policy: .bytes(30)),
            "Total output lines: 1\n\nthis is an exam…30 chars truncated…ld be truncated"
        )
    }

    func testOriginalLineCountIsReportedWhenTruncated() {
        let content = "this is an example of a long output that should be truncated\nalso some other line"

        XCTAssertEqual(
            Truncation.formattedTruncateText(content, policy: .bytes(30)),
            "Total output lines: 2\n\nthis is an exam…51 chars truncated…some other line"
        )
        XCTAssertEqual(
            Truncation.formattedTruncateText(content, policy: .tokens(10)),
            "Total output lines: 2\n\nthis is an example o…11 tokens truncated…also some other line"
        )
    }

    func testTruncateWithTokenBudgetReturnsOriginalWhenUnderLimit() {
        let output = Truncation.truncateWithTokenBudget("short output", policy: .tokens(100))

        XCTAssertEqual(output.text, "short output")
        XCTAssertNil(output.originalTokenCount)
    }

    func testTruncateWithTokenBudgetReportsTruncationAtZeroLimit() {
        let output = Truncation.truncateWithTokenBudget("abcdef", policy: .tokens(0))

        XCTAssertEqual(output.text, "…2 tokens truncated…")
        XCTAssertEqual(output.originalTokenCount, 2)
    }

    func testTruncateMiddleTokensHandlesUTF8Content() {
        let text = "😀😀😀😀😀😀😀😀😀😀\nsecond line with text\n"
        let output = Truncation.truncateWithTokenBudget(text, policy: .tokens(8))

        XCTAssertEqual(output.text, "😀😀😀😀…8 tokens truncated… line with text\n")
        XCTAssertEqual(output.originalTokenCount, 16)
    }

    func testTruncateMiddleBytesHandlesUTF8Content() {
        let text = "😀😀😀😀😀😀😀😀😀😀\nsecond line with text\n"

        XCTAssertEqual(
            Truncation.truncateText(text, policy: .bytes(20)),
            "😀😀…21 chars truncated…with text\n"
        )
    }

    func testTruncatesAcrossMultipleUnderLimitTextsAndReportsOmitted() {
        let chunk = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega.\n"
        let chunkTokens = Truncation.approxTokenCount(chunk)
        XCTAssertGreaterThan(chunkTokens, 0)
        let limit = chunkTokens * 3
        let t1 = chunk
        let t2 = chunk
        let t3 = String(repeating: chunk, count: 10)
        let t4 = chunk
        let t5 = chunk

        let items: [FunctionCallOutputContentItem] = [
            .inputText(text: t1),
            .inputText(text: t2),
            .inputImage(imageURL: "img:mid"),
            .inputText(text: t3),
            .inputText(text: t4),
            .inputText(text: t5)
        ]

        let output = Truncation.truncateFunctionOutputItems(items, policy: .tokens(limit))

        XCTAssertEqual(output.count, 5)
        XCTAssertEqual(output[0], .inputText(text: t1))
        XCTAssertEqual(output[1], .inputText(text: t2))
        XCTAssertEqual(output[2], .inputImage(imageURL: "img:mid"))

        guard case let .inputText(fourthText) = output[3] else {
            return XCTFail("Expected fourth item to be truncated text")
        }
        XCTAssertTrue(fourthText.contains("tokens truncated"), "expected marker in \(fourthText)")

        guard case let .inputText(summaryText) = output[4] else {
            return XCTFail("Expected summary item")
        }
        XCTAssertTrue(summaryText.contains("omitted 2 text items"))
    }

    func testPolicyMultiplierAndBudgetsMatchRustHeuristic() {
        XCTAssertEqual(TruncationPolicy.bytes(3).multiplied(by: 1.5), .bytes(5))
        XCTAssertEqual(TruncationPolicy.tokens(3).multiplied(by: 1.5), .tokens(5))
        XCTAssertEqual(TruncationPolicy.bytes(9).tokenBudget, 3)
        XCTAssertEqual(TruncationPolicy.tokens(9).byteBudget, 36)
    }
}
