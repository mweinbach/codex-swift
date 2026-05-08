import Foundation

public struct McpOAuthDiscoveryHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data
    public let headers: [String: [String]]

    public init(statusCode: Int, body: Data, headers: [String: [String]] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    public func headerValues(named name: String) -> [String] {
        headers.reduce(into: []) { values, entry in
            guard entry.key.compare(name, options: [.caseInsensitive]) == .orderedSame else {
                return
            }
            values.append(contentsOf: entry.value)
        }
    }
}

public typealias McpOAuthDiscoveryTransport = @Sendable (URLRequest) async throws -> McpOAuthDiscoveryHTTPResponse

public enum McpOAuthDiscovery {
    public static let discoveryHeader = "MCP-Protocol-Version"
    public static let discoveryVersion = "2024-11-05"
    public static let discoveryTimeout: TimeInterval = 5

    public static func supportsOAuthLogin(
        url: String,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: McpOAuthDiscoveryTransport? = nil
    ) async throws -> Bool {
        guard let baseURL = URL(string: url),
              let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil
        else {
            throw McpOAuthDiscoveryError.invalidURL(url)
        }

        let headers = defaultHeaders(
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: environment
        )
        let send = transport ?? urlSessionTransport

        for candidatePath in discoveryPaths(basePath: components.percentEncodedPath) {
            guard let discoveryURL = discoveryURL(baseURL: baseURL, path: candidatePath) else {
                continue
            }
            var request = URLRequest(url: discoveryURL, timeoutInterval: discoveryTimeout)
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.setValue(discoveryVersion, forHTTPHeaderField: discoveryHeader)

            let response: McpOAuthDiscoveryHTTPResponse
            do {
                response = try await send(request)
            } catch {
                continue
            }

            guard response.statusCode == 200 else {
                continue
            }
            guard let metadata = try? JSONDecoder().decode(OAuthDiscoveryMetadata.self, from: response.body),
                  metadata.authorizationEndpoint != nil,
                  metadata.tokenEndpoint != nil
            else {
                continue
            }
            return true
        }

        return false
    }

    public static func discoveryPaths(basePath: String) -> [String] {
        wellKnownPaths(basePath: basePath, resource: "oauth-authorization-server")
    }

    public static func wellKnownPaths(basePath: String, resource: String) -> [String] {
        let trimmed = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let canonical = "/.well-known/\(resource)"
        guard !trimmed.isEmpty else {
            return [canonical]
        }

        var candidates: [String] = []
        func pushUnique(_ candidate: String) {
            if !candidates.contains(candidate) {
                candidates.append(candidate)
            }
        }

        pushUnique("\(canonical)/\(trimmed)")
        pushUnique("/\(trimmed)/.well-known/\(resource)")
        pushUnique(canonical)
        return candidates
    }

    static func discoveryURL(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.percentEncodedPath = path
        return components.url
    }

    static func defaultHeaders(
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        environment: [String: String]
    ) -> [String: String] {
        var headers: [String: String] = [:]

        for (name, value) in httpHeaders ?? [:] where isValidHeaderName(name) && isValidHeaderValue(value) {
            headers[name] = value
        }

        for (name, envVar) in envHttpHeaders ?? [:] {
            guard let value = environment[envVar], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard isValidHeaderName(name), isValidHeaderValue(value) else {
                continue
            }
            headers[name] = value
        }

        return headers
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else {
            return false
        }
        let separators = CharacterSet(charactersIn: #"()<>@,;:\"/[]?={} "#)
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && scalar.value > 32
                && scalar.value < 127
                && !separators.contains(scalar)
        }
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            scalar.value == 10 || scalar.value == 13
        }
    }

    static func urlSessionTransport(_ request: URLRequest) async throws -> McpOAuthDiscoveryHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw McpOAuthDiscoveryError.nonHTTPResponse
        }
        var headers: [String: [String]] = [:]
        for (name, value) in httpResponse.allHeaderFields {
            guard let name = name as? String else {
                continue
            }
            if let values = value as? [String] {
                headers[name] = values
            } else {
                headers[name] = [String(describing: value)]
            }
        }
        return McpOAuthDiscoveryHTTPResponse(statusCode: httpResponse.statusCode, body: data, headers: headers)
    }
}

public enum McpOAuthDiscoveryError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidURL(String)
    case nonHTTPResponse

    public var description: String {
        switch self {
        case let .invalidURL(url):
            return "invalid MCP server URL for OAuth discovery: \(url)"
        case .nonHTTPResponse:
            return "OAuth discovery response was not HTTP"
        }
    }
}

private struct OAuthDiscoveryMetadata: Decodable {
    let authorizationEndpoint: String?
    let tokenEndpoint: String?

    private enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
    }
}
