import CryptoKit
import Foundation

public enum CloudRequirements {
    public static let timeout: TimeInterval = 15
    public static let maxAttempts = 5
    public static let cacheRefreshInterval: TimeInterval = 5 * 60
    public static let fetchAttemptMetricName = "codex.cloud_requirements.fetch_attempt"
    public static let fetchFinalMetricName = "codex.cloud_requirements.fetch_final"
    public static let loadMetricName = "codex.cloud_requirements.load"
    public static let loadFailedMessage = "Failed to load cloud requirements (workspace-managed policies)."
    public static let parseFailedMessagePrefix = "Cloud requirements (workspace-managed policies) are invalid and could not be parsed. Please contact your workspace admin."
    public static let authRecoveryFailedMessage = "Your authentication session could not be refreshed automatically. Please log out and sign in again."
    public static let cacheFilename = "cloud-requirements-cache.json"
    public static let cacheTTL: TimeInterval = 30 * 60

    private static let cacheSigningKey = SymmetricKey(
        data: Data("codex-cloud-requirements-cache-v3-064f8542-75b4-494c-a294-97d3ce597271".utf8)
    )

    public static func parse(_ contents: String) throws -> ConfigRequirementsToml? {
        guard contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let requirements = try ConfigRequirementsToml.parse(contents)
        return requirements.isEmpty ? nil : requirements
    }

    public static func parseFailedMessage(details: Error) -> String {
        "\(parseFailedMessagePrefix)\n\nDetails:\n\(details)"
    }

    public static func isEligibleAuth(planType: PlanType?, usesCodexBackend: Bool) -> Bool {
        guard usesCodexBackend, let planType else {
            return false
        }
        return planType.isBusinessLike || planType == .enterprise
    }

    public static func statusCodeTag(_ statusCode: Int?) -> String {
        statusCode.map(String.init) ?? "none"
    }

    public static func cachePayloadBytes(_ payload: CloudRequirementsCacheSignedPayload) throws -> Data {
        Data(cachePayloadJSONString(payload).utf8)
    }

    public static func signCachePayload(_ payloadBytes: Data) -> String {
        let signature = HMAC<SHA256>.authenticationCode(for: payloadBytes, using: cacheSigningKey)
        return Data(signature).base64EncodedString()
    }

    public static func verifyCacheSignature(payloadBytes: Data, signature: String) -> Bool {
        guard let signatureBytes = Data(base64Encoded: signature) else {
            return false
        }
        let expected = HMAC<SHA256>.authenticationCode(for: payloadBytes, using: cacheSigningKey)
        return constantTimeEqual(Array(signatureBytes), Array(Data(expected)))
    }

    public static func loadCacheFileData(
        _ data: Data,
        chatgptUserID: String?,
        accountID: String?,
        now: Date = Date()
    ) throws -> CloudRequirementsCacheSignedPayload {
        guard let chatgptUserID, let accountID else {
            throw CloudRequirementsCacheLoadStatus.authIdentityIncomplete
        }

        let cacheFile: CloudRequirementsCacheFile
        do {
            cacheFile = try JSONDecoder().decode(CloudRequirementsCacheFile.self, from: data)
        } catch {
            throw CloudRequirementsCacheLoadStatus.cacheParseFailed(String(describing: error))
        }

        let payloadBytes: Data
        do {
            payloadBytes = try cachePayloadBytes(cacheFile.signedPayload)
        } catch {
            throw CloudRequirementsCacheLoadStatus.cacheParseFailed("failed to serialize cache payload")
        }

        guard verifyCacheSignature(payloadBytes: payloadBytes, signature: cacheFile.signature) else {
            throw CloudRequirementsCacheLoadStatus.cacheSignatureInvalid
        }
        guard let cachedChatGPTUserID = cacheFile.signedPayload.chatgptUserID,
              let cachedAccountID = cacheFile.signedPayload.accountID
        else {
            throw CloudRequirementsCacheLoadStatus.cacheIdentityIncomplete
        }
        guard cachedChatGPTUserID == chatgptUserID, cachedAccountID == accountID else {
            throw CloudRequirementsCacheLoadStatus.cacheIdentityMismatch
        }
        guard cacheFile.signedPayload.isExpired(now: now) == false else {
            throw CloudRequirementsCacheLoadStatus.cacheExpired
        }

        return cacheFile.signedPayload
    }

