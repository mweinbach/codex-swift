import Foundation

public let defaultMemoriesListMaxResults = 2_000
public let maxMemoriesListResults = 2_000
public let defaultMemoriesSearchMaxResults = 200
public let maxMemoriesSearchResults = 200
public let defaultMemoryReadMaxTokens = 20_000

public struct ListMemoriesRequest: Equatable, Sendable {
    public let path: String?
    public let cursor: String?
    public let maxResults: Int

    public init(path: String? = nil, cursor: String? = nil, maxResults: Int = defaultMemoriesListMaxResults) {
        self.path = path
        self.cursor = cursor
        self.maxResults = maxResults
    }
}

public struct ListMemoriesResponse: Equatable, Codable, Sendable {
    public let path: String?
    public let entries: [MemoryEntry]
    public let nextCursor: String?
    public let truncated: Bool

    public init(path: String?, entries: [MemoryEntry], nextCursor: String?, truncated: Bool) {
        self.path = path
        self.entries = entries
        self.nextCursor = nextCursor
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case entries
        case nextCursor = "next_cursor"
        case truncated
    }
}

public struct ReadMemoryRequest: Equatable, Sendable {
    public let path: String
    public let lineOffset: Int
    public let maxLines: Int?
    public let maxTokens: Int

    public init(
        path: String,
        lineOffset: Int = 1,
        maxLines: Int? = nil,
        maxTokens: Int = defaultMemoryReadMaxTokens
    ) {
        self.path = path
        self.lineOffset = lineOffset
        self.maxLines = maxLines
        self.maxTokens = maxTokens
    }
}

public struct ReadMemoryResponse: Equatable, Codable, Sendable {
    public let path: String
    public let startLineNumber: Int
    public let content: String
    public let truncated: Bool

    public init(path: String, startLineNumber: Int, content: String, truncated: Bool) {
        self.path = path
        self.startLineNumber = startLineNumber
        self.content = content
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case startLineNumber = "start_line_number"
        case content
        case truncated
    }
}

public struct SearchMemoriesRequest: Equatable, Sendable {
    public let queries: [String]
    public let matchMode: SearchMatchMode
    public let path: String?
    public let cursor: String?
    public let contextLines: Int
    public let caseSensitive: Bool
    public let normalized: Bool
    public let maxResults: Int

    public init(
        queries: [String],
        matchMode: SearchMatchMode = .any,
        path: String? = nil,
        cursor: String? = nil,
        contextLines: Int = 0,
        caseSensitive: Bool = true,
        normalized: Bool = false,
        maxResults: Int = defaultMemoriesSearchMaxResults
    ) {
        self.queries = queries
        self.matchMode = matchMode
        self.path = path
        self.cursor = cursor
        self.contextLines = contextLines
        self.caseSensitive = caseSensitive
        self.normalized = normalized
        self.maxResults = maxResults
    }
}

public struct SearchMemoriesResponse: Equatable, Codable, Sendable {
    public let queries: [String]
    public let matchMode: SearchMatchMode
    public let path: String?
    public let matches: [MemorySearchMatch]
    public let nextCursor: String?
    public let truncated: Bool

    public init(
        queries: [String],
        matchMode: SearchMatchMode,
        path: String?,
        matches: [MemorySearchMatch],
        nextCursor: String?,
        truncated: Bool
    ) {
        self.queries = queries
        self.matchMode = matchMode
        self.path = path
        self.matches = matches
        self.nextCursor = nextCursor
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case queries
        case matchMode = "match_mode"
        case path
        case matches
        case nextCursor = "next_cursor"
        case truncated
    }
}

public enum SearchMatchMode: Equatable, Codable, Sendable {
    case any
    case allOnSameLine
    case allWithinLines(lineCount: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case lineCount = "line_count"
    }

    private enum Mode: String, Codable {
        case any
        case allOnSameLine = "all_on_same_line"
        case allWithinLines = "all_within_lines"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .type) {
        case .any:
            self = .any
        case .allOnSameLine:
            self = .allOnSameLine
        case .allWithinLines:
            self = .allWithinLines(lineCount: try container.decode(Int.self, forKey: .lineCount))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(Mode.any, forKey: .type)
        case .allOnSameLine:
            try container.encode(Mode.allOnSameLine, forKey: .type)
        case let .allWithinLines(lineCount):
            try container.encode(Mode.allWithinLines, forKey: .type)
            try container.encode(lineCount, forKey: .lineCount)
        }
    }
}

