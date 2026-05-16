import CodexCore
import Foundation

public enum DoctorStatePathProbe: Equatable, Sendable {
    case directory
    case file
    case other
    case missing
    case failed(String)
}

public enum DoctorStateSQLiteIntegrityProbe: Equatable, Sendable {
    case skippedMissing
    case rows([String])
    case failed(String)
}

public struct DoctorStateRolloutStats: Equatable, Sendable {
    public let files: UInt64
    public let totalBytes: UInt64
    public let error: String?

    public init(files: UInt64, totalBytes: UInt64, error: String? = nil) {
        self.files = files
        self.totalBytes = totalBytes
        self.error = error
    }
}

public struct DoctorStatePathsCheckInputs: Equatable, Sendable {
    public let codexHomePath: String
    public let logDirPath: String
    public let sqliteHomePath: String
    public let codexHome: DoctorStatePathProbe
    public let logDir: DoctorStatePathProbe
    public let sqliteHome: DoctorStatePathProbe
    public let stateDB: DoctorStatePathProbe
    public let logDB: DoctorStatePathProbe
    public let stateDBIntegrity: DoctorStateSQLiteIntegrityProbe
    public let logDBIntegrity: DoctorStateSQLiteIntegrityProbe
    public let activeRollouts: DoctorStateRolloutStats
    public let archivedRollouts: DoctorStateRolloutStats
    public let standaloneReleaseCache: String?

    public init(
        codexHomePath: String,
        logDirPath: String,
        sqliteHomePath: String,
        codexHome: DoctorStatePathProbe,
        logDir: DoctorStatePathProbe,
        sqliteHome: DoctorStatePathProbe,
        stateDB: DoctorStatePathProbe,
        logDB: DoctorStatePathProbe,
        stateDBIntegrity: DoctorStateSQLiteIntegrityProbe,
        logDBIntegrity: DoctorStateSQLiteIntegrityProbe,
        activeRollouts: DoctorStateRolloutStats,
        archivedRollouts: DoctorStateRolloutStats,
        standaloneReleaseCache: String? = nil
    ) {
        self.codexHomePath = codexHomePath
        self.logDirPath = logDirPath
        self.sqliteHomePath = sqliteHomePath
        self.codexHome = codexHome
        self.logDir = logDir
        self.sqliteHome = sqliteHome
        self.stateDB = stateDB
        self.logDB = logDB
        self.stateDBIntegrity = stateDBIntegrity
        self.logDBIntegrity = logDBIntegrity
        self.activeRollouts = activeRollouts
        self.archivedRollouts = archivedRollouts
        self.standaloneReleaseCache = standaloneReleaseCache
    }
}

extension DoctorCommandRuntime {
    public static func fallbackStatePathsCheck(
        codexHomeResolver: () throws -> URL = { try CodexHome.find() }
    ) -> DoctorCheck {
        do {
            let path = try codexHomeResolver().standardizedFileURL.path
            return DoctorCheck(
                id: "state.paths",
                category: "state",
                status: .ok,
                summary: "CODEX_HOME was resolved without config",
                details: ["CODEX_HOME: \(path)"]
            )
        } catch {
            return DoctorCheck(
                id: "state.paths",
                category: "state",
                status: .warning,
                summary: "CODEX_HOME could not be resolved",
                details: [String(describing: error)]
            )
        }
    }

    public static func statePathsCheck(codexHome: URL, settings: CodexRuntimeConfig) -> DoctorCheck {
        let codexHomePath = codexHome.standardizedFileURL.path
        let logDirPath = settings.logDir ?? codexHome.appendingPathComponent("log", isDirectory: true).path
        let sqliteHomePath = settings.sqliteHome ?? codexHomePath
        let stateDBPath = stateDatabasePath(sqliteHomePath: sqliteHomePath)
        let logDBPath = logDatabasePath(sqliteHomePath: sqliteHomePath)
        return statePathsCheck(inputs: DoctorStatePathsCheckInputs(
            codexHomePath: codexHomePath,
            logDirPath: logDirPath,
            sqliteHomePath: sqliteHomePath,
            codexHome: statePathProbe(path: codexHomePath),
            logDir: statePathProbe(path: logDirPath),
            sqliteHome: statePathProbe(path: sqliteHomePath),
            stateDB: statePathProbe(path: stateDBPath),
            logDB: statePathProbe(path: logDBPath),
            stateDBIntegrity: sqliteIntegrityProbe(path: stateDBPath),
            logDBIntegrity: sqliteIntegrityProbe(path: logDBPath),
            activeRollouts: collectRolloutStats(
                root: URL(fileURLWithPath: codexHomePath).appendingPathComponent("sessions", isDirectory: true)
            ),
            archivedRollouts: collectRolloutStats(
                root: URL(fileURLWithPath: codexHomePath).appendingPathComponent("archived_sessions", isDirectory: true)
            )
        ))
    }

