import Foundation

public struct UpdateVersionInfo: Equatable, Codable, Sendable {
    public var latestVersion: String
    public var lastCheckedAt: Date
    public var dismissedVersion: String?

    public init(latestVersion: String, lastCheckedAt: Date, dismissedVersion: String? = nil) {
        self.latestVersion = latestVersion
        self.lastCheckedAt = lastCheckedAt
        self.dismissedVersion = dismissedVersion
    }

    private enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case lastCheckedAt = "last_checked_at"
        case dismissedVersion = "dismissed_version"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latestVersion = try container.decode(String.self, forKey: .latestVersion)
        let rawDate = try container.decode(String.self, forKey: .lastCheckedAt)
        guard let date = Self.makeDateFormatter().date(from: rawDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastCheckedAt,
                in: container,
                debugDescription: "Invalid RFC3339 timestamp: \(rawDate)"
            )
        }
        lastCheckedAt = date
        dismissedVersion = try container.decodeIfPresent(String.self, forKey: .dismissedVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latestVersion, forKey: .latestVersion)
        try container.encode(Self.makeDateFormatter().string(from: lastCheckedAt), forKey: .lastCheckedAt)
        try container.encodeIfPresent(dismissedVersion, forKey: .dismissedVersion)
    }

    private static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

public enum UpdateVersionError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingCaskVersion
    case invalidLatestTag(String)

    public var description: String {
        switch self {
        case .missingCaskVersion:
            return "Failed to find version in Homebrew cask file"
        case let .invalidLatestTag(tag):
            return "Failed to parse latest tag name '\(tag)'"
        }
    }
}

public enum UpdateVersion {
    public static let versionFilename = "version.json"
    public static let homebrewCaskURL = "https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/c/codex.rb"
    public static let latestReleaseURL = "https://api.github.com/repos/openai/codex/releases/latest"

    public static func versionFilePath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent(versionFilename, isDirectory: false)
    }

    public static func shouldRefreshVersionInfo(_ info: UpdateVersionInfo?, now: Date = Date()) -> Bool {
        guard let info else {
            return true
        }
        return info.lastCheckedAt < now.addingTimeInterval(-20 * 60 * 60)
    }

    public static func upgradeVersion(
        cachedInfo: UpdateVersionInfo?,
        currentVersion: String,
        checkForUpdateOnStartup: Bool
    ) -> String? {
        guard checkForUpdateOnStartup,
              let cachedInfo,
              isNewer(latest: cachedInfo.latestVersion, current: currentVersion) == true
        else {
            return nil
        }
        return cachedInfo.latestVersion
    }

    public static func upgradeVersionForPopup(
        cachedInfo: UpdateVersionInfo?,
        currentVersion: String,
        checkForUpdateOnStartup: Bool
    ) -> String? {
        guard let latest = upgradeVersion(
            cachedInfo: cachedInfo,
            currentVersion: currentVersion,
            checkForUpdateOnStartup: checkForUpdateOnStartup
        ) else {
            return nil
        }
        if cachedInfo?.dismissedVersion == latest {
            return nil
        }
        return latest
    }

    public static func dismissVersion(info: UpdateVersionInfo?, version: String) -> UpdateVersionInfo? {
        guard var info else {
            return nil
        }
        info.dismissedVersion = version
        return info
    }

    public static func extractVersionFromCask(_ caskContents: String) throws -> String {
        for rawLine in caskContents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("version \""),
                  line.hasSuffix("\"")
            else {
                continue
            }
            return String(line.dropFirst("version \"".count).dropLast())
        }
        throw UpdateVersionError.missingCaskVersion
    }

    public static func extractVersionFromLatestTag(_ latestTagName: String) throws -> String {
        guard latestTagName.hasPrefix("rust-v") else {
            throw UpdateVersionError.invalidLatestTag(latestTagName)
        }
        return String(latestTagName.dropFirst("rust-v".count))
    }

    public static func isNewer(latest: String, current: String) -> Bool? {
        guard let latestVersion = parseVersion(latest),
              let currentVersion = parseVersion(current)
        else {
            return nil
        }
        return latestVersion > currentVersion
    }

    public static func parseVersion(_ version: String) -> (major: UInt64, minor: UInt64, patch: UInt64)? {
        let parts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let major = UInt64(parts[0]),
              let minor = UInt64(parts[1]),
              let patch = UInt64(parts[2])
        else {
            return nil
        }
        return (major, minor, patch)
    }
}
