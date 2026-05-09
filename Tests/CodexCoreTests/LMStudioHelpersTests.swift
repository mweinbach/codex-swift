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
}

private struct BoomError: Error, CustomStringConvertible {
    var description: String { "boom" }
}
