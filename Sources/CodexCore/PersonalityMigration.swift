import Darwin
import Foundation

public enum PersonalityMigrationStatus: Equatable, Sendable {
    case skippedMarker
    case skippedExplicitPersonality
    case skippedNoSessions
    case applied
}

public enum PersonalityMigration {
    public static let markerFilename = ".personality_migration"

    public static func maybeMigratePersonality(
        codexHome: URL,
        configToml: URL? = nil,
        defaultModelProvider: String = "openai"
    ) throws -> PersonalityMigrationStatus {
        let codexHome = codexHome.standardizedFileURL
        let marker = codexHome.appendingPathComponent(markerFilename, isDirectory: false)
        if FileManager.default.fileExists(atPath: marker.path) {
            return .skippedMarker
        }

        let configURL = (configToml ?? codexHome.appendingPathComponent("config.toml", isDirectory: false))
            .standardizedFileURL
        let config = try readConfigValue(at: configURL)
        let root = config.tableValue ?? [:]
        let activeProfile = try activeProfileName(in: root)
        let selectedProfile = try selectedProfile(activeProfile, in: root)

        if root["personality"] != nil || selectedProfile?["personality"] != nil {
            try writeMarker(marker)
            return .skippedExplicitPersonality
        }

        let provider = try selectedProfile?["model_provider"].map {
            try stringValue($0, key: "profiles.\(activeProfile ?? "<active>").model_provider")
        } ?? root["model_provider"].map {
            try stringValue($0, key: "model_provider")
        } ?? defaultModelProvider

        guard try hasRecordedSession(codexHome: codexHome, defaultProvider: provider) else {
            try writeMarker(marker)
            return .skippedNoSessions
        }

        try persistPragmaticPersonality(config: config, to: configURL)
        try writeMarker(marker)
        return .applied
    }

    private static func readConfigValue(at url: URL) throws -> ConfigValue {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .table([:])
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try ConfigTomlParser.parse(contents)
    }

    private static func activeProfileName(in root: [String: ConfigValue]) throws -> String? {
        guard let value = root["profile"] else {
            return nil
        }
        return try stringValue(value, key: "profile")
    }

    private static func selectedProfile(
        _ activeProfile: String?,
        in root: [String: ConfigValue]
    ) throws -> [String: ConfigValue]? {
        guard let activeProfile else {
            return nil
        }
        guard case let .table(profiles)? = root["profiles"],
              case let .table(profile)? = profiles[activeProfile]
        else {
            throw CodexConfigLoadError.profileNotFound(activeProfile)
        }
        return profile
    }

    private static func stringValue(_ value: ConfigValue, key: String) throws -> String {
        guard case let .string(string) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return string
    }

    private static func hasRecordedSession(codexHome: URL, defaultProvider: String) throws -> Bool {
        let active = try RolloutListing.getConversations(
            codexHome: codexHome,
            pageSize: 1,
            defaultProvider: defaultProvider
        )
        if !active.items.isEmpty {
            return true
        }

        let archived = try RolloutListing.getConversations(
            codexHome: codexHome,
            pageSize: 1,
            archivedOnly: true,
            defaultProvider: defaultProvider
        )
        return !archived.items.isEmpty
    }

    private static func persistPragmaticPersonality(config: ConfigValue, to url: URL) throws {
        var root = config.tableValue ?? [:]
        root["personality"] = .string(Personality.pragmatic.rawValue)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ConfigTomlRenderer.render(.table(root)).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeMarker(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if descriptor == -1 {
            if errno == EEXIST {
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let bytes = Array("v1\n".utf8)
        let written = bytes.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        let closeResult = close(descriptor)
        if written != bytes.count {
            throw POSIXError(.EIO)
        }
        if closeResult == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

private extension ConfigValue {
    var tableValue: [String: ConfigValue]? {
        guard case let .table(table) = self else {
            return nil
        }
        return table
    }
}
