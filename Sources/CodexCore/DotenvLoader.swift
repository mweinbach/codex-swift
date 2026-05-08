import Foundation

public enum DotenvLoader {
    public static let illegalPrefix = "CODEX_"

    public static func loadCodexDotenv(
        codexHome: URL? = nil,
        setEnvironment: (String, String) -> Void = { key, value in setenv(key, value, 1) }
    ) {
        let home: URL
        if let codexHome {
            home = codexHome
        } else {
            do {
                home = try CodexHome.find()
            } catch {
                return
            }
        }

        let dotenv = home.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: dotenv, encoding: .utf8) else {
            return
        }

        for entry in entries(from: contents) {
            guard !entry.key.uppercased().hasPrefix(illegalPrefix) else {
                continue
            }
            setEnvironment(entry.key, entry.value)
        }
    }

    public static func entries(from contents: String) -> [(key: String, value: String)] {
        contents
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }

        if trimmed.hasPrefix("export ") {
            trimmed.removeFirst("export ".count)
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }

        guard let equalsIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }

        let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
        guard isValidKey(key) else {
            return nil
        }

        let rawValue = String(trimmed[trimmed.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)
        guard let value = parseValue(rawValue) else {
            return nil
        }

        return (key, value)
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isLetter else {
            return false
        }
        return key.allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
        }
    }

    private static func parseValue(_ rawValue: String) -> String? {
        guard let first = rawValue.first else {
            return ""
        }

        if first == "'" {
            guard rawValue.count >= 2, rawValue.last == "'" else {
                return nil
            }
            return String(rawValue.dropFirst().dropLast())
        }

        if first == "\"" {
            guard rawValue.count >= 2, rawValue.last == "\"" else {
                return nil
            }
            return unescapeDoubleQuoted(String(rawValue.dropFirst().dropLast()))
        }

        return stripUnquotedComment(rawValue).trimmingCharacters(in: .whitespaces)
    }

    private static func stripUnquotedComment(_ value: String) -> String {
        var previousWasWhitespace = false
        for index in value.indices {
            let character = value[index]
            if character == "#", previousWasWhitespace {
                return String(value[..<index])
            }
            previousWasWhitespace = character.isWhitespace
        }
        return value
    }

    private static func unescapeDoubleQuoted(_ value: String) -> String {
        var output = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                output.append(character)
                continue
            }

            guard let escaped = iterator.next() else {
                output.append("\\")
                break
            }

            switch escaped {
            case "n":
                output.append("\n")
            case "r":
                output.append("\r")
            case "t":
                output.append("\t")
            case "\"", "\\":
                output.append(escaped)
            default:
                output.append("\\")
                output.append(escaped)
            }
        }
        return output
    }
}
