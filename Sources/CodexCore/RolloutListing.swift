import Foundation

public struct ConversationsPage: Equatable, Sendable {
    public let items: [ConversationItem]
    public let nextCursor: ConversationCursor?
    public let backwardsCursor: ConversationCursor?
    public let numScannedFiles: Int
    public let reachedScanCap: Bool

    public init(
        items: [ConversationItem] = [],
        nextCursor: ConversationCursor? = nil,
        backwardsCursor: ConversationCursor? = nil,
        numScannedFiles: Int = 0,
        reachedScanCap: Bool = false
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
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

    fileprivate init(timestamp: Date) {
        self.timestamp = timestamp
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
        RolloutListing.formatRFC3339Timestamp(timestamp)
    }

    public var anchorTimestamp: Date {
        timestamp
    }
}

public enum ConversationSortKey: Equatable, Sendable {
    case createdAt
    case updatedAt
}

public enum ConversationSortDirection: Equatable, Sendable {
    case ascending
    case descending
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
        sortKey: ConversationSortKey = .createdAt,
        sortDirection: ConversationSortDirection = .descending,
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
            sourceMatcher: sourceMatcher,
            sortKey: sortKey,
            sortDirection: sortDirection
        )
    }

    public static func parseCursor(_ token: String) -> ConversationCursor? {
        if let timestamp = parseRFC3339Date(token) {
            return ConversationCursor(timestamp: timestamp)
        }

        if let timestamp = filenameTimestampFormatter.date(from: token) {
            return ConversationCursor(timestamp: timestamp)
        }

        let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2,
           let timestamp = filenameTimestampFormatter.date(from: String(parts[0])),
           UUID(uuidString: String(parts[1])) != nil
        {
            return ConversationCursor(timestamp: timestamp)
        }

        return nil
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
        idString: String,
        includeArchived: Bool = false
    ) throws -> String? {
        guard UUID(uuidString: idString) != nil else {
            return nil
        }

        let roots = [
            codexHome.appendingPathComponent(sessionsSubdirectory, isDirectory: true)
        ] + (includeArchived ? [
            codexHome.appendingPathComponent(RolloutErrors.archivedSessionsSubdirectory, isDirectory: true)
        ] : [])

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else {
                continue
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
        sourceMatcher: SessionSourceMatcher?,
        sortKey: ConversationSortKey,
        sortDirection: ConversationSortDirection
    ) throws -> ConversationsPage {
        var candidates: [ConversationCandidate] = []
        var scannedFiles = 0

        func rolloutFiles(in directory: URL) throws -> [RolloutFile] {
            try collectFiles(directory) { fileName, path -> RolloutFile? in
                guard let (timestamp, uuid) = parseTimestampUUIDFromFilename(fileName) else {
                    return nil
                }
                return RolloutFile(timestamp: timestamp, uuid: uuid, path: path)
            }
        }

        func processRolloutFiles(_ files: [RolloutFile]) throws -> Bool {
            for file in files {
                scannedFiles += 1
                if scannedFiles >= maxScanFiles {
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
                          cwdFilters.contains(where: { pathsMatchAfterNormalization(cwd, $0) })
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
                    candidates.append(ConversationCandidate(
                        uuid: file.uuid,
                        sortCreatedAt: file.timestamp,
                        sortUpdatedAt: parseRFC3339Date(updatedAt) ?? file.timestamp,
                        item: ConversationItem(
                            path: file.path.path,
                            head: summary.head,
                            createdAt: summary.createdAt,
                            updatedAt: updatedAt
                        )
                    ))
                }
            }
            return false
        }

        if try processRolloutFiles(rolloutFiles(in: root)) {
            let page = pageCandidates(
                candidates,
                pageSize: pageSize,
                anchor: anchor,
                sortKey: sortKey,
                sortDirection: sortDirection,
                forceMoreMatches: true
            )
            return ConversationsPage(
                items: page.items,
                nextCursor: page.nextCursor,
                backwardsCursor: page.backwardsCursor,
                numScannedFiles: scannedFiles,
                reachedScanCap: true
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

                    if try processRolloutFiles(rolloutFiles(in: dayPath)) {
                        break outer
                    }
                }
            }
        }

        let reachedScanCap = scannedFiles >= maxScanFiles
        let pageWasFilledWithFilteredMatches = pageSize > 0 && candidates.count >= pageSize
        let unreturnedFilesMayRemain = pageWasFilledWithFilteredMatches && scannedFiles > candidates.count
        let page = pageCandidates(
            candidates,
            pageSize: pageSize,
            anchor: anchor,
            sortKey: sortKey,
            sortDirection: sortDirection,
            forceMoreMatches: (reachedScanCap && !candidates.isEmpty) || unreturnedFilesMayRemain
        )

        return ConversationsPage(
            items: page.items,
            nextCursor: page.nextCursor,
            backwardsCursor: page.backwardsCursor,
            numScannedFiles: scannedFiles,
            reachedScanCap: reachedScanCap
        )
    }

    private static func pathsMatchAfterNormalization(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs, isDirectory: true).standardizedFileURL.path ==
            URL(fileURLWithPath: rhs, isDirectory: true).standardizedFileURL.path
    }

    private static func pageCandidates(
        _ candidates: [ConversationCandidate],
        pageSize: Int,
        anchor: ConversationCursor?,
        sortKey: ConversationSortKey,
        sortDirection: ConversationSortDirection,
        forceMoreMatches: Bool
    ) -> (items: [ConversationItem], nextCursor: ConversationCursor?, backwardsCursor: ConversationCursor?) {
        let sorted = candidates.sorted { lhs, rhs in
            let comparison = compareCandidate(lhs, rhs, sortKey: sortKey)
            switch sortDirection {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
        let filtered: [ConversationCandidate]
        if let anchorTimestamp = anchor?.timestamp {
            filtered = sorted.filter { candidate in
                let timestamp = candidate.timestamp(for: sortKey)
                switch sortDirection {
                case .ascending:
                    return timestamp > anchorTimestamp
                case .descending:
                    return timestamp < anchorTimestamp
                }
            }
        } else {
            filtered = sorted
        }

        let normalizedPageSize = max(pageSize, 0)
        let pageCandidates = Array(filtered.prefix(normalizedPageSize))
        let moreMatchesAvailable = filtered.count > pageCandidates.count || forceMoreMatches
        return (
            items: pageCandidates.map(\.item),
            nextCursor: moreMatchesAvailable ? pageCandidates.last.map { buildCursor($0, sortKey: sortKey) } : nil,
            backwardsCursor: pageCandidates.first.map {
                buildBackwardsCursor($0, sortKey: sortKey, sortDirection: sortDirection)
            }
        )
    }

    private static func compareCandidate(
        _ lhs: ConversationCandidate,
        _ rhs: ConversationCandidate,
        sortKey: ConversationSortKey
    ) -> ComparisonResult {
        let lhsTimestamp = lhs.timestamp(for: sortKey)
        let rhsTimestamp = rhs.timestamp(for: sortKey)
        if lhsTimestamp < rhsTimestamp {
            return .orderedAscending
        }
        if lhsTimestamp > rhsTimestamp {
            return .orderedDescending
        }
        return uuidCompare(lhs.uuid, rhs.uuid)
    }

    private static func buildCursor(
        _ candidate: ConversationCandidate,
        sortKey: ConversationSortKey
    ) -> ConversationCursor {
        ConversationCursor(timestamp: candidate.timestamp(for: sortKey))
    }

    private static func buildBackwardsCursor(
        _ candidate: ConversationCandidate,
        sortKey: ConversationSortKey,
        sortDirection: ConversationSortDirection
    ) -> ConversationCursor {
        let interval: TimeInterval = sortDirection == .ascending ? 0.001 : -0.001
        return ConversationCursor(timestamp: candidate.timestamp(for: sortKey).addingTimeInterval(interval))
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

        return formatRFC3339Timestamp(modified)
    }

    fileprivate static func formatRFC3339Timestamp(_ date: Date) -> String {
        let wholeSeconds = date.timeIntervalSince1970.rounded(.towardZero)
        if abs(date.timeIntervalSince1970 - wholeSeconds) < 0.000_001 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseRFC3339Date(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let timestamp = fractionalFormatter.date(from: value) {
            return timestamp
        }
        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        wholeSecondFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return wholeSecondFormatter.date(from: value)
    }

    private static func uuidCompare(_ lhs: UUID, _ rhs: UUID) -> ComparisonResult {
        let lhsBytes = lhs.byteArray
        let rhsBytes = rhs.byteArray
        for index in lhsBytes.indices {
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

private struct RolloutFile {
    let timestamp: Date
    let uuid: UUID
    let path: URL
}

private struct ConversationCandidate {
    let uuid: UUID
    let sortCreatedAt: Date
    let sortUpdatedAt: Date
    let item: ConversationItem

    func timestamp(for sortKey: ConversationSortKey) -> Date {
        switch sortKey {
        case .createdAt:
            return sortCreatedAt
        case .updatedAt:
            return sortUpdatedAt
        }
    }
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

private extension UUID {
    var byteArray: [UInt8] {
        [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11,
            uuid.12, uuid.13, uuid.14, uuid.15
        ]
    }
}
