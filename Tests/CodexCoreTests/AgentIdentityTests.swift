import Foundation
import CryptoKit
import XCTest
@testable import CodexCore

final class AgentIdentityTests: XCTestCase {
    func testAgentIdentityURLBuildersMatchRust() {
        XCTAssertEqual(
            AgentIdentity.agentRegistrationURL(chatGPTBaseURL: "https://chatgpt.com/backend-api/"),
            "https://chatgpt.com/backend-api/v1/agent/register"
        )
        XCTAssertEqual(
            AgentIdentity.agentTaskRegistrationURL(
                chatGPTBaseURL: "https://chatgpt.com/backend-api/",
                agentRuntimeID: "agent-123"
            ),
            "https://chatgpt.com/backend-api/v1/agent/agent-123/task/register"
        )
        XCTAssertEqual(
            AgentIdentity.agentIdentityBiscuitURL(chatGPTBaseURL: "https://chatgpt.com/backend-api/"),
            "https://chatgpt.com/backend-api/authenticate_app_v2"
        )
    }

    func testAgentIdentityJWKSURLUsesBackendAPIBaseURL() {
        XCTAssertEqual(
            AgentIdentity.agentIdentityJWKSURL(chatGPTBaseURL: "https://chatgpt.com/backend-api"),
            "https://chatgpt.com/backend-api/wham/agent-identities/jwks"
        )
        XCTAssertEqual(
            AgentIdentity.agentIdentityJWKSURL(chatGPTBaseURL: "https://chatgpt.com/backend-api/"),
            "https://chatgpt.com/backend-api/wham/agent-identities/jwks"
        )
    }

    func testAgentIdentityJWKSURLUsesCodexAPIBaseURL() {
        XCTAssertEqual(
            AgentIdentity.agentIdentityJWKSURL(chatGPTBaseURL: "http://localhost:8080/api/codex"),
            "http://localhost:8080/api/codex/agent-identities/jwks"
        )
        XCTAssertEqual(
            AgentIdentity.agentIdentityJWKSURL(chatGPTBaseURL: "http://localhost:8080/api/codex/"),
            "http://localhost:8080/api/codex/agent-identities/jwks"
        )
    }

    func testAgentIdentityRequestIDUsesRustPrefixAndBase64URLNoPadding() throws {
        let bytes = Array(UInt8(0)..<UInt8(16))

        let requestID = try AgentIdentity.agentIdentityRequestID(randomBytes: bytes)

        XCTAssertEqual(requestID, "codex-agent-identity-AAECAwQFBgcICQoLDA0ODw")
        XCTAssertFalse(requestID.contains("="))
    }

    func testAgentIdentityRequestIDRejectsWrongByteCount() {
        XCTAssertThrowsError(try AgentIdentity.agentIdentityRequestID(randomBytes: [1, 2, 3])) { error in
            XCTAssertEqual(
                String(describing: error),
                "agent identity request id generation requires 16 random bytes, got 3"
            )
        }
    }

    func testBuildABOMMatchesRustHarnessAndLocationRules() {
        XCTAssertEqual(
            AgentIdentity.buildABOM(
                sessionSource: .vscode,
                agentVersion: "1.2.3",
                operatingSystem: "macos"
            ),
            AgentBillOfMaterials(
                agentVersion: "1.2.3",
                agentHarnessID: "codex-app",
                runningLocation: "vscode-macos"
            )
        )

        XCTAssertEqual(
            AgentIdentity.buildABOM(
                sessionSource: .cli,
                agentVersion: "1.2.3",
                operatingSystem: "linux"
            ),
            AgentBillOfMaterials(
                agentVersion: "1.2.3",
                agentHarnessID: "codex-cli",
                runningLocation: "cli-linux"
            )
        )
    }

