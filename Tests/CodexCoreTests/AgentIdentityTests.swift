import Foundation
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
}