public struct MemoryEntry: Equatable, Codable, Sendable {
    public let path: String
    public let entryType: MemoryEntryType

    public init(path: String, entryType: MemoryEntryType) {
        self.path = path
        self.entryType = entryType
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case entryType = "entry_type"
    }
}

public enum MemoryEntryType: String, Codable, Equatable, Sendable {
    case file
    case directory
}

public struct MemorySearchMatch: Equatable, Codable, Sendable {
    public let path: String
    public let matchLineNumber: Int
    public let contentStartLineNumber: Int
    public let content: String
    public let matchedQueries: [String]

    public init(
        path: String,
        matchLineNumber: Int,
        contentStartLineNumber: Int,
        content: String,
        matchedQueries: [String]
    ) {
        self.path = path
        self.matchLineNumber = matchLineNumber
        self.contentStartLineNumber = contentStartLineNumber
        self.content = content
        self.matchedQueries = matchedQueries
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case matchLineNumber = "match_line_number"
        case contentStartLineNumber = "content_start_line_number"
        case content
        case matchedQueries = "matched_queries"
    }
}

public enum MemoriesBackendError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidPath(path: String, reason: String)
    case invalidCursor(cursor: String, reason: String)
    case notFound(path: String)
    case invalidLineOffset
    case invalidMaxLines
    case lineOffsetExceedsFileLength
    case notFile(path: String)
    case emptyQuery
    case invalidMatchWindow
    case io(String)

    public var description: String {
        switch self {
        case let .invalidPath(path, reason):
            return "path '\(path)' \(reason)"
        case let .invalidCursor(cursor, reason):
            return "cursor '\(cursor)' \(reason)"
        case let .notFound(path):
            return "path '\(path)' was not found"
        case .invalidLineOffset:
            return "line_offset must be a 1-indexed line number"
        case .invalidMaxLines:
            return "max_lines must be a positive integer"
        case .lineOffsetExceedsFileLength:
            return "line_offset exceeds file length"
        case let .notFile(path):
            return "path '\(path)' is not a file"
        case .emptyQuery:
            return "queries must not be empty or contain empty strings"
        case .invalidMatchWindow:
            return "all_within_lines.line_count must be a positive integer"
        case let .io(message):
            return "I/O error while reading memories: \(message)"
        }
    }
}

public struct LocalMemoriesBackend: Sendable {
    public let root: URL

    public init(codexHome: URL) {
        self.init(memoryRoot: codexHome.appendingPathComponent("memories", isDirectory: true))
    }

    public init(memoryRoot: URL) {
        self.root = memoryRoot.standardizedFileURL
    }

    public func list(_ request: ListMemoriesRequest) throws -> ListMemoriesResponse {
        let maxResults = min(max(0, request.maxResults), maxMemoriesListResults)
        let start = try resolveScopedPath(request.path)
        let startIndex = try parseCursor(request.cursor)
        guard let metadata = try metadataIfExists(start) else {
            throw MemoriesBackendError.notFound(path: request.path ?? "")
        }
        try rejectSymlink(displayRelativePath(start), metadata: metadata)

        var entries: [MemoryEntry]
        if metadata.isRegularFile == true {
            entries = [MemoryEntry(path: displayRelativePath(start), entryType: .file)]
        } else if metadata.isDirectory == true {
            entries = try sortedDirectoryChildren(start).compactMap { child in
                guard !isHiddenPath(child),
                      let childMetadata = try metadataIfExists(child),
                      childMetadata.isSymbolicLink != true
                else {
                    return nil
                }
                if childMetadata.isDirectory == true {
                    return MemoryEntry(path: displayRelativePath(child), entryType: .directory)
                }
                if childMetadata.isRegularFile == true {
                    return MemoryEntry(path: displayRelativePath(child), entryType: .file)
                }
                return nil
            }
        } else {
            entries = []
        }

        guard startIndex <= entries.count else {
            throw MemoriesBackendError.invalidCursor(cursor: "\(startIndex)", reason: "exceeds result count")
        }
        let endIndex = min(entries.count, startIndex + maxResults)
        let nextCursor = endIndex < entries.count ? "\(endIndex)" : nil
        return ListMemoriesResponse(
            path: request.path,
            entries: Array(entries[startIndex..<endIndex]),
            nextCursor: nextCursor,
            truncated: nextCursor != nil
        )
    }

