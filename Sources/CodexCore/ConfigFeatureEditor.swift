import Foundation

public enum ConfigFeatureEditError: Error, Equatable, CustomStringConvertible, Sendable {
    case unknownFeature(String)

    public var description: String {
        switch self {
        case let .unknownFeature(feature):
            return "Unknown feature flag: \(feature)"
        }
    }
}

public enum ConfigFeatureEditor {
    public static func setFeatureEnabled(
        codexHome: URL,
        feature: String,
        enabled: Bool,
        profile: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard FeatureKeys.isKnown(feature) else {
            throw ConfigFeatureEditError.unknownFeature(feature)
        }

        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = fileManager.fileExists(atPath: configFile.path)
            ? try String(contentsOf: configFile, encoding: .utf8)
            : ""
        let updated = setFeatureEnabled(in: existing, feature: feature, enabled: enabled, profile: profile)
        try updated.write(to: configFile, atomically: true, encoding: .utf8)
    }

    public static func setFeatureEnabled(
        in contents: String,
        feature: String,
        enabled: Bool,
        profile: String? = nil
    ) -> String {
        let sectionName = featureSectionName(profile: profile)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var inTargetSection = false
        var foundSection = false
        var wroteFeature = false
        let assignment = "\(tomlKey(feature)) = \(enabled ? "true" : "false")"

        for line in lines {
            let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                if inTargetSection, !wroteFeature {
                    output.append(assignment)
                    wroteFeature = true
                }
                inTargetSection = trimmed == "[\(sectionName)]"
                foundSection = foundSection || inTargetSection
                output.append(line)
                continue
            }

            if inTargetSection, let equalsIndex = firstEqualsIndex(in: trimmed) {
                let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if key == tomlKey(feature) || key == feature {
                    output.append(assignment)
                    wroteFeature = true
                    continue
                }
            }
            output.append(line)
        }

        if inTargetSection, !wroteFeature {
            output.append(assignment)
            wroteFeature = true
        }

        var result = output.joined(separator: "\n")
        result = trimTrailingBlankLines(result)

        if !foundSection {
            if !result.isEmpty {
                result.append("\n\n")
            }
            result.append("[\(sectionName)]\n\(assignment)")
        }

        if !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    private static func featureSectionName(profile: String?) -> String {
        guard let profile, !profile.isEmpty else {
            return "features"
        }
        return "profiles.\(tomlKey(profile)).features"
    }

    private static func stripComment(from line: String) -> String {
        var inString = false
        var isEscaped = false
        for (index, character) in line.enumerated() {
            if character == "\\" && inString {
                isEscaped.toggle()
                continue
            }
            if character == #"""#, !isEscaped {
                inString.toggle()
            }
            if character == "#", !inString {
                let stringIndex = line.index(line.startIndex, offsetBy: index)
                return String(line[..<stringIndex])
            }
            isEscaped = false
        }
        return line
    }

    private static func firstEqualsIndex(in line: String) -> String.Index? {
        var inString = false
        var isEscaped = false
        for index in line.indices {
            let character = line[index]
            if character == "\\" && inString {
                isEscaped.toggle()
                continue
            }
            if character == #"""#, !isEscaped {
                inString.toggle()
            }
            if character == "=", !inString {
                return index
            }
            isEscaped = false
        }
        return nil
    }

    private static func tomlKey(_ key: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if key.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return key
        }
        return #""\#(key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))""#
    }

    private static func trimTrailingBlankLines(_ contents: String) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
