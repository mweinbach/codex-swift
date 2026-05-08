import CodexCore
import XCTest

final class ConfigOverrideTests: XCTestCase {
    func testParseBasicTomlScalars() throws {
        XCTAssertEqual(try ConfigValueParser.parseTomlLiteral("42"), .integer(42))
        XCTAssertEqual(try ConfigValueParser.parseTomlLiteral("true"), .bool(true))
        XCTAssertEqual(try ConfigValueParser.parseTomlLiteral("\"o3\""), .string("o3"))
    }

    func testUnquotedStringFallsBackToStringInOverrideParser() throws {
        let overrides = CliConfigOverrides(rawOverrides: ["model=o3"])
        XCTAssertEqual(try overrides.parseOverrides().first?.1, .string("o3"))
    }

    func testOnlySplitsOnFirstEquals() throws {
        let overrides = CliConfigOverrides(rawOverrides: ["env.VALUE=a=b=c"])
        XCTAssertEqual(try overrides.parseOverrides().first?.0, "env.VALUE")
        XCTAssertEqual(try overrides.parseOverrides().first?.1, .string("a=b=c"))
    }

    func testParsesArraysAndInlineTables() throws {
        XCTAssertEqual(
            try ConfigValueParser.parseTomlLiteral("[1, 2, \"three\"]"),
            .array([.integer(1), .integer(2), .string("three")])
        )
        XCTAssertEqual(
            try ConfigValueParser.parseTomlLiteral("{a = 1, b = false}"),
            .table(["a": .integer(1), "b": .bool(false)])
        )
    }

    func testApplyOverrideCreatesIntermediateTables() throws {
        let overrides = CliConfigOverrides(rawOverrides: [
            "features.web_search_request=true",
            "model=\"o3\""
        ])
        let applied = try overrides.applying()
        XCTAssertEqual(
            applied,
            .table([
                "features": .table(["web_search_request": .bool(true)]),
                "model": .string("o3")
            ])
        )
    }

    func testInvalidOverrideErrors() {
        XCTAssertThrowsError(try CliConfigOverrides(rawOverrides: ["missing"]).parseOverrides())
        XCTAssertThrowsError(try CliConfigOverrides(rawOverrides: ["=value"]).parseOverrides())
    }
}
