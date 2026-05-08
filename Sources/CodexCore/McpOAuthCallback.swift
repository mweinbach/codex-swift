import Foundation

public struct McpOAuthCallbackResult: Equatable, Sendable {
    public let code: String
    public let state: String

    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

public enum McpOAuthCallbackParser {
    public static func parse(path: String) -> McpOAuthCallbackResult? {
        guard let queryStart = path.firstIndex(of: "?") else {
            return nil
        }
        let route = String(path[..<queryStart])
        guard route == "/callback" else {
            return nil
        }

        let query = path[path.index(after: queryStart)...]
        var code: String?
        var state: String?

        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let equals = pair.firstIndex(of: "=") else {
                return nil
            }

            let key = String(pair[..<equals])
            let rawValue = String(pair[pair.index(after: equals)...])
            guard let value = rawValue.removingPercentEncoding else {
                return nil
            }

            switch key {
            case "code":
                code = value
            case "state":
                state = value
            default:
                continue
            }
        }

        guard let code, let state else {
            return nil
        }
        return McpOAuthCallbackResult(code: code, state: state)
    }
}