    public static func statePathsCheck(inputs: DoctorStatePathsCheckInputs) -> DoctorCheck {
        let stateDBPath = stateDatabasePath(sqliteHomePath: inputs.sqliteHomePath)
        let logDBPath = logDatabasePath(sqliteHomePath: inputs.sqliteHomePath)
        var details = [
            statePathDetail(label: "CODEX_HOME", path: inputs.codexHomePath, probe: inputs.codexHome),
            statePathDetail(label: "log dir", path: inputs.logDirPath, probe: inputs.logDir),
            statePathDetail(label: "sqlite home", path: inputs.sqliteHomePath, probe: inputs.sqliteHome),
            statePathDetail(label: "state DB", path: stateDBPath, probe: inputs.stateDB),
            statePathDetail(label: "log DB", path: logDBPath, probe: inputs.logDB)
        ]
        let stateIntegrity = sqliteIntegrityDetail(label: "state DB", probe: inputs.stateDBIntegrity)
        let logIntegrity = sqliteIntegrityDetail(label: "log DB", probe: inputs.logDBIntegrity)
        details.append(stateIntegrity.detail)
        details.append(logIntegrity.detail)
        details.append(rolloutStatsDetail(label: "active rollout files", stats: inputs.activeRollouts))
        details.append(rolloutStatsDetail(label: "archived rollout files", stats: inputs.archivedRollouts))
        if let standaloneReleaseCache = inputs.standaloneReleaseCache {
            details.append(standaloneReleaseCache)
        }
        let failedIntegrity = stateIntegrity.failed || logIntegrity.failed
        return DoctorCheck(
            id: "state.paths",
            category: "state",
            status: failedIntegrity ? .fail : .ok,
            summary: failedIntegrity
                ? "state database integrity check failed"
                : "state paths and databases are inspectable",
            details: details,
            remediation: failedIntegrity
                ? "Back up CODEX_HOME, then remove or repair the affected SQLite database."
                : nil
        )
    }

    private static let stateDatabaseFilename = "state_5.sqlite"
    private static let logDatabaseFilename = "logs_2.sqlite"

    private static func stateDatabasePath(sqliteHomePath: String) -> String {
        URL(fileURLWithPath: sqliteHomePath)
            .appendingPathComponent(stateDatabaseFilename, isDirectory: false)
            .standardizedFileURL
            .path
    }

    private static func logDatabasePath(sqliteHomePath: String) -> String {
        URL(fileURLWithPath: sqliteHomePath)
            .appendingPathComponent(logDatabaseFilename, isDirectory: false)
            .standardizedFileURL
            .path
    }

    private static func statePathDetail(label: String, path: String, probe: DoctorStatePathProbe) -> String {
        switch probe {
        case .directory:
            "\(label): \(path) (dir)"
        case .file:
            "\(label): \(path) (file)"
        case .other:
            "\(label): \(path) (other)"
        case .missing:
            "\(label): \(path) (missing)"
        case let .failed(error):
            "\(label): \(path) (\(error))"
        }
    }

    private static func sqliteIntegrityDetail(
        label: String,
        probe: DoctorStateSQLiteIntegrityProbe
    ) -> (detail: String, failed: Bool) {
        switch probe {
        case .skippedMissing:
            return ("\(label) integrity: skipped (missing)", false)
        case let .rows(rows) where rows.allSatisfy({ $0 == "ok" }):
            return ("\(label) integrity: ok", false)
        case let .rows(rows):
            return ("\(label) integrity: \(rows.joined(separator: "; "))", true)
        case let .failed(error):
            return ("\(label) integrity: \(error)", true)
        }
    }

    private static func rolloutStatsDetail(label: String, stats: DoctorStateRolloutStats) -> String {
        if let error = stats.error {
            return "\(label): scan failed (\(error))"
        }
        let average = stats.files == 0 ? 0 : stats.totalBytes / stats.files
        return "\(label): \(stats.files) files, \(stats.totalBytes) total bytes, \(average) average bytes"
    }

    private static func statePathProbe(path: String) -> DoctorStatePathProbe {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                return .directory
            case .typeRegular:
                return .file
            case .some, .none:
                return .other
            }
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError
            {
                return .missing
            }
            return .failed(error.localizedDescription)
        }
    }

    private static func sqliteIntegrityProbe(path: String) -> DoctorStateSQLiteIntegrityProbe {
        guard FileManager.default.fileExists(atPath: path) else {
            return .skippedMissing
        }
        switch runStateCommand("sqlite3", [path, "PRAGMA integrity_check;"]) {
        case let .success(output):
            let rows = output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .rows(rows.isEmpty ? [""] : rows)
        case let .failure(error):
            return .failed(error)
        }
    }

    private static func collectRolloutStats(root: URL) -> DoctorStateRolloutStats {
        var files: UInt64 = 0
        var totalBytes: UInt64 = 0
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return DoctorStateRolloutStats(files: 0, totalBytes: 0)
        }
        var scanError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                scanError = error
                return false
            }
        ) else {
            return DoctorStateRolloutStats(files: 0, totalBytes: 0, error: "unable to scan directory")
        }
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-")
                else {
                    continue
                }
                files += 1
                let next = totalBytes.addingReportingOverflow(UInt64(values.fileSize ?? 0))
                totalBytes = next.overflow ? UInt64.max : next.partialValue
            } catch {
                return DoctorStateRolloutStats(files: files, totalBytes: totalBytes, error: error.localizedDescription)
            }
        }
        if let scanError {
            return DoctorStateRolloutStats(files: files, totalBytes: totalBytes, error: scanError.localizedDescription)
        }
        return DoctorStateRolloutStats(files: files, totalBytes: totalBytes)
    }

    private static func runStateCommand(_ command: String, _ arguments: [String]) -> DoctorCommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus == 0 {
            return .success(output)
        }
        let error = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if error.isEmpty {
            return .failure("exited with status \(process.terminationStatus)")
        }
        return .failure(error)
    }
}
