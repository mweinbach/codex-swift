import Foundation

public struct ProjectDocConfig: Equatable, Sendable {
    public var cwd: URL
    public var userInstructions: String?
    public var projectDocMaxBytes: Int
    public var projectDocFallbackFilenames: [String]
    public var projectRootMarkers: [String]

    public init(
        cwd: URL,
        userInstructions: String? = nil,
        projectDocMaxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        projectDocFallbackFilenames: [String] = [],
        projectRootMarkers: [String] = CodexConfigDefaults.projectRootMarkers
    ) {
        self.cwd = cwd
        self.userInstructions = userInstructions
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
        self.projectRootMarkers = projectRootMarkers
    }

    public init(runtimeConfig: CodexRuntimeConfig, cwd: URL, userInstructions: String? = nil) {
        self.init(
            cwd: cwd,
            userInstructions: userInstructions,
            projectDocMaxBytes: runtimeConfig.projectDocMaxBytes,
            projectDocFallbackFilenames: runtimeConfig.projectDocFallbackFilenames,
            projectRootMarkers: runtimeConfig.projectRootMarkers
        )
    }
}

public enum ProjectDoc {
    public static let defaultFilename = "AGENTS.md"
    public static let localOverrideFilename = "AGENTS.override.md"
    public static let separator = "\n\n--- project-doc ---\n\n"

    public static func getUserInstructions(
        config: ProjectDocConfig,
        fileManager: FileManager = .default
    ) -> String? {
        let projectDocs: String?
        do {
            projectDocs = try readProjectDocs(config: config, fileManager: fileManager)
        } catch {
            return config.userInstructions
        }

        var parts: [String] = []
        if let userInstructions = config.userInstructions {
            parts.append(userInstructions)
        }
        if let projectDocs {
            if !parts.isEmpty {
                parts.append(separator)
            }
            parts.append(projectDocs)
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

            guard try regularFileExists(at: path, fileManager: fileManager) else {
                continue
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
        let chain = try directoryChainAndProjectRoot(
            from: cwd,
            projectRootMarkers: config.projectRootMarkers,
            fileManager: fileManager
        )
        let searchDirs: [URL]
        if let projectRoot = chain.projectRoot {
            var sawRoot = false
            searchDirs = chain.directories.reversed().compactMap { directory in
                if !sawRoot {
                    if samePath(directory, projectRoot) {
                        sawRoot = true
                    } else {
                        return nil
                    }
                }
                return directory
            }
        } else {
            searchDirs = [cwd]
        }

        let candidates = candidateFilenames(config)
        var found: [URL] = []
        for directory in searchDirs {
            for filename in candidates {
                let candidate = directory.appendingPathComponent(filename, isDirectory: false)
                if try regularFileExists(at: candidate, fileManager: fileManager) {
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

    private static func directoryChainAndProjectRoot(
        from cwd: URL,
        projectRootMarkers: [String],
        fileManager: FileManager
    ) throws -> (directories: [URL], projectRoot: URL?) {
        var directories = [cwd]
        var cursor = cwd

        guard !projectRootMarkers.isEmpty else {
            return (directories, cwd)
        }

        while true {
            let hasMarker = projectRootMarkers.contains { marker in
                let markerPath = cursor.appendingPathComponent(marker, isDirectory: false)
                return fileManager.fileExists(atPath: markerPath.path)
            }
            if hasMarker {
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

    private static func regularFileExists(at url: URL, fileManager: FileManager) throws -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return (attributes[.type] as? FileAttributeType) == .typeRegular
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError
        {
            return false
        }
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
