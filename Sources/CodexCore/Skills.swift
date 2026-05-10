import Foundation

public enum SkillScope: String, Codable, Equatable, Sendable {
    case user
    case repo
    case system
    case admin
}

public struct SkillMetadata: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let shortDescription: String?
    public let path: String
    public let scope: SkillScope

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case shortDescription = "short_description"
        case path
        case scope
    }

    public init(
        name: String,
        description: String,
        shortDescription: String? = nil,
        path: String,
        scope: SkillScope
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.path = path
        self.scope = scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        self.path = try container.decode(String.self, forKey: .path)
        self.scope = try container.decode(SkillScope.self, forKey: .scope)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encode(path, forKey: .path)
        try container.encode(scope, forKey: .scope)
    }
}

public struct SkillErrorInfo: Codable, Equatable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public typealias SkillError = SkillErrorInfo

public struct SkillLoadOutcome: Codable, Equatable, Sendable {
    public var skills: [SkillMetadata]
    public var errors: [SkillErrorInfo]

    public init(skills: [SkillMetadata] = [], errors: [SkillErrorInfo] = []) {
        self.skills = skills
        self.errors = errors
    }
}

public struct SkillsListEntry: Codable, Equatable, Sendable {
    public let cwd: String
    public let skills: [SkillMetadata]
    public let errors: [SkillErrorInfo]

    public init(cwd: String, skills: [SkillMetadata], errors: [SkillErrorInfo]) {
        self.cwd = cwd
        self.skills = skills
        self.errors = errors
    }
}

public struct ListSkillsResponseEvent: Codable, Equatable, Sendable {
    public let skills: [SkillsListEntry]

    public init(skills: [SkillsListEntry]) {
        self.skills = skills
    }
}

public struct SkillInjections: Equatable, Sendable {
    public var items: [ResponseItem]
    public var warnings: [String]

    public init(items: [ResponseItem] = [], warnings: [String] = []) {
        self.items = items
        self.warnings = warnings
    }
}

public enum Skills {
    public static let sectionIntro =
        "These skills are discovered at startup from multiple local sources. Each entry includes a name, description, and file path so you can open the source for full instructions."

    public static let sectionGuidance = #"""
- Discovery: Available skills are listed in project docs and may also appear in a runtime "## Skills" section (name + description + file path). These are the sources of truth; skill bodies live on disk at the listed paths.
- Trigger rules: If the user names a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's description, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
  1) After deciding to use a skill, open its `SKILL.md`. Read only enough to follow the workflow.
  2) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
  3) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
  4) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Description as trigger: The YAML `description` in `SKILL.md` is the primary trigger signal; rely on it to decide applicability. If unsure, ask a brief clarification before proceeding.
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
  - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
  - Avoid deeply nested references; prefer one-hop files explicitly linked from `SKILL.md`.
  - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.