    public func read(_ request: ReadMemoryRequest) throws -> ReadMemoryResponse {
        guard request.lineOffset > 0 else {
            throw MemoriesBackendError.invalidLineOffset
        }
        if request.maxLines == 0 {
            throw MemoriesBackendError.invalidMaxLines
        }

        let path = try resolveScopedPath(request.path)
        guard let metadata = try metadataIfExists(path) else {
            throw MemoriesBackendError.notFound(path: request.path)
        }
        try rejectSymlink(request.path, metadata: metadata)
        guard metadata.isRegularFile == true else {
            throw MemoriesBackendError.notFile(path: request.path)
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw MemoriesBackendError.io(error.localizedDescription)
        }
        let startIndex = try lineStartIndex(in: originalContent, lineOffset: request.lineOffset)
        let endIndex = lineEndIndex(in: originalContent, startIndex: startIndex, maxLines: request.maxLines)
        let contentFromOffset = String(originalContent[startIndex..<endIndex])
        let maxTokens = request.maxTokens == 0 ? defaultMemoryReadMaxTokens : request.maxTokens
        let content = Truncation.truncateText(contentFromOffset, policy: .tokens(maxTokens))
        return ReadMemoryResponse(
            path: request.path,
            startLineNumber: request.lineOffset,
            content: content,
            truncated: endIndex < originalContent.endIndex || content != contentFromOffset
        )
    }

    public func search(_ request: SearchMemoriesRequest) throws -> SearchMemoriesResponse {
        let queries = request.queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !queries.isEmpty, !queries.contains(where: \.isEmpty) else {
            throw MemoriesBackendError.emptyQuery
        }
        if case let .allWithinLines(lineCount) = request.matchMode, lineCount == 0 {
            throw MemoriesBackendError.invalidMatchWindow
        }

        let maxResults = min(max(0, request.maxResults), maxMemoriesSearchResults)
        let start = try resolveScopedPath(request.path)
        let startIndex = try parseCursor(request.cursor)
        guard let metadata = try metadataIfExists(start) else {
            throw MemoriesBackendError.notFound(path: request.path ?? "")
        }
        try rejectSymlink(displayRelativePath(start), metadata: metadata)

        let matcher = try SearchMatcher(
            queries: queries,
            matchMode: request.matchMode,
            caseSensitive: request.caseSensitive,
            normalized: request.normalized
        )
        var matches: [MemorySearchMatch] = []
        try searchEntries(start, metadata: metadata, matcher: matcher, contextLines: request.contextLines, matches: &matches)
        matches.sort {
            if $0.path != $1.path {
                return $0.path < $1.path
            }
            return $0.matchLineNumber < $1.matchLineNumber
        }

        guard startIndex <= matches.count else {
            throw MemoriesBackendError.invalidCursor(cursor: "\(startIndex)", reason: "exceeds result count")
        }
        let endIndex = min(matches.count, startIndex + maxResults)
        let nextCursor = endIndex < matches.count ? "\(endIndex)" : nil
        return SearchMemoriesResponse(
            queries: queries,
            matchMode: request.matchMode,
            path: request.path,
            matches: Array(matches[startIndex..<endIndex]),
            nextCursor: nextCursor,
            truncated: nextCursor != nil
        )
    }

