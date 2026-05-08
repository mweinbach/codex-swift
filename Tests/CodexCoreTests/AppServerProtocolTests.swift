import CodexCore
import XCTest

final class AppServerProtocolTests: XCTestCase {
    func testAttestationGenerateServerRequestMatchesRustWireShape() throws {
        let request = AppServerProtocol.ServerRequest.attestationGenerate(
            requestID: .integer(9),
            params: Attestation.GenerateParams()
        )

        XCTAssertEqual(request.id, .integer(9))
        XCTAssertEqual(request.method, "attestation/generate")
        try XCTAssertJSONObjectEqual(request, [
            "method": "attestation/generate",
            "id": 9,
            "params": [String: Any]()
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.attestationGenerate().request(withID: .integer(9)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/generate","id":9,"params":{}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testAttestationGenerateServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.attestationGenerate(
            requestID: .string("request-9"),
            response: Attestation.GenerateResponse(token: "v1.integration-test")
        )

        XCTAssertEqual(response.id, .string("request-9"))
        XCTAssertEqual(response.method, "attestation/generate")
        try XCTAssertJSONObjectEqual(response, [
            "method": "attestation/generate",
            "id": "request-9",
            "response": [
                "token": "v1.integration-test"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"attestation/generate","id":"request-9","response":{"token":"v1.integration-test"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testUnknownServerRequestMethodFailsLikeTaggedRustEnum() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/unknown","id":1,"params":{}}"#.utf8)
        ))
    }
}
