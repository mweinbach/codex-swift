import Foundation

public enum ShellEnvironmentPolicyInherit: String, Codable, Equatable, Sendable {
    case core
    case all
    case none
}

public struct EnvironmentVariablePattern: Equatable, Sendable {
    public let pattern: String
    public let caseInsensitive: Bool

    public init(pattern: String, caseInsensitive: Bool = false) {
        self.pattern = pattern
        self.caseInsensitive = caseInsensitive
    }

    public static func newCaseInsensitive(_ pattern: String) -> EnvironmentVariablePattern {
        EnvironmentVariablePattern(pattern: pattern, caseInsensitive: true)
    }

    public func matches(_ name: String) -> Bool {
        let pattern = caseInsensitive ? pattern.lowercased() : pattern
        let name = caseInsensitive ? name.lowercased() : name
        return Self.wildcard(pattern: Array(pattern), matches: Array(name))
    }

    private static func wildcard(pattern: [Character], matches text: [Character]) -> Bool {
        var previous = Array(repeating: false, count: text.count + 1)
        previous[0] = true

        for patternIndex in pattern.indices {
            var current = Array(repeating: false, count: text.count + 1)
            if pattern[patternIndex] == "*" {
                current[0] = previous[0]
                if !text.isEmpty {
                    for textIndex in 1...text.count {
                        current[textIndex] = previous[textIndex] || current[textIndex - 1]
                    }
                }
            } else {
                if !text.isEmpty {
                    for textIndex in 1...text.count {
                        current[textIndex] = previous[textIndex - 1]
                            && (pattern[patternIndex] == "?" || pattern[patternIndex] == text[textIndex - 1])
                    }
                }
            }
            previous = current
        }

        return previous[text.count]
    }
}

public struct ShellEnvironmentPolicyToml: Codable, Equatable, Sendable {
    public var inherit: ShellEnvironmentPolicyInherit?
    public var ignoreDefaultExcludes: Bool?
    public var exclude: [String]?
    public var set: [String: String]?
    public var includeOnly: [String]?
    public var experimentalUseProfile: Bool?

    private enum CodingKeys: String, CodingKey {
        case inherit
        case ignoreDefaultExcludes = "ignore_default_excludes"
        case exclude
        case set
        case includeOnly = "include_only"
        case experimentalUseProfile = "experimental_use_profile"
    }

    public init(
        inherit: ShellEnvironmentPolicyInherit? = nil,
        ignoreDefaultExcludes: Bool? = nil,
        exclude: [String]? = nil,
        set: [String: String]? = nil,
        includeOnly: [String]? = nil,
        experimentalUseProfile: Bool? = nil
    ) {
        self.inherit = inherit
        self.ignoreDefaultExcludes = ignoreDefaultExcludes
        self.exclude = exclude
        self.set = set
        self.includeOnly = includeOnly
        self.experimentalUseProfile = experimentalUseProfile
    }
}

public struct ShellEnvironmentPolicy: Equatable, Sendable {
    public var inherit: ShellEnvironmentPolicyInherit
    public var ignoreDefaultExcludes: Bool
    public var exclude: [EnvironmentVariablePattern]
    public var set: [String: String]
    public var includeOnly: [EnvironmentVariablePattern]
    public var useProfile: Bool

    public init(
        inherit: ShellEnvironmentPolicyInherit = .all,
        ignoreDefaultExcludes: Bool = true,
        exclude: [EnvironmentVariablePattern] = [],
        set: [String: String] = [:],
        includeOnly: [EnvironmentVariablePattern] = [],
        useProfile: Bool = false
    ) {
        self.inherit = inherit
        self.ignoreDefaultExcludes = ignoreDefaultExcludes
        self.exclude = exclude
        self.set = set
        self.includeOnly = includeOnly
        self.useProfile = useProfile
    }

    public init(toml: ShellEnvironmentPolicyToml) {
        self.init(
            inherit: toml.inherit ?? .all,
            ignoreDefaultExcludes: toml.ignoreDefaultExcludes ?? true,
            exclude: (toml.exclude ?? []).map(EnvironmentVariablePattern.newCaseInsensitive),
            set: toml.set ?? [:],
            includeOnly: (toml.includeOnly ?? []).map(EnvironmentVariablePattern.newCaseInsensitive),
            useProfile: toml.experimentalUseProfile ?? false
        )
    }
}

public enum ExecEnvironment {
    public static func createEnv(
        policy: ShellEnvironmentPolicy,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        populateEnv(environment, policy: policy)
    }

    public static func populateEnv(
        _ vars: [String: String],
        policy: ShellEnvironmentPolicy
    ) -> [String: String] {
        var envMap: [String: String]
        switch policy.inherit {
        case .all:
            envMap = vars
        case .none:
            envMap = [:]
        case .core:
            let coreVars: Set<String> = [
                "HOME", "LOGNAME", "PATH", "SHELL", "USER", "USERNAME", "TMPDIR", "TEMP", "TMP"
            ]
            envMap = vars.filter { key, _ in coreVars.contains(key) }
        }

        if !policy.ignoreDefaultExcludes {
            let defaultExcludes = [
                EnvironmentVariablePattern.newCaseInsensitive("*KEY*"),
                EnvironmentVariablePattern.newCaseInsensitive("*SECRET*"),
                EnvironmentVariablePattern.newCaseInsensitive("*TOKEN*")
            ]
            envMap = envMap.filter { key, _ in !matchesAny(key, patterns: defaultExcludes) }
        }

        if !policy.exclude.isEmpty {
            envMap = envMap.filter { key, _ in !matchesAny(key, patterns: policy.exclude) }
        }

        for (key, value) in policy.set {
            envMap[key] = value
        }

        if !policy.includeOnly.isEmpty {
            envMap = envMap.filter { key, _ in matchesAny(key, patterns: policy.includeOnly) }
        }

        return envMap
    }

    private static func matchesAny(
        _ name: String,
        patterns: [EnvironmentVariablePattern]
    ) -> Bool {
        patterns.contains { $0.matches(name) }
    }
}
