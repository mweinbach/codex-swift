@testable import CodexCore
import XCTest

final class LMStudioHelpersTests: XCTestCase {
    func testTryFromProviderProbesModelsEndpointLikeRust() async throws {
        var requestedPaths: [String] = []
        let provider = ModelProviderInfo.createOSSProvider(baseURL: "http://lmstudio.example/v1", wireAPI: .responses)

        let client = try await LMStudioClient.tryFromProvider(provider) { request in
            requestedPaths.append(try XCTUnwrap(request.url?.path))
            return LMStudioHTTPResponse(statusCode: 200)
        }

        XCTAssertEqual(client.baseURL, "http://lmstudio.example/v1")
        XCTAssertEqual(requestedPaths, ["/v1/models"])
    }

    func testTryFromProviderRejectsMissingBaseURLLikeRust() async throws {
        let provider = ModelProviderInfo(name: "gpt-oss", wireAPI: .responses)

        do {
            _ = try await LMStudioClient.tryFromProvider(provider)
            XCTFail("expected missing base URL")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .missingBaseURL)
            XCTAssertEqual(String(describing: error), "oss provider must have a base_url")
        }
    }

    func testCheckServerErrorsMatchRustMessages() async throws {
        let serverErrorClient = LMStudioClient(baseURL: "http://lmstudio.example") { _ in
            LMStudioHTTPResponse(statusCode: 404)
        }
        do {
            try await serverErrorClient.checkServer()
            XCTFail("expected server error")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .serverReturnedError(statusCode: 404))
            XCTAssertTrue(String(describing: error).contains("Server returned error: 404"))
            XCTAssertTrue(String(describing: error).contains(LMStudioClientError.connectionErrorMessage))
        }

        let connectionClient = LMStudioClient(baseURL: "http://lmstudio.example") { _ in
            throw BoomError()
        }
        do {
            try await connectionClient.checkServer()
            XCTFail("expected connection error")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .connectionUnavailable)
            XCTAssertEqual(String(describing: error), LMStudioClientError.connectionErrorMessage)
        }
    }

    func testFetchModelsParsesDataIDsLikeRust() async throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example/") { request in
            XCTAssertEqual(request.url?.path, "/models")
            return LMStudioHTTPResponse(
                statusCode: 200,
                data: Data(#"{"data":[{"id":"openai/gpt-oss-20b"},{"object":"model"},{"id":"other"}]}"#.utf8)
            )
        }

        let models = try await client.fetchModels()
        XCTAssertEqual(models, ["openai/gpt-oss-20b", "other"])
    }

    func testFetchModelsErrorsMatchRustMessages() async throws {
        let missingDataClient = LMStudioClient(baseURL: "http://lmstudio.example") { _ in
            LMStudioHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
        }
        do {
            _ = try await missingDataClient.fetchModels()
            XCTFail("expected missing data array")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .missingDataArray)
            XCTAssertEqual(String(describing: error), "No 'data' array in response")
        }

        let serverErrorClient = LMStudioClient(baseURL: "http://lmstudio.example") { _ in
            LMStudioHTTPResponse(statusCode: 500)
        }
        do {
            _ = try await serverErrorClient.fetchModels()
            XCTFail("expected fetch error")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .fetchModelsFailed(statusCode: 500))
            XCTAssertEqual(String(describing: error), "Failed to fetch models: 500")
        }
    }

    func testLoadModelPostsMinimalResponsesRequestLikeRust() async throws {
        var capturedRequest: URLRequest?
        let client = LMStudioClient(baseURL: "http://lmstudio.example/v1") { request in
            capturedRequest = request
            return LMStudioHTTPResponse(statusCode: 200)
        }

        try await client.loadModel("openai/gpt-oss-20b")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "openai/gpt-oss-20b")
        XCTAssertEqual(json["input"] as? String, "")
        XCTAssertEqual(json["max_output_tokens"] as? Int, 1)
    }

    func testLoadModelFailureMatchesRustMessage() async throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example") { _ in
            LMStudioHTTPResponse(statusCode: 503)
        }

        do {
            try await client.loadModel("openai/gpt-oss-20b")
            XCTFail("expected load failure")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .loadModelFailed(statusCode: 503))
            XCTAssertEqual(String(describing: error), "Failed to load model: 503")
        }
    }

    func testFindLMSReturnsLiteralCommandWhenPathContainsExecutableLikeRust() throws {
        let lms = try LMStudioClient.findLMS(
            pathEnvironment: "/usr/local/bin:/opt/lmstudio/bin",
            homeDirectory: "/test/home",
            fileExists: { $0 == "/opt/lmstudio/bin/lms" }
        )

        XCTAssertEqual(lms, "lms")
    }

    func testFindLMSFallsBackToHomeLMStudioBinLikeRust() throws {
        let expected = LMStudioClient.fallbackLMSPath(homeDirectory: "/test/home")

        let lms = try LMStudioClient.findLMS(
            pathEnvironment: "/usr/local/bin",
            homeDirectory: "/test/home",
            fileExists: { $0 == expected }
        )

        XCTAssertEqual(lms, expected)
        #if !os(Windows)
        XCTAssertEqual(expected, "/test/home/.lmstudio/bin/lms")
        #endif
    }

    func testFindLMSErrorMatchesRustMessage() throws {
        do {
            _ = try LMStudioClient.findLMS(
                pathEnvironment: "/usr/local/bin",
                homeDirectory: "/test/home",
                fileExists: { _ in false }
            )
            XCTFail("expected missing lms error")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .lmsNotFound)
            XCTAssertEqual(
                String(describing: error),
                "LM Studio not found. Please install LM Studio from https://lmstudio.ai/"
            )
        }
    }

    func testDownloadCommandUsesRustArguments() {
        let command = LMStudioClient.downloadCommand(for: "openai/gpt-oss-20b", lmsExecutable: "lms")

        XCTAssertEqual(command.executable, "lms")
        XCTAssertEqual(command.arguments, ["get", "--yes", "openai/gpt-oss-20b"])
        XCTAssertEqual(command.displayCommand, "lms get --yes openai/gpt-oss-20b")
    }

    func testDownloadErrorMessagesMatchRust() {
        XCTAssertEqual(
            String(describing: LMStudioClientError.downloadExecutionFailed(
                command: "lms get --yes openai/gpt-oss-20b",
                underlying: "boom"
            )),
            "Failed to execute 'lms get --yes openai/gpt-oss-20b': boom"
        )
        XCTAssertEqual(
            String(describing: LMStudioClientError.downloadFailed(exitCode: 7)),
            "Model download failed with exit code: 7"
        )
        XCTAssertEqual(
            String(describing: LMStudioClientError.downloadFailed(exitCode: nil)),
            "Model download failed with exit code: -1"
        )
    }

    func testDownloadModelFindsLMSPrintsAndRunsCommandLikeRust() throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example")
        var stderrLines: [String] = []
        var capturedCommand: LMStudioDownloadCommand?

        try client.downloadModel(
            "openai/gpt-oss-20b",
            findLMS: { "lms" },
            runDownloadCommand: { command in
                capturedCommand = command
                return 0
            },
            writeStandardError: { stderrLines.append($0) }
        )

        XCTAssertEqual(stderrLines, ["Downloading model: openai/gpt-oss-20b"])
        XCTAssertEqual(capturedCommand?.executable, "lms")
        XCTAssertEqual(capturedCommand?.arguments, ["get", "--yes", "openai/gpt-oss-20b"])
        XCTAssertEqual(capturedCommand?.displayCommand, "lms get --yes openai/gpt-oss-20b")
    }

    func testDownloadModelPropagatesMissingLMSBeforeRunning() throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example")
        var didRun = false

        do {
            try client.downloadModel(
                "openai/gpt-oss-20b",
                findLMS: { throw LMStudioClientError.lmsNotFound },
                runDownloadCommand: { _ in
                    didRun = true
                    return 0
                },
                writeStandardError: { _ in }
            )
            XCTFail("expected missing lms")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .lmsNotFound)
            XCTAssertFalse(didRun)
        }
    }

    func testDownloadModelMapsExecutionFailureLikeRust() throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example")

        do {
            try client.downloadModel(
                "openai/gpt-oss-20b",
                findLMS: { "lms" },
                runDownloadCommand: { _ in throw BoomError() },
                writeStandardError: { _ in }
            )
            XCTFail("expected execution failure")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(
                error,
                .downloadExecutionFailed(command: "lms get --yes openai/gpt-oss-20b", underlying: "boom")
            )
            XCTAssertEqual(
                String(describing: error),
                "Failed to execute 'lms get --yes openai/gpt-oss-20b': boom"
            )
        }
    }

    func testDownloadModelMapsExitStatusLikeRust() throws {
        let client = LMStudioClient(baseURL: "http://lmstudio.example")

        do {
            try client.downloadModel(
                "openai/gpt-oss-20b",
                findLMS: { "lms" },
                runDownloadCommand: { _ in 7 },
                writeStandardError: { _ in }
            )
            XCTFail("expected nonzero exit")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .downloadFailed(exitCode: 7))
            XCTAssertEqual(String(describing: error), "Model download failed with exit code: 7")
        }

        do {
            try client.downloadModel(
                "openai/gpt-oss-20b",
                findLMS: { "lms" },
                runDownloadCommand: { _ in nil },
                writeStandardError: { _ in }
            )
            XCTFail("expected signal exit")
        } catch let error as LMStudioClientError {
            XCTAssertEqual(error, .downloadFailed(exitCode: nil))
            XCTAssertEqual(String(describing: error), "Model download failed with exit code: -1")
        }
    }
}

private struct BoomError: Error, CustomStringConvertible {
    var description: String { "boom" }
}
