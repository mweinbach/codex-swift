import Foundation

public indirect enum ConfigValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case array([ConfigValue])
    case table([String: ConfigValue])
}

public enum ConfigOverrideError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingEquals(String)
    case emptyKey(String)
    case invalidLiteral(String)
    case invalidInlineTable(String)

    public var description: String {
        switch self {
        case let .missingEquals(raw):
            return "Invalid override (missing '='): \(raw)"
        case let .emptyKey(raw):
            return "Empty key in override: \(raw)"
        case let .invalidLiteral(raw):
            return "Invalid TOML literal: \(raw)"
        case let .invalidInlineTable(raw):
            return "Invalid inline table: \(raw)"
        }
    }
}

public struct CliConfigOverrides: Equatable, Sendable {
    public var rawOverrides: [String]

    public init(rawOverrides: [String] = []) {
        self.rawOverrides = rawOverrides
    }

    public func parseOverrides() throws -> [(String, ConfigValue)] {
        try rawOverrides.map { raw in
            guard let equalsIndex = raw.firstIndex(of: "=") else {
                throw ConfigOverrideError.missingEquals(raw)
            }

            let key = String(raw[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = raw.index(after: equalsIndex)
            let valueText = String(raw[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty else {
                throw ConfigOverrideError.emptyKey(raw)
            }

            let value: ConfigValue
            do {
                value = try ConfigValueParser.parseTomlLiteral(valueText)
            } catch {
                value = .string(valueText.trimmingMatchingQuotes())
            }
            return (key, value)
        }
    }

    public func applying(to target: ConfigValue = .table([:])) throws -> ConfigValue {
        var copy = target
        try apply(on: &copy)
        return copy
    }

    public func apply(on target: inout ConfigValue) throws {
        for (path, value) in try parseOverrides() {
            applySingleOverride(path: path, value: value, target: &target)
        }
    }

    private func applySingleOverride(path: String, value: ConfigValue, target: inout ConfigValue) {
        let parts = path.split(separator: ".").map(String.init)
        apply(value: value, pathParts: parts, target: &target)
    }

    private func apply(value: ConfigValue, pathParts: [String], target: inout ConfigValue) {
        guard let first = pathParts.first else { return }

        var table: [String: ConfigValue]
        if case let .table(existing) = target {
            table = existing
        } else {
            table = [:]
        }

        if pathParts.count == 1 {
            table[first] = value
            target = .table(table)
            return
        }

        var child = table[first] ?? .table([:])
        apply(value: value, pathParts: Array(pathParts.dropFirst()), target: &child)
        table[first] = child
        target = .table(table)
    }
}

public enum ConfigValueParser {
    public static func parseTomlLiteral(_ raw: String) throws -> ConfigValue {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }

        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            return .string(String(text.dropFirst().dropLast()).unescapedDoubleQuotedString())
        }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            return .string(String(text.dropFirst().dropLast()))
        }

        if text.hasPrefix("["), text.hasSuffix("]") {
            let body = String(text.dropFirst().dropLast())
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .array([])
            }
            return .array(try splitTopLevel(body, separator: ",").map(parseTomlLiteral))
        }

        if text.hasPrefix("{"), text.hasSuffix("}") {
            let body = String(text.dropFirst().dropLast())
            var table: [String: ConfigValue] = [:]
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .table(table)
            }
            for pair in try splitTopLevel(body, separator: ",") {
                guard let equalsIndex = pair.firstIndex(of: "=") else {
                    throw ConfigOverrideError.invalidInlineTable(raw)
                }
                let key = String(pair[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingMatchingQuotes()
                let valueStart = pair.index(after: equalsIndex)
                let valueText = String(pair[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    throw ConfigOverrideError.invalidInlineTable(raw)
                }
                table[key] = try parseTomlLiteral(valueText)
            }
            return .table(table)
        }

        if let integer = Int64(text), !text.contains(".") {
            return .integer(integer)
        }
        if let double = Double(text), text.contains(".") {
            return .double(double)
        }

        throw ConfigOverrideError.invalidLiteral(raw)
    }

    private static func splitTopLevel(_ text: String, separator: Character) throws -> [String] {
        var pieces: [String] = []
        var current = String()
        var squareDepth = 0
        var braceDepth = 0
        var quote: Character?
        var previousWasBackslash = false

        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case separator where squareDepth == 0 && braceDepth == 0:
                pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }

        pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return pieces
    }
}

private extension StringProtocol {
    func trimmingMatchingQuotes() -> String {
        let text = String(self)
        guard text.count >= 2 else { return text }
        if (text.first == "\"" && text.last == "\"") || (text.first == "'" && text.last == "'") {
            return String(text.dropFirst().dropLast())
        }
        return text
    }
}

private extension String {
    func unescapedDoubleQuotedString() -> String {
        var result = String()
        var iterator = makeIterator()
        while let character = iterator.next() {
            if character == "\\", let escaped = iterator.next() {
                switch escaped {
                case "n":
                    result.append("\n")
                case "t":
                    result.append("\t")
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                default:
                    result.append(escaped)
                }
            } else {
                result.append(character)
            }
        }
        return result
    }
}
