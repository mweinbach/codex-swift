import Foundation

public struct McpServerRefreshConfig: Codable, Equatable, Sendable {
    public let mcpServers: JSONValue
    public let mcpOAuthCredentialsStoreMode: JSONValue

    private enum CodingKeys: String, CodingKey {
        case mcpServers = "mcp_servers"
        case mcpOAuthCredentialsStoreMode = "mcp_oauth_credentials_store_mode"
    }

    public init(mcpServers: JSONValue, mcpOAuthCredentialsStoreMode: JSONValue) {
        self.mcpServers = mcpServers
        self.mcpOAuthCredentialsStoreMode = mcpOAuthCredentialsStoreMode
    }
}
