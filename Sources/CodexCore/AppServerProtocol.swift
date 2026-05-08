import Foundation

public enum AppServerProtocol {
    public enum ServerRequest: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, params: Attestation.GenerateParams)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
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
            }
        }
    }

    public enum ServerRequestPayload: Equatable, Sendable {
        case attestationGenerate(Attestation.GenerateParams)

        public static func attestationGenerate() -> ServerRequestPayload {
            .attestationGenerate(Attestation.GenerateParams())
        }

        public func request(withID id: RequestID) -> ServerRequest {
            switch self {
            case let .attestationGenerate(params):
                .attestationGenerate(requestID: id, params: params)
            }
        }
    }

    public enum ServerResponse: Equatable, Codable, Sendable {
        case attestationGenerate(requestID: RequestID, response: Attestation.GenerateResponse)

        public var id: RequestID {
            switch self {
            case let .attestationGenerate(requestID, _):
                requestID
            }
        }

        public var method: String {
            switch self {
            case .attestationGenerate:
                Attestation.generateMethod
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
            }
        }
    }
}
