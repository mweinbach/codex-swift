import CryptoKit
import Foundation
import Security

public struct PKCECodes: Equatable, Sendable {
    public let codeVerifier: String
    public let codeChallenge: String

    public init(codeVerifier: String, codeChallenge: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }
}

public enum PKCEError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidRandomByteCount(Int)
    case randomBytesFailed(OSStatus)

    public var description: String {
        switch self {
        case let .invalidRandomByteCount(count):
            return "PKCE verifier generation requires 64 random bytes, got \(count)"
        case let .randomBytesFailed(status):
            return "Failed to generate PKCE verifier bytes: OSStatus \(status)"
        }
    }
}

public enum PKCE {
    public static let verifierByteCount = 64

    public static func generate() throws -> PKCECodes {
        try generate(randomBytes: secureRandomBytes(count: verifierByteCount))
    }

    public static func generate(randomBytes bytes: [UInt8]) throws -> PKCECodes {
        guard bytes.count == verifierByteCount else {
            throw PKCEError.invalidRandomByteCount(bytes.count)
        }

        let codeVerifier = base64URLEncodedNoPadding(Data(bytes))
        return PKCECodes(
            codeVerifier: codeVerifier,
            codeChallenge: codeChallenge(forVerifier: codeVerifier)
        )
    }

    public static func codeChallenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncodedNoPadding(Data(digest))
    }

    static func base64URLEncodedNoPadding(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func secureRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw PKCEError.randomBytesFailed(status)
        }
        return bytes
    }
}
