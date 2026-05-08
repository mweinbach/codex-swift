import CodexCore
import Foundation
import XCTest

final class NumberFormatTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    func testSIFormattingMatchesRustCases() {
        let cases: [(Int64, String)] = [
            (0, "0"),
            (999, "999"),
            (1_000, "1.00K"),
            (1_200, "1.20K"),
            (10_000, "10.0K"),
            (100_000, "100K"),
            (999_500, "1.00M"),
            (1_000_000, "1.00M"),
            (1_234_000, "1.23M"),
            (12_345_678, "12.3M"),
            (999_950_000, "1.00G"),
            (1_000_000_000, "1.00G"),
            (1_234_000_000, "1.23G"),
            (1_234_000_000_000, "1,234G")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(NumberFormat.formatSISuffix(input, locale: enUS), expected, "input \(input)")
        }
    }

    func testNegativeSIFormattingClampsToZero() {
        XCTAssertEqual(NumberFormat.formatSISuffix(-42, locale: enUS), "0")
    }
}