    func testGenerateAgentKeyMaterialEncodesPKCS8AndSSHPublicKeyLikeRust() throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)

        XCTAssertEqual(
            material.privateKeyPKCS8Base64,
            "MC4CAQAwBQYDK2VwBCIEIAcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcH"
        )
        XCTAssertEqual(
            try AgentIdentity.publicKeySSH(privateKeyPKCS8Base64: material.privateKeyPKCS8Base64),
            material.publicKeySSH
        )
        XCTAssertTrue(material.publicKeySSH.hasPrefix("ssh-ed25519 "))
    }

    func testSignTaskRegistrationPayloadUsesRuntimeAndTimestamp() throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)

        let signature = try AgentIdentity.signTaskRegistrationPayload(
            key: key,
            timestamp: "2026-05-13T12:00:00Z"
        )

        let signatureBytes = try XCTUnwrap(Data(base64Encoded: signature))
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(Self.testEd25519Seed))
        XCTAssertTrue(
            privateKey.publicKey.isValidSignature(
                signatureBytes,
                for: Data("agent-123:2026-05-13T12:00:00Z".utf8)
            )
        )
    }

    func testRegisterAgentTaskPostsSignedRequestAndReadsSnakeTaskID() async throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)
        let transport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data(#"{"task_id":"task-123"}"#.utf8)))
        )

        let taskID = try await AgentIdentity.registerAgentTask(
            transport: transport,
            chatGPTBaseURL: "https://chatgpt.com/backend-api/",
            key: key,
            timestamp: "2026-05-13T12:00:00Z"
        )

        XCTAssertEqual(taskID, "task-123")
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, "https://chatgpt.com/backend-api/v1/agent/agent-123/task/register")
        XCTAssertEqual(request.timeoutMilliseconds, 30_000)
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(body.objectValue)
        XCTAssertEqual(object["timestamp"], .string("2026-05-13T12:00:00Z"))

        let signature = try XCTUnwrap(object["signature"]?.stringValue.flatMap { Data(base64Encoded: $0) })
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(Self.testEd25519Seed))
        XCTAssertTrue(
            privateKey.publicKey.isValidSignature(
                signature,
                for: Data("agent-123:2026-05-13T12:00:00Z".utf8)
            )
        )
    }

    func testRegisterAgentTaskReadsCamelTaskID() async throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)
        let transport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data(#"{"taskId":"task-camel"}"#.utf8)))
        )

        let taskID = try await AgentIdentity.registerAgentTask(
            transport: transport,
            chatGPTBaseURL: "https://chatgpt.com/backend-api",
            key: key,
            timestamp: "2026-05-13T12:00:00Z"
        )

        XCTAssertEqual(taskID, "task-camel")
    }

    func testRegisterAgentTaskErrorsMatchRust() async throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)
        let longBody = String(repeating: "x", count: 520)
        let failingTransport = RecordingAgentIdentityTransport(
            result: .failure(.http(statusCode: 500, headers: [:], body: longBody))
        )

        do {
            _ = try await AgentIdentity.registerAgentTask(
                transport: failingTransport,
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                key: key,
                timestamp: "2026-05-13T12:00:00Z"
            )
            XCTFail("expected registration failure")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "failed to register agent task with status 500 Internal Server Error: \(String(longBody.prefix(512)))..."
            )
        }

        let malformedTransport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data("not json".utf8)))
        )
        do {
            _ = try await AgentIdentity.registerAgentTask(
                transport: malformedTransport,
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                key: key,
                timestamp: "2026-05-13T12:00:00Z"
            )
            XCTFail("expected decode failure")
        } catch {
            XCTAssertEqual(String(describing: error), "failed to decode agent task registration response")
        }

        let omittedIDTransport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data(#"{}"#.utf8)))
        )
        do {
            _ = try await AgentIdentity.registerAgentTask(
                transport: omittedIDTransport,
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                key: key,
                timestamp: "2026-05-13T12:00:00Z"
            )
            XCTFail("expected omitted task id failure")
        } catch {
            XCTAssertEqual(String(describing: error), "agent task registration response omitted task id")
        }

        let invalidEncryptedIDTransport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data(#"{"encrypted_task_id":"not base64"}"#.utf8)))
        )
        do {
            _ = try await AgentIdentity.registerAgentTask(
                transport: invalidEncryptedIDTransport,
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                key: key,
                timestamp: "2026-05-13T12:00:00Z"
            )
            XCTFail("expected invalid encrypted task id failure")
        } catch {
            XCTAssertEqual(String(describing: error), "encrypted task id is not valid base64")
        }

        let encryptedIDTransport = RecordingAgentIdentityTransport(
            result: .success(APIResponse(statusCode: 200, body: Data(#"{"encryptedTaskId":"dmFsaWQtYmFzZTY0"}"#.utf8)))
        )
        do {
            _ = try await AgentIdentity.registerAgentTask(
                transport: encryptedIDTransport,
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                key: key,
                timestamp: "2026-05-13T12:00:00Z"
            )
            XCTFail("expected encrypted task id decrypt failure")
        } catch {
            XCTAssertEqual(String(describing: error), "failed to decrypt encrypted task id")
        }
    }

    func testAuthorizationHeaderForAgentTaskSerializesSignedAgentAssertionLikeRust() throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)
        let target = AgentTaskAuthorizationTarget(agentRuntimeID: "agent-123", taskID: "task-123")

        let header = try AgentIdentity.authorizationHeaderForAgentTask(
            key: key,
            target: target,
            timestamp: "2026-05-13T12:00:00Z"
        )

        let headerPrefix = "AgentAssertion "
        XCTAssertTrue(header.hasPrefix(headerPrefix))
        let token = String(header.dropFirst(headerPrefix.count))
        XCTAssertFalse(token.contains("="))
        let payload = try base64URLDecode(token)
        let payloadString = try XCTUnwrap(String(data: payload, encoding: .utf8))
        let agentRuntimeIDRange = try XCTUnwrap(payloadString.range(of: #""agent_runtime_id""#))
        let signatureRange = try XCTUnwrap(payloadString.range(of: #""signature""#))
        let taskIDRange = try XCTUnwrap(payloadString.range(of: #""task_id""#))
        let timestampRange = try XCTUnwrap(payloadString.range(of: #""timestamp""#))
        XCTAssertLessThan(agentRuntimeIDRange.lowerBound, signatureRange.lowerBound)
        XCTAssertLessThan(signatureRange.lowerBound, taskIDRange.lowerBound)
        XCTAssertLessThan(taskIDRange.lowerBound, timestampRange.lowerBound)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        XCTAssertEqual(object["agent_runtime_id"], "agent-123")
        XCTAssertEqual(object["task_id"], "task-123")
        XCTAssertEqual(object["timestamp"], "2026-05-13T12:00:00Z")

        let signature = try XCTUnwrap(object["signature"].flatMap { Data(base64Encoded: $0) })
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(Self.testEd25519Seed))
        XCTAssertTrue(
            privateKey.publicKey.isValidSignature(
                signature,
                for: Data("agent-123:task-123:2026-05-13T12:00:00Z".utf8)
            )
        )
    }

    func testAuthorizationHeaderForAgentTaskRejectsMismatchedRuntime() throws {
        let material = try AgentIdentity.generateAgentKeyMaterial(privateKeyBytes: Self.testEd25519Seed)
        let key = AgentIdentityKey(agentRuntimeID: "agent-123", privateKeyPKCS8Base64: material.privateKeyPKCS8Base64)
        let target = AgentTaskAuthorizationTarget(agentRuntimeID: "agent-456", taskID: "task-123")

        XCTAssertThrowsError(try AgentIdentity.authorizationHeaderForAgentTask(
            key: key,
            target: target,
            timestamp: "2026-05-13T12:00:00Z"
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "agent task runtime agent-456 does not match stored agent identity agent-123"
            )
        }
    }

    func testStoredAgentPrivateKeyDecodeErrorsMatchRust() {
        XCTAssertThrowsError(try AgentIdentity.publicKeySSH(privateKeyPKCS8Base64: "not base64")) { error in
            XCTAssertEqual(String(describing: error), "stored agent identity private key is not valid base64")
        }
        XCTAssertThrowsError(try AgentIdentity.publicKeySSH(privateKeyPKCS8Base64: Data("nope".utf8).base64EncodedString())) { error in
            XCTAssertEqual(String(describing: error), "stored agent identity private key is not valid PKCS#8")
        }
    }

    func testDecodeAgentIdentityJWTReadsClaims() throws {
        let jwt = jwtWithPayload([
            "iss": AgentIdentity.jwtIssuer,
            "aud": AgentIdentity.jwtAudience,
            "iat": 1_700_000_000,
            "exp": 4_000_000_000,
            "agent_runtime_id": "agent-runtime-id",
            "agent_private_key": "private-key",
            "account_id": "account-id",
            "chatgpt_user_id": "user-id",
            "email": "user@example.com",
            "plan_type": "pro",
            "chatgpt_account_is_fedramp": false,
        ])

        let claims = try AgentIdentity.decodeJWTClaims(jwt)

        XCTAssertEqual(
            claims,
            AgentIdentityJWTClaims(
                iss: AgentIdentity.jwtIssuer,
                aud: AgentIdentity.jwtAudience,
                iat: 1_700_000_000,
                exp: 4_000_000_000,
                agentRuntimeID: "agent-runtime-id",
                agentPrivateKey: "private-key",
                accountID: "account-id",
                chatGPTUserID: "user-id",
                email: "user@example.com",
                planType: .pro,
                chatGPTAccountIsFedRAMP: false
            )
        )
    }

    func testDecodeAgentIdentityJWTMapsRawPlanAliases() throws {
        let jwt = jwtWithPayload([
            "iss": AgentIdentity.jwtIssuer,
            "aud": AgentIdentity.jwtAudience,
            "iat": 1_700_000_000,
            "exp": 4_000_000_000,
            "agent_runtime_id": "agent-runtime-id",
            "agent_private_key": "private-key",
            "account_id": "account-id",
            "chatgpt_user_id": "user-id",
            "email": "user@example.com",
            "plan_type": "hc",
            "chatgpt_account_is_fedramp": false,
        ])

        XCTAssertEqual(try AgentIdentity.decodeJWTClaims(jwt).planType, .enterprise)
    }

    func testDecodeAgentIdentityJWTVerifiesWhenJWKSIsPresent() throws {
        let claims = try AgentIdentity.decodeJWTClaims(Self.signedRS256JWT, jwks: testJWKS(kid: "test-key"))

        XCTAssertEqual(
            claims,
            AgentIdentityJWTClaims(
                iss: AgentIdentity.jwtIssuer,
                aud: AgentIdentity.jwtAudience,
                iat: 1_700_000_000,
                exp: 4_000_000_000,
                agentRuntimeID: "agent-runtime-id",
                agentPrivateKey: "private-key",
                accountID: "account-id",
                chatGPTUserID: "user-id",
                email: "user@example.com",
                planType: .pro,
                chatGPTAccountIsFedRAMP: false
            )
        )
    }

    func testDecodeAgentIdentityJWTRejectsUntrustedKid() {
        XCTAssertThrowsError(try AgentIdentity.decodeJWTClaims(Self.signedRS256JWT, jwks: testJWKS(kid: "other-key"))) { error in
            XCTAssertEqual(String(describing: error), "agent identity JWT kid test-key is not trusted")
        }
    }

    func testDecodeAgentIdentityJWTRequiresIssuerAndAudience() {
        XCTAssertThrowsError(
            try AgentIdentity.decodeJWTClaims(Self.signedRS256JWTWithoutIssuerOrAudience, jwks: testJWKS(kid: "test-key"))
        ) { error in
            XCTAssertEqual(String(describing: error), "failed to verify agent identity JWT")
        }
    }

    func testDecodeAgentIdentityJWTRequiresKidWhenJWKSIsPresent() {
        XCTAssertThrowsError(try AgentIdentity.decodeJWTClaims(jwtWithPayload([
            "iss": AgentIdentity.jwtIssuer,
            "aud": AgentIdentity.jwtAudience,
            "iat": 1_700_000_000,
            "exp": 4_000_000_000,
            "agent_runtime_id": "agent-runtime-id",
            "agent_private_key": "private-key",
            "account_id": "account-id",
            "chatgpt_user_id": "user-id",
            "email": "user@example.com",
            "plan_type": "pro",
            "chatgpt_account_is_fedramp": false,
        ]), jwks: testJWKS(kid: "test-key"))) { error in
            XCTAssertEqual(String(describing: error), "agent identity JWT header does not include a kid")
        }
    }

    func testDecodeAgentIdentityJWTRejectsMalformedInputWithRustMessages() {
        XCTAssertThrowsError(try AgentIdentity.decodeJWTClaims("header.payload")) { error in
            XCTAssertEqual(String(describing: error), "invalid agent identity JWT format")
        }

        XCTAssertThrowsError(try AgentIdentity.decodeJWTClaims("header.not@base64.sig")) { error in
            XCTAssertEqual(
                String(describing: error),
                "agent identity JWT payload is not valid base64url"
            )
        }

        XCTAssertThrowsError(try AgentIdentity.decodeJWTClaims("header.\(base64URL(Data("nope".utf8))).sig")) { error in
            XCTAssertEqual(String(describing: error), "agent identity JWT payload is not valid JSON")
        }
    }

    private func jwtWithPayload(_ payload: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "\(header).\(base64URL(payloadData)).\(base64URL(Data("sig".utf8)))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func base64URLDecode(_ value: String) throws -> Data {
        var standard = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 {
            standard.append("=")
        }
        return try XCTUnwrap(Data(base64Encoded: standard))
    }

    private func testJWKS(kid: String) -> AgentIdentityJWKS {
        AgentIdentityJWKS(keys: [
            AgentIdentityJWK(
                kty: "RSA",
                kid: kid,
                use: "sig",
                alg: "RS256",
                n: "1qQF2MqTrGAMDm7wXbjJP5sWqGA83tAGUs2ksy7iJXLJdhCg4AtwGm4SFl4f6kxhCSzlN1QdXuZjvRT2wZZiGUi9xUE28rf4WLrTxSnwqLuTy5knMP08yC0t_0YU_FGPZMcWb14hG05IvZr8UbmRaVagxSR8H4rSIymRoVwwmFSrqz068XrWGSYNIfLEASyo5GdAaqmk1JALINHgYGQJVxMxtwcvDxoVKmC7eltUNymMNBZhsv4E8sx9YNLpBoEibznfEpDU_DGzrM5eZCsQzaqbhBOlGd427ifud_Nnd9cPqzgCUc23-0FXSPfpbgksCXAwAmD0OFjQWrgqVdKL6Q",
                e: "AQAB"
            ),
        ])
    }

    private static let signedRS256JWT = """
    eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InRlc3Qta2V5In0.\
    eyJhY2NvdW50X2lkIjoiYWNjb3VudC1pZCIsImFnZW50X3ByaXZhdGVfa2V5IjoicHJpdmF0ZS1rZXkiLCJhZ2VudF9ydW50aW1lX2lkIjoiYWdlbnQtcnVudGltZS1pZCIsImF1ZCI6ImNvZGV4LWFwcC1zZXJ2ZXIiLCJjaGF0Z3B0X2FjY291bnRfaXNfZmVkcmFtcCI6ZmFsc2UsImNoYXRncHRfdXNlcl9pZCI6InVzZXItaWQiLCJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20iLCJleHAiOjQwMDAwMDAwMDAsImlhdCI6MTcwMDAwMDAwMCwiaXNzIjoiaHR0cHM6Ly9jaGF0Z3B0LmNvbS9jb2RleC1iYWNrZW5kL2FnZW50LWlkZW50aXR5IiwicGxhbl90eXBlIjoicHJvIn0.\
    zyIDXds5aNy0-pO9jz4BsXZ-7urXwd4fd6VyWOIV-57cksl_gUkr0F6Tx2O8f-8CQ_qDPuUDREfsFspunz-payxQiOjwhH1Rj4ko7vsndIO3L_bWInQOTANELA3UmBa2Rh669HWqiFg5hbvXsqEr84DK8TylLzd55roPqfhOU3MK5KOy8MO30AmQ0gcDJZWz12b18vM9tZNoHRsD1b0g_TbxrhtziwdqPy0Ptl_R_TiT1VeyMbMu_oj4EhN7eZ6KKWe2yo516pgIMA_o9nJfiYFD-lLzlnQPtR2Gk39Gn8xkGCLlBvilaPvyWypjNngOENqDkLQBfCk7_ESKNjJscA
    """

    private static let signedRS256JWTWithoutIssuerOrAudience = """
    eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InRlc3Qta2V5In0.\
    eyJhY2NvdW50X2lkIjoiYWNjb3VudC1pZCIsImFnZW50X3ByaXZhdGVfa2V5IjoicHJpdmF0ZS1rZXkiLCJhZ2VudF9ydW50aW1lX2lkIjoiYWdlbnQtcnVudGltZS1pZCIsImNoYXRncHRfYWNjb3VudF9pc19mZWRyYW1wIjpmYWxzZSwiY2hhdGdwdF91c2VyX2lkIjoidXNlci1pZCIsImVtYWlsIjoidXNlckBleGFtcGxlLmNvbSIsImV4cCI6NDAwMDAwMDAwMCwiaWF0IjoxNzAwMDAwMDAwLCJwbGFuX3R5cGUiOiJwcm8ifQ.\
    QmHUZqnS48T8-vKmjxhwiYoGywLzhpQOAl_FNOPoYe2Xi11uBA_dZRK9s7I75swqF6h6MoZXZOzKJWjyAEi2Uq8_hbz845Nd9Ie3nZJoxSLV28uaP67z07-1XhaQ6vtCYbJr8gg6nCTsMDqpMEisyokq6bMgzIOhdBxfTQdOqj4xiguKhMUToahF9J6VAJjNbHpmlj0p42HYMUG2DgoYUsI-1rrb1bEqHftRgVIDyNME3l9B6BqGCz9WnCa2IQqn2O4XCSZkHkpWDbFW7hFD6VoaP8XFIHLdBuPx25mwdeVt_Pxy2Liwk69FJbrTHL-WiP0gnoheQD8fhliWQlgauQ
    """

    private static let testEd25519Seed = [UInt8](repeating: 7, count: 32)
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }
}

private actor RecordingAgentIdentityTransport: APITransport {
    private var requests: [APIRequest] = []
    private let result: Result<APIResponse, TransportError>

    init(result: Result<APIResponse, TransportError>) {
        self.result = result
    }

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        requests.append(request)
        return result
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        requests.append(request)
        return .failure(.network("stream is not supported"))
    }

    func recordedRequests() -> [APIRequest] {
        requests
    }
}
