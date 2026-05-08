import Foundation

public enum OllamaHelpers {
    public static let minimumResponsesVersion = OllamaVersion(major: 0, minor: 13, patch: 4)

    public static func isOpenAICompatibleBaseURL(_ baseURL: String) -> Bool {
        trimTrailingSlashes(baseURL).hasSuffix("/v1")
    }

    public static func baseURLToHostRoot(_ baseURL: String) -> String {
        let trimmed = trimTrailingSlashes(baseURL)
        guard trimmed.hasSuffix("/v1") else {
            return trimmed
        }

        let withoutV1 = String(trimmed.dropLast(3))
        return trimTrailingSlashes(withoutV1)
    }

    public static func pullEvents(from update: OllamaPullUpdate) -> [OllamaPullEvent] {
        var events: [OllamaPullEvent] = []
        if let status = update.status {
            events.append(.status(status))
            if status == "success" {
                events.append(.success)
            }
        }

        if update.total != nil || update.completed != nil {
            events.append(.chunkProgress(
                digest: update.digest ?? "",
                total: update.total,
                completed: update.completed
            ))
        }
        return events
    }

    public static func pullEvents(fromJSONData data: Data) throws -> [OllamaPullEvent] {
        try pullEvents(from: JSONDecoder().decode(OllamaPullUpdate.self, from: data))
    }

    public static func parseVersion(_ versionString: String) -> OllamaVersion? {
        OllamaVersion(versionString)
    }

    public static func supportsResponses(version: OllamaVersion) -> Bool {
        version == .devZero || version >= minimumResponsesVersion
    }

    public static func supportsResponses(versionString: String) -> Bool? {
        parseVersion(versionString).map(supportsResponses(version:))
    }

    public static func unsupportedResponsesVersionMessage(for version: OllamaVersion) -> String {
        "Ollama \(version.description) is too old. Codex requires Ollama \(minimumResponsesVersion.description) or newer."
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

public struct OllamaVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    public static let devZero = OllamaVersion(major: 0, minor: 0, patch: 0)

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let buildMetadata: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil, buildMetadata: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(_ versionString: String) {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let releaseAndBuildMetadata = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard releaseAndBuildMetadata.count <= 2 else {
            return nil
        }

        let releaseAndPrerelease = releaseAndBuildMetadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard releaseAndPrerelease.count <= 2 else {
            return nil
        }

        let numbers = releaseAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Int(numbers[0]),
              let minor = Int(numbers[1]),
              let patch = Int(numbers[2]),
              major >= 0,
              minor >= 0,
              patch >= 0
        else {
            return nil
        }

        let prerelease = releaseAndPrerelease.count == 2 ? releaseAndPrerelease[1] : nil
        let buildMetadata = releaseAndBuildMetadata.count == 2 ? releaseAndBuildMetadata[1] : nil
        guard Self.isValidPrerelease(prerelease),
              Self.isValidBuildMetadata(buildMetadata)
        else {
            return nil
        }

        self.init(major: major, minor: minor, patch: patch, prerelease: prerelease, buildMetadata: buildMetadata)
    }

    public var description: String {
        var release = "\(major).\(minor).\(patch)"
        if let prerelease {
            release += "-\(prerelease)"
        }
        if let buildMetadata {
            release += "+\(buildMetadata)"
        }
        return release
    }

    public static func < (lhs: OllamaVersion, rhs: OllamaVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (left?, right?):
            return Self.comparePrerelease(left, right) == .orderedAscending
        }
    }

    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftIdentifiers = lhs.split(separator: ".").map(String.init)
        let rightIdentifiers = rhs.split(separator: ".").map(String.init)

        for index in 0..<min(leftIdentifiers.count, rightIdentifiers.count) {
            let left = leftIdentifiers[index]
            let right = rightIdentifiers[index]
            if left == right {
                continue
            }

            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (left?, right?):
                return left < right ? .orderedAscending : .orderedDescending
            case (_?, nil):
                return .orderedAscending
            case (nil, _?):
                return .orderedDescending
            case (nil, nil):
                return left < right ? .orderedAscending : .orderedDescending
            }
        }

        if leftIdentifiers.count == rightIdentifiers.count {
            return .orderedSame
        }
        return leftIdentifiers.count < rightIdentifiers.count ? .orderedAscending : .orderedDescending
    }

    private static func isValidPrerelease(_ prerelease: String?) -> Bool {
        guard let prerelease else {
            return true
        }
        let identifiers = prerelease.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !identifiers.isEmpty else {
            return false
        }
        return identifiers.allSatisfy { identifier in
            isSemverIdentifier(identifier)
                && !(identifier.count > 1 && identifier.allSatisfy(\.isNumber) && identifier.first == "0")
        }
    }

    private static func isValidBuildMetadata(_ buildMetadata: String?) -> Bool {
        guard let buildMetadata else {
            return true
        }
        let identifiers = buildMetadata.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !identifiers.isEmpty else {
            return false
        }
        return identifiers.allSatisfy(isSemverIdentifier)
    }

    private static func isSemverIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }
}

public struct OllamaPullUpdate: Equatable, Decodable, Sendable {
    public let status: String?
    public let digest: String?
    public let total: UInt64?
    public let completed: UInt64?

    public init(status: String? = nil, digest: String? = nil, total: UInt64? = nil, completed: UInt64? = nil) {
        self.status = status
        self.digest = digest
        self.total = total
        self.completed = completed
    }
}

public enum OllamaPullEvent: Equatable, Sendable {
    case status(String)
    case chunkProgress(digest: String, total: UInt64?, completed: UInt64?)
    case success
    case error(String)
}
