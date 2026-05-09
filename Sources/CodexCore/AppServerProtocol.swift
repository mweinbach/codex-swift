import Foundation

public enum AppServerProtocol {
    public enum ServerRequest: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, params: Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(requestID: RequestID, params: ChatGPTAuthTokensRefreshParams)
        case execCommandApproval(requestID: RequestID, params: ExecCommandApprovalParams)
        case applyPatchApproval(requestID: RequestID, params: ApplyPatchApprovalParams)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            case let .execCommandApproval(requestID, _):
                requestID
            case let .applyPatchApproval(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
            case .execCommandApproval:
                ExecCommandApprovalParams.method
            case .applyPatchApproval:
                ApplyPatchApprovalParams.method
            }
        }

        private enum CodingKeys: String, CodingKey {
            case method
            case id
            case params
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            switch method {
            case Attestation.generateMethod:
                self = .attestationGenerate(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(Attestation.GenerateParams.self, forKey: .params)
                )
            case ChatGPTAuthTokensRefreshParams.method:
                self = .chatGPTAuthTokensRefresh(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ChatGPTAuthTokensRefreshParams.self, forKey: .params)
                )
            case ExecCommandApprovalParams.method:
                self = .execCommandApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ExecCommandApprovalParams.self, forKey: .params)
                )
            case ApplyPatchApprovalParams.method:
                self = .applyPatchApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    params: try container.decode(ApplyPatchApprovalParams.self, forKey: .params)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "unknown app-server request method: \(method)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(method, forKey: .method)
            try container.encode(id, forKey: .id)
            switch self {
            case let .attestationGenerate(_, params):
                try container.encode(params, forKey: .params)
            case let .chatGPTAuthTokensRefresh(_, params):
                try container.encode(params, forKey: .params)
            case let .execCommandApproval(_, params):
                try container.encode(params, forKey: .params)
            case let .applyPatchApproval(_, params):
                try container.encode(params, forKey: .params)
            }
        }
    }

    public enum ServerRequestPayload: Equatable, Sendable {
        case attestationGenerate(Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(ChatGPTAuthTokensRefreshParams)
        case execCommandApproval(ExecCommandApprovalParams)
        case applyPatchApproval(ApplyPatchApprovalParams)

        public static func attestationGenerate() -> ServerRequestPayload {
            .attestationGenerate(Attestation.GenerateParams())
        }

        public func request(withID id: RequestID) -> ServerRequest {
            switch self {
            case let .attestationGenerate(params):
                .attestationGenerate(requestID: id, params: params)
            case let .chatGPTAuthTokensRefresh(params):
                .chatGPTAuthTokensRefresh(requestID: id, params: params)
            case let .execCommandApproval(params):
                .execCommandApproval(requestID: id, params: params)
            case let .applyPatchApproval(params):
                .applyPatchApproval(requestID: id, params: params)
            }
        }
    }

    public enum ServerResponse: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, response: Attestation.GenerateResponse)
        case chatGPTAuthTokensRefresh(requestID: RequestID, response: ChatGPTAuthTokensRefreshResponse)
        case execCommandApproval(requestID: RequestID, response: ExecCommandApprovalResponse)
        case applyPatchApproval(requestID: RequestID, response: ApplyPatchApprovalResponse)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            case let .execCommandApproval(requestID, _):
                requestID
            case let .applyPatchApproval(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
            case .execCommandApproval:
                ExecCommandApprovalParams.method
            case .applyPatchApproval:
                ApplyPatchApprovalParams.method
            }
        }

        private enum CodingKeys: String, CodingKey {
            case method
            case id
            case response
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            switch method {
            case Attestation.generateMethod:
                self = .attestationGenerate(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(Attestation.GenerateResponse.self, forKey: .response)
                )
            case ChatGPTAuthTokensRefreshParams.method:
                self = .chatGPTAuthTokensRefresh(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ChatGPTAuthTokensRefreshResponse.self, forKey: .response)
                )
            case ExecCommandApprovalParams.method:
                self = .execCommandApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ExecCommandApprovalResponse.self, forKey: .response)
                )
            case ApplyPatchApprovalParams.method:
                self = .applyPatchApproval(
                    requestID: try container.decode(RequestID.self, forKey: .id),
                    response: try container.decode(ApplyPatchApprovalResponse.self, forKey: .response)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "unknown app-server response method: \(method)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(method, forKey: .method)
            try container.encode(id, forKey: .id)
            switch self {
            case let .attestationGenerate(_, response):
                try container.encode(response, forKey: .response)
            case let .chatGPTAuthTokensRefresh(_, response):
                try container.encode(response, forKey: .response)
            case let .execCommandApproval(_, response):
                try container.encode(response, forKey: .response)
            case let .applyPatchApproval(_, response):
                try container.encode(response, forKey: .response)
            }
        }
    }

    public struct ApplyPatchApprovalParams: Equatable, Codable, Sendable {
        public static let method = "applyPatchApproval"

        public let conversationID: String
        public let callID: String
        public let fileChanges: [String: FileChange]
        public let reason: String?
        public let grantRoot: String?

        public init(
            conversationID: String,
            callID: String,
            fileChanges: [String: FileChange],
            reason: String? = nil,
            grantRoot: String? = nil
        ) {
            self.conversationID = conversationID
            self.callID = callID
            self.fileChanges = fileChanges
            self.reason = reason
            self.grantRoot = grantRoot
        }

        private enum CodingKeys: String, CodingKey {
            case conversationID = "conversationId"
            case callID = "callId"
            case fileChanges
            case reason
            case grantRoot
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(callID, forKey: .callID)
            try container.encode(fileChanges, forKey: .fileChanges)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encodeNilOrValue(grantRoot, forKey: .grantRoot)
        }
    }

    public struct ApplyPatchApprovalResponse: Equatable, Codable, Sendable {
        public let decision: ReviewDecision

        public init(decision: ReviewDecision) {
            self.decision = decision
        }
    }

    public struct ExecCommandApprovalParams: Equatable, Codable, Sendable {
        public static let method = "execCommandApproval"

        public let conversationID: String
        public let callID: String
        public let approvalID: String?
        public let command: [String]
        public let cwd: String
        public let reason: String?
        public let parsedCmd: [ParsedCommand]

        public init(
            conversationID: String,
            callID: String,
            approvalID: String? = nil,
            command: [String],
            cwd: String,
            reason: String? = nil,
            parsedCmd: [ParsedCommand]
        ) {
            self.conversationID = conversationID
            self.callID = callID
            self.approvalID = approvalID
            self.command = command
            self.cwd = cwd
            self.reason = reason
            self.parsedCmd = parsedCmd
        }

        private enum CodingKeys: String, CodingKey {
            case conversationID = "conversationId"
            case callID = "callId"
            case approvalID = "approvalId"
            case command
            case cwd
            case reason
            case parsedCmd
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(callID, forKey: .callID)
            try container.encodeNilOrValue(approvalID, forKey: .approvalID)
            try container.encode(command, forKey: .command)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encode(parsedCmd, forKey: .parsedCmd)
        }
    }

    public struct ExecCommandApprovalResponse: Equatable, Codable, Sendable {
        public let decision: ReviewDecision

        public init(decision: ReviewDecision) {
            self.decision = decision
        }
    }

    public enum ChatGPTAuthTokensRefreshReason: String, Codable, Equatable, Sendable {
        case unauthorized
    }

    public struct ChatGPTAuthTokensRefreshParams: Equatable, Codable, Sendable {
        public static let method = "account/chatgptAuthTokens/refresh"

        public let reason: ChatGPTAuthTokensRefreshReason
        public let previousAccountID: String?

        public init(reason: ChatGPTAuthTokensRefreshReason, previousAccountID: String?) {
            self.reason = reason
            self.previousAccountID = previousAccountID
        }

        private enum CodingKeys: String, CodingKey {
            case reason
            case previousAccountID = "previousAccountId"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reason, forKey: .reason)
            try container.encodeNilOrValue(previousAccountID, forKey: .previousAccountID)
        }
    }

    public struct ChatGPTAuthTokensRefreshResponse: Equatable, Codable, Sendable {
        public let accessToken: String
        public let chatGPTAccountID: String
        public let chatGPTPlanType: String?

        public init(accessToken: String, chatGPTAccountID: String, chatGPTPlanType: String?) {
            self.accessToken = accessToken
            self.chatGPTAccountID = chatGPTAccountID
            self.chatGPTPlanType = chatGPTPlanType
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken
            case chatGPTAccountID = "chatgptAccountId"
            case chatGPTPlanType = "chatgptPlanType"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(accessToken, forKey: .accessToken)
            try container.encode(chatGPTAccountID, forKey: .chatGPTAccountID)
            try container.encodeNilOrValue(chatGPTPlanType, forKey: .chatGPTPlanType)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
