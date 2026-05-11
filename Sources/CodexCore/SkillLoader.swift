import Foundation

public enum SkillParseError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingFrontmatter
    case missingField(String)
    case invalidField(String, String)

    public var description: String {
        switch self {
        case .missingFrontmatter:
            return "missing frontmatter"
        case let .missingField(field):
            return "missing \(field)"
        case let .invalidField(field, reason):
            return "invalid \(field): \(reason)"
        }
    }
}

public enum SkillLoader {
    public static func load(
        cwd: URL,
        codexHome: URL,
        configLayerStack: ConfigLayerStack? = nil,
        pluginSkillRoots: [PluginSkillRoot] = [],
        includeSystemSkills: Bool = true,
        fileManager: FileManager = .default
    ) -> SkillLoadOutcome {
        var outcome = SkillLoadOutcome()
        for root in resolvedSkillRoots(
            cwd: cwd,
            codexHome: codexHome,
            pluginSkillRoots: pluginSkillRoots,
            includeSystemSkills: includeSystemSkills,
            fileManager: fileManager
        ) {
            let standardizedRoot = root.path.resolvingSymlinksInPath().standardizedFileURL
            discoverSkills(
                root: standardizedRoot,
                scope: root.scope,
                pluginID: root.pluginID,
                outcome: &outcome,
                fileManager: fileManager
            )
        }

        let rules = configLayerStack.map(skillConfigRules) ?? []
        if !rules.isEmpty {
            outcome.skills = outcome.skills.filter { isSkillEnabled($0, rules: rules) }
        }

        finalize(outcome: &outcome)
        return outcome
    }

    public static func skillRoots(
        cwd: URL,
        codexHome: URL,
        includeSystemSkills: Bool = true,
        fileManager: FileManager = .default
    ) -> [(path: URL, scope: SkillScope)] {
        var roots: [(URL, SkillScope)] = []
        if let repoRoot = repoSkillsRoot(cwd: cwd, fileManager: fileManager) {
            roots.append((repoRoot, .repo))
        }
        roots.append((codexHome.appendingPathComponent("skills", isDirectory: true), .user))
        if includeSystemSkills {
            roots.append((codexHome.appendingPathComponent("skills/.system", isDirectory: true), .system))
        }
        #if os(Windows)
        #else
        roots.append((URL(fileURLWithPath: "/etc/codex/skills", isDirectory: true), .admin))
        #endif
        return roots
    }

