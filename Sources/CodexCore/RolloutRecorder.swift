import Foundation

public enum RolloutRecorderError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptySessionFile
    case missingConversationID
    case writeAfterShutdown

    public var description: String {
        switch self {
        case .emptySessionFile:
            return "empty session file"
        case .missingConversationID:
            return "failed to parse conversation ID from rollout file"
        case .writeAfterShutdown:
            return "rollout recorder has been shut down"
        }
    }
}

public enum RolloutRecorderParams: Equatable, Sendable {
    case create(conversationID: ConversationId, instructions: String?, source: SessionSource)
    case resume(path: URL)

    public static func new(
        conversationID: ConversationId,
        instructions: String?,
        source: SessionSource
    ) -> RolloutRecorderParams {
        .create(conversationID: conversationID, instructions: instructions, source: source)
    }

    public static func resume(_ path: URL) -> RolloutRecorderParams {
        .resume(path: path)
    }
}

public final class RolloutRecorder {
    public let rolloutPath: URL

    private static let persistedExecAggregatedOutputMaxBytes = 10_000

    private let timestampProvider: () -> Date
    private let eventPersistenceMode: EventPersistenceMode
    private var fileHandle: FileHandle?

    private init(
        rolloutPath: URL,
        fileHandle: FileHandle,
        eventPersistenceMode: EventPersistenceMode,
        timestampProvider: @escaping () -> Date
    ) {
        self.rolloutPath = rolloutPath
        self.fileHandle = fileHandle
        self.eventPersistenceMode = eventPersistenceMode
        self.timestampProvider = timestampProvider
    }

    deinit {
        try? fileHandle?.close()
    }

    public static func create(
        codexHome: URL,
        cwd: URL,
        conversationID: ConversationId,
        instructions: String? = nil,
        source: SessionSource,
        forkedFromID: ConversationId? = nil,
        threadSource: ThreadSource? = nil,
        originator: String,
        cliVersion: String,
        modelProvider: String?,
        dynamicTools: [DynamicToolSpec]? = nil,
        gitInfo: GitInfo? = nil,
        eventPersistenceMode: EventPersistenceMode = .limited,
        calendar: Calendar = .current,
        timestampProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) throws -> RolloutRecorder {
        let sessionStartedAt = timestampProvider()
        let rolloutPath = try createLogFile(
            codexHome: codexHome,
            conversationID: conversationID,
            timestamp: sessionStartedAt,
            calendar: calendar,
            fileManager: fileManager
        )
        let handle = try openForAppend(path: rolloutPath, fileManager: fileManager)
        let recorder = RolloutRecorder(
            rolloutPath: rolloutPath,
            fileHandle: handle,
            eventPersistenceMode: eventPersistenceMode,
            timestampProvider: timestampProvider
        )
        try recorder.writeRolloutItem(.sessionMeta(SessionMetaLine(
            meta: SessionMeta(
                id: conversationID,
                forkedFromID: forkedFromID,
                timestamp: rolloutTimestampFormatter.string(from: sessionStartedAt),
                cwd: cwd.path,
                originator: originator,
                cliVersion: cliVersion,
                instructions: instructions,
                source: source,
                threadSource: threadSource,
                modelProvider: modelProvider,
                dynamicTools: dynamicTools
            ),
            git: gitInfo
        )))
        return recorder
    }

    public static func resume(
        path: URL,
        eventPersistenceMode: EventPersistenceMode = .limited,
        timestampProvider: @escaping () -> Date = Date.init
    ) throws -> RolloutRecorder {
        let handle = try openForAppend(path: path, fileManager: .default)
        return RolloutRecorder(
            rolloutPath: path,
            fileHandle: handle,
            eventPersistenceMode: eventPersistenceMode,
            timestampProvider: timestampProvider
        )
    }

    public static func createFork(
        codexHome: URL,
        cwd: URL,
        conversationID: ConversationId,
        forkedFromID: ConversationId,
        initialHistory: InitialHistory,
        instructions: String? = nil,
        source: SessionSource,
        threadSource: ThreadSource? = nil,
        originator: String,
        cliVersion: String,
        modelProvider: String?,
        dynamicTools: [DynamicToolSpec]? = nil,
        gitInfo: GitInfo? = nil,
        eventPersistenceMode: EventPersistenceMode = .limited,
        calendar: Calendar = .current,
        timestampProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) throws -> RolloutRecorder {
        let recorder = try create(
            codexHome: codexHome,
            cwd: cwd,
            conversationID: conversationID,
            instructions: instructions,
            source: source,
            forkedFromID: forkedFromID,
            threadSource: threadSource,
            originator: originator,
            cliVersion: cliVersion,
            modelProvider: modelProvider,
            dynamicTools: dynamicTools ?? initialHistory.dynamicTools,
            gitInfo: gitInfo,
            eventPersistenceMode: eventPersistenceMode,
            calendar: calendar,
            timestampProvider: timestampProvider,
            fileManager: fileManager
        )
        do {
            try recorder.recordItems(forkedRolloutItems(from: initialHistory))
        } catch {
            try? recorder.shutdown()
            throw error
        }
        return recorder
    }

