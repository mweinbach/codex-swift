import XCTest
@testable import CodexCore

final class FlagsTests: XCTestCase {
    func testSSEFixtureFlagReadsEnvironmentValue() {
        XCTAssertEqual(
            CodexEnvironmentFlags.sseFixturePath(environment: [
                "CODEX_RS_SSE_FIXTURE": "/tmp/fixture.jsonl"
            ]),
            "/tmp/fixture.jsonl"
        )
    }

    func testSSEFixtureFlagDefaultsToNilWhenUnset() {
        XCTAssertNil(CodexEnvironmentFlags.sseFixturePath(environment: [:]))
    }
}
