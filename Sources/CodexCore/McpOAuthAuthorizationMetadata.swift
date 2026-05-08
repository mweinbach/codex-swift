import Foundation

public struct McpOAuthAuthorizationMetadata: Codable, Equatable, Sendable {
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let registrationEndpoint: String?
    public let issuer: String?
    public let jwksURI: String?
    public let scopesSupported: [String]?
    public let responseTypesSupported: [String]?
    public let clientIDMetadataDocumentSupported: Bool?

    private enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case issuer
        case jwksURI = "jwks_uri"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case clientIDMetadataDocumentSupported = "client_id_metadata_document_supported"
    }

    public init(
        authorizationEndpoint: String,
        tokenEndpoint: String,
        registrationEndpoint: String? = nil,
        issuer: String? = nil,
        jwksURI: String? = nil,
        scopesSupported: [String]? = nil,
        responseTypesSupported: [String]? = nil,
        clientIDMetadataDocumentSupported: Bool? = nil
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.issuer = issuer
        self.jwksURI = jwksURI
        self.scopesSupported = scopesSupported
        self.responseTypesSupported = responseTypesSupported
        self.clientIDMetadataDocumentSupported = clientIDMetadataDocumentSupported
    }
}

public enum McpOAuthAuthorizationMetadataDiscovery {
    public static func discoverMetadata(
        url: String,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: McpOAuthDiscoveryTransport? = nil
    ) async throws -> McpOAuthAuthorizationMetadata? {
        guard let baseURL = URL(string: url),
              let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil
        else {
            throw McpOAuthDiscoveryError.invalidURL(url)
        }

        let headers = McpOAuthDiscovery.defaultHeaders(
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: environment
        )
        let send = transport ?? McpOAuthDiscovery.urlSessionTransport

        if let metadata = try await tryDiscoverOAuthServer(
            baseURL: baseURL,
            headers: headers,
            transport: send
        ) {
            return metadata
        }

        return try await discoverOAuthServerViaResourceMetadata(
            baseURL: baseURL,
            headers: headers,
            transport: send
        )
    }

    public static func extractResourceMetadataURL(from header: String, baseURL: URL) -> URL? {
        let lowercased = header.lowercased()
        let fragmentKey = "resource_metadata="
        var searchOffset = 0

        while searchOffset < lowercased.count {
            let searchStart = lowercased.index(lowercased.startIndex, offsetBy: searchOffset)
            guard let range = lowercased.range(of: fragmentKey, range: searchStart..<lowercased.endIndex) else {
                break
            }
            let valueOffset = lowercased.distance(from: lowercased.startIndex, to: range.upperBound)
            let valueStart = header.index(header.startIndex, offsetBy: valueOffset)
            let valueSlice = String(header[valueStart...])

            guard let (value, consumed) = parseNextHeaderValue(valueSlice) else {
                break
            }
            if let absoluteURL = URL(string: value), absoluteURL.scheme != nil {
                return absoluteURL
            }
            if let relativeURL = URL(string: value, relativeTo: baseURL)?.absoluteURL {
                return relativeURL
            }
            searchOffset = valueOffset + consumed
        }

        return nil
    }

    public static func parseNextHeaderValue(_ fragment: String) -> (String, Int)? {
        let leadingWhitespace = fragment.prefix { $0.isWhitespace }.count
        let trimmed = fragment.dropFirst(leadingWhitespace)
        guard let first = trimmed.first else {
            return nil
        }

        if first == "\"" {
            var escaped = false
            var result = ""
            var consumed = leadingWhitespace + 1
            for character in trimmed.dropFirst() {
                consumed += 1
                if escaped {
                    result.append(character)
                    escaped = false
                    continue
                }
                switch character {
                case "\\":
                    escaped = true
                case "\"":
                    return (result, consumed)
                default:
                    result.append(character)
                }
            }
            return nil
        }

        var tokenLength = 0
        for character in trimmed {
            if character == "," || character == ";" || character.isWhitespace {
                break
            }
            tokenLength += 1
        }
        return (String(trimmed.prefix(tokenLength)), leadingWhitespace + tokenLength)
    }

