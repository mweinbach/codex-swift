import Foundation

public struct ConversationsPage: Equatable, Sendable {
    public let items: [ConversationItem]
    public let nextCursor: ConversationCursor?
    public let numScannedFiles: Int
    public let reachedScanCap: Bool

    public init(
        items: [ConversationItem] = [],
        nextCursor: ConversationCursor? = nil,
        numScannedFiles: Int = 0,
        reachedScanCap: Bool = false
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.numScannedFiles = numScannedFiles
        self.reachedScanCap = reachedScanCap
    }
}

public struct ConversationItem: Equatable, Sendable {
    public let path: String
    public let head: [JSONValue]
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        path: String,
        head: [JSONValue],
        createdAt: String?,
        updatedAt: String?
    ) {
        self.path = path
        self.head = head
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ConversationCursor: Equatable, Codable, Sendable {
    fileprivate let timestamp: Date
    fileprivate let uuid: UUID

    fileprivate init(timestamp: Date, uuid: UUID) {
        self.timestamp = timestamp
        self.uuid = uuid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        guard let cursor = RolloutListing.parseCursor(token) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid cursor"
            )
        }
        self = cursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    public var token: String {
        "\(RolloutListing.filenameTimestampFormatter.string(from: timestamp))|\(uuid.uuidString.lowercased())"
    }
}

public enum RolloutListing {
    public static let sessionsSubdirectory = "sessions"
    public static let headRecordLimit = 10
    public static let maxScanFiles = 10_000

    public static func getConversations(
        codexHome: URL,
        pageSize: Int,
        cursor: ConversationCursor? = nil,
        allowedSources: [SessionSource] = [],
        modelProviders: [String]? = nil,
        archivedOnly: Bool = false,
        cwdFilters: [String]? = nil,
        searchTerm: String? = nil,
        sourceMatcher: SessionSourceMatcher? = nil,
        defaultProvider: String
    ) throws -> ConversationsPage {
        let root = codexHome.appendingPathComponent(
            archivedOnly ? RolloutErrors.archivedSessionsSubdirectory : sessionsSubdirectory,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ConversationsPage()
        }

        let providerMatcher = ProviderMatcher(filters: modelProviders, defaultProvider: defaultProvider)
        let normalizedPageSize = max(pageSize, 0)
        return try traverseDirectoriesForPaths(
            root: root,
            pageSize: normalizedPageSize,
            anchor: cursor,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters,
            searchTerm: searchTerm,
            sourceMatcher: sourceMatcher
        )
    }

    public static func parseCursor(_ token: String) -> ConversationCursor? {
        let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let timestamp = filenameTimestampFormatter.date(from: String(parts[0])),
              let uuid = UUID(uuidString: String(parts[1]))
        else {
            return nil
        }

        return ConversationCursor(timestamp: timestamp, uuid: uuid)
    }

    public static func parseTimestampUUIDFromFilename(_ name: String) -> (Date, UUID)? {
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else {
            return nil
        }

        let prefixLength = "rollout-".count
        let suffixLength = ".jsonl".count
        let coreStart = name.index(name.startIndex, offsetBy: prefixLength)
        let coreEnd = name.index(name.endIndex, offsetBy: -suffixLength)
        let core = String(name[coreStart..<coreEnd])

        for index in core.indices.reversed() where core[index] == "-" {
            let uuidStart = core.index(after: index)
            let timestampText = String(core[..<index])
            let uuidText = String(core[uuidStart...])
            if let uuid = UUID(uuidString: uuidText),
               let timestamp = filenameTimestampFormatter.date(from: timestampText)
            {
                return (timestamp, uuid)
            }
        }

        return nil
    }

    public static func readHeadForSummary(path: URL) throws -> [JSONValue] {
        try readHeadSummary(path: path, headLimit: headRecordLimit).head
    }

    public static func findConversationPathByIDString(
        codexHome: URL,
        idString: String
    ) throws -> String? {
        guard UUID(uuidString: idString) != nil else {
            return nil
        }

        let root = codexHome.appendingPathComponent(sessionsSubdirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return nil
        }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent.hasSuffix(".jsonl") else {
                continue
            }

            if url.lastPathComponent.contains(idString) {
                return url.path
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(idString)
            else {
                continue
            }

            return url.path
        }

        return nil
    }

