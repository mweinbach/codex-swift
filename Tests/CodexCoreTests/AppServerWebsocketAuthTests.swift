import CodexCore
import CryptoKit
import Foundation
import XCTest

final class AppServerWebsocketAuthTests: XCTestCase {
    func testCapabilityTokenFileSettingsRequireAbsolutePath() throws {
        let settings = try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
            mode: .capabilityToken,
            tokenFile: "/tmp/codex-token"
        ))

        XCTAssertEqual(settings, AppServerWebsocketAuthSettings(config: .capabilityToken(source: .tokenFile("/tmp/codex-token"))))

        XCTAssertThrowsError(try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
            mode: .capabilityToken,
            tokenFile: "codex-token"
        ))) { error in
            XCTAssertEqual(error as? AppServerWebsocketAuthValidationError, .absolutePathRequired(flagName: "--ws-token-file"))
            XCTAssertEqual(String(describing: error), "--ws-token-file must be an absolute path")
        }
    }

    func testCapabilityTokenHashSettingsValidateRustSHA256Shape() throws {
        let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let settings = try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
            mode: .capabilityToken,
            tokenSHA256: "  \(digest)  "
        ))

        XCTAssertEqual(settings.config, .capabilityToken(source: .tokenSHA256([
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef
        ])))

        for invalidDigest in ["not-a-sha256", String(repeating: "z", count: 64)] {
            XCTAssertThrowsError(try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
                mode: .capabilityToken,
                tokenSHA256: invalidDigest
            ))) { error in
                XCTAssertEqual(error as? AppServerWebsocketAuthValidationError, .invalidSHA256Digest(flagName: "--ws-token-sha256"))
                XCTAssertEqual(String(describing: error), "--ws-token-sha256 must be a 64-character hex SHA-256 digest")
            }
        }
    }

    func testCapabilityTokenModeRejectsRustInvalidFlagCombinations() {
        let cases: [(AppServerWebsocketAuthArguments, AppServerWebsocketAuthValidationError)] = [
            (
                AppServerWebsocketAuthArguments(mode: .capabilityToken, tokenFile: "/tmp/token", tokenSHA256: String(repeating: "a", count: 64)),
                .capabilityTokenSourceMutuallyExclusive
            ),
            (
                AppServerWebsocketAuthArguments(mode: .capabilityToken),
                .capabilityTokenSourceRequired
            ),
            (
                AppServerWebsocketAuthArguments(mode: .capabilityToken, tokenFile: "/tmp/token", sharedSecretFile: "/tmp/secret"),
                .signedBearerFlagsRequireSignedBearerMode
            )
        ]

        for (arguments, expectedError) in cases {
            XCTAssertThrowsError(try AppServerWebsocketAuthValidator.settings(from: arguments)) { error in
                XCTAssertEqual(error as? AppServerWebsocketAuthValidationError, expectedError)
                XCTAssertEqual(String(describing: error), expectedError.description)
            }
        }
    }

    func testSignedBearerSettingsDefaultClockSkewAndTrimClaims() throws {
        let settings = try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
            mode: .signedBearerToken,
            sharedSecretFile: "/tmp/codex-secret",
            issuer: " issuer ",
            audience: "   "
        ))

        XCTAssertEqual(settings, AppServerWebsocketAuthSettings(config: .signedBearerToken(
            sharedSecretFile: "/tmp/codex-secret",
            issuer: "issuer",
            audience: nil,
            maxClockSkewSeconds: AppServerWebsocketAuthValidator.defaultMaxClockSkewSeconds
        )))
    }

    func testSignedBearerModeRejectsRustInvalidFlagCombinations() {
        let cases: [(AppServerWebsocketAuthArguments, AppServerWebsocketAuthValidationError)] = [
            (
                AppServerWebsocketAuthArguments(mode: .signedBearerToken, tokenFile: "/tmp/token", sharedSecretFile: "/tmp/secret"),
                .capabilityTokenFlagsRequireCapabilityMode
            ),
            (
                AppServerWebsocketAuthArguments(mode: .signedBearerToken),
                .signedBearerSharedSecretRequired
            ),
            (
                AppServerWebsocketAuthArguments(sharedSecretFile: "/tmp/secret"),
                .websocketAuthFlagsRequireMode
            )
        ]

        for (arguments, expectedError) in cases {
            XCTAssertThrowsError(try AppServerWebsocketAuthValidator.settings(from: arguments)) { error in
                XCTAssertEqual(error as? AppServerWebsocketAuthValidationError, expectedError)
                XCTAssertEqual(String(describing: error), expectedError.description)
            }
        }
    }

    func testCapabilityTokenPolicyAuthorizesRustBearerTokenShape() throws {
        let token = "super-secret-token"
        let digest = Array(SHA256.hash(data: Data(token.utf8)))
        let policy = try AppServerWebsocketAuthPolicyBuilder.policy(
            from: AppServerWebsocketAuthSettings(config: .capabilityToken(source: .tokenSHA256(digest)))
        )

        XCTAssertNil(AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer \(token)", policy: policy))
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer wrong-token", policy: policy),
            .invalidBearerToken
        )
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: nil, policy: policy),
            .missingBearerToken
        )
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Basic \(token)", policy: policy),
            .invalidAuthorizationHeader
        )
    }

    func testCapabilityTokenFilePolicyReadsTrimmedSecretLikeRust() throws {
        let temp = try TemporaryDirectory()
        let tokenFile = temp.url.appendingPathComponent("token.txt")
        try "  file-token\n".write(to: tokenFile, atomically: true, encoding: .utf8)

        let settings = try AppServerWebsocketAuthValidator.settings(from: AppServerWebsocketAuthArguments(
            mode: .capabilityToken,
            tokenFile: tokenFile.path
        ))
        let policy = try AppServerWebsocketAuthPolicyBuilder.policy(from: settings)

        XCTAssertNil(AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer file-token", policy: policy))
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer   ", policy: policy),
            .invalidAuthorizationHeader
        )
    }

    func testSignedBearerPolicyAuthorizesHS256JWTLikeRust() throws {
        let secret = Array("0123456789abcdef0123456789abcdef".utf8)
        let policy = AppServerWebsocketAuthPolicy(mode: .signedBearerToken(
            sharedSecret: secret,
            issuer: "codex",
            audience: "desktop",
            maxClockSkewSeconds: 30
        ))
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        let token = signedJWT(
            claims: [
                "iss": "codex",
                "aud": ["web", "desktop"],
                "exp": 1_735_000_060,
                "nbf": 1_734_999_990
            ],
            secret: secret
        )

        XCTAssertNil(AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer \(token)", policy: policy, now: now))
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(
                authorizationHeader: "Bearer \(token.dropLast())x",
                policy: policy,
                now: now
            ),
            .invalidJWT
        )
        let expired = signedJWT(claims: ["exp": 1_734_999_900], secret: secret)
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer \(expired)", policy: policy, now: now),
            .expiredJWT
        )
        let booleanExpiration = signedJWT(claims: ["exp": true], secret: secret)
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(
                authorizationHeader: "Bearer \(booleanExpiration)",
                policy: policy,
                now: now
            ),
            .invalidJWT
        )
        let wrongIssuer = signedJWT(claims: ["iss": "other", "aud": "desktop", "exp": 1_735_000_060], secret: secret)
        XCTAssertEqual(
            AppServerWebsocketAuthorizer.authorize(authorizationHeader: "Bearer \(wrongIssuer)", policy: policy, now: now),
            .issuerMismatch
        )
    }

    func testSignedBearerPolicyReadsSecretAndRejectsShortSecretLikeRust() throws {
        let temp = try TemporaryDirectory()
        let secretFile = temp.url.appendingPathComponent("secret.txt")
        try "0123456789abcdef0123456789abcdef\n".write(to: secretFile, atomically: true, encoding: .utf8)
        let policy = try AppServerWebsocketAuthPolicyBuilder.policy(from: AppServerWebsocketAuthSettings(config: .signedBearerToken(
            sharedSecretFile: secretFile.path,
            issuer: nil,
            audience: nil,
            maxClockSkewSeconds: 30
        )))
        XCTAssertEqual(policy, AppServerWebsocketAuthPolicy(mode: .signedBearerToken(
            sharedSecret: Array("0123456789abcdef0123456789abcdef".utf8),
            issuer: nil,
            audience: nil,
            maxClockSkewSeconds: 30
        )))

        let shortSecretFile = temp.url.appendingPathComponent("short.txt")
        try "too-short".write(to: shortSecretFile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AppServerWebsocketAuthPolicyBuilder.policy(from: AppServerWebsocketAuthSettings(config: .signedBearerToken(
            sharedSecretFile: shortSecretFile.path,
            issuer: nil,
            audience: nil,
            maxClockSkewSeconds: 30
        )))) { error in
            XCTAssertEqual(error as? AppServerWebsocketAuthValidationError, .shortSignedBearerSecret(path: shortSecretFile.path))
        }
    }

    private func signedJWT(claims: [String: Any], secret: [UInt8]) -> String {
        let header = ["alg": "HS256", "typ": "JWT"]
        let headerSegment = base64URL(try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let claimsSegment = base64URL(try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        let signingInput = "\(headerSegment).\(claimsSegment)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(secret))
        )
        return "\(signingInput).\(base64URL(Data(mac)))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
