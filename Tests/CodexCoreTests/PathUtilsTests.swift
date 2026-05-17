import CodexCore
import XCTest

final class PathUtilsTests: XCTestCase {
    func testNormalizeForWSLComparisonLowercasesMountedDrivePaths() {
        XCTAssertEqual(
            PathUtils.normalizeForWSLComparisonPath("/mnt/C/Users/Dev/Project", isWSL: true),
            "/mnt/c/users/dev/project"
        )
        XCTAssertEqual(
            PathUtils.normalizeForWSLComparisonPath("/MNT/d/Users/Dev/Project", isWSL: true),
            "/mnt/d/users/dev/project"
        )
    }

    func testNormalizeForWSLComparisonLeavesNonDrivePathsUnchanged() {
        XCTAssertEqual(
            PathUtils.normalizeForWSLComparisonPath("/mnt/cc/Users/Dev", isWSL: true),
            "/mnt/cc/Users/Dev"
        )
        XCTAssertEqual(
            PathUtils.normalizeForWSLComparisonPath("/home/Dev", isWSL: true),
            "/home/Dev"
        )
        XCTAssertEqual(
            PathUtils.normalizeForWSLComparisonPath("/mnt/C/Users/Dev", isWSL: false),
            "/mnt/C/Users/Dev"
        )
    }

    func testWSLCaseInsensitivePathDetectionMatchesRustComponents() {
        XCTAssertTrue(PathUtils.isWSLCaseInsensitivePath("/mnt/c/Users/Dev"))
        XCTAssertTrue(PathUtils.isWSLCaseInsensitivePath("/MNT/Z/Users/Dev"))
        XCTAssertFalse(PathUtils.isWSLCaseInsensitivePath("mnt/c/Users/Dev"))
        XCTAssertFalse(PathUtils.isWSLCaseInsensitivePath("/mnt/cc/Users/Dev"))
        XCTAssertFalse(PathUtils.isWSLCaseInsensitivePath("/mnt/1/Users/Dev"))
        XCTAssertFalse(PathUtils.isWSLCaseInsensitivePath("/home/Dev"))
    }

    func testNormalizeForPathComparisonResolvesSymlinkAndStandardizesPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-utils-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("Real", isDirectory: true)
        let nested = real.appendingPathComponent("Nested", isDirectory: true)
        let link = root.appendingPathComponent("Link", isDirectory: false)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let pathThroughLink = link
            .appendingPathComponent("Nested", isDirectory: true)
            .appendingPathComponent("..", isDirectory: false)
            .path

        XCTAssertEqual(
            try PathUtils.normalizeForPathComparison(pathThroughLink, isWSL: false),
            real.path
        )
    }

    func testNormalizeForPathComparisonThrowsWhenPathIsMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-missing-\(UUID().uuidString)")
            .path

        XCTAssertThrowsError(try PathUtils.normalizeForPathComparison(missing, isWSL: false))
    }

    func testPathsMatchAfterNormalizationMatchesIdenticalExistingPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-match-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertTrue(PathUtils.pathsMatchAfterNormalization(root.path, root.path, isWSL: false))
    }

    func testPathsMatchAfterNormalizationFallsBackToRawEqualityWhenMissing() {
        XCTAssertTrue(PathUtils.pathsMatchAfterNormalization("missing", "missing", isWSL: false))
        XCTAssertFalse(PathUtils.pathsMatchAfterNormalization("missing-a", "missing-b", isWSL: false))
    }

    func testNormalizeForNativeWorkdirSimplifiesWindowsVerbatimPrefix() {
        XCTAssertEqual(
            PathUtils.normalizeForNativeWorkdir(#"\\?\D:\c\x\worktrees\2508\swift-base"#, isWindows: true),
            #"D:\c\x\worktrees\2508\swift-base"#
        )
    }

    func testNormalizeForNativeWorkdirLeavesNonWindowsPathsUnchanged() {
        let path = #"\\?\D:\c\x\worktrees\2508\swift-base"#
        XCTAssertEqual(PathUtils.normalizeForNativeWorkdir(path, isWindows: false), path)
    }

    func testResolveSymlinkWritePathsReturnsNonSymlinkPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-write-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("config.toml", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "model = \"old\"\n".write(to: file, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertEqual(
            PathUtils.resolveSymlinkWritePaths(file.path),
            .init(readPath: file.standardizedFileURL.path, writePath: file.standardizedFileURL.path)
        )
    }

    func testResolveSymlinkWritePathsFollowsRelativeSymlinkChain() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-symlink-chain-\(UUID().uuidString)", isDirectory: true)
        let actualDirectory = root.appendingPathComponent("actual", isDirectory: true)
        let target = actualDirectory.appendingPathComponent("config.toml", isDirectory: false)
        let middle = root.appendingPathComponent("middle.toml", isDirectory: false)
        let link = root.appendingPathComponent("config.toml", isDirectory: false)
        try FileManager.default.createDirectory(at: actualDirectory, withIntermediateDirectories: true)
        try "model = \"old\"\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: middle.path, withDestinationPath: "actual/config.toml")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "middle.toml")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertEqual(
            PathUtils.resolveSymlinkWritePaths(link.path),
            .init(readPath: target.standardizedFileURL.path, writePath: target.standardizedFileURL.path)
        )
    }

    func testResolveSymlinkWritePathsMissingTargetUsesFinalPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-missing-link-\(UUID().uuidString)", isDirectory: true)
        let link = root.appendingPathComponent("config.toml", isDirectory: false)
        let target = root.appendingPathComponent("missing.toml", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing.toml")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertEqual(
            PathUtils.resolveSymlinkWritePaths(link.path),
            .init(readPath: target.standardizedFileURL.path, writePath: target.standardizedFileURL.path)
        )
    }

    func testResolveSymlinkWritePathsCyclesFallBackToRootWritePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-cycle-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("a", isDirectory: false)
        let second = root.appendingPathComponent("b", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: second)
        try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertEqual(
            PathUtils.resolveSymlinkWritePaths(first.path),
            .init(readPath: nil, writePath: first.standardizedFileURL.path)
        )
    }

    func testWriteAtomicallyCreatesParentDirectoriesAndReplacesContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-atomic-\(UUID().uuidString)", isDirectory: true)
        let file = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try PathUtils.writeAtomically("first", to: file.path)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "first")

        try PathUtils.writeAtomically("second", to: file.path)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "second")
    }
}