    fileprivate static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter
    }()

    private static func traverseDirectoriesForPaths(
        root: URL,
        pageSize: Int,
        anchor: ConversationCursor?,
        allowedSources: [SessionSource],
        providerMatcher: ProviderMatcher?,
        cwdFilters: [String]?,
        searchTerm: String?,
        sourceMatcher: SessionSourceMatcher?
    ) throws -> ConversationsPage {
        var items: [ConversationItem] = []
        items.reserveCapacity(max(pageSize, 0))
        var scannedFiles = 0
        var anchorPassed = anchor == nil
        let anchorTimestamp = anchor?.timestamp ?? Date(timeIntervalSince1970: 0)
        let anchorID = anchor?.uuid ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var moreMatchesAvailable = false

        func sortedRolloutFiles(in directory: URL) throws -> [RolloutFile] {
            var files = try collectFiles(directory) { fileName, path -> RolloutFile? in
                guard let (timestamp, uuid) = parseTimestampUUIDFromFilename(fileName) else {
                    return nil
                }
                return RolloutFile(timestamp: timestamp, uuid: uuid, path: path)
            }
            files.sort { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return uuidCompare(lhs.uuid, rhs.uuid) == .orderedDescending
            }
            return files
        }

        func processRolloutFiles(_ files: [RolloutFile]) throws -> Bool {
            for file in files {
                scannedFiles += 1
                if scannedFiles >= maxScanFiles && items.count >= pageSize {
                    moreMatchesAvailable = true
                    return true
                }

                if !anchorPassed {
                    if file.timestamp < anchorTimestamp
                        || (file.timestamp == anchorTimestamp && uuidCompare(file.uuid, anchorID) == .orderedAscending)
                    {
                        anchorPassed = true
                    } else {
                        continue
                    }
                }

                if items.count == pageSize {
                    moreMatchesAvailable = true
                    return true
                }

                let summary = (try? readHeadSummary(path: file.path, headLimit: headRecordLimit)) ?? HeadTailSummary()
                if !allowedSources.isEmpty {
                    guard let source = summary.source,
                          allowedSources.contains(source)
                    else {
                        continue
                    }
                }

                if let sourceMatcher,
                   !sourceMatcher.matches(summary.source)
                {
                    continue
                }

                if let providerMatcher,
                   !providerMatcher.matches(summary.modelProvider)
                {
                    continue
                }

                if let cwdFilters {
                    guard let cwd = summary.cwd,
                          cwdFilters.contains(cwd)
                    else {
                        continue
                    }
                }

                if let searchTerm,
                   !searchTerm.isEmpty,
                   summary.preview?.contains(searchTerm) != true
                {
                    continue
                }

                if summary.sawSessionMeta && summary.sawUserEvent {
                    let updatedAt = summary.updatedAt
                        ?? fileModifiedRFC3339(file.path)
                        ?? summary.createdAt
                    items.append(ConversationItem(
                        path: file.path.path,
                        head: summary.head,
                        createdAt: summary.createdAt,
                        updatedAt: updatedAt
                    ))
                }
            }
            return false
        }

        if try processRolloutFiles(sortedRolloutFiles(in: root)) {
            return ConversationsPage(
                items: items,
                nextCursor: moreMatchesAvailable ? buildNextCursor(items) : nil,
                numScannedFiles: scannedFiles,
                reachedScanCap: scannedFiles >= maxScanFiles
            )
        }

        let yearDirectories: [(Int, URL)] = try collectDirectoriesDescending(root) { Int($0) }

        outer: for (_, yearPath) in yearDirectories {
            if scannedFiles >= maxScanFiles {
                break
            }

            let monthDirectories: [(Int, URL)] = try collectDirectoriesDescending(yearPath) { Int($0) }
            for (_, monthPath) in monthDirectories {
                if scannedFiles >= maxScanFiles {
                    break outer
                }

                let dayDirectories: [(Int, URL)] = try collectDirectoriesDescending(monthPath) { Int($0) }
                for (_, dayPath) in dayDirectories {
                    if scannedFiles >= maxScanFiles {
                        break outer
                    }

                    if try processRolloutFiles(sortedRolloutFiles(in: dayPath)) {
                        break outer
                    }
                }
            }
        }

        let reachedScanCap = scannedFiles >= maxScanFiles
        if reachedScanCap && !items.isEmpty {
            moreMatchesAvailable = true
        }

        return ConversationsPage(
            items: items,
            nextCursor: moreMatchesAvailable ? buildNextCursor(items) : nil,
            numScannedFiles: scannedFiles,
            reachedScanCap: reachedScanCap
        )
    }

    private static func buildNextCursor(_ items: [ConversationItem]) -> ConversationCursor? {
        guard let last = items.last,
              let fileName = URL(fileURLWithPath: last.path).lastPathComponent.nilIfEmpty,
              let (timestamp, uuid) = parseTimestampUUIDFromFilename(fileName)
        else {
            return nil
        }

        return ConversationCursor(timestamp: timestamp, uuid: uuid)
    }

    private static func collectDirectoriesDescending<T: Comparable>(
        _ parent: URL,
        parse: (String) -> T?
    ) throws -> [(T, URL)] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        var directories: [(T, URL)] = []
        for url in urls {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                  let value = parse(url.lastPathComponent)
            else {
                continue
            }
            directories.append((value, url))
        }

        return directories.sorted { lhs, rhs in lhs.0 > rhs.0 }
    }

    private static func collectFiles<T>(
        _ parent: URL,
        parse: (String, URL) -> T?
    ) throws -> [T] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return parse(url.lastPathComponent, url)
        }
    }

    private static func readHeadSummary(path: URL, headLimit: Int) throws -> HeadTailSummary {
        let text = try String(contentsOf: path, encoding: .utf8)
        var summary = HeadTailSummary()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard summary.head.count < headLimit else {
                break
            }

            let trimmed = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let rolloutLine = try? JSONDecoder().decode(RolloutLine.self, from: data)
            else {
                continue
            }

            switch rolloutLine.item {
            case let .sessionMeta(sessionMetaLine):
                summary.source = sessionMetaLine.meta.source
                summary.modelProvider = sessionMetaLine.meta.modelProvider
                summary.cwd = sessionMetaLine.meta.cwd
                if summary.createdAt == nil {
                    summary.createdAt = rolloutLine.timestamp
                }
                if let value = try? jsonValue(sessionMetaLine) {
                    summary.head.append(value)
                    summary.sawSessionMeta = true
                }

            case let .responseItem(responseItem):
                if summary.createdAt == nil {
                    summary.createdAt = rolloutLine.timestamp
                }
                if let value = try? jsonValue(responseItem) {
                    summary.head.append(value)
                }

            case .turnContext,
                 .compacted:
                break

            case let .eventMsg(event):
                if case let .userMessage(message) = event {
                    summary.preview = message.message
                    summary.sawUserEvent = true
                }
            }

            if summary.sawSessionMeta && summary.sawUserEvent {
                break
            }
        }

        return summary
    }

    private static func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func fileModifiedRFC3339(_ path: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: modified)
    }

    private static func uuidCompare(_ lhs: UUID, _ rhs: UUID) -> ComparisonResult {
        withUnsafeBytes(of: lhs.uuid) { lhsBytes in
            withUnsafeBytes(of: rhs.uuid) { rhsBytes in
                for index in 0..<16 {
                    let lhsByte = lhsBytes[index]
                    let rhsByte = rhsBytes[index]
                    if lhsByte < rhsByte {
                        return .orderedAscending
                    }
                    if lhsByte > rhsByte {
                        return .orderedDescending
                    }
                }
                return .orderedSame
            }
        }
    }
}

