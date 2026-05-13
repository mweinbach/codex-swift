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

    func testPullEventsFromJSONObjectMatchesRustParser() {
        XCTAssertEqual(
            OllamaHelpers.pullEvents(fromJSONObject: [
                "status": "downloading",
                "digest": "sha256:abc",
                "total": NSNumber(value: 100),
                "completed": NSNumber(value: 25)
            ]),
            [
                .status("downloading"),
                .chunkProgress(digest: "sha256:abc", total: 100, completed: 25)
            ]
        )
    }

    func testCLIProgressReporterFiltersManifestPadsStatusAndFinishesLikeRust() throws {
        var output = ""
        var reporter = OllamaCLIProgressReporter(
            now: { 0 },
            write: { output += $0 }
        )
        let longStatus = "downloading layer"
        let shortStatus = "done"

        try reporter.onEvent(.status(longStatus))
        try reporter.onEvent(.status("pulling manifest"))
        try reporter.onEvent(.status(shortStatus))
        try reporter.onEvent(.success)

        XCTAssertEqual(
            output,
            "\r\(longStatus)\r\(shortStatus)\(String(repeating: " ", count: longStatus.count - shortStatus.count))\n"
        )
    }

    func testCLIProgressReporterFormatsProgressLikeRust() throws {
        var currentTime = 0.0
        var output = ""
        var reporter = OllamaCLIProgressReporter(
            now: { currentTime },
            write: { output += $0 }
        )
        let gibibyte = UInt64(1024 * 1024 * 1024)

        currentTime = 2.0
        try reporter.onEvent(.chunkProgress(
            digest: "sha256:first",
            total: gibibyte,
            completed: gibibyte / 4
        ))
        currentTime = 3.0
        try reporter.onEvent(.chunkProgress(
            digest: "sha256:second",
            total: gibibyte,
            completed: gibibyte / 2
        ))

        XCTAssertEqual(
            output,
            "\r\u{1B}[2KDownloading model: total 1.00 GB\n"
                + "\r0.25/1.00 GB (25.0%) 128.0 MB/s"
                + "\r0.75/2.00 GB (37.5%) 512.0 MB/s"
        )
    }

    func testCLIProgressReporterIgnoresErrorsAndProgressWithoutTotalsLikeRust() throws {
        var output = ""
        var reporter = OllamaCLIProgressReporter(
            now: { 0 },
            write: { output += $0 }
        )

        try reporter.onEvent(.chunkProgress(digest: "sha256:first", total: nil, completed: 10))
        try reporter.onEvent(.error("pull failed"))

        XCTAssertEqual(output, "")
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

    func testClientProbeUsesOpenAICompatibleModelsEndpointLikeRust() async throws {
        var requestedPaths: [String] = []
        let provider = ModelProviderInfo.createOSSProvider(baseURL: "http://ollama.example/v1", wireAPI: .responses)

        _ = try await OllamaClient.tryFromProvider(provider) { request in
            requestedPaths.append(try XCTUnwrap(request.url?.path))
            return OllamaHTTPResponse(statusCode: 200)
        }

        XCTAssertEqual(requestedPaths, ["/v1/models"])
    }

    func testClientProbeUsesNativeTagsEndpointLikeRust() async throws {
        var requestedPaths: [String] = []
        let provider = ModelProviderInfo.createOSSProvider(baseURL: "http://ollama.example", wireAPI: .chat)

        _ = try await OllamaClient.tryFromProvider(provider) { request in
            requestedPaths.append(try XCTUnwrap(request.url?.path))
            return OllamaHTTPResponse(statusCode: 200)
        }

        XCTAssertEqual(requestedPaths, ["/api/tags"])
    }

    func testClientProbeFailureUsesRustConnectionErrorMessage() async throws {
        let provider = ModelProviderInfo.createOSSProvider(baseURL: "http://ollama.example/v1", wireAPI: .responses)

        do {
            _ = try await OllamaClient.tryFromProvider(provider) { _ in
                OllamaHTTPResponse(statusCode: 503)
            }
            XCTFail("expected probe failure")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .connectionUnavailable)
            XCTAssertEqual(String(describing: error), OllamaHelpers.connectionErrorMessage)
        }
    }

    func testClientFetchModelsParsesNamesAndTreatsHTTPFailureAsEmptyLikeRust() async throws {
        let client = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return OllamaHTTPResponse(
                statusCode: 200,
                data: Data(#"{"models":[{"name":"gpt-oss:20b"},{"digest":"sha256:abc"},{"name":"llama3"}]}"#.utf8)
            )
        }
        let models = try await client.fetchModels()
        XCTAssertEqual(models, ["gpt-oss:20b", "llama3"])

        let failingClient = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 500)
        }
        let failingModels = try await failingClient.fetchModels()
        XCTAssertEqual(failingModels, [])
    }

    func testClientFetchVersionParsesVersionAndReturnsNilForMissingOrUnparseableLikeRust() async throws {
        let client = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { request in
            XCTAssertEqual(request.url?.path, "/api/version")
            return OllamaHTTPResponse(statusCode: 200, data: Data(#"{"version":" v0.14.1 "}"#.utf8))
        }
        let version = try await client.fetchVersion()
        XCTAssertEqual(version, OllamaVersion(major: 0, minor: 14, patch: 1))

        let missingClient = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
        }
        let missingVersion = try await missingClient.fetchVersion()
        XCTAssertNil(missingVersion)

        let unparseableClient = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 200, data: Data(#"{"version":"dev"}"#.utf8))
        }
        let unparseableVersion = try await unparseableClient.fetchVersion()
        XCTAssertNil(unparseableVersion)
    }

    func testEnsureResponsesSupportedAllowsMissingVersionAndRejectsTooOldVersionLikeRust() async throws {
        let provider = ModelProviderInfo.createOSSProvider(baseURL: "http://ollama.example/v1", wireAPI: .responses)

        do {
            try await OllamaClient.ensureResponsesSupported(provider: provider) { request in
                if request.url?.path == "/v1/models" {
                    return OllamaHTTPResponse(statusCode: 200)
                }
                return OllamaHTTPResponse(statusCode: 200, data: Data(#"{"version":"0.13.3"}"#.utf8))
            }
            XCTFail("expected old version failure")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .unsupportedResponsesVersion(OllamaVersion(major: 0, minor: 13, patch: 3)))
            XCTAssertEqual(
                String(describing: error),
                "Ollama 0.13.3 is too old. Codex requires Ollama 0.13.4 or newer."
            )
        }

        try await OllamaClient.ensureResponsesSupported(provider: provider) { request in
            if request.url?.path == "/v1/models" {
                return OllamaHTTPResponse(statusCode: 200)
            }
            return OllamaHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
        }
    }

    func testPullModelPostsStreamRequestAndStopsAtSuccessLikeRustReporterPath() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { request in
            capturedRequest = request
            return OllamaHTTPResponse(
                statusCode: 200,
                data: Data("""
                {"status":"pulling manifest"}
                {"digest":"sha256:abc","total":100,"completed":50}
                {"status":"success"}
                {"status":"ignored after success"}
                """.utf8)
            )
        }

        var events: [OllamaPullEvent] = []
        try await client.pullModel("gpt-oss:20b") { event in
            events.append(event)
        }

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/pull")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-oss:20b")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(events, [
            .status("Pulling model gpt-oss:20b..."),
            .status("pulling manifest"),
            .chunkProgress(digest: "sha256:abc", total: 100, completed: 50),
            .status("success"),
            .success
        ])
    }

    func testPullModelReportsStreamErrorAndUnexpectedEOFLikeRustReporterPath() async throws {
        let errorClient = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 200, data: Data((#"{"error":"model not found"}"# + "\n").utf8))
        }
        var errorEvents: [OllamaPullEvent] = []
        do {
            try await errorClient.pullModel("missing") { event in
                errorEvents.append(event)
            }
            XCTFail("expected pull stream error")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .pullFailed("model not found"))
            XCTAssertEqual(String(describing: error), "Pull failed: model not found")
        }
        XCTAssertEqual(errorEvents, [
            .status("Pulling model missing..."),
            .error("model not found")
        ])

        let eofClient = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 200, data: Data(#"{"status":"pulling"}"#.utf8))
        }
        do {
            try await eofClient.pullModel("gpt-oss:20b") { _ in }
            XCTFail("expected unexpected EOF")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .pullStreamEndedUnexpectedly)
            XCTAssertEqual(String(describing: error), "Pull stream ended unexpectedly without success.")
        }
    }

    func testPullModelStartFailureMatchesRustHTTPError() async throws {
        let client = OllamaClient(hostRoot: "http://ollama.example", usesOpenAICompatibleAPI: false) { _ in
            OllamaHTTPResponse(statusCode: 404)
        }

        do {
            try await client.pullModel("gpt-oss:20b") { _ in }
            XCTFail("expected pull start failure")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .pullStartFailed(statusCode: 404))
            XCTAssertEqual(String(describing: error), "failed to start pull: HTTP 404")
        }
    }
}
