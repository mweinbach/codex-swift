import CodexCore
import XCTest

final class SeatbeltSandboxTests: XCTestCase {
    func testReadOnlyCommandArgumentsUseRustSeatbeltShape() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let args = SeatbeltSandbox.commandArguments(
            command: ["echo", "ok"],
            sandboxPolicy: .readOnly,
            sandboxPolicyCwd: cwd,
            environment: [:]
        )

        XCTAssertEqual(args[0], "-p")
        XCTAssertTrue(args[1].contains("(deny default)"))
        XCTAssertTrue(args[1].contains("; allow read-only file operations\n(allow file-read*)"))
        XCTAssertFalse(args[1].contains("(allow file-write*"))
        XCTAssertEqual(Array(args.suffix(3)), ["--", "echo", "ok"])
    }

    func testWorkspaceWriteArgumentsProtectGitAndCodexSubpaths() throws {
        let tempDir = try SeatbeltSandboxTemporaryDirectory()
        let writableRoot = tempDir.url.appendingPathComponent("workspace", isDirectory: true)
        let cwd = tempDir.url.appendingPathComponent("cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: writableRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: writableRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: writableRoot.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )

        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [try AbsolutePath(absolutePath: writableRoot.path)],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let args = SeatbeltSandbox.commandArguments(
            command: ["touch", "file"],
            sandboxPolicy: policy,
            sandboxPolicyCwd: try AbsolutePath(absolutePath: cwd.path),
            environment: [:]
        )

        let policyText = args[1]
        XCTAssertTrue(policyText.contains(#"(subpath (param "WRITABLE_ROOT_0"))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (subpath (param "WRITABLE_ROOT_0_RO_0")))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (subpath (param "WRITABLE_ROOT_0_RO_1")))"#))
        XCTAssertTrue(policyText.contains(#"(subpath (param "WRITABLE_ROOT_1"))"#))
        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_0=\(writableRoot.path)"))
        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_0_RO_0=\(writableRoot.appendingPathComponent(".git").path)"))
        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_0_RO_1=\(writableRoot.appendingPathComponent(".codex").path)"))
        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_1=\(cwd.path)"))
        XCTAssertEqual(Array(args.suffix(3)), ["--", "touch", "file"])
    }

    func testFullAutoSelectsWorkspaceWritePolicy() {
        XCTAssertEqual(SeatbeltSandbox.sandboxPolicy(fullAuto: false), .readOnly)
        XCTAssertEqual(SeatbeltSandbox.sandboxPolicy(fullAuto: true), .newWorkspaceWritePolicy())
    }
}

private final class SeatbeltSandboxTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
