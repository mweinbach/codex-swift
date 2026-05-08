import Foundation

public struct CompactionInput: Equatable, Codable, Sendable {
    public var model: String
    public var input: [ResponseItem]
    public var instructions: String

    public init(model: String, input: [ResponseItem], instructions: String) {
        self.model = model
        self.input = input
        self.instructions = instructions
    }
}

public struct CompactHistoryResponse: Equatable, Codable, Sendable {
    public var output: [ResponseItem]

    public init(output: [ResponseItem]) {
        self.output = output
    }
}

public enum CompactAPIError: Error, Equatable, CustomStringConvertible, Sendable {
    case requiresResponsesWireAPI
    case encodeCompactionInput(String)

    public var description: String {
        switch self {
        case .requiresResponsesWireAPI:
            return "compact endpoint requires responses wire api"
        case let .encodeCompactionInput(message):
            return "failed to encode compaction input: \(message)"
        }
    }
}

public enum CompactAPI {
    public static let path = "responses/compact"

    public static func path(for provider: APIProvider) throws -> String {
        switch provider.wireAPI {
        case .responses,
             .compact:
            return path
        case .chat:
            throw CompactAPIError.requiresResponsesWireAPI
        }
    }

    public static func body(for input: CompactionInput) throws -> JSONValue {
        do {
            let data = try JSONEncoder().encode(input)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw CompactAPIError.encodeCompactionInput(String(describing: error))
        }
    }
}
