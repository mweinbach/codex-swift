import Foundation

public enum ModelsAPIError: Error, Equatable, CustomStringConvertible, Sendable {
    case decodeModelsResponse(String)

    public var description: String {
        switch self {
        case let .decodeModelsResponse(message):
            return message
        }
    }
}

public enum ModelsAPI {
    public static let path = "models"

    public static func request(
        provider: APIProvider,
        clientVersion: String,
        extraHeaders: [String: String] = [:]
    ) -> APIRequest {
        var request = provider.buildRequest(method: .get, path: path)
        for (name, value) in extraHeaders {
            request.headers[name] = value
        }

        let separator = request.url.contains("?") ? "&" : "?"
        request.url.append("\(separator)client_version=\(clientVersion)")
        return request
    }

    public static func decodeResponse(body: Data, headers: [String: String] = [:]) throws -> ModelsResponse {
        let response: ModelsResponse
        do {
            response = try JSONDecoder().decode(ModelsResponse.self, from: body)
        } catch {
            let bodyText = String(decoding: body, as: UTF8.self)
            throw ModelsAPIError.decodeModelsResponse(
                "failed to decode models response: \(error); body: \(bodyText)"
            )
        }

        return ModelsResponse(models: response.models, etag: headerETag(in: headers) ?? response.etag)
    }

    private static func headerETag(in headers: [String: String]) -> String? {
        for (name, value) in headers where name.caseInsensitiveCompare("etag") == .orderedSame {
            return value
        }
        return nil
    }
}
