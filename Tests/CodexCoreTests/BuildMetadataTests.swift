import CodexCore
import XCTest

final class BuildMetadataTests: XCTestCase {
    func testBuildMetadataVersionIsGenerated() {
        XCTAssertFalse(CodexBuildMetadata.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotEqual(CodexBuildMetadata.version, "0.0.0")
        XCTAssertFalse(CodexBuildMetadata.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testVersionedCoreDefaultsUseBuildMetadata() {
        XCTAssertEqual(
            ConfigLockfile.current(config: .table([:])).codexVersion,
            CodexBuildMetadata.version
        )
        XCTAssertEqual(
            ModelProviderInfo.createOpenAIProvider(environment: [:]).httpHeaders?["version"],
            CodexBuildMetadata.version
        )
    }
}
