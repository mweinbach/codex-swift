import Foundation
import Security

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

public struct McpOAuthClientConfig: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String?
    public let scopes: [String]
    public let redirectURI: String

    public init(clientID: String, clientSecret: String? = nil, scopes: [String] = [], redirectURI: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
        self.redirectURI = redirectURI
    }
}

public enum McpOAuthAuthorizationError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidScope(String)
    case registrationFailed(String)

    public var description: String {
        switch self {
        case let .invalidScope(scope):
            return "Invalid scope: \(scope)"
        case let .registrationFailed(message):
            return "Registration failed: \(message)"
        }
    }
}

public enum McpOAuthClientRegistration {
    public static func registerClient(
        metadata: McpOAuthAuthorizationMetadata,
        clientName: String,
        redirectURI: String,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: McpOAuthDiscoveryTransport? = nil
    ) async throws -> McpOAuthClientConfig {
        guard let registrationEndpoint = metadata.registrationEndpoint else {
            throw McpOAuthAuthorizationError.registrationFailed("Dynamic client registration not supported")
        }
        if let responseTypes = metadata.responseTypesSupported, !responseTypes.contains("code") {
            throw McpOAuthAuthorizationError.invalidScope("code")
        }
        guard let registrationURL = URL(string: registrationEndpoint) else {
            throw McpOAuthAuthorizationError.registrationFailed("HTTP request error: invalid registration URL: \(registrationEndpoint)")
        }

        let requestBody = ClientRegistrationRequest(
            clientName: clientName,
            redirectURIs: [redirectURI],
            grantTypes: ["authorization_code", "refresh_token"],
            tokenEndpointAuthMethod: "none",
            responseTypes: ["code"]
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(requestBody)
        } catch {
            throw McpOAuthAuthorizationError.registrationFailed("analyze response error: \(String(describing: error))")
        }

        let headers = McpOAuthDiscovery.defaultHeaders(
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: environment
        )
        let send = transport ?? McpOAuthDiscovery.urlSessionTransport
        let response: McpOAuthDiscoveryHTTPResponse
        do {
            response = try await send(registrationRequest(url: registrationURL, headers: headers, body: body))
        } catch {
            throw McpOAuthAuthorizationError.registrationFailed("HTTP request error: \(String(describing: error))")
        }

        guard (200..<300).contains(response.statusCode) else {
            let errorText = String(data: response.body, encoding: .utf8) ?? "cannot get error details"
            throw McpOAuthAuthorizationError.registrationFailed("HTTP \(response.statusCode): \(errorText)")
        }

        let registrationResponse: ClientRegistrationResponse
        do {
            registrationResponse = try JSONDecoder().decode(ClientRegistrationResponse.self, from: response.body)
        } catch {
            throw McpOAuthAuthorizationError.registrationFailed("analyze response error: \(String(describing: error))")
        }

        return McpOAuthClientConfig(
            clientID: registrationResponse.clientID,
            clientSecret: registrationResponse.clientSecret?.isEmpty == true ? nil : registrationResponse.clientSecret,
            scopes: [],
            redirectURI: redirectURI
        )
    }

    private static func registrationRequest(url: URL, headers: [String: String], body: Data) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: McpOAuthDiscovery.discoveryTimeout)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(McpOAuthDiscovery.discoveryVersion, forHTTPHeaderField: McpOAuthDiscovery.discoveryHeader)
        return request
    }
}

public struct McpOAuthAuthorizationSession: Equatable, Sendable {
    public let metadata: McpOAuthAuthorizationMetadata
    public let clientConfig: McpOAuthClientConfig
    public let authURL: String
    public let redirectURI: String
    public let csrfToken: String
    public let pkceVerifier: String

    public init(
        metadata: McpOAuthAuthorizationMetadata,
        clientConfig: McpOAuthClientConfig,
        authURL: String,
        redirectURI: String,
        csrfToken: String,
        pkceVerifier: String
    ) {
        self.metadata = metadata
        self.clientConfig = clientConfig
        self.authURL = authURL
        self.redirectURI = redirectURI
        self.csrfToken = csrfToken
        self.pkceVerifier = pkceVerifier
    }

