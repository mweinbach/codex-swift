import Foundation

public struct RemoteControlStatusReadResponse: Equatable, Sendable {
    public let status: RemoteControlConnectionStatus
    public let serverName: String
    public let installationID: String
    public let environmentID: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case serverName
        case installationID = "installationId"
        case environmentID = "environmentId"
    }

    public init(
        status: RemoteControlConnectionStatus,
        serverName: String = RemoteControlStatusSnapshot.defaultServerName,
        installationID: String,
        environmentID: String?
    ) {
        self.status = status
        self.serverName = serverName
        self.installationID = installationID
        self.environmentID = environmentID
    }

    public init(snapshot: RemoteControlStatusSnapshot) {
        self.init(
            status: snapshot.status,
            serverName: snapshot.serverName,
            installationID: snapshot.installationID,
            environmentID: snapshot.environmentID
        )
    }
}

extension RemoteControlStatusReadResponse: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(serverName, forKey: .serverName)
        try container.encode(installationID, forKey: .installationID)
        try container.encodeNilOrValue(environmentID, forKey: .environmentID)
    }
}

public typealias RemoteControlEnableResponse = RemoteControlStatusReadResponse
public typealias RemoteControlDisableResponse = RemoteControlStatusReadResponse

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
