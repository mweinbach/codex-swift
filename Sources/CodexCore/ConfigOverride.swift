import Foundation

public indirect enum ConfigValue: Equatable, Sendable {
    case none
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case array([ConfigValue])
    case table([String: ConfigValue])
    case range(start: Int, stop: Int, step: Int)

    public func merging(overlay: ConfigValue) -> ConfigValue {
        var base = self
        base.merge(overlay: overlay)
        return base
    }

    public mutating func merge(overlay: ConfigValue) {
        guard case let .table(overlayTable) = overlay,
              case var .table(baseTable) = self
        else {
            self = overlay
            return
        }

        for (key, value) in overlayTable {
            if var existing = baseTable[key] {
                existing.merge(overlay: value)
                baseTable[key] = existing
            } else {
                baseTable[key] = value
            }
        }
        self = .table(baseTable)
    }
}

public enum ConfigTomlRenderer {
    public static func render(_ value: ConfigValue) -> String {
        guard case let .table(table) = value else {
            return ""
        }
        var lines: [String] = []
        renderTable(table, path: [], lines: &lines)
        guard !lines.isEmpty else {
            return ""
        }
        return trimTrailingBlankLines(lines.joined(separator: "\n")) + "\n"
    }

    private static func renderTable(_ table: [String: ConfigValue], path: [String], lines: inout [String]) {
        let scalarKeys = table.keys.sorted { left, right in
            let leftRank = scalarSortRank(left, path: path)
            let rightRank = scalarSortRank(right, path: path)
            if leftRank.rank != rightRank.rank {
                return leftRank.rank < rightRank.rank
            }
            return leftRank.key < rightRank.key
        }.filter { key in
            if case .table = table[key] { return false }
            if isArrayOfTables(table[key], key: key, path: path) { return false }
            return true
        }
        for key in scalarKeys {
            guard let value = table[key] else { continue }
            lines.append("\(tomlKey(key)) = \(tomlLiteral(value))")
        }

        let arrayTableKeys = table.keys.sorted().filter { key in
            isArrayOfTables(table[key], key: key, path: path)
        }
        for key in arrayTableKeys {
            guard case let .array(entries)? = table[key] else { continue }
            let nextPath = path + [key]
            for entry in entries {
                guard case let .table(child) = entry else { continue }
                if !lines.isEmpty, lines.last?.isEmpty == false {
                    lines.append("")
                }
                lines.append("[[\(nextPath.map(tomlKey).joined(separator: "."))]]")
                renderTable(child, path: nextPath, lines: &lines)
            }
        }

        let tableKeys = table.keys.sorted().filter { key in
            if case .table = table[key] { return true }
            return false
        }
        for key in tableKeys {
            guard case let .table(child)? = table[key] else { continue }
            let nextPath = path + [key]
            if !child.isEmpty,
               child.keys.allSatisfy({ isArrayOfTables(child[$0], key: $0, path: nextPath) }) {
                renderTable(child, path: nextPath, lines: &lines)
                continue
            }
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[\(nextPath.map(tomlKey).joined(separator: "."))]")
            renderTable(child, path: nextPath, lines: &lines)
        }
    }

    private static func scalarSortRank(_ key: String, path: [String]) -> (rank: Int, key: String) {
        if path == ["skills", "config"] {
            switch key {
            case "path":
                return (0, key)
            case "name":
                return (1, key)
            case "enabled":
                return (2, key)
            default:
                return (3, key)
            }
        }
        return (0, key)
    }

    private static func isArrayOfTables(_ value: ConfigValue?, key: String, path: [String]) -> Bool {
        if path == ["tool_suggest"], ["discoverables", "disabled_tools"].contains(key) {
            return false
        }
        guard case let .array(values)? = value else {
            return false
        }
        return !values.isEmpty && values.allSatisfy { element in
            if case .table = element {
                return true
            }
            return false
        }
    }

    private static func tomlLiteral(_ value: ConfigValue) -> String {
        switch value {
        case .none:
            return "null"
        case let .string(string):
            return tomlString(string)
        case let .integer(integer):
            return String(integer)
        case let .double(double):
            return String(double)
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .array(array):
            return "[\(array.map(tomlLiteral).joined(separator: ", "))]"
        case let .table(table):
            let body = table.keys.sorted().map { key in
                "\(tomlKey(key)) = \(tomlLiteral(table[key]!))"
            }.joined(separator: ", ")
            return "{\(body)}"
        case let .range(start, stop, step):
            return "[\(starlarkRangeValues(start: start, stop: stop, step: step).map { String($0) }.joined(separator: ", "))]"
        }
    }

    static func starlarkRangeValues(start: Int, stop: Int, step: Int) -> [Int] {
        guard step != 0 else {
            return []
        }
        var values: [Int] = []
        var current = start
        if step > 0 {
            while current < stop {
                values.append(current)
                current += step
            }
        } else {
            while current > stop {
                values.append(current)
                current += step
            }
        }
        return values
    }

    private static func tomlKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return tomlString(value)
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func trimTrailingBlankLines(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

public enum PluginConfigEditor {
    public static func setEnabled(
        id: String,
        enabled: Bool,
        in config: inout ConfigValue
    ) {
        var root = configTable(config) ?? [:]
        var plugins = root["plugins"].flatMap(configTable) ?? [:]
        var plugin = plugins[id].flatMap(configTable) ?? [:]
        plugin["enabled"] = .bool(enabled)
        plugins[id] = .table(plugin)
        root["plugins"] = .table(plugins)
        config = .table(root)
    }

    @discardableResult
    public static func clear(id: String, from config: inout ConfigValue) -> Bool {
        guard var root = configTable(config),
              var plugins = root["plugins"].flatMap(configTable),
              plugins.removeValue(forKey: id) != nil
        else {
            return false
        }
        if plugins.isEmpty {
            root.removeValue(forKey: "plugins")
        } else {
            root["plugins"] = .table(plugins)
        }
        config = .table(root)
        return true
    }

    private static func configTable(_ value: ConfigValue) -> [String: ConfigValue]? {
        guard case let .table(table) = value else {
            return nil
        }
        return table
    }
}

extension ConfigValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([ConfigValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: ConfigValue].self) {
            self = .table(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported config value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .none:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .double(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .array(values):
            var container = encoder.singleValueContainer()
            try container.encode(values)
        case let .table(values):
            var container = encoder.singleValueContainer()
            try container.encode(values)
        case let .range(start, stop, step):
            var container = encoder.singleValueContainer()
            try container.encode(ConfigTomlRenderer.starlarkRangeValues(start: start, stop: stop, step: step).map { ConfigValue.integer(Int64($0)) })
        }
    }
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
            return .array(try splitTopLevel(body, separator: ",")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(parseTomlLiteral))
        }

        if text.hasPrefix("{"), text.hasSuffix("}") {
            let body = String(text.dropFirst().dropLast())
            var table: [String: ConfigValue] = [:]
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .table(table)
            }
            for pair in try splitTopLevel(body, separator: ",")
                where !pair.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
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
                case "r":
                    result.append("\r")
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
