import CodexCore
import XCTest

final class AnsiEscapeTests: XCTestCase {
    func testEscapeLineStripsEscapeSequences() {
        let line = AnsiEscape.ansiEscapeLine("\u{1B}[31mRED\u{1B}[0m")

        XCTAssertEqual(line.plainText, "RED")
        XCTAssertEqual(line.spans.map(\.text), ["RED"])
        XCTAssertFalse(line.plainText.contains("\u{1B}"))
    }

    func testEscapeLineExpandsTabs() {
        let line = AnsiEscape.ansiEscapeLine("1\tcontent")

        XCTAssertEqual(line.plainText, "1    content")
    }

    func testAnsiEscapeDoesNotExpandTabs() {
        let text = AnsiEscape.ansiEscape("1\tcontent")

        XCTAssertEqual(text.plainText, "1\tcontent")
    }

    func testEscapeLineReturnsFirstLineOnly() {
        let line = AnsiEscape.ansiEscapeLine("first\nsecond")

        XCTAssertEqual(line.plainText, "first")
    }

    func testAnsiEscapeSplitsLinesAndCarriesStyle() {
        let text = AnsiEscape.ansiEscape("\u{1B}[31mred\nstill red\u{1B}[0m")

        XCTAssertEqual(text.lines.map(\.plainText), ["red", "still red"])
        XCTAssertEqual(text.lines[0].spans.first?.style.foreground, .red)
        XCTAssertEqual(text.lines[1].spans.first?.style.foreground, .red)
    }

    func testAnsiEscapeResetsForegroundAndModifiers() {
        let text = AnsiEscape.ansiEscape("a\u{1B}[1;32mbold green\u{1B}[22;39mplain")

        XCTAssertEqual(text.lines.count, 1)
        XCTAssertEqual(text.lines[0].spans.map(\.text), ["a", "bold green", "plain"])
        XCTAssertEqual(text.lines[0].spans[1].style.foreground, .green)
        XCTAssertTrue(text.lines[0].spans[1].style.modifiers.contains(.bold))
        XCTAssertEqual(text.lines[0].spans[2].style, .default)
    }

    func testAnsiEscapeParsesExtendedColorsAndBackground() {
        let text = AnsiEscape.ansiEscape("\u{1B}[38;5;196;48;2;1;2;3mcolor")

        XCTAssertEqual(text.lines.first?.spans.first?.style.foreground, .indexed(196))
        XCTAssertEqual(text.lines.first?.spans.first?.style.background, .rgb(red: 1, green: 2, blue: 3))
    }

    func testAnsiEscapeDropsNonSgrControlSequences() {
        let text = AnsiEscape.ansiEscape("a\u{1B}[2Kb\u{1B}]0;title\u{7}c")

        XCTAssertEqual(text.plainText, "abc")
    }

    func testAnsiEscapeDropsTrailingLineBreakLikeRustLines() {
        let text = AnsiEscape.ansiEscape("a\n")

        XCTAssertEqual(text.lines.map(\.plainText), ["a"])
    }

    func testAnsiEscapePreservesIntermediateEmptyLine() {
        let text = AnsiEscape.ansiEscape("a\n\nb")

        XCTAssertEqual(text.lines.map(\.plainText), ["a", "", "b"])
    }
}
