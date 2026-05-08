import Foundation

public struct ExecPolicyAmendment: Equatable, Codable, Sendable {
    public let command: [String]

    public init(command: [String]) {
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.command = try container.decode([String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(command)
    }
}
