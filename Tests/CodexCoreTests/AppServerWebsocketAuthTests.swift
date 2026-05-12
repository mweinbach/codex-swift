import CodexCore
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
}