private struct RolloutFile {
    let timestamp: Date
    let uuid: UUID
    let path: URL
}

private struct HeadTailSummary {
    var head: [JSONValue] = []
    var sawSessionMeta = false
    var sawUserEvent = false
    var source: SessionSource?
    var modelProvider: String?
    var cwd: String?
    var preview: String?
    var createdAt: String?
    var updatedAt: String?
}

public struct SessionSourceMatcher: Equatable, Sendable {
    public enum SourceKind: String, Equatable, Sendable {
        case cli
        case vscode
        case exec
        case appServer
        case subAgent
        case subAgentReview
        case subAgentCompact
        case subAgentThreadSpawn
        case subAgentOther
        case unknown
    }

    private let kinds: [SourceKind]

    public init(kinds: [SourceKind]) {
        self.kinds = kinds
    }

    public func matches(_ source: SessionSource?) -> Bool {
        guard let source else {
            return kinds.contains(.unknown)
        }
        return kinds.contains { kind in
            switch kind {
            case .cli:
                return source == .cli
            case .vscode:
                return source == .vscode
            case .exec:
                return source == .exec
            case .appServer:
                return source == .mcp
            case .subAgent:
                if case .subagent = source {
                    return true
                }
                return false
            case .subAgentReview:
                return source == .subagent(.review)
            case .subAgentCompact:
                return source == .subagent(.compact)
            case .subAgentThreadSpawn:
                if case .subagent(.threadSpawn) = source {
                    return true
                }
                return false
            case .subAgentOther:
                if case .subagent(.other) = source {
                    return true
                }
                return false
            case .unknown:
                return source == .unknown
            }
        }
    }
}

private struct ProviderMatcher {
    let filters: [String]
    let matchesDefaultProvider: Bool

    init?(filters: [String]?, defaultProvider: String) {
        guard let filters, !filters.isEmpty else {
            return nil
        }
        self.filters = filters
        self.matchesDefaultProvider = filters.contains(defaultProvider)
    }

    func matches(_ sessionProvider: String?) -> Bool {
        guard let sessionProvider else {
            return matchesDefaultProvider
        }
        return filters.contains(sessionProvider)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
