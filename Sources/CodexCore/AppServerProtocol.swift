import Foundation

public enum AppServerProtocol {
    public enum ServerRequest: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, params: Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(requestID: RequestID, params: ChatGPTAuthTokensRefreshParams)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
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
            }
        }
    }

    public enum ServerRequestPayload: Equatable, Sendable {
        case attestationGenerate(Attestation.GenerateParams)
        case chatGPTAuthTokensRefresh(ChatGPTAuthTokensRefreshParams)

        public static func attestationGenerate() -> ServerRequestPayload {
            .attestationGenerate(Attestation.GenerateParams())
        }

        public func request(withID id: RequestID) -> ServerRequest {
            switch self {
            case let .attestationGenerate(params):
                .attestationGenerate(requestID: id, params: params)
            case let .chatGPTAuthTokensRefresh(params):
                .chatGPTAuthTokensRefresh(requestID: id, params: params)
            }
        }
    }

    public enum ServerResponse: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, response: Attestation.GenerateResponse)
        case chatGPTAuthTokensRefresh(requestID: RequestID, response: ChatGPTAuthTokensRefreshResponse)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            case let .chatGPTAuthTokensRefresh(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
            case .chatGPTAuthTokensRefresh:
                ChatGPTAuthTokensRefreshParams.method
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
            }
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