    private func resolveScopedPath(_ relativePath: String?) throws -> URL {
        guard let relativePath else {
            return root
        }
        let path = NSString(string: relativePath)
        guard !path.isAbsolutePath else {
            throw MemoriesBackendError.invalidPath(path: relativePath, reason: "must stay within the memories root")
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.contains("..") else {
            throw MemoriesBackendError.invalidPath(path: relativePath, reason: "must stay within the memories root")
        }
        guard !components.contains(where: { $0.hasPrefix(".") }) else {
            throw MemoriesBackendError.notFound(path: relativePath)
        }

        var scopedPath = root
        for (index, component) in components.enumerated() {
            scopedPath.appendPathComponent(component, isDirectory: false)
            guard let metadata = try metadataIfExists(scopedPath) else {
                for remaining in components.dropFirst(index + 1) {
                    scopedPath.appendPathComponent(remaining, isDirectory: false)
                }
                return scopedPath
            }
            try rejectSymlink(displayRelativePath(scopedPath), metadata: metadata)
            if index + 1 < components.count, metadata.isDirectory != true {
                throw MemoriesBackendError.invalidPath(
                    path: relativePath,
                    reason: "traverses through a non-directory path component"
                )
            }
        }
        return scopedPath
    }

    private func metadataIfExists(_ url: URL) throws -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            throw MemoriesBackendError.io(error.localizedDescription)
        }
    }

    private func sortedDirectoryChildren(_ url: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ).sorted { $0.path < $1.path }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        } catch {
            throw MemoriesBackendError.io(error.localizedDescription)
        }
    }

    private func rejectSymlink(_ path: String, metadata: URLResourceValues) throws {
        if metadata.isSymbolicLink == true {
            throw MemoriesBackendError.invalidPath(path: path, reason: "must not be a symlink")
        }
    }

    private func parseCursor(_ cursor: String?) throws -> Int {
        guard let cursor else {
            return 0
        }
        guard let value = Int(cursor), value >= 0 else {
            throw MemoriesBackendError.invalidCursor(cursor: cursor, reason: "must be a non-negative integer")
        }
        return value
    }

    private func searchEntries(
        _ current: URL,
        metadata: URLResourceValues,
        matcher: SearchMatcher,
        contextLines: Int,
        matches: inout [MemorySearchMatch]
    ) throws {
        if metadata.isRegularFile == true {
            try searchFile(current, matcher: matcher, contextLines: contextLines, matches: &matches)
            return
        }
        guard metadata.isDirectory == true else {
            return
        }

        var pending = [current]
        while let directory = pending.popLast() {
            for child in try sortedDirectoryChildren(directory) {
                guard !isHiddenPath(child),
                      let childMetadata = try metadataIfExists(child),
                      childMetadata.isSymbolicLink != true
                else {
                    continue
                }
                if childMetadata.isDirectory == true {
                    pending.append(child)
                } else if childMetadata.isRegularFile == true {
                    try searchFile(child, matcher: matcher, contextLines: contextLines, matches: &matches)
                }
            }
        }
    }

    private func searchFile(
        _ path: URL,
        matcher: SearchMatcher,
        contextLines: Int,
        matches: inout [MemorySearchMatch]
    ) throws {
        let content: String
        do {
            content = try String(contentsOf: path, encoding: .utf8)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadInapplicableStringEncodingError {
            return
        } catch {
            throw MemoriesBackendError.io(error.localizedDescription)
        }
        let lines = rustLines(content)
        let lineMatches = lines.map { matcher.matchedQueryFlags($0) }
        switch matcher.matchMode {
        case .any:
            for (index, flags) in lineMatches.enumerated() where flags.contains(true) {
                matches.append(buildSearchMatch(path, lines: lines, matchStartIndex: index, matchEndIndex: index, contextLines: contextLines, matchedQueries: matcher.matchedQueries(flags)))
            }
        case .allOnSameLine:
            for (index, flags) in lineMatches.enumerated() where flags.allSatisfy({ $0 }) {
                matches.append(buildSearchMatch(path, lines: lines, matchStartIndex: index, matchEndIndex: index, contextLines: contextLines, matchedQueries: matcher.matchedQueries(flags)))
            }
        case let .allWithinLines(lineCount):
            var windows: [(start: Int, end: Int, flags: [Bool])] = []
            for startIndex in lines.indices where lineMatches[startIndex].contains(true) {
                let lastAllowedIndex = min(lines.count - 1, startIndex + max(0, lineCount - 1))
                var matchedFlags = Array(repeating: false, count: matcher.queries.count)
                for endIndex in startIndex...lastAllowedIndex {
                    for flagIndex in matchedFlags.indices {
                        matchedFlags[flagIndex] = matchedFlags[flagIndex] || lineMatches[endIndex][flagIndex]
                    }
                    if matchedFlags.allSatisfy({ $0 }) {
                        windows.append((startIndex, endIndex, matchedFlags))
                        break
                    }
                }
            }
            for (index, window) in windows.enumerated() {
                let containsAnother = windows.enumerated().contains { otherIndex, other in
                    index != otherIndex &&
                        window.start <= other.start &&
                        window.end >= other.end &&
                        (window.start != other.start || window.end != other.end)
                }
                if !containsAnother {
                    matches.append(buildSearchMatch(path, lines: lines, matchStartIndex: window.start, matchEndIndex: window.end, contextLines: contextLines, matchedQueries: matcher.matchedQueries(window.flags)))
                }
            }
        }
    }

    private func buildSearchMatch(
        _ path: URL,
        lines: [String],
        matchStartIndex: Int,
        matchEndIndex: Int,
        contextLines: Int,
        matchedQueries: [String]
    ) -> MemorySearchMatch {
        let contentStartIndex = max(0, matchStartIndex - contextLines)
        let contentEndIndex = min(lines.count, matchEndIndex + max(0, contextLines) + 1)
        return MemorySearchMatch(
            path: displayRelativePath(path),
            matchLineNumber: matchStartIndex + 1,
            contentStartLineNumber: contentStartIndex + 1,
            content: lines[contentStartIndex..<contentEndIndex].joined(separator: "\n"),
            matchedQueries: matchedQueries
        )
    }

    private func displayRelativePath(_ url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return path
        }
        var relative = String(path.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }

    private func isHiddenPath(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }
}

