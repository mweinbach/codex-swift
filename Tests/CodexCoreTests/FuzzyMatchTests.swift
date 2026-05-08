import CodexCore
import XCTest

final class FuzzyMatchTests: XCTestCase {
    func testASCIIBasicIndices() throws {
        let result = try XCTUnwrap(FuzzyMatcher.match(haystack: "hello", needle: "hl"))
        XCTAssertEqual(result.indices, [0, 2])
        XCTAssertEqual(result.score, -99)
    }

    func testUnicodeDottedIstanbulHighlighting() throws {
        let result = try XCTUnwrap(FuzzyMatcher.match(haystack: "İstanbul", needle: "is"))
        XCTAssertEqual(result.indices, [0, 1])
        XCTAssertEqual(result.score, -99)
    }

    func testUnicodeGermanSharpSCasefold() {
        XCTAssertNil(FuzzyMatcher.match(haystack: "straße", needle: "strasse"))
    }

    func testPreferContiguousMatchOverSpread() throws {
        let contiguous = try XCTUnwrap(FuzzyMatcher.match(haystack: "abc", needle: "abc"))
        let spread = try XCTUnwrap(FuzzyMatcher.match(haystack: "a-b-c", needle: "abc"))
        XCTAssertEqual(contiguous.score, -100)
        XCTAssertEqual(spread.score, -98)
        XCTAssertLessThan(contiguous.score, spread.score)
    }

    func testStartOfStringBonusApplies() throws {
        let prefix = try XCTUnwrap(FuzzyMatcher.match(haystack: "file_name", needle: "file"))
        let infix = try XCTUnwrap(FuzzyMatcher.match(haystack: "my_file_name", needle: "file"))
        XCTAssertEqual(prefix.score, -100)
        XCTAssertEqual(infix.score, 0)
        XCTAssertLessThan(prefix.score, infix.score)
    }

    func testEmptyNeedleMatchesWithMaxScoreAndNoIndices() throws {
        let result = try XCTUnwrap(FuzzyMatcher.match(haystack: "anything", needle: ""))
        XCTAssertTrue(result.indices.isEmpty)
        XCTAssertEqual(result.score, Int32.max)
    }

    func testCaseInsensitiveMatchingBasic() throws {
        let result = try XCTUnwrap(FuzzyMatcher.match(haystack: "FooBar", needle: "foO"))
        XCTAssertEqual(result.indices, [0, 1, 2])
        XCTAssertEqual(result.score, -100)
    }

    func testIndicesAreDedupedForMultiScalarLowercaseExpansion() throws {
        let needle = "\u{0069}\u{0307}"
        let result = try XCTUnwrap(FuzzyMatcher.match(haystack: "İ", needle: needle))
        XCTAssertEqual(result.indices, [0])
        XCTAssertEqual(result.score, -100)
    }
}