    public static func loadCacheFile(
        at path: URL,
        chatgptUserID: String?,
        accountID: String?,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> CloudRequirementsCacheSignedPayload {
        guard chatgptUserID != nil, accountID != nil else {
            throw CloudRequirementsCacheLoadStatus.authIdentityIncomplete
        }
        guard fileManager.fileExists(atPath: path.path) else {
            throw CloudRequirementsCacheLoadStatus.cacheFileNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw CloudRequirementsCacheLoadStatus.cacheReadFailed(error.localizedDescription)
        }

        return try loadCacheFileData(
            data,
            chatgptUserID: chatgptUserID,
            accountID: accountID,
            now: now
        )
    }

    public static func saveCacheFile(
        at path: URL,
        cachedAt: Date = Date(),
        chatgptUserID: String?,
        accountID: String?,
        contents: String?,
        fileManager: FileManager = .default
    ) throws {
        let cacheFile: CloudRequirementsCacheFile
        let data: Data
        do {
            cacheFile = try makeCacheFile(
                cachedAt: cachedAt,
                chatgptUserID: chatgptUserID,
                accountID: accountID,
                contents: contents
            )
            data = try prettyCacheFileData(cacheFile)
        } catch {
            throw CloudRequirementsCacheWriteError.cacheWrite
        }

        do {
            let parent = path.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: path)
        } catch {
            throw CloudRequirementsCacheWriteError.cacheWrite
        }
    }

    public static func makeCacheFile(
        cachedAt: Date,
        chatgptUserID: String?,
        accountID: String?,
        contents: String?
    ) throws -> CloudRequirementsCacheFile {
        let payload = CloudRequirementsCacheSignedPayload(
            cachedAt: cachedAt,
            expiresAt: cachedAt.addingTimeInterval(cacheTTL),
            chatgptUserID: chatgptUserID,
            accountID: accountID,
            contents: contents
        )
        let payloadBytes = try cachePayloadBytes(payload)
        return CloudRequirementsCacheFile(
            signedPayload: payload,
            signature: signCachePayload(payloadBytes)
        )
    }

    public static func prettyCacheFileData(_ cacheFile: CloudRequirementsCacheFile) throws -> Data {
        try prettyCacheFileEncoder.encode(cacheFile)
    }

    private static let cachePayloadEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom(rfc3339DateEncoding)
        return encoder
    }()

    private static let prettyCacheFileEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom(rfc3339DateEncoding)
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()

    private static func rfc3339DateEncoding(_ date: Date, encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rfc3339String(from: date))
    }

    private static func cachePayloadJSONString(_ payload: CloudRequirementsCacheSignedPayload) -> String {
        "{"
            + "\"cached_at\":\(jsonStringLiteral(rfc3339String(from: payload.cachedAt))),"
            + "\"expires_at\":\(jsonStringLiteral(rfc3339String(from: payload.expiresAt))),"
            + "\"chatgpt_user_id\":\(jsonOptionalStringLiteral(payload.chatgptUserID)),"
            + "\"account_id\":\(jsonOptionalStringLiteral(payload.accountID)),"
            + "\"contents\":\(jsonOptionalStringLiteral(payload.contents))"
            + "}"
    }

    private static func jsonOptionalStringLiteral(_ value: String?) -> String {
        guard let value else {
            return "null"
        }
        return jsonStringLiteral(value)
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? cachePayloadEncoder.encode(value) else {
            return String(reflecting: value)
        }
        return String(decoding: data, as: UTF8.self)
    }

    fileprivate static func rfc3339Date(from string: String) -> Date? {
        makeRFC3339Formatter(formatOptions: [.withInternetDateTime]).date(from: string)
            ?? makeRFC3339Formatter(formatOptions: [.withInternetDateTime, .withFractionalSeconds]).date(from: string)
    }

    fileprivate static func rfc3339String(from date: Date) -> String {
        let roundedToSecond = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.towardZero))
        let formatOptions: ISO8601DateFormatter.Options = abs(date.timeIntervalSince(roundedToSecond)) < 0.000_001
            ? [.withInternetDateTime]
            : [.withInternetDateTime, .withFractionalSeconds]
        return rfc3339String(from: date, formatOptions: formatOptions)
    }

    private static func rfc3339String(
        from date: Date,
        formatOptions: ISO8601DateFormatter.Options
    ) -> String {
        makeRFC3339Formatter(formatOptions: formatOptions).string(from: date)
    }

    private static func makeRFC3339Formatter(
        formatOptions: ISO8601DateFormatter.Options
    ) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        return formatter
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

