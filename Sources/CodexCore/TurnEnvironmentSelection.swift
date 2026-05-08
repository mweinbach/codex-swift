import Foundation

public struct TurnEnvironmentSelection: Codable, Equatable, Sendable {
    public let environmentID: String
    public let cwd: String

    private enum CodingKeys: String, CodingKey {
        case environmentID = "environment_id"
        case cwd
    }

    public init(environmentID: String, cwd: String) {
        self.environmentID = environmentID
        self.cwd = cwd
    }
}