    public static func forkedRolloutItems(from history: InitialHistory) -> [RolloutRecordItem] {
        history.rolloutItems.filter { item in
            if case .sessionMeta = item {
                return false
            }
            return true
        }
    }

    public static func create(
        codexHome: URL,
        cwd: URL,
        originator: String,
        cliVersion: String,
        modelProvider: String?,
        dynamicTools: [DynamicToolSpec]? = nil,
        forkedFromID: ConversationId? = nil,
        threadSource: ThreadSource? = nil,
        params: RolloutRecorderParams,
        gitInfo: GitInfo? = nil,
        eventPersistenceMode: EventPersistenceMode = .limited,
        calendar: Calendar = .current,
        timestampProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) throws -> RolloutRecorder {
        switch params {
        case let .create(conversationID, instructions, source):
            return try create(
                codexHome: codexHome,
                cwd: cwd,
                conversationID: conversationID,
                instructions: instructions,
                source: source,
                forkedFromID: forkedFromID,
                threadSource: threadSource,
                originator: originator,
                cliVersion: cliVersion,
                modelProvider: modelProvider,
                dynamicTools: dynamicTools,
                gitInfo: gitInfo,
                eventPersistenceMode: eventPersistenceMode,
                calendar: calendar,
                timestampProvider: timestampProvider,
                fileManager: fileManager
            )
        case let .resume(path):
            return try resume(
                path: path,
                eventPersistenceMode: eventPersistenceMode,
                timestampProvider: timestampProvider
            )
        }
    }

    public func recordItems(_ items: [RolloutRecordItem]) throws {
        let filtered = items
            .filter { Self.shouldPersist($0, mode: eventPersistenceMode) }
            .map { Self.sanitizeForPersistence($0, mode: eventPersistenceMode) }
        guard !filtered.isEmpty else {
            return
        }
        for item in filtered {
            try writeRolloutItem(item)
        }
    }

    public func flush() throws {
        guard let fileHandle else {
            throw RolloutRecorderError.writeAfterShutdown
        }
        try fileHandle.synchronize()
    }

    public func shutdown() throws {
        guard let handle = fileHandle else {
            return
        }
        try handle.synchronize()
        try handle.close()
        fileHandle = nil
    }

    public static func getRolloutHistory(path: URL) throws -> InitialHistory {
        let text = try String(contentsOf: path, encoding: .utf8)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RolloutRecorderError.emptySessionFile
        }

