@testable import CodexCore
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

    func testNetworkPolicyAllowsTLSWithoutDarwinUserCacheWrite() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: true,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        )
        let args = SeatbeltSandbox.commandArguments(
            command: ["curl", "https://example.com"],
            sandboxPolicy: policy,
            sandboxPolicyCwd: cwd,
            environment: [:]
        )

        XCTAssertTrue(
            args[1].contains(#"(global-name "com.apple.trustd.agent")"#),
            "policy should keep trustd agent access for TLS certificate verification"
        )
        XCTAssertFalse(args[1].contains("DARWIN_USER_CACHE_DIR"))
        XCTAssertFalse(args.contains { $0.hasPrefix("-DDARWIN_USER_CACHE_DIR=") })
    }

    func testReadOnlyNetworkAccessUsesRustSeatbeltNetworkPolicy() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let args = SeatbeltSandbox.commandArguments(
            command: ["curl", "https://example.com"],
            sandboxPolicy: .readOnlyWithNetworkAccess,
            sandboxPolicyCwd: cwd,
            environment: [:]
        )

        XCTAssertTrue(args[1].contains("; allow read-only file operations\n(allow file-read*)"))
        XCTAssertFalse(args[1].contains("(allow file-write*"))
        XCTAssertTrue(args[1].contains(#"(allow network-outbound)"#))
    }

    func testAllowUnixSocketsAddsRustSeatbeltPolicyAndParams() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let tempDir = try SeatbeltSandboxTemporaryDirectory()
        let socketRoot = tempDir.url.appendingPathComponent("codex-browser-use", isDirectory: true)
        try FileManager.default.createDirectory(at: socketRoot, withIntermediateDirectories: true)

        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            sandboxPolicy: .readOnly,
            sandboxPolicyCwd: cwd,
            allowUnixSockets: [socketRoot.path],
            environment: [:]
        )

        let policyText = args[1]
        XCTAssertTrue(policyText.contains("; allow unix domain sockets for local IPC"))
        XCTAssertTrue(policyText.contains("(allow system-socket (socket-domain AF_UNIX))"))
        XCTAssertTrue(
            policyText.contains(#"(allow network-bind (local unix-socket (subpath (param "UNIX_SOCKET_PATH_0"))))"#)
        )
        XCTAssertTrue(
            policyText.contains(#"(allow network-outbound (remote unix-socket (subpath (param "UNIX_SOCKET_PATH_0"))))"#)
        )
        XCTAssertFalse(policyText.contains("(allow network-outbound (remote unix-socket))"))
        XCTAssertTrue(args.contains("-DUNIX_SOCKET_PATH_0=\(socketRoot.path)"))
    }

    func testAllowUnixSocketsUseStableSortedDeduplicatedParamNames() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let tempDir = try SeatbeltSandboxTemporaryDirectory()
        let aSocketRoot = tempDir.url.appendingPathComponent("a.sock", isDirectory: true)
        let bSocketRoot = tempDir.url.appendingPathComponent("b.sock", isDirectory: true)
        try FileManager.default.createDirectory(at: aSocketRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bSocketRoot, withIntermediateDirectories: true)

        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            sandboxPolicy: .readOnly,
            sandboxPolicyCwd: cwd,
            allowUnixSockets: [bSocketRoot.path, aSocketRoot.path, aSocketRoot.path, "relative.sock"],
            environment: [:]
        )

        let unixSocketParams = args.filter { $0.hasPrefix("-DUNIX_SOCKET_PATH_") }
        XCTAssertEqual(unixSocketParams, [
            "-DUNIX_SOCKET_PATH_0=\(aSocketRoot.path)",
            "-DUNIX_SOCKET_PATH_1=\(bSocketRoot.path)"
        ])
    }

    func testFullNetworkStillIncludesExplicitUnixSocketAllowlist() throws {
        let cwd = try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
        let tempDir = try SeatbeltSandboxTemporaryDirectory()
        let socketRoot = tempDir.url.appendingPathComponent("codex-browser-use", isDirectory: true)
        try FileManager.default.createDirectory(at: socketRoot, withIntermediateDirectories: true)

        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            sandboxPolicy: .readOnlyWithNetworkAccess,
            sandboxPolicyCwd: cwd,
            allowUnixSockets: [socketRoot.path],
            environment: [:]
        )

        let policyText = args[1]
        XCTAssertTrue(policyText.contains("(allow network-outbound)"))
        XCTAssertTrue(policyText.contains("(allow network-inbound)"))
        XCTAssertTrue(
            policyText.contains(#"(allow network-outbound (remote unix-socket (subpath (param "UNIX_SOCKET_PATH_0"))))"#)
        )
        XCTAssertTrue(args.contains("-DUNIX_SOCKET_PATH_0=\(socketRoot.path)"))
    }

    func testDirectFileSystemPolicyExcludesUnreadableRootsFromReadAndWrite() throws {
        let unreadableRoot = try AbsolutePath(absolutePath: "/tmp/codex-unreadable")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(unreadableRoot.path), access: .none)
        ])
        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            fileSystemSandboxPolicy: policy,
            networkSandboxPolicy: .restricted,
            sandboxPolicyCwd: try AbsolutePath(absolutePath: "/")
        )

        let policyText = args[1]
        XCTAssertTrue(policyText.contains(#"(deny file-read* (regex #"^/private/tmp/codex-unreadable(/.*)?$"))"#))
        XCTAssertTrue(policyText.contains(#"(deny file-write-unlink (regex #"^/private/tmp/codex-unreadable(/.*)?$"))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (literal (param "READABLE_ROOT_0_EXCLUDED_0")))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (subpath (param "READABLE_ROOT_0_EXCLUDED_0")))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (literal (param "WRITABLE_ROOT_0_EXCLUDED_0")))"#))
        XCTAssertTrue(policyText.contains(#"(require-not (subpath (param "WRITABLE_ROOT_0_EXCLUDED_0")))"#))
        XCTAssertTrue(args.contains("-DREADABLE_ROOT_0_EXCLUDED_0=/private/tmp/codex-unreadable"))
        XCTAssertTrue(args.contains { $0.hasPrefix("-DWRITABLE_ROOT_0_EXCLUDED_") && $0.hasSuffix("=/private/tmp/codex-unreadable") })
    }

    func testDirectWritableRootsIncludeTopLevelTmpAliasForSeatbelt() throws {
        let cwd = try AbsolutePath(absolutePath: "/tmp/codex-direct-cwd")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ])
        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            fileSystemSandboxPolicy: policy,
            networkSandboxPolicy: .restricted,
            sandboxPolicyCwd: cwd
        )

        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_0=/private/tmp/codex-direct-cwd"))
        XCTAssertTrue(args.contains("-DWRITABLE_ROOT_1=/tmp/codex-direct-cwd"))
    }

    func testDirectReadableRootsExcludeNestedUnreadableRoots() throws {
        let readableRoot = try AbsolutePath(absolutePath: "/tmp/codex-readable")
        let unreadableRoot = try readableRoot.join("private")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(readableRoot.path), access: .read),
            FileSystemSandboxEntry(path: .path(unreadableRoot.path), access: .none)
        ])
        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            fileSystemSandboxPolicy: policy,
            networkSandboxPolicy: .restricted,
            sandboxPolicyCwd: try AbsolutePath(absolutePath: "/")
        )

        XCTAssertTrue(args.contains("-DREADABLE_ROOT_0=/private/tmp/codex-readable"))
        XCTAssertTrue(args.contains("-DREADABLE_ROOT_0_EXCLUDED_0=/private/tmp/codex-readable/private"))
        XCTAssertTrue(args[1].contains(#"(require-not (literal (param "READABLE_ROOT_0_EXCLUDED_0")))"#))
        XCTAssertTrue(args[1].contains(#"(require-not (subpath (param "READABLE_ROOT_0_EXCLUDED_0")))"#))
    }

    func testUnreadableGlobRegexMatchesRustSeatbeltTranslation() {
        XCTAssertEqual(
            SeatbeltSandbox.seatbeltRegexForUnreadableGlob("/tmp/repo/**/*.env"),
            #"^/tmp/repo/(.*/)?[^/]*\.env$"#
        )
        XCTAssertEqual(
            SeatbeltSandbox.seatbeltRegexForUnreadableGlob("/tmp/repo/[!a-c]?.txt"),
            #"^/tmp/repo/[^a-c][^/]\.txt$"#
        )
        XCTAssertEqual(
            SeatbeltSandbox.seatbeltRegexForUnreadableGlob("/tmp/repo/[abc"),
            #"^/tmp/repo/\[abc(/.*)?$"#
        )
    }

    func testDirectSeatbeltArgsIncludeUnreadableGlobDenyPolicy() throws {
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("/tmp/repo/**/*.env"), access: .none)
        ])
        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            fileSystemSandboxPolicy: policy,
            networkSandboxPolicy: .restricted,
            sandboxPolicyCwd: try AbsolutePath(absolutePath: "/")
        )

        let regex = #"^/tmp/repo/(.*/)?[^/]*\.env$"#
        XCTAssertTrue(args[1].contains(#"(deny file-read* (regex #"\#(regex)"))"#))
        XCTAssertTrue(args[1].contains(#"(deny file-write-unlink (regex #"\#(regex)"))"#))
    }

    func testDirectMinimalReadProfileIncludesRustPlatformDefaults() throws {
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read)
        ])
        let args = SeatbeltSandbox.commandArguments(
            command: ["/usr/bin/true"],
            fileSystemSandboxPolicy: policy,
            networkSandboxPolicy: .restricted,
            sandboxPolicyCwd: try AbsolutePath(absolutePath: "/")
        )

        XCTAssertTrue(args[1].contains("macOS platform defaults included when a split filesystem policy requests `:minimal`"))
        XCTAssertTrue(args[1].contains(#"(allow file-read-data (subpath "/usr/bin"))"#))
    }

    func testFullAutoSelectsWorkspaceWritePolicy() {
        XCTAssertEqual(SeatbeltSandbox.sandboxPolicy(fullAuto: false), .readOnly)
        XCTAssertEqual(SeatbeltSandbox.sandboxPolicy(fullAuto: true), .newWorkspaceWritePolicy())
    }

    func testDenialParserFiltersTrackedPIDsAndDeduplicates() {
        let logs = """
        {"eventMessage":"Sandbox: bash(123) deny(1) file-read-data /private/etc/passwd"}
        {"eventMessage":"Sandbox: bash(123) deny(1) file-read-data /private/etc/passwd"}
        {"eventMessage":"Sandbox: sh(456) deny(1) file-write-create /tmp/nope"}
        {"eventMessage":"Sandbox: ignored(789) deny(1) network-outbound *"}
        {"eventMessage":"not a sandbox denial"}
        not-json
        """

        let denials = SeatbeltDenialLogParser.parseDenials(from: logs, trackedPIDs: [123, 456])

        XCTAssertEqual(denials, [
            SeatbeltSandboxDenial(name: "bash", capability: "file-read-data /private/etc/passwd"),
            SeatbeltSandboxDenial(name: "sh", capability: "file-write-create /tmp/nope")
        ])
    }

    func testDenialSummaryMatchesRustShape() throws {
        let emptySummary = String(
            decoding: SeatbeltDenialLogger.formatSummary(denials: []),
            as: UTF8.self
        )
        XCTAssertEqual(emptySummary, "\n=== Sandbox denials ===\nNone found.\n")

        let denialSummary = String(
            decoding: SeatbeltDenialLogger.formatSummary(denials: [
                SeatbeltSandboxDenial(name: "bash", capability: "file-read-data /private/etc/passwd"),
                SeatbeltSandboxDenial(name: "sh", capability: "file-write-create /tmp/nope")
            ]),
            as: UTF8.self
        )
        XCTAssertEqual(
            denialSummary,
            "\n=== Sandbox denials ===\n(bash) file-read-data /private/etc/passwd\n(sh) file-write-create /tmp/nope\n"
        )
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