"""#

    public static func renderSkillsSection(_ skills: [SkillMetadata]) -> String? {
        guard !skills.isEmpty else {
            return nil
        }

        var lines: [String] = [
            "## Skills",
            sectionIntro
        ]

        for skill in skills {
            let path = skill.path.replacingOccurrences(of: "\\", with: "/")
            lines.append("- \(skill.name): \(skill.description) (file: \(path))")
        }

        lines.append(sectionGuidance)
        return lines.joined(separator: "\n")
    }

    public static func buildSkillInjections(
        inputs: [UserInput],
        skills outcome: SkillLoadOutcome?,
        readFile: (String) throws -> String
    ) -> SkillInjections {
        guard !inputs.isEmpty, let outcome else {
            return SkillInjections()
        }

        let mentionedSkills = collectExplicitSkillMentions(inputs: inputs, skills: outcome.skills)
        guard !mentionedSkills.isEmpty else {
            return SkillInjections()
        }

        var result = SkillInjections(items: [], warnings: [])
        result.items.reserveCapacity(mentionedSkills.count)

        for skill in mentionedSkills {
            do {
                let contents = try readFile(skill.path)
                result.items.append(SkillInstructions(
                    name: skill.name,
                    path: skill.path,
                    contents: contents
                ).asResponseItem())
            } catch {
                result.warnings.append("Failed to load skill \(skill.name) at \(skill.path): \(error)")
            }
        }

        return result
    }

    public static func buildSkillInjections(
        inputs: [UserInput],
        skills outcome: SkillLoadOutcome?,
        fileManager _: FileManager = .default
    ) -> SkillInjections {
        buildSkillInjections(inputs: inputs, skills: outcome) { path in
            try String(contentsOfFile: path, encoding: .utf8)
        }
    }

    public static func collectExplicitSkillMentions(
        inputs: [UserInput],
        skills: [SkillMetadata],
        disabledPaths: Set<String> = [],
        connectorSlugCounts: [String: Int] = [:]
    ) -> [SkillMetadata] {
        let skillNameCounts = skillNameCounts(skills: skills, disabledPaths: disabledPaths)
        var selected: [SkillMetadata] = []
        var seen: Set<String> = []
        var seenPaths: Set<String> = []
        var blockedPlainNames: Set<String> = []

        for input in inputs {
            guard case let .skill(name, path) = input else {
                continue
            }
            blockedPlainNames.insert(name)
            guard !disabledPaths.contains(path), !seenPaths.contains(path) else {
                continue
            }
            if let skill = skills.first(where: { $0.path == path }) {
                seenPaths.insert(skill.path)
                seen.insert(skill.name)
                selected.append(skill)
            }
        }

        for input in inputs {
            guard case let .text(text, _) = input else {
                continue
            }
            let mentions = extractToolMentions(text)
            selectSkillsFromMentions(
                mentions,
                skills: skills,
                disabledPaths: disabledPaths,
                skillNameCounts: skillNameCounts,
                connectorSlugCounts: connectorSlugCounts,
                blockedPlainNames: blockedPlainNames,
                seenNames: &seen,
                seenPaths: &seenPaths,
                selected: &selected
            )
        }

        return selected
    }

    private static func selectSkillsFromMentions(
        _ mentions: ToolMentions,
        skills: [SkillMetadata],
        disabledPaths: Set<String>,
        skillNameCounts: [String: Int],
        connectorSlugCounts: [String: Int],
        blockedPlainNames: Set<String>,
        seenNames: inout Set<String>,
        seenPaths: inout Set<String>,
        selected: inout [SkillMetadata]
    ) {
        guard !mentions.isEmpty else {
            return
        }

        let mentionSkillPaths = Set(mentions.paths.compactMap { path -> String? in
            switch toolKind(forPath: path) {
            case .app, .mcp, .plugin:
                return nil
            case .skill, .other:
                return normalizeSkillPath(path)
            }
        })

        for skill in skills {
            guard !disabledPaths.contains(skill.path), !seenPaths.contains(skill.path) else {
                continue
            }
            if mentionSkillPaths.contains(skill.path) {
                seenPaths.insert(skill.path)
                seenNames.insert(skill.name)
                selected.append(skill)
            }
        }

        for skill in skills {
            guard !disabledPaths.contains(skill.path), !seenPaths.contains(skill.path) else {
                continue
            }
            guard !blockedPlainNames.contains(skill.name), mentions.plainNames.contains(skill.name) else {
                continue
            }

            let skillCount = skillNameCounts[skill.name] ?? 0
            let connectorCount = connectorSlugCounts[skill.name.lowercased()] ?? 0
            guard skillCount == 1, connectorCount == 0 else {
                continue
            }

            if seenNames.insert(skill.name).inserted {
                seenPaths.insert(skill.path)
                selected.append(skill)
            }
        }
    }

    private static func skillNameCounts(skills: [SkillMetadata], disabledPaths: Set<String>) -> [String: Int] {
        var counts: [String: Int] = [:]
        for skill in skills where !disabledPaths.contains(skill.path) {
            counts[skill.name, default: 0] += 1
        }
        return counts
    }

    private struct ToolMentions {
        var names: Set<String> = []
        var paths: Set<String> = []
        var plainNames: Set<String> = []

        var isEmpty: Bool {
            names.isEmpty && paths.isEmpty
        }
    }

    private enum ToolMentionKind {
        case app
        case mcp
        case plugin
        case skill
        case other
    }

    private static func extractToolMentions(_ text: String) -> ToolMentions {
        let bytes = Array(text.utf8)
        var mentions = ToolMentions()
        var index = 0

        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "["),
               let linked = parseLinkedToolMention(bytes: bytes, start: index) {
                if !isCommonEnvironmentVariable(linked.name) {
                    switch toolKind(forPath: linked.path) {
                    case .app, .mcp, .plugin:
                        break
                    case .skill, .other:
                        mentions.names.insert(linked.name)
                    }
                    mentions.paths.insert(linked.path)
                }
                index = linked.endIndex
                continue
            }

            guard bytes[index] == UInt8(ascii: "$") else {
                index += 1
                continue
            }

            let nameStart = index + 1
            guard nameStart < bytes.count, isMentionNameCharacter(bytes[nameStart]) else {
                index += 1
                continue
            }

            var nameEnd = nameStart + 1
            while nameEnd < bytes.count, isMentionNameCharacter(bytes[nameEnd]) {
                nameEnd += 1
            }

            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
            if !isCommonEnvironmentVariable(name) {
                mentions.names.insert(name)
                mentions.plainNames.insert(name)
            }
            index = nameEnd
        }

        return mentions
    }

    private static func parseLinkedToolMention(
        bytes: [UInt8],
        start: Int
    ) -> (name: String, path: String, endIndex: Int)? {
        let sigilIndex = start + 1
        guard bytes.indices.contains(sigilIndex), bytes[sigilIndex] == UInt8(ascii: "$") else {
            return nil
        }

        let nameStart = sigilIndex + 1
        guard bytes.indices.contains(nameStart), isMentionNameCharacter(bytes[nameStart]) else {
            return nil
        }

        var nameEnd = nameStart + 1
        while bytes.indices.contains(nameEnd), isMentionNameCharacter(bytes[nameEnd]) {
            nameEnd += 1
        }
        guard bytes.indices.contains(nameEnd), bytes[nameEnd] == UInt8(ascii: "]") else {
            return nil
        }

        var pathStart = nameEnd + 1
        while bytes.indices.contains(pathStart), bytes[pathStart].isASCIIWhitespace {
            pathStart += 1
        }
        guard bytes.indices.contains(pathStart), bytes[pathStart] == UInt8(ascii: "(") else {
            return nil
        }

        var pathEnd = pathStart + 1
        while bytes.indices.contains(pathEnd), bytes[pathEnd] != UInt8(ascii: ")") {
            pathEnd += 1
        }
        guard bytes.indices.contains(pathEnd), bytes[pathEnd] == UInt8(ascii: ")") else {
            return nil
        }

        let rawPath = String(decoding: bytes[(pathStart + 1)..<pathEnd], as: UTF8.self)
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }

        return (
            name: String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self),
            path: path,
            endIndex: pathEnd + 1
        )
    }

    private static func toolKind(forPath path: String) -> ToolMentionKind {
        if path.hasPrefix("app://") {
            return .app
        }
        if path.hasPrefix("mcp://") {
            return .mcp
        }
        if path.hasPrefix("plugin://") {
            return .plugin
        }
        if path.hasPrefix("skill://") || lastPathComponent(path).lowercased() == "skill.md" {
            return .skill
        }
        return .other
    }

    private static func lastPathComponent(_ path: String) -> Substring {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? Substring(path)
    }

    private static func normalizeSkillPath(_ path: String) -> String {
        if path.hasPrefix("skill://") {
            return String(path.dropFirst("skill://".count))
        }
        return path
    }

    private static func isCommonEnvironmentVariable(_ name: String) -> Bool {
        switch name.uppercased() {
        case "PATH", "HOME", "USER", "SHELL", "PWD", "TMPDIR", "TEMP", "TMP", "LANG", "TERM", "XDG_CONFIG_HOME":
            return true
        default:
            return false
        }
    }

    private static func isMentionNameCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "_"),
             UInt8(ascii: "-"),
             UInt8(ascii: ":"):
            return true
        default:
            return false
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }
}
