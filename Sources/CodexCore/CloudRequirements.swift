import CryptoKit
import Foundation

public enum CloudRequirements {
    public static let loadFailedMessage = "Failed to load cloud requirements (workspace-managed policies)."
    public static let parseFailedMessagePrefix = "Cloud requirements (workspace-managed policies) are invalid and could not be parsed. Please contact your workspace admin."
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