        var items: [RolloutRecordItem] = []
        var conversationID: ConversationId?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8)
            else {
                continue
            }
            if isLegacyGhostSnapshotResponseLine(data) {
                continue
            }
            guard let rolloutLine = try? JSONDecoder().decode(RolloutLine.self, from: data) else {
                continue
            }

            guard let item = sanitizedLoadedItem(rolloutLine.item) else {
                continue
            }

            if case let .sessionMeta(sessionMetaLine) = item, conversationID == nil {
                conversationID = sessionMetaLine.meta.id
            }
            items.append(item)
        }

        guard let conversationID else {
            throw RolloutRecorderError.missingConversationID
        }
        if items.isEmpty {
            return .new
        }
        return .resumed(ResumedHistory(
            conversationID: conversationID,
            history: items,
            rolloutPath: path.path
        ))
    }

    public static func reconstructResponseHistory(
        from rolloutItems: [RolloutRecordItem],
        initialContext: [ResponseItem] = []
    ) -> [ResponseItem] {
        var history = initialContext

        for item in rolloutItems {
            switch item {
            case let .responseItem(responseItem):
                history.append(responseItem)

            case let .compacted(compacted):
                if let replacementHistory = compacted.replacementHistory {
                    history = replacementHistory
                } else {
                    let snapshot = history
                    history = Compact.buildCompactedHistory(
                        initialContext: initialContext,
                        userMessages: Compact.collectUserMessages(snapshot),
                        summaryText: compacted.message
                    )
                }

            case .sessionMeta,
                 .turnContext,
                 .eventMsg:
                continue
            }
        }

        ContextNormalization.normalizeHistory(&history)
        return history
    }

    public static func listConversations(
        codexHome: URL,
        pageSize: Int,
        cursor: ConversationCursor? = nil,
        allowedSources: [SessionSource] = [],
        modelProviders: [String]? = nil,
        defaultProvider: String
    ) throws -> ConversationsPage {
        try RolloutListing.getConversations(
            codexHome: codexHome,
            pageSize: pageSize,
            cursor: cursor,
            allowedSources: allowedSources,
            modelProviders: modelProviders,
            defaultProvider: defaultProvider
        )
    }

    private func writeRolloutItem(_ item: RolloutRecordItem) throws {
        guard let fileHandle else {
            throw RolloutRecorderError.writeAfterShutdown
        }

        let line = RolloutLine(
            timestamp: Self.rolloutTimestampFormatter.string(from: timestampProvider()),
            item: item
        )
        let data = try JSONEncoder().encode(line)
        try fileHandle.write(contentsOf: data)
        try fileHandle.write(contentsOf: Data([0x0A]))
        try fileHandle.synchronize()
    }

    private static func shouldPersist(_ item: RolloutRecordItem, mode: EventPersistenceMode) -> Bool {
        switch item {
        case .sessionMeta, .compacted, .turnContext:
            return true
        case let .responseItem(responseItem):
            return RolloutPolicy.shouldPersistResponseItem(responseItem)
        case let .eventMsg(event):
            return RolloutPolicy.shouldPersistEventMessage(event, mode: mode)
        }
    }

    private static func sanitizeForPersistence(
        _ item: RolloutRecordItem,
        mode: EventPersistenceMode
    ) -> RolloutRecordItem {
        guard mode == .extended else {
            return item
        }
        switch item {
        case let .eventMsg(.execCommandEnd(event)):
            let sanitized = ExecCommandEndEvent(
                callID: event.callID,
                processID: event.processID,
                turnID: event.turnID,
                command: event.command,
                cwd: event.cwd,
                parsedCmd: event.parsedCmd,
                source: event.source,
                interactionInput: event.interactionInput,
                stdout: "",
                stderr: "",
                aggregatedOutput: Truncation.truncateText(
                    event.aggregatedOutput,
                    policy: .bytes(persistedExecAggregatedOutputMaxBytes)
                ),
                exitCode: event.exitCode,
                duration: event.duration,
                formattedOutput: ""
            )
            return .eventMsg(.execCommandEnd(sanitized))
        case .sessionMeta,
             .responseItem,
             .compacted,
             .turnContext,
             .eventMsg:
            return item
        }
    }

    private static func sanitizedLoadedItem(_ item: RolloutRecordItem) -> RolloutRecordItem? {
        switch item {
        case .responseItem(.ghostSnapshot):
            return nil

        case let .compacted(compacted):
            guard let replacementHistory = compacted.replacementHistory else {
                return item
            }
            return .compacted(CompactedItem(
                message: compacted.message,
                replacementHistory: replacementHistory.filter { responseItem in
                    if case .ghostSnapshot = responseItem {
                        return false
                    }
                    return true
                }
            ))

        case .sessionMeta,
             .responseItem,
             .turnContext,
             .eventMsg:
            return item
        }
    }

    private static func isLegacyGhostSnapshotResponseLine(_ data: Data) -> Bool {
        guard let rawLine = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(lineFields) = rawLine,
              lineFields["type"] == .string("response_item"),
              case let .object(payloadFields)? = lineFields["payload"],
              payloadFields["type"] == .string("ghost_snapshot")
        else {
            return false
        }
        return true
    }

    private static func createLogFile(
        codexHome: URL,
        conversationID: ConversationId,
        timestamp: Date,
        calendar: Calendar,
        fileManager: FileManager
    ) throws -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: timestamp)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let directory = codexHome
            .appendingPathComponent(RolloutListing.sessionsSubdirectory, isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let filenameFormatter = DateFormatter()
        filenameFormatter.locale = Locale(identifier: "en_US_POSIX")
        filenameFormatter.calendar = calendar
        filenameFormatter.timeZone = calendar.timeZone
        filenameFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"

        return directory.appendingPathComponent(
            "rollout-\(filenameFormatter.string(from: timestamp))-\(conversationID.description).jsonl",
            isDirectory: false
        )
    }

    private static func openForAppend(path: URL, fileManager: FileManager) throws -> FileHandle {
        if !fileManager.fileExists(atPath: path.path) {
            _ = fileManager.createFile(atPath: path.path, contents: nil)
        }
        let size = (try? fileManager.attributesOfItem(atPath: path.path)[.size] as? NSNumber)?.uint64Value ?? 0
        var needsSeparator = false
        if size > 0 {
            let readHandle = try FileHandle(forReadingFrom: path)
            try readHandle.seek(toOffset: size - 1)
            needsSeparator = readHandle.readData(ofLength: 1) != Data([0x0A])
            try readHandle.close()
        }
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        if needsSeparator {
            try handle.write(contentsOf: Data([0x0A]))
        }
        return handle
    }

    private static let rolloutTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
}
