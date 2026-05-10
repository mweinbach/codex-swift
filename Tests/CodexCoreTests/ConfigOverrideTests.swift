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

    func testApplyOverrideReplacesNonTableIntermediates() throws {
        let overrides = CliConfigOverrides(rawOverrides: [
            "profile.name=\"work\""
        ])

        XCTAssertEqual(
            try overrides.applying(to: .table(["profile": .string("old")])),
            .table(["profile": .table(["name": .string("work")])])
        )
    }

    func testMergeTomlValuesRecursesIntoTablesAndKeepsBaseValues() {
        let base = ConfigValue.table([
            "model": .string("o3"),
            "features": .table([
                "web_search_request": .bool(false),
                "agents": .bool(true)
            ])
        ])
        let overlay = ConfigValue.table([
            "features": .table([
                "web_search_request": .bool(true)
            ]),
            "profile": .string("work")
        ])

        XCTAssertEqual(
            base.merging(overlay: overlay),
            .table([
                "model": .string("o3"),
                "features": .table([
                    "web_search_request": .bool(true),
                    "agents": .bool(true)
                ]),
                "profile": .string("work")
            ])
        )
    }

    func testMergeTomlValuesReplacesNonTables() {
        XCTAssertEqual(
            ConfigValue.string("old").merging(overlay: .table(["model": .string("o3")])),
            .table(["model": .string("o3")])
        )
        XCTAssertEqual(
            ConfigValue.table(["profile": .string("work")]).merging(overlay: .string("replace")),
            .string("replace")
        )
        XCTAssertEqual(
            ConfigValue.table(["profile": .string("work")]).merging(overlay: .table(["profile": .bool(true)])),
            .table(["profile": .bool(true)])
        )
    }

    func testPluginConfigEditorSetEnabledPreservesExistingFields() {
        var config = ConfigValue.table([
            "plugins": .table([
                "demo@market": .table([
                    "enabled": .bool(false),
                    "source": .string("/tmp/plugin")
                ])
            ])
        ])

        PluginConfigEditor.setEnabled(id: "demo@market", enabled: true, in: &config)

        XCTAssertEqual(
            config,
            .table([
                "plugins": .table([
                    "demo@market": .table([
                        "enabled": .bool(true),
                        "source": .string("/tmp/plugin")
                    ])
                ])
            ])
        )
    }

    func testPluginConfigEditorSetEnabledCreatesPluginEntry() {
        var config = ConfigValue.table([:])

        PluginConfigEditor.setEnabled(id: "demo@market", enabled: true, in: &config)

        XCTAssertEqual(
            config,
            .table([
                "plugins": .table([
                    "demo@market": .table(["enabled": .bool(true)])
                ])
            ])
        )
    }

    func testPluginConfigEditorClearRemovesEmptyPluginsTable() {
        var config = ConfigValue.table([
            "plugins": .table([
                "demo@market": .table(["enabled": .bool(true)])
            ])
        ])

        XCTAssertTrue(PluginConfigEditor.clear(id: "demo@market", from: &config))

        XCTAssertEqual(config, .table([:]))
    }

    func testPluginConfigEditorClearMissingEntryDoesNotMutateConfig() {
        var config = ConfigValue.table([:])

        XCTAssertFalse(PluginConfigEditor.clear(id: "demo@market", from: &config))

        XCTAssertEqual(config, .table([:]))
    }

    func testInvalidOverrideErrors() {
        XCTAssertThrowsError(try CliConfigOverrides(rawOverrides: ["missing"]).parseOverrides())
        XCTAssertThrowsError(try CliConfigOverrides(rawOverrides: ["=value"]).parseOverrides())
    }
}