    public static func start(
        metadata: McpOAuthAuthorizationMetadata,
        scopes: [String],
        redirectURI: String,
        clientName: String? = nil,
        clientMetadataURL: String? = nil,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: McpOAuthDiscoveryTransport? = nil,
        pkceGenerator: @Sendable () throws -> PKCECodes = { try PKCE.generate() },
        csrfTokenGenerator: @Sendable () throws -> String = { try generateCSRFToken() }
    ) async throws -> McpOAuthAuthorizationSession {
        let clientConfig = try await resolveClientConfig(
            metadata: metadata,
            scopes: scopes,
            redirectURI: redirectURI,
            clientName: clientName,
            clientMetadataURL: clientMetadataURL,
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: environment,
            transport: transport
        )
        guard URL(string: metadata.authorizationEndpoint)?.scheme != nil else {
            throw McpOAuthAuthorizationError.registrationFailed(
                "Dynamic registration failed: OAuth error: Invalid authorization URL: \(metadata.authorizationEndpoint)"
            )
        }
        guard URL(string: metadata.tokenEndpoint)?.scheme != nil else {
            throw McpOAuthAuthorizationError.registrationFailed(
                "Dynamic registration failed: OAuth error: Invalid token URL: \(metadata.tokenEndpoint)"
            )
        }

        let pkce = try pkceGenerator()
        let csrfToken = try csrfTokenGenerator()
        let authURL = try authorizationURL(
            authorizationEndpoint: metadata.authorizationEndpoint,
            clientID: clientConfig.clientID,
            redirectURI: redirectURI,
            scopes: scopes,
            csrfToken: csrfToken,
            codeChallenge: pkce.codeChallenge
        )

        return McpOAuthAuthorizationSession(
            metadata: metadata,
            clientConfig: clientConfig,
            authURL: authURL,
            redirectURI: redirectURI,
            csrfToken: csrfToken,
            pkceVerifier: pkce.codeVerifier
        )
    }

    private static func resolveClientConfig(
        metadata: McpOAuthAuthorizationMetadata,
        scopes: [String],
        redirectURI: String,
        clientName: String?,
        clientMetadataURL: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        environment: [String: String],
        transport: McpOAuthDiscoveryTransport?
    ) async throws -> McpOAuthClientConfig {
        if metadata.clientIDMetadataDocumentSupported == true, let clientMetadataURL {
            guard isHTTPSURLWithNonRootPath(clientMetadataURL) else {
                throw McpOAuthAuthorizationError.registrationFailed(
                    "client_metadata_url must be a valid HTTPS URL with a non-root pathname, got: \(clientMetadataURL)"
                )
            }
            return McpOAuthClientConfig(
                clientID: clientMetadataURL,
                clientSecret: nil,
                scopes: scopes,
                redirectURI: redirectURI
            )
        }

        do {
            return try await McpOAuthClientRegistration.registerClient(
                metadata: metadata,
                clientName: clientName ?? "MCP Client",
                redirectURI: redirectURI,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                environment: environment,
                transport: transport
            )
        } catch {
            throw McpOAuthAuthorizationError.registrationFailed(
                "Dynamic registration failed: \(String(describing: error))"
            )
        }
    }

    private static func authorizationURL(
        authorizationEndpoint: String,
        clientID: String,
        redirectURI: String,
        scopes: [String],
        csrfToken: String,
        codeChallenge: String
    ) throws -> String {
        guard var components = URLComponents(string: authorizationEndpoint) else {
            throw McpOAuthAuthorizationError.registrationFailed(
                "Dynamic registration failed: OAuth error: Invalid authorization URL: \(authorizationEndpoint)"
            )
        }

        var encodedPairs = [
            ("response_type", "code"),
            ("client_id", clientID),
            ("state", csrfToken),
            ("code_challenge", codeChallenge),
            ("code_challenge_method", "S256"),
            ("redirect_uri", redirectURI)
        ].map { "\(formEncode($0.0))=\(formEncode($0.1))" }

        if !scopes.isEmpty {
            encodedPairs.append("\(formEncode("scope"))=\(formEncode(scopes.joined(separator: " ")))")
        }

        let encodedQuery = encodedPairs.joined(separator: "&")
        if let existingQuery = components.percentEncodedQuery, !existingQuery.isEmpty {
            components.percentEncodedQuery = "\(existingQuery)&\(encodedQuery)"
        } else {
            components.percentEncodedQuery = encodedQuery
        }

        guard let url = components.url else {
            throw McpOAuthAuthorizationError.registrationFailed(
                "Dynamic registration failed: OAuth error: Invalid authorization URL: \(authorizationEndpoint)"
            )
        }
        return url.absoluteString
    }

    private static func isHTTPSURLWithNonRootPath(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }
        return url.scheme == "https" && url.host != nil && !url.path.isEmpty && url.path != "/"
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }

    public static func generateCSRFToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PKCEError.randomBytesFailed(status)
        }
        return PKCE.base64URLEncodedNoPadding(Data(bytes))
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

private struct ClientRegistrationRequest: Encodable {
    let clientName: String
    let redirectURIs: [String]
    let grantTypes: [String]
    let tokenEndpointAuthMethod: String
    let responseTypes: [String]

    private enum CodingKeys: String, CodingKey {
        case clientName = "client_name"
        case redirectURIs = "redirect_uris"
        case grantTypes = "grant_types"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case responseTypes = "response_types"
    }
}

private struct ClientRegistrationResponse: Decodable {
    let clientID: String
    let clientSecret: String?
    let clientName: String?
    let redirectURIs: [String]

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case clientName = "client_name"
        case redirectURIs = "redirect_uris"
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
