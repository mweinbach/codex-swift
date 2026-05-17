import Foundation

public struct EnvironmentAddParams: Codable, Equatable, Sendable {
    public let environmentID: String
    public let execServerURL: String

    private enum CodingKeys: String, CodingKey {
        case environmentID = "environmentId"
        case execServerURL = "execServerUrl"
    }

    public init(environmentID: String, execServerURL: String) {
        self.environmentID = environmentID
        self.execServerURL = execServerURL
    }
}

public struct EnvironmentAddResponse: Codable, Equatable, Sendable {
    public init() {}
}
