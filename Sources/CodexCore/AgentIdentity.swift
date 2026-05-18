import Foundation
import CryptoKit
import Security

public enum AgentIdentity {
    public static let jwtAudience = "codex-app-server"
    public static let jwtIssuer = "https://chatgpt.com/codex-backend/agent-identity"
    public static let requestIDByteCount = 16
    public static let agentPrivateKeyByteCount = 32

    public static func agentRegistrationURL(chatGPTBaseURL: String) -> String {
        "\(trimmedBaseURL(chatGPTBaseURL))/v1/agent/register"
    }

    public static func agentTaskRegistrationURL(chatGPTBaseURL: String, agentRuntimeID: String) -> String {
        "\(trimmedBaseURL(chatGPTBaseURL))/v1/agent/\(agentRuntimeID)/task/register"
    }

    public static func agentIdentityBiscuitURL(chatGPTBaseURL: String) -> String {
        "\(trimmedBaseURL(chatGPTBaseURL))/authenticate_app_v2"
    }

    public static func agentIdentityJWKSURL(chatGPTBaseURL: String) -> String {
        let trimmed = trimmedBaseURL(chatGPTBaseURL)
        if trimmed.contains("/backend-api") {
            return "\(trimmed)/wham/agent-identities/jwks"
        }
        return "\(trimmed)/agent-identities/jwks"
    }

    public static func agentIdentityRequestID() throws -> String {
        var bytes = [UInt8](repeating: 0, count: requestIDByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentIdentityError.randomBytesFailed(status)
        }
        return try agentIdentityRequestID(randomBytes: bytes)
    }

    public static func agentIdentityRequestID(randomBytes bytes: [UInt8]) throws -> String {
        guard bytes.count == requestIDByteCount else {
            throw AgentIdentityError.invalidRequestIDByteCount(bytes.count)
        }
        return "codex-agent-identity-\(PKCE.base64URLEncodedNoPadding(Data(bytes)))"
    }

    public static func buildABOM(
        sessionSource: SessionSource,
        agentVersion: String = CodexBuildMetadata.version,
        operatingSystem: String = currentOperatingSystemName
    ) -> AgentBillOfMaterials {
        AgentBillOfMaterials(
            agentVersion: agentVersion,
            agentHarnessID: sessionSource == .vscode ? "codex-app" : "codex-cli",
            runningLocation: "\(sessionSource.description)-\(operatingSystem)"
        )
    }

    public static func generateAgentKeyMaterial() throws -> GeneratedAgentKeyMaterial {
        var bytes = [UInt8](repeating: 0, count: agentPrivateKeyByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentIdentityError.message("failed to generate agent identity private key bytes")
        }
        return try generateAgentKeyMaterial(privateKeyBytes: bytes)
    }

    static func generateAgentKeyMaterial(privateKeyBytes bytes: [UInt8]) throws -> GeneratedAgentKeyMaterial {
        guard bytes.count == agentPrivateKeyByteCount else {
            throw AgentIdentityError.invalidPrivateKeyByteCount(bytes.count)
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(bytes))
        let privateKeyPKCS8 = ed25519PKCS8PrivateKey(seed: privateKey.rawRepresentation)
        return GeneratedAgentKeyMaterial(
            privateKeyPKCS8Base64: privateKeyPKCS8.base64EncodedString(),
            publicKeySSH: encodeSSHEd25519PublicKey(publicKey: privateKey.publicKey)
        )
    }

    public static func publicKeySSH(privateKeyPKCS8Base64: String) throws -> String {
        let privateKey = try signingPrivateKeyFromPKCS8Base64(privateKeyPKCS8Base64)
        return encodeSSHEd25519PublicKey(publicKey: privateKey.publicKey)
    }

    public static func signTaskRegistrationPayload(key: AgentIdentityKey, timestamp: String) throws -> String {
        let signingKey = try signingPrivateKeyFromPKCS8Base64(key.privateKeyPKCS8Base64)
        let signature = try signingKey.signature(for: Data("\(key.agentRuntimeID):\(timestamp)".utf8))
        return signature.base64EncodedString()
    }

