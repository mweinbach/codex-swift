import CodexCLI
import XCTest

final class StateDBRecoveryTests: XCTestCase {
    func testRepairBacksUpOwnedDatabaseFilesLikeRust() throws {
        let temp = try StateDBRecoveryTemporaryDirectory()
        let statePath = temp.url.appendingPathComponent("state_5.sqlite", isDirectory: false)
        let stateWALPath = URL(fileURLWithPath: statePath.path + "-wal", isDirectory: false)
        let logsPath = temp.url.appendingPathComponent("logs_2.sqlite", isDirectory: false)
        try Data("state".utf8).write(to: statePath)
        try Data("state-wal".utf8).write(to: stateWALPath)
        try Data("logs".utf8).write(to: logsPath)
        let startupError = LocalStateDBStartupError(stateDBPath: statePath, detail: "corrupt")

        let backups = try StateDBRecovery.repairFiles(for: startupError)

        XCTAssertEqual(backups.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: statePath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateWALPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logsPath.path))
        for backup in backups {
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        }
    }

    func testRepairReplacesBlockingSQLiteHomeFileLikeRust() throws {
        let temp = try StateDBRecoveryTemporaryDirectory()
        let sqliteHome = temp.url.appendingPathComponent("sqlite-home", isDirectory: false)
        try Data("not-a-directory".utf8).write(to: sqliteHome)
        let startupError = LocalStateDBStartupError(
            stateDBPath: sqliteHome.appendingPathComponent("state_5.sqlite", isDirectory: false),
            detail: "File exists"
        )

        let backups = try StateDBRecovery.repairFiles(for: startupError)

        XCTAssertEqual(backups.count, 1)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteHome.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups[0].path))
    }

    func testLockFailuresSkipRepairLikeRust() {
        XCTAssertTrue(StateDBRecovery.isLocked(detail: "database is locked"))
        XCTAssertTrue(StateDBRecovery.isLocked(detail: "database is busy"))
        XCTAssertFalse(StateDBRecovery.isLocked(detail: "database disk image is malformed"))
    }

    func testGuidanceMatchesRustPolicy() {
        let error = LocalStateDBStartupError(
            stateDBPath: URL(fileURLWithPath: "/tmp/codex/state_5.sqlite", isDirectory: false),
            detail: "database disk image is malformed"
        )

        XCTAssertTrue(StateDBRecovery.repairPrompt(for: error).contains("Repair Codex local data now? [y/N]: "))
        XCTAssertTrue(StateDBRecovery.diagnosticGuidance(for: error).contains("Run `codex doctor`"))
        XCTAssertTrue(StateDBRecovery.lockedGuidance(for: error).contains("another Codex process"))
        XCTAssertTrue(String(describing: error).contains("failed to initialize sqlite state db at /tmp/codex/state_5.sqlite"))
    }
}

private final class StateDBRecoveryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateDBRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
