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
        skills: [SkillMetadata]
    ) -> [SkillMetadata] {
        var selected: [SkillMetadata] = []
        var seen: Set<String> = []

        for input in inputs {
            guard case let .skill(name, path) = input else {
                continue
            }
            guard seen.insert(name).inserted else {
                continue
            }
            if let skill = skills.first(where: { $0.name == name && $0.path == path }) {
                selected.append(skill)
            }
        }

        return selected
    }
}
