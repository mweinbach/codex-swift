import CodexCore
import XCTest

final class FeatureTogglesTests: XCTestCase {
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
