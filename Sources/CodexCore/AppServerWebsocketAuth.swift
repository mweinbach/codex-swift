import CryptoKit
import Foundation

public enum AppServerWebsocketAuthMode: Equatable, Sendable {
    case capabilityToken
    case signedBearerToken
}

public struct AppServerWebsocketAuthArguments: Equatable, Sendable {
    public let mode: AppServerWebsocketAuthMode?
    public let tokenFile: String?
    public let tokenSHA256: String?
    public let sharedSecretFile: String?
    public let issuer: String?
    public let audience: String?
    public let maxClockSkewSeconds: UInt64?

    public init(
        mode: AppServerWebsocketAuthMode? = nil,
        tokenFile: String? = nil,
        tokenSHA256: String? = nil,
        sharedSecretFile: String? = nil,
        issuer: String? = nil,
        audience: String? = nil,
        maxClockSkewSeconds: UInt64? = nil
    ) {
        self.mode = mode
        self.tokenFile = tokenFile
        self.tokenSHA256 = tokenSHA256
        self.sharedSecretFile = sharedSecretFile
        self.issuer = issuer
        self.audience = audience
        self.maxClockSkewSeconds = maxClockSkewSeconds
    }
}

public struct AppServerWebsocketAuthSettings: Equatable, Sendable {
    public let config: AppServerWebsocketAuthConfig?

    public init(config: AppServerWebsocketAuthConfig? = nil) {
        self.config = config
    }
}

public struct AppServerWebsocketAuthPolicy: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case capabilityToken(tokenSHA256: [UInt8])
        case signedBearerToken(
            sharedSecret: [UInt8],
            issuer: String?,
            audience: String?,
            maxClockSkewSeconds: Int64
        )
    }

    public let mode: Mode?

    public init(mode: Mode? = nil) {
        self.mode = mode
    }
}

public enum AppServerWebsocketAuthConfig: Equatable, Sendable {
    case capabilityToken(source: AppServerWebsocketCapabilityTokenSource)
    case signedBearerToken(
        sharedSecretFile: String,
        issuer: String?,
        audience: String?,
        maxClockSkewSeconds: UInt64
    )
}

public enum AppServerWebsocketCapabilityTokenSource: Equatable, Sendable {
    case tokenFile(String)
    case tokenSHA256([UInt8])
}

public enum AppServerWebsocketAuthValidationError: Error, CustomStringConvertible, Equatable, Sendable {
    case signedBearerFlagsRequireSignedBearerMode
    case capabilityTokenSourceMutuallyExclusive
    case capabilityTokenSourceRequired
    case capabilityTokenFlagsRequireCapabilityMode
    case signedBearerSharedSecretRequired
    case websocketAuthFlagsRequireMode
    case absolutePathRequired(flagName: String)
    case invalidSHA256Digest(flagName: String)
    case clockSkewTooLarge
    case shortSignedBearerSecret(path: String)
    case emptySecret(path: String)
    case readSecretFailed(path: String, message: String)

    public var description: String {
        switch self {
        case .signedBearerFlagsRequireSignedBearerMode:
            return "`--ws-shared-secret-file`, `--ws-issuer`, `--ws-audience`, and `--ws-max-clock-skew-seconds` require `--ws-auth signed-bearer-token`"
        case .capabilityTokenSourceMutuallyExclusive:
            return "`--ws-token-file` and `--ws-token-sha256` are mutually exclusive"
        case .capabilityTokenSourceRequired:
            return "`--ws-token-file` or `--ws-token-sha256` is required when `--ws-auth capability-token` is set"
        case .capabilityTokenFlagsRequireCapabilityMode:
            return "`--ws-token-file` and `--ws-token-sha256` require `--ws-auth capability-token`, not `signed-bearer-token`"
        case .signedBearerSharedSecretRequired:
            return "`--ws-shared-secret-file` is required when `--ws-auth signed-bearer-token` is set"
        case .websocketAuthFlagsRequireMode:
            return "websocket auth flags require `--ws-auth capability-token` or `--ws-auth signed-bearer-token`"
        case let .absolutePathRequired(flagName):
            return "\(flagName) must be an absolute path"
        case let .invalidSHA256Digest(flagName):
            return "\(flagName) must be a 64-character hex SHA-256 digest"
        case .clockSkewTooLarge:
            return "websocket auth clock skew must fit in a signed 64-bit integer"
        case let .shortSignedBearerSecret(path):
            return "signed websocket bearer secret \(path) must be at least 32 bytes"
        case let .emptySecret(path):
            return "websocket auth secret \(path) must not be empty"
        case let .readSecretFailed(path, message):
            return "failed to read websocket auth secret \(path): \(message)"
        }
    }
}

public enum AppServerWebsocketAuthValidator {
    public static let defaultMaxClockSkewSeconds: UInt64 = 30
    public static let minimumSignedBearerSecretBytes = 32