public enum CloudRequirementsCacheWriteError: Error, Equatable, CustomStringConvertible, Sendable {
    case cacheWrite

    public var description: String {
        "failed to write cloud requirements cache"
    }
}

public enum CloudRequirementsRetryableFailureKind: Equatable, Sendable {
    case backendClientInit
    case request(statusCode: Int?)

    public var statusCode: Int? {
        switch self {
        case .backendClientInit:
            nil
        case let .request(statusCode):
            statusCode
        }
    }
}

public enum CloudRequirementsFetchAttemptError: Error, Equatable, Sendable {
    case retryable(CloudRequirementsRetryableFailureKind)
    case unauthorized(statusCode: Int?, message: String)

    public var statusCode: Int? {
        switch self {
        case let .retryable(kind):
            kind.statusCode
        case let .unauthorized(statusCode, _):
            statusCode
        }
    }
}

public enum CloudRequirementsCacheLoadStatus: Error, Equatable, CustomStringConvertible, Sendable {
    case authIdentityIncomplete
    case cacheFileNotFound
    case cacheReadFailed(String)
    case cacheParseFailed(String)
    case cacheSignatureInvalid
    case cacheIdentityIncomplete
    case cacheIdentityMismatch
    case cacheExpired

    public var description: String {
        switch self {
        case .authIdentityIncomplete:
            return "Skipping cloud requirements cache read because auth identity is incomplete."
        case .cacheFileNotFound:
            return "Cloud requirements cache file not found."
        case let .cacheReadFailed(message):
            return "Failed to read cloud requirements cache: \(message)."
        case let .cacheParseFailed(message):
            return "Failed to parse cloud requirements cache: \(message)."
        case .cacheSignatureInvalid:
            return "Cloud requirements cache failed signature verification."
        case .cacheIdentityIncomplete:
            return "Ignoring cloud requirements cache because cached identity is incomplete."
        case .cacheIdentityMismatch:
            return "Ignoring cloud requirements cache for different auth identity."
        case .cacheExpired:
            return "Cloud requirements cache expired."
        }
    }
}

public struct CloudRequirementsCacheFile: Codable, Equatable, Sendable {
    public var signedPayload: CloudRequirementsCacheSignedPayload
    public var signature: String

    public init(signedPayload: CloudRequirementsCacheSignedPayload, signature: String) {
        self.signedPayload = signedPayload
        self.signature = signature
    }

    private enum CodingKeys: String, CodingKey {
        case signedPayload = "signed_payload"
        case signature
    }
}

public struct CloudRequirementsCacheSignedPayload: Codable, Equatable, Sendable {
    public var cachedAt: Date
    public var expiresAt: Date
    public var chatgptUserID: String?
    public var accountID: String?
    public var contents: String?

    public init(
        cachedAt: Date,
        expiresAt: Date,
        chatgptUserID: String?,
        accountID: String?,
        contents: String?
    ) {
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
        self.chatgptUserID = chatgptUserID
        self.accountID = accountID
        self.contents = contents
    }

    public func requirements() -> ConfigRequirementsToml? {
        contents.flatMap { try? CloudRequirements.parse($0) }
    }

    public func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    private enum CodingKeys: String, CodingKey {
        case cachedAt = "cached_at"
        case expiresAt = "expires_at"
        case chatgptUserID = "chatgpt_user_id"
        case accountID = "account_id"
        case contents
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CloudRequirements.rfc3339String(from: cachedAt), forKey: .cachedAt)
        try container.encode(CloudRequirements.rfc3339String(from: expiresAt), forKey: .expiresAt)
        try container.encode(chatgptUserID, forKey: .chatgptUserID)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(contents, forKey: .contents)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cachedAt = try Self.decodeDate(forKey: .cachedAt, in: container)
        expiresAt = try Self.decodeDate(forKey: .expiresAt, in: container)
        chatgptUserID = try container.decodeIfPresent(String.self, forKey: .chatgptUserID)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        contents = try container.decodeIfPresent(String.self, forKey: .contents)
    }

    private static func decodeDate(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)
        guard let date = CloudRequirements.rfc3339Date(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected RFC3339 date string"
            )
        }
        return date
    }
}
