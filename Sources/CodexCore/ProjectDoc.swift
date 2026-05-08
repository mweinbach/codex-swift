import Foundation

public struct ProjectDocConfig: Equatable, Sendable {
    public var cwd: URL
    public var userInstructions: String?
    public var projectDocMaxBytes: Int
    public var projectDocFallbackFilenames: [String]

    public init(
        cwd: URL,
        userInstructions: String? = nil,
        projectDocMaxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        projectDocFallbackFilenames: [String] = []
    ) {
        self.cwd = cwd
        self.userInstructions = userInstructions
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
    }

    public init(runtimeConfig: CodexRuntimeConfig, cwd: URL, userInstructions: String? = nil) {
        self.init(
            cwd: cwd,
            userInstructions: userInstructions,
            projectDocMaxBytes: runtimeConfig.projectDocMaxBytes,
            projectDocFallbackFilenames: runtimeConfig.projectDocFallbackFilenames
        )
    }
}

public enum ProjectDoc {
    public static let defaultFilename = "AGENTS.md"
    public static let localOverrideFilename = "AGENTS.override.md"
    public static let separator = "\n\n--- project-doc ---\n\n"

    public static func getUserInstructions(
        config: ProjectDocConfig,
        skills: [SkillMetadata]? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let skillsSection = skills.flatMap(Skills.renderSkillsSection)
        let projectDocs: String?
        do {
            projectDocs = try readProjectDocs(config: config, fileManager: fileManager)
        } catch {
            return config.userInstructions
        }

        let combinedProjectDocs = mergeProjectDocsWithSkills(
            projectDocs: projectDocs,
            skillsSection: skillsSection
        )

        var parts: [String] = []
        if let userInstructions = config.userInstructions {
            parts.append(userInstructions)
        }
        if let combinedProjectDocs {
            if !parts.isEmpty {
                parts.append(separator)
            }
            parts.append(combinedProjectDocs)
        }

        return parts.isEmpty ? nil : parts.joined()
    }

    public static func readProjectDocs(
        config: ProjectDocConfig,
        fileManager: FileManager = .default
    ) throws -> String? {
        guard config.projectDocMaxBytes > 0 else {
            return nil
        }

        let paths = try discoverProjectDocPaths(config: config, fileManager: fileManager)
        guard !paths.isEmpty else {
            return nil
        }

        var remaining = config.projectDocMaxBytes
        var parts: [String] = []

        for path in paths {
            guard remaining > 0 else {
                break
            }

            let data: Data
            do {
                data = try Data(contentsOf: path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError
            {
                continue
            }

            let slice = data.prefix(remaining)
            let text = String(decoding: slice, as: UTF8.self)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(text)
                remaining = max(0, remaining - slice.count)
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    public static func discoverProjectDocPaths(
        config: ProjectDocConfig,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard config.projectDocMaxBytes > 0 else {
            return []
        }

        let cwd = normalizedDirectoryURL(config.cwd)
        let chain = try directoryChainAndGitRoot(from: cwd, fileManager: fileManager)
        let searchDirs: [URL]
        if let gitRoot = chain.gitRoot {
            var sawRoot = false
            searchDirs = chain.directories.reversed().compactMap { directory in
                if !sawRoot {
                    if samePath(directory, gitRoot) {
                        sawRoot = true
                    } else {
                        return nil
                    }
                }
                return directory
            }
        } else {
            searchDirs = [config.cwd]
        }

        let candidates = candidateFilenames(config)
        var found: [URL] = []
        for directory in searchDirs {
            for filename in candidates {
                let candidate = directory.appendingPathComponent(filename, isDirectory: false)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                   !isDirectory.boolValue
                {
                    found.append(candidate)
                    break
                }
            }
        }

        return found
    }

    static func candidateFilenames(_ config: ProjectDocConfig) -> [String] {
        var names = [localOverrideFilename, defaultFilename]
        for candidate in config.projectDocFallbackFilenames where !candidate.isEmpty {
            if !names.contains(candidate) {
                names.append(candidate)
            }
        }
        return names
    }

    static func mergeProjectDocsWithSkills(projectDocs: String?, skillsSection: String?) -> String? {
        switch (projectDocs, skillsSection) {
        case let (doc?, skills?):
            return "\(doc)\n\n\(skills)"
        case let (doc?, nil):
            return doc
        case let (nil, skills?):
            return skills
        case (nil, nil):
            return nil
        }
    }

    private static func directoryChainAndGitRoot(
        from cwd: URL,
        fileManager: FileManager
    ) throws -> (directories: [URL], gitRoot: URL?) {
        var directories = [cwd]
        var cursor = cwd

        while true {
            let gitMarker = cursor.appendingPathComponent(".git", isDirectory: false)
            if fileManager.fileExists(atPath: gitMarker.path) {
                return (directories, cursor)
            }

            let parent = cursor.deletingLastPathComponent()
            if samePath(parent, cursor) {
                return (directories, nil)
            }

            directories.append(parent)
            cursor = parent
        }
    }

    private static func normalizedDirectoryURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
