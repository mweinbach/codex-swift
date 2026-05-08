import CodexCore
import XCTest

final class FeatureTogglesTests: XCTestCase {
    func testFeatureRegistryMatchesRustListOrderStagesAndDefaults() {
        XCTAssertEqual(FeatureRegistry.specs.map(\.key), [
            "undo",
            "parallel",
            "view_image_tool",
            "shell_tool",
            "warnings",
            "web_search_request",
            "unified_exec",
            "shell_snapshot",
            "apply_patch_freeform",
            "computer_use_gui",
            "exec_policy",
            "experimental_windows_sandbox",
            "elevated_windows_sandbox",
            "remote_compaction",
            "remote_models",
            "skills",
            "powershell_utf8",
            "tool_search",
            "tui2"
        ])
        XCTAssertEqual(FeatureRegistry.specs.map(\.stage.listName), [
            "stable",
            "stable",
            "stable",
            "stable",
            "stable",
            "stable",
            "beta",
            "beta",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "experimental",
            "stable",
            "experimental"
        ])
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.parallel))
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.execPolicy))
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.toolSearch))
        XCTAssertFalse(FeatureStates.withDefaults().isEnabled(.webSearchRequest))
    }

    func testFeatureTogglesBecomeConfigOverrides() throws {
        let toggles = FeatureToggles(enable: ["web_search_request"], disable: ["unified_exec"])
        XCTAssertEqual(
            try toggles.toOverrides(),
            [
                "features.web_search_request=true",
                "features.unified_exec=false"
            ]
        )
    }

    func testLegacyFeatureAliasesAreKnown() throws {
        let toggles = FeatureToggles(enable: ["experimental_use_unified_exec_tool"])
        XCTAssertEqual(try toggles.toOverrides(), ["features.experimental_use_unified_exec_tool=true"])
    }

    func testUnknownFeatureThrows() {
        XCTAssertThrowsError(try FeatureToggles(enable: ["definitely_not_real"]).toOverrides())
    }
}
