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
        }
    }
}

public enum AppServerWebsocketAuthValidator {
    public static let defaultMaxClockSkewSeconds: UInt64 = 30

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
