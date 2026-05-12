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
    public let interface: SkillInterface?
    public let dependencies: SkillDependencies?
    public let policy: SkillPolicy?
    public let path: String
    public let scope: SkillScope
    public let pluginID: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case shortDescription = "short_description"
        case interface
        case dependencies
        case path
        case scope
        case pluginID = "plugin_id"
    }

    public init(
        name: String,
        description: String,
        shortDescription: String? = nil,
        interface: SkillInterface? = nil,
        dependencies: SkillDependencies? = nil,
        policy: SkillPolicy? = nil,
        path: String,
        scope: SkillScope,
        pluginID: String? = nil
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.interface = interface
        self.dependencies = dependencies
        self.policy = policy
        self.path = path
        self.scope = scope
        self.pluginID = pluginID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        self.interface = try container.decodeIfPresent(SkillInterface.self, forKey: .interface)
        self.dependencies = try container.decodeIfPresent(SkillDependencies.self, forKey: .dependencies)
        self.policy = nil
        self.path = try container.decode(String.self, forKey: .path)
        self.scope = try container.decode(SkillScope.self, forKey: .scope)
        self.pluginID = try container.decodeIfPresent(String.self, forKey: .pluginID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(interface, forKey: .interface)
        try container.encodeIfPresent(dependencies, forKey: .dependencies)
        try container.encode(path, forKey: .path)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(pluginID, forKey: .pluginID)
    }

    public func allowsImplicitInvocation() -> Bool {
        policy?.allowImplicitInvocation ?? true
    }

    public func matchesProductRestriction(for restrictionProduct: Product?) -> Bool {
        guard let policy else {
            return true
        }
        return policy.products.isEmpty || restrictionProduct.map { policy.products.contains($0) } == true
    }
}

public struct SkillPolicy: Codable, Equatable, Sendable {
    public let allowImplicitInvocation: Bool?
    public let products: [Product]

    private enum CodingKeys: String, CodingKey {
        case allowImplicitInvocation = "allow_implicit_invocation"
        case products
    }

    public init(allowImplicitInvocation: Bool? = nil, products: [Product] = []) {
        self.allowImplicitInvocation = allowImplicitInvocation
        self.products = products
    }
}

public struct SkillInterface: Codable, Equatable, Sendable {
    public let displayName: String?
    public let shortDescription: String?
    public let iconSmall: String?
    public let iconLarge: String?
    public let brandColor: String?
    public let defaultPrompt: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case shortDescription = "short_description"
        case iconSmall = "icon_small"
        case iconLarge = "icon_large"
        case brandColor = "brand_color"
        case defaultPrompt = "default_prompt"
    }

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        iconSmall: String? = nil,
        iconLarge: String? = nil,
        brandColor: String? = nil,
        defaultPrompt: String? = nil
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.iconSmall = iconSmall
        self.iconLarge = iconLarge
        self.brandColor = brandColor
        self.defaultPrompt = defaultPrompt
    }
}

public struct SkillDependencies: Codable, Equatable, Sendable {
    public let tools: [SkillToolDependency]

    public init(tools: [SkillToolDependency]) {
        self.tools = tools
    }
}

public struct SkillToolDependency: Codable, Equatable, Sendable {
    public let type: String
    public let value: String
    public let description: String?
    public let transport: String?
    public let command: String?
    public let url: String?

    public init(
        type: String,
        value: String,
        description: String? = nil,
        transport: String? = nil,
        command: String? = nil,
        url: String? = nil
    ) {
        self.type = type
        self.value = value
        self.description = description
        self.transport = transport
        self.command = command
        self.url = url
    }
}

public struct PluginSkillRoot: Equatable, Sendable {
    public let path: URL
    public let pluginID: String

    public init(path: URL, pluginID: String) {
        self.path = path
        self.pluginID = pluginID
    }
}

public struct RemoteInstalledPluginReference: Equatable, Sendable {
    public let marketplaceName: String
    public let pluginName: String
    public let enabled: Bool

