@testable import CodexCore
import XCTest

final class OllamaHelpersTests: XCTestCase {
    func testBaseURLToHostRootStripsOpenAICompatibleSuffixLikeRust() {
        XCTAssertTrue(OllamaHelpers.isOpenAICompatibleBaseURL("http://localhost:11434/v1"))
        XCTAssertTrue(OllamaHelpers.isOpenAICompatibleBaseURL("http://localhost:11434/v1/"))
        XCTAssertFalse(OllamaHelpers.isOpenAICompatibleBaseURL("http://localhost:11434/v10"))

        XCTAssertEqual(
            OllamaHelpers.baseURLToHostRoot("http://localhost:11434/v1"),
            "http://localhost:11434"
        )
        XCTAssertEqual(
            OllamaHelpers.baseURLToHostRoot("http://localhost:11434"),
            "http://localhost:11434"
        )
        XCTAssertEqual(
            OllamaHelpers.baseURLToHostRoot("http://localhost:11434/"),
            "http://localhost:11434"
        )
        XCTAssertEqual(
            OllamaHelpers.baseURLToHostRoot("http://localhost:11434/v1///"),
            "http://localhost:11434"
        )
    }

    func testPullEventsDecoderStatusAndSuccessMatchesRustParser() throws {
        XCTAssertEqual(
            try OllamaHelpers.pullEvents(fromJSONData: Data(#"{"status":"verifying"}"#.utf8)),
            [.status("verifying")]
        )

        XCTAssertEqual(
            try OllamaHelpers.pullEvents(fromJSONData: Data(#"{"status":"success"}"#.utf8)),
            [.status("success"), .success]
        )
    }

    func testPullEventsDecoderProgressMatchesRustParser() throws {
        XCTAssertEqual(
            try OllamaHelpers.pullEvents(fromJSONData: Data(#"{"digest":"sha256:abc","total":100}"#.utf8)),
            [.chunkProgress(digest: "sha256:abc", total: 100, completed: nil)]
        )

        XCTAssertEqual(
            try OllamaHelpers.pullEvents(fromJSONData: Data(#"{"digest":"sha256:def","completed":42}"#.utf8)),
            [.chunkProgress(digest: "sha256:def", total: nil, completed: 42)]
        )
    }

    func testPullEventsDefaultsMissingDigestToEmptyString() throws {
        XCTAssertEqual(
            try OllamaHelpers.pullEvents(fromJSONData: Data(#"{"total":100,"completed":25}"#.utf8)),
            [.chunkProgress(digest: "", total: 100, completed: 25)]
        )
    }

    func testPullEventsCanEmitStatusAndProgressFromOneUpdate() {
        XCTAssertEqual(
            OllamaHelpers.pullEvents(from: OllamaPullUpdate(
                status: "pulling layer",
                digest: "sha256:abc",
                total: 100,
                completed: 50
            )),
            [
                .status("pulling layer"),
                .chunkProgress(digest: "sha256:abc", total: 100, completed: 50)
            ]
        )
    }
}
