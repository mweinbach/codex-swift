import XCTest
@testable import CodexCore

final class CodeModeTests: XCTestCase {
    func testParseExecSourceWithoutPragma() {
        XCTAssertEqual(
            CodeMode.parseExecSource("text('hi')").successValue,
            ParsedExecSource(code: "text('hi')")
        )
    }

    func testParseExecSourceWithPragma() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 10}\ntext('hi')").successValue,
            ParsedExecSource(code: "text('hi')", yieldTimeMS: 10)
        )
    }

    func testParseExecSourceAllowsEmptyPragmaObject() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {}\ntext('hi')").successValue,
            ParsedExecSource(code: "text('hi')")
        )
    }

    func testParseExecSourceRejectsEmptyInput() {
        XCTAssertEqual(
            CodeMode.parseExecSource(" \n\t").failureValue,
            "exec expects raw JavaScript source text (non-empty). Provide JS only, optionally with first-line `// @exec: {\"yield_time_ms\": 10000, \"max_output_tokens\": 1000}`."
        )
    }

    func testParseExecSourceRejectsPragmaWithoutCode() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 10}\n   ").failureValue,
            "exec pragma must be followed by JavaScript source on subsequent lines"
        )
    }

    func testParseExecSourceRejectsUnsupportedPragmaFields() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"foo\": 1}\ntext('hi')").failureValue,
            "exec pragma only supports `yield_time_ms` and `max_output_tokens`; got `foo`"
        )
    }

    func testParseExecSourceRejectsUnsafeIntegers() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 9007199254740992}\ntext('hi')").failureValue,
            "exec pragma field `yield_time_ms` must be a non-negative safe integer"
        )
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"max_output_tokens\": -1}\ntext('hi')").failureValue,
            "exec pragma field `max_output_tokens` must be a non-negative safe integer"
        )
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": true}\ntext('hi')").failureValue,
            "exec pragma field `yield_time_ms` must be a non-negative safe integer"
        )
    }

    func testNormalizeIdentifierRewritesInvalidCharacters() {
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("mcp__ologs__get_profile"),
            "mcp__ologs__get_profile"
        )
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("hidden-dynamic-tool"),
            "hidden_dynamic_tool"
        )
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("123 abc"),
            "_23_abc"
        )
        XCTAssertEqual(CodeMode.normalizeCodeModeIdentifier(""), "_")
    }

    func testIsCodeModeNestedToolSkipsPublicTools() {
        XCTAssertFalse(CodeMode.isCodeModeNestedTool("exec"))
        XCTAssertFalse(CodeMode.isCodeModeNestedTool("wait"))
        XCTAssertTrue(CodeMode.isCodeModeNestedTool("mcp__server__tool"))
    }
}

private extension Result where Success == ParsedExecSource, Failure == CodeModeParseError {
    var successValue: ParsedExecSource? {
        guard case let .success(value) = self else {
            return nil
        }
        return value
    }

    var failureValue: String? {
        guard case let .failure(value) = self else {
            return nil
        }
        return value.description
    }
}