private struct SearchMatcher: Sendable {
    let queries: [String]
    let preparedQueries: [String]
    let comparison: SearchComparison
    let matchMode: SearchMatchMode

    init(queries: [String], matchMode: SearchMatchMode, caseSensitive: Bool, normalized: Bool) throws {
        let comparison = SearchComparison(caseSensitive: caseSensitive, normalized: normalized)
        let preparedQueries = queries.map { comparison.prepare($0) }
        guard !preparedQueries.contains(where: \.isEmpty) else {
            throw MemoriesBackendError.emptyQuery
        }
        self.queries = queries
        self.preparedQueries = preparedQueries
        self.comparison = comparison
        self.matchMode = matchMode
    }

    func matchedQueryFlags(_ line: String) -> [Bool] {
        let line = comparison.prepare(line)
        return preparedQueries.map { line.contains($0) }
    }

    func matchedQueries(_ flags: [Bool]) -> [String] {
        zip(queries, flags).compactMap { query, matched in
            matched ? query : nil
        }
    }
}

private struct SearchComparison: Sendable {
    let caseSensitive: Bool
    let normalized: Bool

    func prepare(_ value: String) -> String {
        let cased = caseSensitive ? value : value.lowercased()
        guard normalized else {
            return cased
        }
        return String(cased.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

private func lineStartIndex(in content: String, lineOffset: Int) throws -> String.Index {
    if lineOffset == 1 {
        return content.startIndex
    }
    var currentLine = 1
    for index in content.indices where content[index] == "\n" {
        currentLine += 1
        if currentLine == lineOffset {
            return content.index(after: index)
        }
    }
    throw MemoriesBackendError.lineOffsetExceedsFileLength
}

private func lineEndIndex(in content: String, startIndex: String.Index, maxLines: Int?) -> String.Index {
    guard let maxLines else {
        return content.endIndex
    }
    var linesSeen = 1
    var index = startIndex
    while index < content.endIndex {
        if content[index] == "\n" {
            if linesSeen == maxLines {
                return content.index(after: index)
            }
            linesSeen += 1
        }
        index = content.index(after: index)
    }
    return content.endIndex
}

private func rustLines(_ content: String) -> [String] {
    if content.isEmpty {
        return []
    }
    var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if content.hasSuffix("\n") {
        lines.removeLast()
    }
    return lines.map { line in
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
}
