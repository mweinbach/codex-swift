import Foundation
import CodexCore

public struct LocalStateDBStartupError: Error, Equatable, CustomStringConvertible, Sendable {
    public let stateDBPath: URL
    public let detail: String

    public init(stateDBPath: URL, detail: String) {
        self.stateDBPath = stateDBPath
        self.detail = detail
    }

    public var description: String {
        "failed to initialize sqlite state db at \(stateDBPath.path): \(detail)"
    }
}

public enum StateDBRecovery {
    private static let stateDatabaseFilename = "state_5.sqlite"
    private static let logDatabaseFilename = "logs_2.sqlite"

    public static func startupError(
        codexHome: URL,
        runtimeConfig: CodexRuntimeConfig,
        underlyingError: Error
    ) -> LocalStateDBStartupError {
        let sqliteHome = runtimeConfig.sqliteHome.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? codexHome
        return LocalStateDBStartupError(
            stateDBPath: stateDatabasePath(sqliteHome: sqliteHome),
            detail: String(describing: underlyingError)
        )
    }

    public static func isLocked(detail: String) -> Bool {
        let lowercased = detail.lowercased()
        return lowercased.contains("database is locked") || lowercased.contains("database is busy")
    }

    public static func repairFiles(for startupError: LocalStateDBStartupError) throws -> [URL] {
        let fileManager = FileManager.default
        let sqliteHome = startupError.stateDBPath.deletingLastPathComponent()
        let repairSuffix = "codex-repair-\(Int(Date().timeIntervalSince1970))"
        var backups: [URL] = []

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sqliteHome.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                backups.append(try backupPath(sqliteHome, repairSuffix: repairSuffix, fileManager: fileManager))
                try fileManager.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
            }
        } else {
            try fileManager.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
        }

        let logDBPath = logDatabasePath(sqliteHome: sqliteHome)
        for path in sqlitePaths(startupError.stateDBPath) + sqlitePaths(logDBPath) {
            if fileManager.fileExists(atPath: path.path) {
                backups.append(try backupPath(path, repairSuffix: repairSuffix, fileManager: fileManager))
            }
        }

        guard !backups.isEmpty else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "no repairable Codex local data files were found"
            ])
        }
        return backups
    }

    public static func diagnosticGuidance(for startupError: LocalStateDBStartupError) -> String {
        [
            "Codex couldn't start because its local database appears to be damaged.",
            "Run `codex doctor` to check your setup and get next-step guidance.",
            "If this keeps happening, share the technical details below when asking for help.",
            technicalDetails(for: startupError)
        ].joined(separator: "\n")
    }

    public static func lockedGuidance(for startupError: LocalStateDBStartupError) -> String {
        [
            "Codex couldn't start because another Codex process is using its local data.",
            "Quit any other copies of Codex that may still be running, then try again.",
            technicalDetails(for: startupError)
        ].joined(separator: "\n")
    }

    public static func repairPrompt(for startupError: LocalStateDBStartupError) -> String {
        [
            "Codex couldn't start because its local database appears to be damaged.",
            "Codex can try a safe repair by backing up those files and rebuilding them.",
            technicalDetails(for: startupError),
            "Repair Codex local data now? [y/N]: "
        ].joined(separator: "\n")
    }

    public static func repairBackupsMessage(_ backups: [URL]) -> String {
        var lines = ["Backed up Codex local data before repair:"]
        lines.append(contentsOf: backups.map { "  \($0.path)" })
        lines.append("Retrying startup with rebuilt local data...")
        return lines.joined(separator: "\n")
    }

    private static func technicalDetails(for startupError: LocalStateDBStartupError) -> String {
        [
            "Technical details:",
            "  Location: \(startupError.stateDBPath.path)",
            "  Cause: \(startupError.detail)"
        ].joined(separator: "\n")
    }

    private static func stateDatabasePath(sqliteHome: URL) -> URL {
        sqliteHome.appendingPathComponent(stateDatabaseFilename, isDirectory: false).standardizedFileURL
    }

    private static func logDatabasePath(sqliteHome: URL) -> URL {
        sqliteHome.appendingPathComponent(logDatabaseFilename, isDirectory: false).standardizedFileURL
    }

    private static func sqlitePaths(_ databasePath: URL) -> [URL] {
        [
            databasePath,
            URL(fileURLWithPath: databasePath.path + "-wal", isDirectory: false),
            URL(fileURLWithPath: databasePath.path + "-shm", isDirectory: false)
        ]
    }

    private static func backupPath(
        _ path: URL,
        repairSuffix: String,
        fileManager: FileManager
    ) throws -> URL {
        let fileName = path.lastPathComponent
        var sequence = 0
        while true {
            let backupName = "\(fileName).\(repairSuffix).\(sequence).bak"
            let backupURL = path.deletingLastPathComponent().appendingPathComponent(backupName, isDirectory: false)
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: path, to: backupURL)
                return backupURL
            }
            sequence += 1
        }
    }
}
