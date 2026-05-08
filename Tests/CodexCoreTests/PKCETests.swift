@testable import CodexCore
import XCTest

final class PKCETests: XCTestCase {
    func testGeneratePKCECodesFromBytesMatchesRust() throws {
        let codes = try PKCE.generate(randomBytes: Array(UInt8(0)...UInt8(63)))

        XCTAssertEqual(
            codes.codeVerifier,
            "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw"
        )
        XCTAssertEqual(
            codes.codeChallenge,
            "wsNdZaf3VpLTsEDmR5gPk2C6xYVWxKb0xcaG3O6kX10"
        )
    }

    func testCodeChallengeUsesVerifierBytes() {
        XCTAssertEqual(
            PKCE.codeChallenge(forVerifier: "abc"),
            "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"
        )
    }

    func testGeneratedPKCECodesUseURLSafeNoPaddingEncoding() throws {
        let codes = try PKCE.generate()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

        XCTAssertEqual(codes.codeVerifier.count, 86)
        XCTAssertEqual(codes.codeChallenge.count, 43)
        XCTAssertTrue(codes.codeVerifier.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertTrue(codes.codeChallenge.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertFalse(codes.codeVerifier.contains("="))
        XCTAssertFalse(codes.codeChallenge.contains("="))
    }

    func testInvalidRandomByteCountReportsCount() throws {
        XCTAssertThrowsError(try PKCE.generate(randomBytes: [1, 2, 3])) { error in
            XCTAssertEqual(
                (error as? PKCEError)?.description,
                "PKCE verifier generation requires 64 random bytes, got 3"
            )
        }
    }
}
