import CodexCore
import XCTest

final class StringByteBoundaryTests: XCTestCase {
    func testPrefixWithinBudgetReturnsOriginal() {
        XCTAssertEqual(StringByteBoundary.takeBytesAtUnicodeScalarBoundary("hello", maxBytes: 5), "hello")
    }

    func testPrefixStopsBeforeMultiByteScalar() {
        XCTAssertEqual(StringByteBoundary.takeBytesAtUnicodeScalarBoundary("aéb", maxBytes: 2), "a")
        XCTAssertEqual(StringByteBoundary.takeBytesAtUnicodeScalarBoundary("aéb", maxBytes: 3), "aé")
    }

    func testSuffixStopsBeforeMultiByteScalar() {
        XCTAssertEqual(StringByteBoundary.takeLastBytesAtUnicodeScalarBoundary("aéb", maxBytes: 2), "b")
        XCTAssertEqual(StringByteBoundary.takeLastBytesAtUnicodeScalarBoundary("aéb", maxBytes: 3), "éb")
    }

    func testNegativeBudgetReturnsEmptyString() {
        XCTAssertEqual(StringByteBoundary.takeBytesAtUnicodeScalarBoundary("hello", maxBytes: -1), "")
        XCTAssertEqual(StringByteBoundary.takeLastBytesAtUnicodeScalarBoundary("hello", maxBytes: -1), "")
    }
}
