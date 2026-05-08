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

    private let timestampProvider: () -> Date
    private var fileHandle: FileHandle?

    private init(rolloutPath: URL, fileHandle: FileHandle, timestampProvider: @escaping () -> Date) {
        self.rolloutPath = rolloutPath
        self.fileHandle = fileHandle
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
        originator: String,
        cliVersion: String,
        modelProvider: String?,
        gitInfo: GitInfo? = nil,
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
            timestampProvider: timestampProvider
        )
        try recorder.writeRolloutItem(.sessionMeta(SessionMetaLine(
            meta: SessionMeta(
                id: conversationID,
                timestamp: rolloutTimestampFormatter.string(from: sessionStartedAt),
                cwd: cwd.path,
                originator: originator,
                cliVersion: cliVersion,
                instructions: instructions,
                source: source,
                modelProvider: modelProvider
            ),
            git: gitInfo
        )))
        return recorder
    }

    public static func resume(path: URL, timestampProvider: @escaping () -> Date = Date.init) throws -> RolloutRecorder {
        let handle = try openForAppend(path: path, fileManager: .default)
        return RolloutRecorder(rolloutPath: path, fileHandle: handle, timestampProvider: timestampProvider)
    }

    public static func create(
        codexHome: URL,
        cwd: URL,
        originator: String,
        cliVersion: String,
        modelProvider: String?,
        params: RolloutRecorderParams,
        gitInfo: GitInfo? = nil,
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
                originator: originator,
                cliVersion: cliVersion,
                modelProvider: modelProvider,
                gitInfo: gitInfo,
                calendar: calendar,
                timestampProvider: timestampProvider,
                fileManager: fileManager
            )
        case let .resume(path):
            return try resume(path: path, timestampProvider: timestampProvider)
        }
    }

    public func recordItems(_ items: [RolloutRecordItem]) throws {
        let filtered = items.filter(Self.shouldPersist)
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
                  let data = trimmed.data(using: .utf8),
                  let rolloutLine = try? JSONDecoder().decode(RolloutLine.self, from: data)
            else {
                continue
            }

            if case let .sessionMeta(sessionMetaLine) = rolloutLine.item, conversationID == nil {
                conversationID = sessionMetaLine.meta.id
            }
            items.append(rolloutLine.item)
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

    private static func shouldPersist(_ item: RolloutRecordItem) -> Bool {
        switch item {
        case .sessionMeta, .compacted, .turnContext:
            return true
        case let .responseItem(responseItem):
            return RolloutPolicy.shouldPersistResponseItem(responseItem)
        case let .eventMsg(event):
            return RolloutPolicy.shouldPersistEventMessage(event)
        }
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
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
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