    public static func settings(
        from arguments: AppServerWebsocketAuthArguments
    ) throws -> AppServerWebsocketAuthSettings {
        let config: AppServerWebsocketAuthConfig?
        switch arguments.mode {
        case .capabilityToken:
            if arguments.sharedSecretFile != nil ||
                arguments.issuer != nil ||
                arguments.audience != nil ||
                arguments.maxClockSkewSeconds != nil {
                throw AppServerWebsocketAuthValidationError.signedBearerFlagsRequireSignedBearerMode
            }
            switch (arguments.tokenFile, arguments.tokenSHA256) {
            case let (.some(tokenFile), .none):
                config = .capabilityToken(source: .tokenFile(try absolutePath("--ws-token-file", tokenFile)))
            case let (.none, .some(tokenSHA256)):
                config = .capabilityToken(source: .tokenSHA256(try sha256Digest("--ws-token-sha256", tokenSHA256)))
            case (.some, .some):
                throw AppServerWebsocketAuthValidationError.capabilityTokenSourceMutuallyExclusive
            case (.none, .none):
                throw AppServerWebsocketAuthValidationError.capabilityTokenSourceRequired
            }

        case .signedBearerToken:
            if arguments.tokenFile != nil || arguments.tokenSHA256 != nil {
                throw AppServerWebsocketAuthValidationError.capabilityTokenFlagsRequireCapabilityMode
            }
            guard let sharedSecretFile = arguments.sharedSecretFile else {
                throw AppServerWebsocketAuthValidationError.signedBearerSharedSecretRequired
            }
            config = .signedBearerToken(
                sharedSecretFile: try absolutePath("--ws-shared-secret-file", sharedSecretFile),
                issuer: normalized(arguments.issuer),
                audience: normalized(arguments.audience),
                maxClockSkewSeconds: arguments.maxClockSkewSeconds ?? defaultMaxClockSkewSeconds
            )

        case .none:
            if arguments.tokenFile != nil ||
                arguments.tokenSHA256 != nil ||
                arguments.sharedSecretFile != nil ||
                arguments.issuer != nil ||
                arguments.audience != nil ||
                arguments.maxClockSkewSeconds != nil {
                throw AppServerWebsocketAuthValidationError.websocketAuthFlagsRequireMode
            }
            config = nil
        }

        return AppServerWebsocketAuthSettings(config: config)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func absolutePath(_ flagName: String, _ path: String) throws -> String {
        guard path.hasPrefix("/") else {
            throw AppServerWebsocketAuthValidationError.absolutePathRequired(flagName: flagName)
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func sha256Digest(_ flagName: String, _ value: String) throws -> [UInt8] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else {
            throw AppServerWebsocketAuthValidationError.invalidSHA256Digest(flagName: flagName)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else {
                throw AppServerWebsocketAuthValidationError.invalidSHA256Digest(flagName: flagName)
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

public enum AppServerWebsocketAuthPolicyBuilder {
    public static func policy(from settings: AppServerWebsocketAuthSettings) throws -> AppServerWebsocketAuthPolicy {
        guard let config = settings.config else {
            return AppServerWebsocketAuthPolicy()
        }

        switch config {
        case let .capabilityToken(source):
            let tokenSHA256: [UInt8]
            switch source {
            case let .tokenFile(path):
                tokenSHA256 = sha256Digest(Array(try readTrimmedSecret(path: path).utf8))
            case let .tokenSHA256(digest):
                tokenSHA256 = digest
            }
            return AppServerWebsocketAuthPolicy(mode: .capabilityToken(tokenSHA256: tokenSHA256))

        case let .signedBearerToken(path, issuer, audience, maxClockSkewSeconds):
            guard maxClockSkewSeconds <= UInt64(Int64.max) else {
                throw AppServerWebsocketAuthValidationError.clockSkewTooLarge
            }
            let sharedSecret = Array(try readTrimmedSecret(path: path).utf8)
            guard sharedSecret.count >= AppServerWebsocketAuthValidator.minimumSignedBearerSecretBytes else {
                throw AppServerWebsocketAuthValidationError.shortSignedBearerSecret(path: path)
            }
            return AppServerWebsocketAuthPolicy(mode: .signedBearerToken(
                sharedSecret: sharedSecret,
                issuer: issuer,
                audience: audience,
                maxClockSkewSeconds: Int64(maxClockSkewSeconds)
            ))
        }
    }

    private static func readTrimmedSecret(path: String) throws -> String {
        let raw: String
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw AppServerWebsocketAuthValidationError.readSecretFailed(
                path: path,
                message: String(describing: error)
            )
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppServerWebsocketAuthValidationError.emptySecret(path: path)
        }
        return trimmed
    }
}

public enum AppServerWebsocketAuthorizationError: Error, CustomStringConvertible, Equatable, Sendable {
    case missingBearerToken
    case invalidAuthorizationHeader
    case invalidBearerToken
    case invalidJWT
    case expiredJWT
    case notYetValidJWT
    case issuerMismatch
    case audienceMismatch

    public var statusCode: Int { 401 }

    public var description: String {
        switch self {
        case .missingBearerToken:
            return "missing websocket bearer token"
        case .invalidAuthorizationHeader:
            return "invalid authorization header"
        case .invalidBearerToken:
            return "invalid websocket bearer token"
        case .invalidJWT:
            return "invalid websocket jwt"
        case .expiredJWT:
            return "expired websocket jwt"
        case .notYetValidJWT:
            return "websocket jwt is not valid yet"
        case .issuerMismatch:
            return "websocket jwt issuer mismatch"
        case .audienceMismatch:
            return "websocket jwt audience mismatch"
        }
    }
}

public enum AppServerWebsocketAuthorizer {
    public static func authorize(
        authorizationHeader: String?,
        policy: AppServerWebsocketAuthPolicy,
        now: Date = Date()
    ) -> AppServerWebsocketAuthorizationError? {
        guard let mode = policy.mode else {
            return nil
        }

        let token: String
        do {
            token = try bearerToken(from: authorizationHeader)
        } catch let error as AppServerWebsocketAuthorizationError {
            return error
        } catch {
            return .invalidAuthorizationHeader
        }

        switch mode {
        case let .capabilityToken(expectedSHA256):
            let actualSHA256 = sha256Digest(Array(token.utf8))
            return constantTimeEqual(expectedSHA256, actualSHA256) ? nil : .invalidBearerToken

        case let .signedBearerToken(sharedSecret, issuer, audience, maxClockSkewSeconds):
            return verifySignedBearerToken(
                token,
                sharedSecret: sharedSecret,
                issuer: issuer,
                audience: audience,
                maxClockSkewSeconds: maxClockSkewSeconds,
                now: now
            )
        }
    }

    private static func bearerToken(from header: String?) throws -> String {
        guard let header else {
            throw AppServerWebsocketAuthorizationError.missingBearerToken
        }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Bearer") == .orderedSame
        else {
            throw AppServerWebsocketAuthorizationError.invalidAuthorizationHeader
        }
        let token = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AppServerWebsocketAuthorizationError.invalidAuthorizationHeader
        }
        return token
    }

    private static func verifySignedBearerToken(
        _ token: String,
        sharedSecret: [UInt8],
        issuer: String?,
        audience: String?,
        maxClockSkewSeconds: Int64,
        now: Date
    ) -> AppServerWebsocketAuthorizationError? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = base64URLDecode(String(segments[0])),
              let claimsData = base64URLDecode(String(segments[1])),
              let signature = base64URLDecode(String(segments[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "HS256"
        else {
            return .invalidJWT
        }

        let signingInput = "\(segments[0]).\(segments[1])"
        let key = SymmetricKey(data: Data(sharedSecret))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        guard constantTimeEqual(Array(Data(mac)), Array(signature)) else {
            return .invalidJWT
        }

        guard let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let expiration = int64Claim(claims["exp"])
        else {
            return .invalidJWT
        }

        let nowSeconds = Int64(now.timeIntervalSince1970)
        if nowSeconds > expiration.saturatingAdd(maxClockSkewSeconds) {
            return .expiredJWT
        }
        if let notBefore = int64Claim(claims["nbf"]),
           nowSeconds < notBefore.saturatingSubtract(maxClockSkewSeconds) {
            return .notYetValidJWT
        }
        if let issuer, claims["iss"] as? String != issuer {
            return .issuerMismatch
        }
        if let audience,
           !audienceMatches(claims["aud"], expected: audience) {
            return .audienceMismatch
        }
        return nil
    }

    private static func audienceMatches(_ value: Any?, expected: String) -> Bool {
        if let value = value as? String {
            return value == expected
        }
        if let values = value as? [String] {
            return values.contains(expected)
        }
        return false
    }

    private static func int64Claim(_ value: Any?) -> Int64? {
        if value is Bool {
            return nil
        }
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? Double, value.rounded() == value {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }
            return value.int64Value
        }
        return nil
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

private func sha256Digest(_ bytes: [UInt8]) -> [UInt8] {
    Array(Data(SHA256.hash(data: Data(bytes))))
}

private func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    var difference: UInt8 = 0
    for index in lhs.indices {
        difference |= lhs[index] ^ rhs[index]
    }
    return difference == 0
}

private extension Int64 {
    func saturatingAdd(_ value: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(value)
        return overflow ? (value >= 0 ? Int64.max : Int64.min) : result
    }

    func saturatingSubtract(_ value: Int64) -> Int64 {
        let (result, overflow) = subtractingReportingOverflow(value)
        return overflow ? (value >= 0 ? Int64.min : Int64.max) : result
    }
}
