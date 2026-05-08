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

    func testVersionParserTrimsPrefixAndBuildMetadataLikeRustSemver() {
        XCTAssertEqual(OllamaHelpers.parseVersion("0.13.4"), OllamaVersion(major: 0, minor: 13, patch: 4))
        XCTAssertEqual(
            OllamaHelpers.parseVersion(" v0.14.0+build.5 "),
            OllamaVersion(major: 0, minor: 14, patch: 0, buildMetadata: "build.5")
        )
        XCTAssertEqual(
            OllamaHelpers.parseVersion("0.13.4-rc.1"),
            OllamaVersion(major: 0, minor: 13, patch: 4, prerelease: "rc.1")
        )
        XCTAssertNil(OllamaHelpers.parseVersion("0.13"))
        XCTAssertNil(OllamaHelpers.parseVersion("not-a-version"))
        XCTAssertNil(OllamaHelpers.parseVersion("0.13.4-"))
        XCTAssertNil(OllamaHelpers.parseVersion("0.13.4+"))
        XCTAssertNil(OllamaHelpers.parseVersion("0.13.4-01"))
    }

    func testVersionDescriptionPreservesBuildMetadataLikeRustSemver() {
        XCTAssertEqual(
            OllamaVersion(major: 0, minor: 13, patch: 3, prerelease: "rc.1", buildMetadata: "build.5").description,
            "0.13.3-rc.1+build.5"
        )
    }

    func testSupportsResponsesVersionGateMatchesRust() {
        XCTAssertTrue(OllamaHelpers.supportsResponses(version: OllamaVersion(major: 0, minor: 0, patch: 0)))
        XCTAssertFalse(OllamaHelpers.supportsResponses(version: OllamaVersion(major: 0, minor: 13, patch: 3)))
        XCTAssertFalse(OllamaHelpers.supportsResponses(version: OllamaVersion(major: 0, minor: 13, patch: 4, prerelease: "rc.1")))
        XCTAssertTrue(OllamaHelpers.supportsResponses(version: OllamaVersion(major: 0, minor: 13, patch: 4)))
        XCTAssertTrue(OllamaHelpers.supportsResponses(version: OllamaVersion(major: 0, minor: 14, patch: 0)))
    }

    func testSupportsResponsesVersionStringReturnsNilForUnparsableVersion() {
        XCTAssertEqual(OllamaHelpers.supportsResponses(versionString: "v0.13.4"), true)
        XCTAssertEqual(OllamaHelpers.supportsResponses(versionString: "0.13.3"), false)
        XCTAssertNil(OllamaHelpers.supportsResponses(versionString: "dev"))
    }

    func testUnsupportedResponsesVersionMessageMatchesRust() {
        XCTAssertEqual(
            OllamaHelpers.unsupportedResponsesVersionMessage(for: OllamaVersion(major: 0, minor: 13, patch: 3)),
            "Ollama 0.13.3 is too old. Codex requires Ollama 0.13.4 or newer."
        )
    }
}
