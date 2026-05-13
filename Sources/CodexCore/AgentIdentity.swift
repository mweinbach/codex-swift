import Foundation
import Security

public enum AgentIdentity {
    public static let jwtAudience = "codex-app-server"
    public static let jwtIssuer = "https://chatgpt.com/codex-backend/agent-identity"
    public static let requestIDByteCount = 16

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
        agentVersion: String = "0.0.0",
        operatingSystem: String = currentOperatingSystemName
    ) -> AgentBillOfMaterials {
        AgentBillOfMaterials(
            agentVersion: agentVersion,
            agentHarnessID: sessionSource == .vscode ? "codex-app" : "codex-cli",
            runningLocation: "\(sessionSource.description)-\(operatingSystem)"
        )
    }

    public static func decodeJWTClaims(_ jwt: String) throws -> AgentIdentityJWTClaims {
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

public enum AgentIdentityError: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case invalidRequestIDByteCount(Int)
    case randomBytesFailed(OSStatus)

    public var description: String {
        switch self {
        case let .message(message):
            return message
        case let .invalidRequestIDByteCount(count):
            return "agent identity request id generation requires 16 random bytes, got \(count)"
        case let .randomBytesFailed(status):
            return "failed to generate agent identity request id: OSStatus \(status)"
        }
    }
}