    public static func discoverSkills(
        root: URL,
        scope: SkillScope,
        pluginID: String? = nil,
        outcome: inout SkillLoadOutcome,
        fileManager: FileManager = .default
    ) {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard isDirectory(root, fileManager: fileManager) else {
            return
        }

        var queue = [root]
        var rootAdded = false
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for entry in entries {
                guard entry.lastPathComponent.first != "." else {
                    continue
                }
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    continue
                }
                if values?.isDirectory == true {
                    queue.append(entry)
                    continue
                }
                if values?.isRegularFile == true, entry.lastPathComponent == "SKILL.md" {
                    do {
                        let skill = try parseSkillFile(
                            entry,
                            scope: scope,
                            pluginID: pluginID,
                            fileManager: fileManager
                        )
                        outcome.skills.append(skill)
                        outcome.skillRootByPath[skill.path] = root.path
                        if !rootAdded {
                            outcome.skillRoots.append(root.path)
                            rootAdded = true
                        }
                    } catch {
                        if scope != .system {
                            outcome.errors.append(SkillErrorInfo(path: entry.path, message: String(describing: error)))
                        }
                    }
                }
            }
        }
    }

    public static func parseSkillFile(
        _ url: URL,
        scope: SkillScope,
        pluginID: String? = nil,
        fileManager: FileManager = .default
    ) throws -> SkillMetadata {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let frontmatter = extractSkillFrontmatter(contents) else {
            throw SkillParseError.missingFrontmatter
        }
        let fields = parseSkillFrontmatter(frontmatter)
        let baseName = sanitizeSkillLine(fields["name"]).flatMap { $0.isEmpty ? nil : $0 } ??
            defaultSkillName(for: url)
        let description = sanitizeSkillLine(fields["description"])
        let shortDescription = sanitizeSkillLine(fields["metadata.short-description"])

        let name = namespacedSkillName(for: url, baseName: baseName, fileManager: fileManager)
        guard name.count <= 64 else {
            throw SkillParseError.invalidField("name", "exceeds maximum length of 64 characters")
        }
        guard let description, !description.isEmpty else {
            throw SkillParseError.missingField("description")
        }
        guard description.count <= 1024 else {
            throw SkillParseError.invalidField("description", "exceeds maximum length of 1024 characters")
        }
        if let shortDescription, shortDescription.count > 1024 {
            throw SkillParseError.invalidField(
                "metadata.short-description",
                "exceeds maximum length of 1024 characters"
            )
        }

        return SkillMetadata(
            name: name,
            description: description,
            shortDescription: shortDescription?.isEmpty == false ? shortDescription : nil,
            path: url.resolvingSymlinksInPath().standardizedFileURL.path,
            scope: scope,
            pluginID: pluginID
        )
    }

    private static func resolvedSkillRoots(
        cwd: URL,
        codexHome: URL,
        pluginSkillRoots: [PluginSkillRoot],
        includeSystemSkills: Bool,
        fileManager: FileManager
    ) -> [(path: URL, scope: SkillScope, pluginID: String?)] {
        var roots = skillRoots(
            cwd: cwd,
            codexHome: codexHome,
            includeSystemSkills: includeSystemSkills,
            fileManager: fileManager
        ).map { (path: $0.path, scope: $0.scope, pluginID: Optional<String>.none) }
        roots.append(contentsOf: pluginSkillRoots.map { (path: $0.path, scope: .user, pluginID: $0.pluginID) })

        var seenPaths: Set<String> = []
        return roots.filter { root in
            seenPaths.insert(root.path.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
    }

    private static func finalize(outcome: inout SkillLoadOutcome) {
        var seenPaths: Set<String> = []
        outcome.skills = outcome.skills.filter { seenPaths.insert($0.path).inserted }
        let retainedSkillPaths = Set(outcome.skills.map(\.path))
        outcome.skillRootByPath = outcome.skillRootByPath.filter { retainedSkillPaths.contains($0.key) }
        let usedRoots = Set(outcome.skillRootByPath.values)
        outcome.skillRoots = outcome.skillRoots.filter { usedRoots.contains($0) }
        outcome.skills.sort {
            let lhsKey = (promptScopeRank($0.scope), $0.name, $0.path)
            let rhsKey = (promptScopeRank($1.scope), $1.name, $1.path)
            return lhsKey < rhsKey
        }
    }

    private static func repoSkillsRoot(cwd: URL, fileManager: FileManager) -> URL? {
        let base = isDirectory(cwd, fileManager: fileManager) ? cwd : cwd.deletingLastPathComponent()
        let normalizedBase = base.resolvingSymlinksInPath().standardizedFileURL
        let repoRoot = GitInfoCollector.resolveRootGitProjectForTrust(cwd: normalizedBase) ??
            GitInfoCollector.gitRepoRoot(baseDir: normalizedBase)

        if let repoRoot {
            var current = normalizedBase
            while true {
                let candidate = current
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                if isDirectory(candidate, fileManager: fileManager) {
                    return candidate
                }
                if current.standardizedFileURL.path == repoRoot.standardizedFileURL.path {
                    return nil
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path {
                    return nil
                }
                current = parent
            }
        }

        let candidate = normalizedBase
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        return isDirectory(candidate, fileManager: fileManager) ? candidate : nil
    }

    private static func skillConfigRules(_ stack: ConfigLayerStack) -> [SkillConfigRule] {
        var rules: [SkillConfigRule] = []
        for layer in stack.getLayers(ordering: .lowestPrecedenceFirst) {
            guard layer.name.isUserOrSessionFlags else {
                continue
            }
            for rule in skillConfigRules(from: layer.config) {
                rules.removeAll { $0.selector == rule.selector }
                rules.append(rule)
            }
        }
        return rules
    }

    private static func skillConfigRules(from config: ConfigValue) -> [SkillConfigRule] {
        guard case let .table(root) = config,
              case let .table(skills)? = root["skills"],
              case let .array(entries)? = skills["config"]
        else {
            return []
        }
        return entries.compactMap { entry in
            guard case let .table(table) = entry,
                  case let .bool(enabled)? = table["enabled"]
            else {
                return nil
            }
            if case let .string(path)? = table["path"],
               table["name"] == nil {
                return SkillConfigRule(selector: .path(normalizeSkillConfigPath(path)), enabled: enabled)
            }
            if case let .string(name)? = table["name"],
               table["path"] == nil {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : SkillConfigRule(selector: .name(trimmed), enabled: enabled)
            }
            return nil
        }
    }

    private static func isSkillEnabled(_ skill: SkillMetadata, rules: [SkillConfigRule]) -> Bool {
        var enabled = true
        let normalizedPath = normalizeSkillConfigPath(skill.path)
        for rule in rules where rule.matches(name: skill.name, path: normalizedPath) {
            enabled = rule.enabled
        }
        return enabled
    }

    private static func extractSkillFrontmatter(_ contents: String) -> String? {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }
        lines.removeFirst()
        var frontmatter: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                return frontmatter.isEmpty ? nil : frontmatter.joined(separator: "\n")
            }
            frontmatter.append(line)
        }
        return nil
    }

    private static func parseSkillFrontmatter(_ frontmatter: String) -> [String: String] {
        var fields: [String: String] = [:]
        var prefix: String?
        for rawLine in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            if !line.hasPrefix(" "), !line.hasPrefix("\t"), trimmed.hasSuffix(":") {
                prefix = String(trimmed.dropLast())
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                continue
            }
            let isNested = line.hasPrefix(" ") || line.hasPrefix("\t")
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: colon)
            let value = trimmingMatchingQuotes(
                String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            fields[[isNested ? prefix : nil, key].compactMap(\.self).joined(separator: ".")] = value
            if !isNested {
                prefix = nil
            }
        }
        return fields
    }

    private static func sanitizeSkillLine(_ value: String?) -> String? {
        value?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func defaultSkillName(for url: URL) -> String {
        let parentName = sanitizeSkillLine(url.deletingLastPathComponent().lastPathComponent)
        guard let parentName, !parentName.isEmpty else {
            return "skill"
        }
        return parentName
    }

    private static func trimmingMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }
        if (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func namespacedSkillName(for url: URL, baseName: String, fileManager: FileManager) -> String {
        guard let namespace = pluginNamespace(forSkillPath: url, fileManager: fileManager) else {
            return baseName
        }
        return "\(namespace):\(baseName)"
    }

    private static func pluginNamespace(forSkillPath url: URL, fileManager: FileManager) -> String? {
        var currentPath = (url.resolvingSymlinksInPath().standardizedFileURL.path as NSString).standardizingPath
        while true {
            let current = URL(fileURLWithPath: currentPath)
            if let namespace = pluginManifestName(pluginRoot: current, fileManager: fileManager) {
                return namespace
            }

            let parent = (currentPath as NSString).deletingLastPathComponent
            let parentPath = parent.isEmpty ? "/" : parent
            if parentPath == currentPath {
                return nil
            }
            currentPath = parentPath
        }
    }

    private static func pluginManifestName(pluginRoot: URL, fileManager: FileManager) -> String? {
        for relativePath in [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"] {
            let manifest = pluginRoot.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: manifest.path),
                  let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }
            let rawName = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawName.isEmpty {
                return pluginRoot.lastPathComponent
            }
            return rawName
        }
        return nil
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func promptScopeRank(_ scope: SkillScope) -> Int {
        switch scope {
        case .repo:
            return 0
        case .user:
            return 1
        case .system:
            return 2
        case .admin:
            return 3
        }
    }
}

private extension ConfigLayerSource {
    var isUserOrSessionFlags: Bool {
        switch self {
        case .user, .sessionFlags:
            return true
        case .mdm, .system, .project, .legacyManagedConfigTomlFromFile, .legacyManagedConfigTomlFromMdm:
            return false
        }
    }
}

private enum SkillConfigRuleSelector: Equatable, Sendable {
    case name(String)
    case path(String)
}

private struct SkillConfigRule: Equatable, Sendable {
    let selector: SkillConfigRuleSelector
    let enabled: Bool

    func matches(name: String, path: String) -> Bool {
        switch selector {
        case let .name(expected):
            return expected == name
        case let .path(expected):
            return expected == path
        }
    }
}

private func normalizeSkillConfigPath(_ path: String) -> String {
    URL(fileURLWithPath: path, isDirectory: false)
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
}
