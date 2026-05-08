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
}