    public init(marketplaceName: String, pluginName: String, enabled: Bool) {
        self.marketplaceName = marketplaceName
        self.pluginName = pluginName
        self.enabled = enabled
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
    public var skillRoots: [String]
    public var skillRootByPath: [String: String]

    private enum CodingKeys: String, CodingKey {
        case skills
        case errors
        case skillRoots = "skill_roots"
        case skillRootByPath = "skill_root_by_path"
    }

    public init(
        skills: [SkillMetadata] = [],
        errors: [SkillErrorInfo] = [],
        skillRoots: [String] = [],
        skillRootByPath: [String: String] = [:]
    ) {
        self.skills = skills
        self.errors = errors
        self.skillRoots = skillRoots
        self.skillRootByPath = skillRootByPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.skills = try container.decodeIfPresent([SkillMetadata].self, forKey: .skills) ?? []
        self.errors = try container.decodeIfPresent([SkillErrorInfo].self, forKey: .errors) ?? []
        self.skillRoots = try container.decodeIfPresent([String].self, forKey: .skillRoots) ?? []
        self.skillRootByPath = try container.decodeIfPresent([String: String].self, forKey: .skillRootByPath) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skills, forKey: .skills)
        try container.encode(errors, forKey: .errors)
        if !skillRoots.isEmpty {
            try container.encode(skillRoots, forKey: .skillRoots)
        }
        if !skillRootByPath.isEmpty {
            try container.encode(skillRootByPath, forKey: .skillRootByPath)
        }
    }

    public func skillsAllowedForImplicitInvocation() -> [SkillMetadata] {
        skills.filter { $0.allowsImplicitInvocation() }
    }

    public mutating func filterSkillsForProduct(_ restrictionProduct: Product?) {
        skills = skills.filter { $0.matchesProductRestriction(for: restrictionProduct) }
        retainMetadataForCurrentSkills()
    }

    public func filteredForImplicitInvocation() -> SkillLoadOutcome {
        var outcome = self
        outcome.skills = outcome.skillsAllowedForImplicitInvocation()
        outcome.retainMetadataForCurrentSkills()
        return outcome
    }

    private mutating func retainMetadataForCurrentSkills() {
        let retainedSkillPaths = Set(skills.map(\.path))
        skillRootByPath = skillRootByPath.filter { retainedSkillPaths.contains($0.key) }
        let retainedRoots = Set(skillRootByPath.values)
        skillRoots = skillRoots.filter { retainedRoots.contains($0) }
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

public enum SkillMetadataBudget: Equatable, Sendable {
    case tokens(Int)
    case characters(Int)

    public var limit: Int {
        switch self {
        case let .tokens(limit), let .characters(limit):
            return limit
        }
    }

    fileprivate func cost(_ text: String) -> Int {
        switch self {
        case .tokens:
            return Skills.approximateTokenCount(bytes: text.utf8.count)
        case .characters:
            return text.count
        }
    }

    fileprivate func cost(characters: Int, bytes: Int) -> Int {
        switch self {
        case .tokens:
            return Skills.approximateTokenCount(bytes: bytes)
        case .characters:
            return characters
        }
    }
}

public struct SkillRenderReport: Equatable, Sendable {
    public let totalCount: Int
    public let includedCount: Int
    public let omittedCount: Int
    public let truncatedDescriptionChars: Int
    public let truncatedDescriptionCount: Int

    fileprivate var averageTruncatedDescriptionChars: Int {
        guard totalCount > 0, truncatedDescriptionChars > 0 else {
            return 0
        }
        return (truncatedDescriptionChars + totalCount - 1) / totalCount
    }
}

public struct AvailableSkills: Equatable, Sendable {
    public let skillRootLines: [String]
    public let skillLines: [String]
    public let report: SkillRenderReport
    public let warningMessage: String?
}

public enum Skills {
    public static let defaultSkillMetadataCharacterBudget = 8_000
    public static let skillMetadataContextWindowPercent = 2
    public static let skillDescriptionTruncationWarningThresholdChars = 100
    private static let approximateBytesPerToken = 4

    public static let skillDescriptionTruncatedWarning =
        "Skill descriptions were shortened to fit the skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest."

    public static let skillDescriptionTruncatedWarningWithPercent =
        "Skill descriptions were shortened to fit the 2% skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest."

    public static let skillDescriptionsRemovedWarningPrefix =
        "Exceeded skills context budget. All skill descriptions were removed and"

    public static let sectionIntro = skillsIntroWithAbsolutePaths

    public static let sectionGuidance = #"""
- Discovery: The list above is the skills available in this session (name + description + file path). Skill bodies live on disk at the listed paths.
- Trigger rules: If the user names a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's description shown above, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
  1) After deciding to use a skill, open its `SKILL.md`. Read only enough to follow the workflow.
  2) When `SKILL.md` references relative paths (e.g., `scripts/foo.py`), resolve them relative to the skill directory listed above first, and only consider other paths if needed.
  3) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
  4) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
  5) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
  - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
  - Avoid deep reference-chasing: prefer opening only files directly linked from `SKILL.md` unless you're blocked.
  - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.