    public static func registerAgentTask<Transport: APITransport>(
        transport: Transport,
        chatGPTBaseURL: String,
        key: AgentIdentityKey
    ) async throws -> String {
        try await registerAgentTask(
            transport: transport,
            chatGPTBaseURL: chatGPTBaseURL,
            key: key,
            timestamp: currentTimestamp()
        )
    }

    static func registerAgentTask<Transport: APITransport>(
        transport: Transport,
        chatGPTBaseURL: String,
        key: AgentIdentityKey,
        timestamp: String
    ) async throws -> String {
        let request = APIRequest(
            method: .post,
            url: agentTaskRegistrationURL(chatGPTBaseURL: chatGPTBaseURL, agentRuntimeID: key.agentRuntimeID),
            body: .object([
                "signature": .string(try signTaskRegistrationPayload(key: key, timestamp: timestamp)),
                "timestamp": .string(timestamp),
            ]),
            timeoutMilliseconds: 30_000
        )

        let response: APIResponse
        switch await transport.execute(request) {
        case let .success(success):
            response = success
        case let .failure(.http(statusCode, _, _, body)):
            throw AgentIdentityError.message(
                "failed to register agent task with status \(HTTPStatus.description(for: statusCode)): \(truncatedTaskRegistrationBody(body))"
            )
        case .failure:
            throw AgentIdentityError.message("failed to register agent task")
        }

        let decoded: RegisterTaskResponse
        do {
            decoded = try JSONDecoder().decode(RegisterTaskResponse.self, from: response.body)
        } catch {
            throw AgentIdentityError.message("failed to decode agent task registration response")
        }
        return try taskID(from: decoded, key: key)
    }

    public static func authorizationHeaderForAgentTask(
        key: AgentIdentityKey,
        target: AgentTaskAuthorizationTarget
    ) throws -> String {
        try authorizationHeaderForAgentTask(key: key, target: target, timestamp: currentTimestamp())
    }

    static func authorizationHeaderForAgentTask(
        key: AgentIdentityKey,
        target: AgentTaskAuthorizationTarget,
        timestamp: String
    ) throws -> String {
        guard key.agentRuntimeID == target.agentRuntimeID else {
            throw AgentIdentityError.message(
                "agent task runtime \(target.agentRuntimeID) does not match stored agent identity \(key.agentRuntimeID)"
            )
        }
        let signature = try signAgentAssertionPayload(key: key, taskID: target.taskID, timestamp: timestamp)
        let envelope = AgentAssertionEnvelope(
            agentRuntimeID: target.agentRuntimeID,
            taskID: target.taskID,
            timestamp: timestamp,
            signature: signature
        )
        return "AgentAssertion \(try serializeAgentAssertion(envelope))"
    }

    public static func decodeJWTClaims(_ jwt: String, jwks: AgentIdentityJWKS? = nil, now: Date = Date()) throws -> AgentIdentityJWTClaims {
        if let jwks {
            return try decodeAndVerifyJWTClaims(jwt, jwks: jwks, now: now)
        }
        return try decodeJWTClaimsPayload(jwt)
    }

    private static func decodeJWTClaimsPayload(_ jwt: String) throws -> AgentIdentityJWTClaims {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
            throw AgentIdentityError.message("invalid agent identity JWT format")
        }

        let payloadBytes: Data
        do {
            payloadBytes = try base64URLDecodeNoPadding(String(parts[1]))
        } catch {
            throw AgentIdentityError.message("agent identity JWT payload is not valid base64url")
        }