    private static func tryDiscoverOAuthServer(
        baseURL: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> McpOAuthAuthorizationMetadata? {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        for candidatePath in McpOAuthDiscovery.wellKnownPaths(
            basePath: components.percentEncodedPath,
            resource: "oauth-authorization-server"
        ) {
            guard let discoveryURL = wellKnownURL(baseURL: baseURL, path: candidatePath),
                  let metadata = try await fetchAuthorizationMetadata(
                    url: discoveryURL,
                    headers: headers,
                    transport: transport
                  )
            else {
                continue
            }
            return metadata
        }
        return nil
    }

    private static func fetchAuthorizationMetadata(
        url: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> McpOAuthAuthorizationMetadata? {
        let response: McpOAuthDiscoveryHTTPResponse
        do {
            response = try await transport(request(url: url, headers: headers))
        } catch {
            return nil
        }
        guard response.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(McpOAuthAuthorizationMetadata.self, from: response.body)
    }

    private static func discoverOAuthServerViaResourceMetadata(
        baseURL: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> McpOAuthAuthorizationMetadata? {
        guard let resourceMetadataURL = try await discoverResourceMetadataURL(
            baseURL: baseURL,
            headers: headers,
            transport: transport
        ) else {
            return nil
        }
        guard let resourceMetadata = try await fetchResourceMetadata(
            url: resourceMetadataURL,
            headers: headers,
            transport: transport
        ) else {
            return nil
        }

        let candidates = resourceMetadata.authorizationCandidates
        for rawCandidate in candidates {
            let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty,
                  let candidateURL = resolve(candidate, relativeTo: resourceMetadataURL)
            else {
                continue
            }

            if candidateURL.path.contains("/.well-known/") {
                if let metadata = try await fetchAuthorizationMetadata(
                    url: candidateURL,
                    headers: headers,
                    transport: transport
                ) {
                    return metadata
                }
                continue
            }

            if let metadata = try await tryDiscoverOAuthServer(
                baseURL: candidateURL,
                headers: headers,
                transport: transport
            ) {
                return metadata
            }
        }

        return nil
    }

    private static func discoverResourceMetadataURL(
        baseURL: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> URL? {
        if let url = try? await fetchResourceMetadataURL(url: baseURL, baseURL: baseURL, headers: headers, transport: transport) {
            return url
        }

        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        for candidatePath in McpOAuthDiscovery.wellKnownPaths(
            basePath: components.percentEncodedPath,
            resource: "oauth-protected-resource"
        ) {
            guard let discoveryURL = wellKnownURL(baseURL: baseURL, path: candidatePath),
                  let resourceMetadataURL = try? await fetchResourceMetadataURL(
                    url: discoveryURL,
                    baseURL: baseURL,
                    headers: headers,
                    transport: transport
                  )
            else {
                continue
            }
            return resourceMetadataURL
        }

        return nil
    }

    private static func fetchResourceMetadataURL(
        url: URL,
        baseURL: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> URL? {
        let response: McpOAuthDiscoveryHTTPResponse
        do {
            response = try await transport(request(url: url, headers: headers))
        } catch {
            return nil
        }

        if response.statusCode == 200 {
            return url
        }
        guard response.statusCode == 401 else {
            return nil
        }

        for value in response.headerValues(named: "WWW-Authenticate") {
            if let url = extractResourceMetadataURL(from: value, baseURL: baseURL) {
                return url
            }
        }
        return nil
    }

    private static func fetchResourceMetadata(
        url: URL,
        headers: [String: String],
        transport: McpOAuthDiscoveryTransport
    ) async throws -> ResourceMetadata? {
        let response: McpOAuthDiscoveryHTTPResponse
        do {
            response = try await transport(request(url: url, headers: headers))
        } catch {
            return nil
        }
        guard response.statusCode == 200 else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ResourceMetadata.self, from: response.body)
        } catch {
            throw McpOAuthAuthorizationMetadataDiscoveryError.metadataParseFailed(
                "Failed to parse resource metadata: \(String(describing: error))"
            )
        }
    }

    private static func resolve(_ candidate: String, relativeTo baseURL: URL) -> URL? {
        if let absoluteURL = URL(string: candidate), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: candidate, relativeTo: baseURL)?.absoluteURL
    }

    private static func wellKnownURL(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        components.percentEncodedPath = path
        return components.url
    }

    private static func request(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: McpOAuthDiscovery.discoveryTimeout)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(McpOAuthDiscovery.discoveryVersion, forHTTPHeaderField: McpOAuthDiscovery.discoveryHeader)
        return request
    }
}

public enum McpOAuthAuthorizationMetadataDiscoveryError: Error, Equatable, CustomStringConvertible, Sendable {
    case metadataParseFailed(String)

    public var description: String {
        switch self {
        case let .metadataParseFailed(message):
            return message
        }
    }
}

private struct ResourceMetadata: Decodable, Equatable, Sendable {
    let authorizationServer: String?
    let authorizationServers: [String]?

    var authorizationCandidates: [String] {
        var candidates: [String] = []
        if let authorizationServer {
            candidates.append(authorizationServer)
        }
        if let authorizationServers {
            candidates.append(contentsOf: authorizationServers)
        }
        return candidates
    }

    private enum CodingKeys: String, CodingKey {
        case authorizationServer = "authorization_server"
        case authorizationServers = "authorization_servers"
    }
}