"""#

    public static let skillsIntroWithAbsolutePaths =
        "A skill is a set of local instructions to follow that is stored in a `SKILL.md` file. Below is the list of skills that can be used. Each entry includes a name, description, and file path so you can open the source for full instructions when using a specific skill."

    public static let skillsIntroWithAliases =
        "A skill is a set of local instructions to follow that is stored in a `SKILL.md` file. Below is the list of skills that can be used. Each entry includes a name, description, and a short path that can be expanded into an absolute path using the skill roots table."

    public static let sectionGuidanceWithAliases = #"""
- Discovery: The list above is the skills available in this session (name + description + short path). Skill bodies live on disk at the listed paths after expanding the matching alias from `### Skill roots`.
- Trigger rules: If the user names a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's description shown above, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
  1) After deciding to use a skill, expand the listed short `path` with the matching alias from `### Skill roots`, then open its `SKILL.md`. Read only enough to follow the workflow.
  2) When `SKILL.md` references relative paths (e.g., `scripts/foo.py`), resolve them relative to the directory containing that expanded `SKILL.md` first, and only consider other paths if needed.
  3) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
  4) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
  5) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
  - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
  - Avoid deep reference-chasing: prefer opening only files directly linked from `SKILL.md` unless you're blocked.
  - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.
"""#

    public static func renderSkillsSection(_ skills: [SkillMetadata]) -> String? {
        guard let available = buildAvailableSkills(
            skills: skills,
            budget: .characters(Int.max)
        ) else {
            return nil
        }
        return renderAvailableSkillsBody(
            skillRootLines: available.skillRootLines,
            skillLines: available.skillLines
        )
    }

    public static func renderAvailableSkillsBody(skillRootLines: [String], skillLines: [String]) -> String {
        let hasAliases = !skillRootLines.isEmpty
        let intro = hasAliases ? skillsIntroWithAliases : skillsIntroWithAbsolutePaths
        let guidance = hasAliases ? sectionGuidanceWithAliases : sectionGuidance
        var lines: [String] = ["## Skills", intro]
        if !skillRootLines.isEmpty {
            lines.append("### Skill roots")
            lines.append(contentsOf: skillRootLines)
        }
        lines.append("### Available skills")
        lines.append(contentsOf: skillLines)
        lines.append("### How to use skills")
        lines.append(guidance)
        return "\n\(lines.joined(separator: "\n"))\n"
    }

    public static func defaultSkillMetadataBudget(contextWindow: Int?) -> SkillMetadataBudget {
        if let contextWindow, contextWindow > 0 {
            return .tokens(max(1, contextWindow * skillMetadataContextWindowPercent / 100))
        }
        return .characters(defaultSkillMetadataCharacterBudget)
    }

    public static func buildAvailableSkills(
        skills: [SkillMetadata],
        budget: SkillMetadataBudget
    ) -> AvailableSkills? {
        buildAvailableSkills(
            lines: orderedAbsoluteSkillLines(skills),
            totalCount: skills.count,
            budget: budget,
            skillRootLines: []
        )
    }

    public static func buildAvailableSkills(
        outcome: SkillLoadOutcome,
        budget: SkillMetadataBudget
    ) -> AvailableSkills? {
        let outcome = outcome.filteredForImplicitInvocation()
        guard !outcome.skills.isEmpty else {
            return nil
        }
        guard let absolute = buildAvailableSkills(skills: outcome.skills, budget: budget) else {
            return nil
        }
        if absolute.report.omittedCount == 0, absolute.report.truncatedDescriptionChars == 0 {
            return absolute
        }
        guard let aliased = buildAliasedAvailableSkills(outcome: outcome, budget: budget) else {
            return absolute
        }
        return aliasedRenderIsBetter(aliased, than: absolute, budget: budget) ? aliased : absolute
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

    private static func buildAvailableSkills(
        lines: [SkillLine],
        totalCount: Int,
        budget: SkillMetadataBudget,
        skillRootLines: [String]
    ) -> AvailableSkills? {
        guard totalCount > 0 else {
            return nil
        }

        let (skillLines, report) = renderSkillLines(lines, totalCount: totalCount, budget: budget)
        let warningMessage: String?
        if report.omittedCount > 0 {
            let skillWord = report.omittedCount == 1 ? "skill" : "skills"
            let verb = report.omittedCount == 1 ? "was" : "were"
            warningMessage = "\(budgetWarningPrefix(budget, prefix: skillDescriptionsRemovedWarningPrefix)) \(report.omittedCount) additional \(skillWord) \(verb) not included in the model-visible skills list."
        } else if report.averageTruncatedDescriptionChars > skillDescriptionTruncationWarningThresholdChars {
            switch budget {
            case .tokens:
                warningMessage = skillDescriptionTruncatedWarningWithPercent
            case .characters:
                warningMessage = skillDescriptionTruncatedWarning
            }
        } else {
            warningMessage = nil
        }

        return AvailableSkills(
            skillRootLines: skillRootLines,
            skillLines: skillLines,
            report: report,
            warningMessage: warningMessage
        )
    }

    private static func buildAliasedAvailableSkills(
        outcome: SkillLoadOutcome,
        budget: SkillMetadataBudget
    ) -> AvailableSkills? {
        guard let plan = buildAliasPlan(outcome: outcome) else {
            return nil
        }
        let tableCost = aliasedMetadataOverheadCost(budget, skillRootLines: plan.skillRootLines)
        guard tableCost < budget.limit else {
            return nil
        }
        let adjustedBudget: SkillMetadataBudget
        switch budget {
        case .tokens:
            adjustedBudget = .tokens(budget.limit - tableCost)
        case .characters:
            adjustedBudget = .characters(budget.limit - tableCost)
        }
        let lines = orderedAliasedSkillLines(outcome.skills, plan: plan)
        return buildAvailableSkills(
            lines: lines,
            totalCount: outcome.skills.count,
            budget: adjustedBudget,
            skillRootLines: plan.skillRootLines
        )
    }

    private struct SkillAliasPlan {
        var skillRootLines: [String]
        var rootAliases: [String: String]
        var aliasRootByPath: [String: String]
    }

    private static func buildAliasPlan(outcome: SkillLoadOutcome) -> SkillAliasPlan? {
        let skillPaths = Set(outcome.skills.map { normalizeSkillPath($0.path) })
        let skillRootByPath = outcome.skillRootByPath.reduce(into: [String: String]()) { result, entry in
            let path = normalizeSkillPath(entry.key)
            guard skillPaths.contains(path) else {
                return
            }
            result[path] = normalizeSkillPath(entry.value)
        }
        let usedRoots = outcome.skillRoots
            .map(normalizeSkillPath)
            .filter { root in skillRootByPath.values.contains(root) }
        guard !usedRoots.isEmpty else {
            return nil
        }

        let pluginVersionSkillCounts = pluginVersionSkillCounts(for: skillRootByPath.values)
        let aliasRootBySkillRoot = Dictionary(
            uniqueKeysWithValues: usedRoots.map { root in
                (root, aliasRoot(forSkillRoot: root, pluginVersionSkillCounts: pluginVersionSkillCounts))
            }
        )
        var seen: Set<String> = []
        let aliasRoots = usedRoots.compactMap { root -> String? in
            guard let aliasRoot = aliasRootBySkillRoot[root], seen.insert(aliasRoot).inserted else {
                return nil
            }
            return aliasRoot
        }
        guard !aliasRoots.isEmpty else {
            return nil
        }
        let rootAliases = Dictionary(uniqueKeysWithValues: aliasRoots.enumerated().map { index, root in
            (root, "r\(index)")
        })
        let aliasRootByPath = skillRootByPath.compactMapValues { aliasRootBySkillRoot[$0] }
        let skillRootLines = aliasRoots.enumerated().map { index, root in
            "- `r\(index)` = `\(root)`"
        }
        return SkillAliasPlan(
            skillRootLines: skillRootLines,
            rootAliases: rootAliases,
            aliasRootByPath: aliasRootByPath
        )
    }

    private static func orderedAliasedSkillLines(_ skills: [SkillMetadata], plan: SkillAliasPlan) -> [SkillLine] {
        skills.sorted { lhs, rhs in
            let lhsKey = (promptScopeRank(lhs.scope), lhs.name, lhs.path)
            let rhsKey = (promptScopeRank(rhs.scope), rhs.name, rhs.path)
            return lhsKey < rhsKey
        }.map { skill in
            SkillLine(
                name: skill.name,
                description: skill.description,
                path: renderSkillPathWithAliases(skill, plan: plan)
            )
        }
    }

    private static func renderSkillPathWithAliases(_ skill: SkillMetadata, plan: SkillAliasPlan) -> String {
        let path = normalizeSkillPath(skill.path)
        guard let aliasRoot = plan.aliasRootByPath[path],
              let alias = plan.rootAliases[aliasRoot],
              let relative = relativePath(path, from: aliasRoot)
        else {
            return path
        }
        return "\(alias)/\(relative)"
    }

    private static func aliasedMetadataOverheadCost(
        _ budget: SkillMetadataBudget,
        skillRootLines: [String]
    ) -> Int {
        let absoluteBody = renderAvailableSkillsBody(skillRootLines: [], skillLines: [])
        let aliasedBody = renderAvailableSkillsBody(skillRootLines: skillRootLines, skillLines: [])
        return max(budget.cost(aliasedBody) - budget.cost(absoluteBody), 0)
    }

    private static func aliasedRenderIsBetter(
        _ aliased: AvailableSkills,
        than absolute: AvailableSkills,
        budget: SkillMetadataBudget
    ) -> Bool {
        if aliased.report.includedCount != absolute.report.includedCount {
            return aliased.report.includedCount > absolute.report.includedCount
        }
        if aliased.report.truncatedDescriptionChars != absolute.report.truncatedDescriptionChars {
            return aliased.report.truncatedDescriptionChars < absolute.report.truncatedDescriptionChars
        }
        return availableSkillsCost(budget, aliased) < availableSkillsCost(budget, absolute)
    }

    private static func availableSkillsCost(_ budget: SkillMetadataBudget, _ available: AvailableSkills) -> Int {
        let metadataCost = available.skillRootLines.isEmpty
            ? 0
            : aliasedMetadataOverheadCost(budget, skillRootLines: available.skillRootLines)
        return metadataCost + available.skillLines.reduce(0) { $0 + budget.cost($1 + "\n") }
    }

    private static func pluginVersionSkillCounts<S: Sequence>(for roots: S) -> [String: Int] where S.Element == String {
        roots.reduce(into: [String: Int]()) { counts, root in
            guard let base = pluginVersionBase(root) else {
                return
            }
            counts[base, default: 0] += 1
        }
    }

    private static func aliasRoot(forSkillRoot root: String, pluginVersionSkillCounts: [String: Int]) -> String {
        guard let pluginVersionBase = pluginVersionBase(root) else {
            return root
        }
        if (pluginVersionSkillCounts[pluginVersionBase] ?? 0) > 1 {
            return root
        }
        return pluginMarketplaceBase(root) ?? root
    }

    private static func pluginMarketplaceBase(_ path: String) -> String? {
        let components = pathComponents(path)
        guard components.count >= 3 else {
            return nil
        }
        for index in 0..<(components.count - 1) where components[index] == "plugins" && components[index + 1] == "cache" {
            let end = index + 3
            guard end <= components.count else {
                return nil
            }
            return "/" + components[..<end].joined(separator: "/")
        }
        return nil
    }

    private static func pluginVersionBase(_ path: String) -> String? {
        guard let marketplaceBase = pluginMarketplaceBase(path),
              let relative = relativePath(path, from: marketplaceBase)
        else {
            return nil
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            return nil
        }
        return "\(marketplaceBase)/\(parts[0])/\(parts[1])"
    }

    private static func relativePath(_ path: String, from root: String) -> String? {
        if path == root {
            return ""
        }
        guard path.hasPrefix(root + "/") else {
            return nil
        }
        return String(path.dropFirst(root.count + 1))
    }

    private static func pathComponents(_ path: String) -> [String] {
        normalizeSkillPath(path).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func renderSkillLines(
        _ lines: [SkillLine],
        totalCount: Int,
        budget: SkillMetadataBudget
    ) -> ([String], SkillRenderReport) {
        let fullCost = lines.reduce(0) { $0 + $1.fullCost(budget) }
        if fullCost <= budget.limit {
            return (
                lines.map(\.renderFull),
                SkillRenderReport(
                    totalCount: totalCount,
                    includedCount: lines.count,
                    omittedCount: 0,
                    truncatedDescriptionChars: 0,
                    truncatedDescriptionCount: 0
                )
            )
        }

        let minimumCost = lines.reduce(0) { $0 + $1.minimumCost(budget) }
        if minimumCost <= budget.limit {
            let rendered = renderLinesWithDescriptionBudget(
                budget,
                lines: lines,
                limit: budget.limit - minimumCost
            )
            let truncatedDescriptionChars = rendered.reduce(0) { $0 + $1.truncatedChars }
            let truncatedDescriptionCount = rendered.filter { $0.truncatedChars > 0 }.count
            return (
                rendered.map(\.line),
                SkillRenderReport(
                    totalCount: totalCount,
                    includedCount: lines.count,
                    omittedCount: 0,
                    truncatedDescriptionChars: truncatedDescriptionChars,
                    truncatedDescriptionCount: truncatedDescriptionCount
                )
            )
        }

        return renderMinimumSkillLinesUntilBudget(budget, lines: lines, totalCount: totalCount)
    }

    private static func renderMinimumSkillLinesUntilBudget(
        _ budget: SkillMetadataBudget,
        lines: [SkillLine],
        totalCount: Int
    ) -> ([String], SkillRenderReport) {
        var included: [String] = []
        var used = 0
        var omittedCount = 0
        var truncatedDescriptionChars = 0
        var truncatedDescriptionCount = 0

        for line in lines {
            let lineCost = line.minimumCost(budget)
            let descriptionCharCount = line.description.count
            if used + lineCost <= budget.limit {
                used += lineCost
                included.append(line.renderMinimum())
            } else {
                omittedCount += 1
            }

            truncatedDescriptionChars += descriptionCharCount
            if descriptionCharCount > 0 {
                truncatedDescriptionCount += 1
            }
        }

        return (
            included,
            SkillRenderReport(
                totalCount: totalCount,
                includedCount: included.count,
                omittedCount: omittedCount,
                truncatedDescriptionChars: truncatedDescriptionChars,
                truncatedDescriptionCount: truncatedDescriptionCount
            )
        )
    }

    private static func renderLinesWithDescriptionBudget(
        _ budget: SkillMetadataBudget,
        lines: [SkillLine],
        limit: Int
    ) -> [RenderedSkillLine] {
        let budgetLines = lines.map { DescriptionBudgetLine(line: $0, budget: budget) }
        var charAllocations = Array(repeating: 0, count: budgetLines.count)
        var currentExtraCosts = Array(repeating: 0, count: budgetLines.count)
        var remaining = limit

        while true {
            var changed = false
            for index in budgetLines.indices {
                let line = budgetLines[index]
                guard charAllocations[index] < line.descriptionCharCount else {
                    continue
                }

                let currentCost = currentExtraCosts[index]
                let nextChars = charAllocations[index] + 1
                let nextCost = line.extraCosts[nextChars]
                let delta = nextCost - currentCost
                if delta <= remaining {
                    charAllocations[index] = nextChars
                    currentExtraCosts[index] = nextCost
                    remaining -= delta
                    changed = true
                }
            }

            if !changed {
                break
            }
        }

        return zip(budgetLines, charAllocations).map { line, descriptionChars in
            RenderedSkillLine(
                line: line.line.render(descriptionCharacters: descriptionChars),
                truncatedChars: line.descriptionCharCount - descriptionChars
            )
        }
    }

    private static func orderedAbsoluteSkillLines(_ skills: [SkillMetadata]) -> [SkillLine] {
        skills.sorted { lhs, rhs in
            let lhsKey = (promptScopeRank(lhs.scope), lhs.name, lhs.path)
            let rhsKey = (promptScopeRank(rhs.scope), rhs.name, rhs.path)
            return lhsKey < rhsKey
        }.map { skill in
            SkillLine(
                name: skill.name,
                description: skill.description,
                path: skill.path.replacingOccurrences(of: "\\", with: "/")
            )
        }
    }

    private static func promptScopeRank(_ scope: SkillScope) -> Int {
        switch scope {
        case .system:
            return 0
        case .admin:
            return 1
        case .repo:
            return 2
        case .user:
            return 3
        }
    }

    private static func lineCost(_ budget: SkillMetadataBudget, line: String) -> Int {
        budget.cost("\(line)\n")
    }

    private static func budgetWarningPrefix(_ budget: SkillMetadataBudget, prefix: String) -> String {
        switch budget {
        case .tokens:
            return prefix.replacingOccurrences(
                of: "Exceeded skills context budget.",
                with: "Exceeded skills context budget of 2%."
            )
        case .characters:
            return prefix
        }
    }

    fileprivate static func approximateTokenCount(bytes: Int) -> Int {
        (bytes + approximateBytesPerToken - 1) / approximateBytesPerToken
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

    private struct SkillLine {
        let name: String
        let description: String
        let path: String

        var renderFull: String {
            render(description: description)
        }

        func renderMinimum() -> String {
            render(description: "")
        }

        func fullCost(_ budget: SkillMetadataBudget) -> Int {
            lineCost(budget, line: renderFull)
        }

        func minimumCost(_ budget: SkillMetadataBudget) -> Int {
            lineCost(budget, line: renderMinimum())
        }

        func render(descriptionCharacters: Int) -> String {
            guard descriptionCharacters > 0 else {
                return render(description: "")
            }
            let endIndex = description.index(
                description.startIndex,
                offsetBy: min(descriptionCharacters, description.count)
            )
            return render(description: String(description[..<endIndex]))
        }

        private func render(description: String) -> String {
            if description.isEmpty {
                return "- \(name): (file: \(path))"
            }
            return "- \(name): \(description) (file: \(path))"
        }
    }

    private struct RenderedSkillLine {
        let line: String
        let truncatedChars: Int
    }

    private struct DescriptionBudgetLine {
        let line: SkillLine
        let descriptionCharCount: Int
        let extraCosts: [Int]

        init(line: SkillLine, budget: SkillMetadataBudget) {
            self.line = line
            self.descriptionCharCount = line.description.count

            let minimumLine = line.renderMinimum()
            let minimumCharacters = minimumLine.count + 1
            let minimumBytes = minimumLine.utf8.count + 1
            let minimumCost = budget.cost(characters: minimumCharacters, bytes: minimumBytes)

            var extraCosts = [0]
            extraCosts.reserveCapacity(descriptionCharCount + 1)
            var prefixCharacters = 0
            var prefixBytes = 0
            for character in line.description {
                prefixCharacters += 1
                prefixBytes += character.utf8.count
                let renderedCharacters = minimumCharacters + prefixCharacters + 1
                let renderedBytes = minimumBytes + prefixBytes + 1
                extraCosts.append(
                    budget.cost(characters: renderedCharacters, bytes: renderedBytes) - minimumCost
                )
            }
            self.extraCosts = extraCosts
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }
}