        do {
            return try JSONDecoder().decode(AgentIdentityJWTClaims.self, from: payloadBytes)
        } catch {
            throw AgentIdentityError.message("agent identity JWT payload is not valid JSON")
        }
    }

    private static func decodeAndVerifyJWTClaims(
        _ jwt: String,
        jwks: AgentIdentityJWKS,
        now: Date
    ) throws -> AgentIdentityJWTClaims {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
            throw AgentIdentityError.message("failed to decode agent identity JWT header")
        }

        let headerData: Data
        do {
            headerData = try base64URLDecodeNoPadding(String(parts[0]))
        } catch {
            throw AgentIdentityError.message("failed to decode agent identity JWT header")
        }

        let header: AgentIdentityJWTHeader
        do {
            header = try JSONDecoder().decode(AgentIdentityJWTHeader.self, from: headerData)
        } catch {
            throw AgentIdentityError.message("failed to decode agent identity JWT header")
        }

        guard let kid = header.kid else {
            throw AgentIdentityError.message("agent identity JWT header does not include a kid")
        }
        guard header.alg == "RS256" else {
            throw AgentIdentityError.message("failed to verify agent identity JWT")
        }
        guard let jwk = jwks.keys.first(where: { $0.kid == kid }) else {
            throw AgentIdentityError.message("agent identity JWT kid \(kid) is not trusted")
        }
        guard jwk.kty == "RSA" else {
            throw AgentIdentityError.message("failed to build JWT decoding key")
        }

        let publicKey: SecKey
        do {
            publicKey = try rsaPublicKey(from: jwk)
        } catch {
            throw AgentIdentityError.message("failed to build JWT decoding key")
        }

        let signature: Data
        do {
            signature = try base64URLDecodeNoPadding(String(parts[2]))
        } catch {
            throw AgentIdentityError.message("failed to verify agent identity JWT")
        }

        let signingInput = "\(parts[0]).\(parts[1])"
        guard SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            signature as CFData,
            nil
        ) else {
            throw AgentIdentityError.message("failed to verify agent identity JWT")
        }

        let rawClaims: [String: Any]
        do {
            rawClaims = try jwtPayloadObject(String(parts[1]))
        } catch {
            throw AgentIdentityError.message("agent identity JWT payload is not valid JSON")
        }
        guard rawClaims["iss"] as? String == jwtIssuer,
              rawClaims["aud"] as? String == jwtAudience,
              let expiration = numericDate(rawClaims["exp"]),
              Date(timeIntervalSince1970: TimeInterval(expiration)) > now
        else {
            throw AgentIdentityError.message("failed to verify agent identity JWT")
        }

        let claims = try decodeJWTClaimsPayload(jwt)
        return claims
    }

    public static var currentOperatingSystemName: String {
        #if os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }

    private static func trimmedBaseURL(_ baseURL: String) -> String {
        var trimmed = baseURL
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func base64URLDecodeNoPadding(_ value: String) throws -> Data {
        guard !value.contains("=") else {
            throw AgentIdentityError.message("agent identity JWT payload is not valid base64url")
        }
        guard value.utf8.allSatisfy({ byte in
            (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45
                || byte == 95
        }) else {
            throw AgentIdentityError.message("agent identity JWT payload is not valid base64url")
        }

        var standard = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch standard.count % 4 {
        case 0:
            break
        case 2:
            standard.append("==")
        case 3:
            standard.append("=")
        default:
            throw AgentIdentityError.message("agent identity JWT payload is not valid base64url")
        }

        guard let data = Data(base64Encoded: standard) else {
            throw AgentIdentityError.message("agent identity JWT payload is not valid base64url")
        }
        return data
    }

    private static func jwtPayloadObject(_ payloadSegment: String) throws -> [String: Any] {
        let payloadBytes = try base64URLDecodeNoPadding(payloadSegment)
        guard let object = try JSONSerialization.jsonObject(with: payloadBytes) as? [String: Any] else {
            throw AgentIdentityError.message("agent identity JWT payload is not valid JSON")
        }
        return object
    }

    private static func numericDate(_ value: Any?) -> Int64? {
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

    private static func taskID(from response: RegisterTaskResponse, key: AgentIdentityKey) throws -> String {
        if let taskID = response.taskID ?? response.taskIDCamel {
            return taskID
        }
        if let encryptedTaskID = response.encryptedTaskID ?? response.encryptedTaskIDCamel {
            return try decryptTaskIDResponse(key: key, encryptedTaskID: encryptedTaskID)
        }
        throw AgentIdentityError.message("agent task registration response omitted task id")
    }

    private static func decryptTaskIDResponse(key: AgentIdentityKey, encryptedTaskID: String) throws -> String {
        let signingKey = try signingPrivateKeyFromPKCS8Base64(key.privateKeyPKCS8Base64)
        guard let ciphertext = Data(base64Encoded: encryptedTaskID) else {
            throw AgentIdentityError.message("encrypted task id is not valid base64")
        }
        let secretKey = curve25519SecretKey(from: signingKey)
        let plaintext: Data
        do {
            plaintext = try NaClSealedBox.open(ciphertext: ciphertext, recipientSecretKey: secretKey)
        } catch {
            throw AgentIdentityError.message("failed to decrypt encrypted task id")
        }
        guard let taskID = String(data: plaintext, encoding: .utf8) else {
            throw AgentIdentityError.message("decrypted task id is not valid UTF-8")
        }
        return taskID
    }

    private static func truncatedTaskRegistrationBody(_ body: String?) -> String {
        guard let body else {
            return ""
        }
        guard body.count > 512 else {
            return body
        }
        return "\(String(body.prefix(512)))..."
    }

    private static func signingPrivateKeyFromPKCS8Base64(_ privateKeyPKCS8Base64: String) throws -> Curve25519.Signing.PrivateKey {
        let privateKeyDER: Data
        guard let decoded = Data(base64Encoded: privateKeyPKCS8Base64) else {
            throw AgentIdentityError.message("stored agent identity private key is not valid base64")
        }
        privateKeyDER = decoded
        guard let seed = ed25519SeedFromPKCS8PrivateKey(privateKeyDER) else {
            throw AgentIdentityError.message("stored agent identity private key is not valid PKCS#8")
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            throw AgentIdentityError.message("stored agent identity private key is not valid PKCS#8")
        }
    }

    private static func ed25519PKCS8PrivateKey(seed: Data) -> Data {
        Data([
            0x30, 0x2e,
            0x02, 0x01, 0x00,
            0x30, 0x05,
            0x06, 0x03, 0x2b, 0x65, 0x70,
            0x04, 0x22,
            0x04, 0x20,
        ]) + seed
    }

    private static func ed25519SeedFromPKCS8PrivateKey(_ der: Data) -> Data? {
        let prefix = Data([
            0x30, 0x2e,
            0x02, 0x01, 0x00,
            0x30, 0x05,
            0x06, 0x03, 0x2b, 0x65, 0x70,
            0x04, 0x22,
            0x04, 0x20,
        ])
        guard der.count == prefix.count + agentPrivateKeyByteCount,
              der.starts(with: prefix)
        else {
            return nil
        }
        return der.suffix(agentPrivateKeyByteCount)
    }

    private static func curve25519SecretKey(from signingKey: Curve25519.Signing.PrivateKey) -> Data {
        var digest = Array(SHA512.hash(data: signingKey.rawRepresentation))
        digest[0] &= 248
        digest[31] &= 127
        digest[31] |= 64
        return Data(digest.prefix(32))
    }

    private static func encodeSSHEd25519PublicKey(publicKey: Curve25519.Signing.PublicKey) -> String {
        var blob = Data()
        appendSSHString(Data("ssh-ed25519".utf8), to: &blob)
        appendSSHString(publicKey.rawRepresentation, to: &blob)
        return "ssh-ed25519 \(blob.base64EncodedString())"
    }

    private static func appendSSHString(_ value: Data, to data: inout Data) {
        data.append(UInt8((value.count >> 24) & 0xff))
        data.append(UInt8((value.count >> 16) & 0xff))
        data.append(UInt8((value.count >> 8) & 0xff))
        data.append(UInt8(value.count & 0xff))
        data.append(value)
    }

    private static func signAgentAssertionPayload(key: AgentIdentityKey, taskID: String, timestamp: String) throws -> String {
        let signingKey = try signingPrivateKeyFromPKCS8Base64(key.privateKeyPKCS8Base64)
        let signature = try signingKey.signature(for: Data("\(key.agentRuntimeID):\(taskID):\(timestamp)".utf8))
        return signature.base64EncodedString()
    }

    private static func serializeAgentAssertion(_ envelope: AgentAssertionEnvelope) throws -> String {
        let payload = """
        {"agent_runtime_id":\(jsonString(envelope.agentRuntimeID)),"signature":\(jsonString(envelope.signature)),"task_id":\(jsonString(envelope.taskID)),"timestamp":\(jsonString(envelope.timestamp))}
        """
        return PKCE.base64URLEncodedNoPadding(Data(payload.utf8))
    }

    private static func jsonString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{08}":
                result += "\\b"
            case "\u{0c}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result += String(scalar)
                }
            }
        }
        result += "\""
        return result
    }

    private static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func rsaPublicKey(from jwk: AgentIdentityJWK) throws -> SecKey {
        let modulus = try base64URLDecodeNoPadding(jwk.n)
        let exponent = try base64URLDecodeNoPadding(jwk.e)
        let der = asn1Sequence([
            asn1Integer(modulus),
            asn1Integer(exponent),
        ])
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? AgentIdentityError.message("failed to build JWT decoding key")
        }
        return key
    }

    private static func asn1Sequence(_ values: [Data]) -> Data {
        let body = values.reduce(into: Data()) { result, value in
            result.append(value)
        }
        return asn1(tag: 0x30, body: body)
    }

    private static func asn1Integer(_ value: Data) -> Data {
        var body = value
        while body.count > 1, body.first == 0, let next = body.dropFirst().first, next < 0x80 {
            body.removeFirst()
        }
        if let first = body.first, first >= 0x80 {
            body.insert(0, at: 0)
        }
        return asn1(tag: 0x02, body: body)
    }

    private static func asn1(tag: UInt8, body: Data) -> Data {
        var data = Data([tag])
        data.append(asn1Length(body.count))
        data.append(body)
        return data
    }

    private static func asn1Length(_ length: Int) -> Data {
        guard length >= 0x80 else {
            return Data([UInt8(length)])
        }
        var bytes: [UInt8] = []
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

public struct AgentIdentityKey: Equatable, Sendable {
    public let agentRuntimeID: String
    public let privateKeyPKCS8Base64: String

    public init(agentRuntimeID: String, privateKeyPKCS8Base64: String) {
        self.agentRuntimeID = agentRuntimeID
        self.privateKeyPKCS8Base64 = privateKeyPKCS8Base64
    }
}

public struct AgentTaskAuthorizationTarget: Equatable, Sendable {
    public let agentRuntimeID: String
    public let taskID: String

    public init(agentRuntimeID: String, taskID: String) {
        self.agentRuntimeID = agentRuntimeID
        self.taskID = taskID
    }
}

public struct AgentBillOfMaterials: Codable, Equatable, Sendable {
    public let agentVersion: String
    public let agentHarnessID: String
    public let runningLocation: String

    public init(agentVersion: String, agentHarnessID: String, runningLocation: String) {
        self.agentVersion = agentVersion
        self.agentHarnessID = agentHarnessID
        self.runningLocation = runningLocation
    }

    private enum CodingKeys: String, CodingKey {
        case agentVersion = "agent_version"
        case agentHarnessID = "agent_harness_id"
        case runningLocation = "running_location"
    }
}

public struct GeneratedAgentKeyMaterial: Equatable, Sendable {
    public let privateKeyPKCS8Base64: String
    public let publicKeySSH: String

    public init(privateKeyPKCS8Base64: String, publicKeySSH: String) {
        self.privateKeyPKCS8Base64 = privateKeyPKCS8Base64
        self.publicKeySSH = publicKeySSH
    }
}

public struct AgentIdentityJWTClaims: Decodable, Equatable, Sendable {
    public let iss: String
    public let aud: String
    public let iat: Int
    public let exp: Int
    public let agentRuntimeID: String
    public let agentPrivateKey: String
    public let accountID: String
    public let chatGPTUserID: String
    public let email: String
    public let planType: PlanType
    public let chatGPTAccountIsFedRAMP: Bool

    public init(
        iss: String,
        aud: String,
        iat: Int,
        exp: Int,
        agentRuntimeID: String,
        agentPrivateKey: String,
        accountID: String,
        chatGPTUserID: String,
        email: String,
        planType: PlanType,
        chatGPTAccountIsFedRAMP: Bool
    ) {
        self.iss = iss
        self.aud = aud
        self.iat = iat
        self.exp = exp
        self.agentRuntimeID = agentRuntimeID
        self.agentPrivateKey = agentPrivateKey
        self.accountID = accountID
        self.chatGPTUserID = chatGPTUserID
        self.email = email
        self.planType = planType
        self.chatGPTAccountIsFedRAMP = chatGPTAccountIsFedRAMP
    }

    private enum CodingKeys: String, CodingKey {
        case iss
        case aud
        case iat
        case exp
        case agentRuntimeID = "agent_runtime_id"
        case agentPrivateKey = "agent_private_key"
        case accountID = "account_id"
        case chatGPTUserID = "chatgpt_user_id"
        case email
        case planType = "plan_type"
        case chatGPTAccountIsFedRAMP = "chatgpt_account_is_fedramp"
    }
}

public struct AgentIdentityJWKS: Decodable, Equatable, Sendable {
    public let keys: [AgentIdentityJWK]

    public init(keys: [AgentIdentityJWK]) {
        self.keys = keys
    }
}

public struct AgentIdentityJWK: Decodable, Equatable, Sendable {
    public let kty: String
    public let kid: String?
    public let use: String?
    public let alg: String?
    public let n: String
    public let e: String

    public init(kty: String, kid: String?, use: String?, alg: String?, n: String, e: String) {
        self.kty = kty
        self.kid = kid
        self.use = use
        self.alg = alg
        self.n = n
        self.e = e
    }
}

private struct AgentIdentityJWTHeader: Decodable {
    let alg: String?
    let kid: String?
}

private struct RegisterTaskResponse: Decodable {
    let taskID: String?
    let taskIDCamel: String?
    let encryptedTaskID: String?
    let encryptedTaskIDCamel: String?

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case taskIDCamel = "taskId"
        case encryptedTaskID = "encrypted_task_id"
        case encryptedTaskIDCamel = "encryptedTaskId"
    }
}

private struct AgentAssertionEnvelope: Encodable {
    let agentRuntimeID: String
    let taskID: String
    let timestamp: String
    let signature: String

    private enum CodingKeys: String, CodingKey {
        case agentRuntimeID = "agent_runtime_id"
        case signature
        case taskID = "task_id"
        case timestamp
    }
}

public enum AgentIdentityError: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case invalidRequestIDByteCount(Int)
    case invalidPrivateKeyByteCount(Int)
    case randomBytesFailed(OSStatus)

    public var description: String {
        switch self {
        case let .message(message):
            return message
        case let .invalidRequestIDByteCount(count):
            return "agent identity request id generation requires 16 random bytes, got \(count)"
        case let .invalidPrivateKeyByteCount(count):
            return "agent identity key generation requires 32 private key bytes, got \(count)"
        case let .randomBytesFailed(status):
            return "failed to generate agent identity request id: OSStatus \(status)"
        }
    }
}
