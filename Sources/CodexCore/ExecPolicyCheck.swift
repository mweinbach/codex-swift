import Foundation

public enum ExecPolicyCheckError: Error, Equatable, CustomStringConvertible, Sendable {
    case readPolicy(path: String, message: String)
    case parsePolicy(path: String, message: String)
    case encodeOutput(message: String)

    public var description: String {
        switch self {
        case let .readPolicy(path, message):
            return "failed to read policy at \(path): \(message)"
        case let .parsePolicy(path, message):
            return "failed to parse policy at \(path): \(message)"
        case let .encodeOutput(message):
            return "failed to serialize execpolicy check output: \(message)"
        }
    }
}

public struct ExecPolicyCheckOutput: Encodable, Equatable, Sendable {
    public let matchedRules: [RuleMatch]
    public let decision: ExecPolicyDecision?

    public init(matchedRules: [RuleMatch]) {
        self.matchedRules = matchedRules
        decision = matchedRules.map(\.decision).max()
    }

    private enum CodingKeys: String, CodingKey {
        case matchedRules
        case decision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchedRules, forKey: .matchedRules)
        try container.encodeIfPresent(decision, forKey: .decision)
    }
}

public enum ExecPolicyCheck {
    public static func run(rulePaths: [URL], command: [String], pretty: Bool = false) throws -> String {
        let policy = try loadPolicies(rulePaths: rulePaths)
        return try formatMatchesJSON(
            matchedRules: policy.matchesForCommand(command, heuristicsFallback: nil),
            pretty: pretty
        )
    }

    public static func loadPolicies(rulePaths: [URL]) throws -> ExecPolicy {
        let parser = PolicyParser()
        for rulePath in rulePaths {
            let contents: String
            do {
                contents = try String(contentsOf: rulePath, encoding: .utf8)
            } catch {
                throw ExecPolicyCheckError.readPolicy(
                    path: rulePath.path,
                    message: String(describing: error)
                )
            }

            do {
                try parser.parse(rulePath.path, contents)
            } catch {
                throw ExecPolicyCheckError.parsePolicy(
                    path: rulePath.path,
                    message: String(describing: error)
                )
            }
        }
        return parser.build()
    }

    public static func formatMatchesJSON(matchedRules: [RuleMatch], pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted] : []
        do {
            let data = try encoder.encode(ExecPolicyCheckOutput(matchedRules: matchedRules))
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            throw ExecPolicyCheckError.encodeOutput(message: String(describing: error))
        }
    }
}
