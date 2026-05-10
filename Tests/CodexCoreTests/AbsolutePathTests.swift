import CodexCore
import XCTest

final class AbsolutePathTests: XCTestCase {
    func testCreateWithAbsolutePathIgnoresBasePath() throws {
        let path = try AbsolutePath.resolve("/tmp/example/../file.txt", against: "/base")
        XCTAssertEqual(path.path, "/tmp/file.txt")
    }

    func testRelativePathIsResolvedAgainstBasePath() throws {
        let path = try AbsolutePath.resolve("subdir/file.txt", against: "/tmp/base")
        XCTAssertEqual(path.path, "/tmp/base/subdir/file.txt")
    }

    func testAbsolutePathExpandsHomeDirectoryLikeRust() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(try AbsolutePath(absolutePath: "~/code").path, home + "/code")
    }

    func testJoinAndParent() throws {
        let base = try AbsolutePath(absolutePath: "/tmp/base")
        XCTAssertEqual(try base.join("child/../file.txt").path, "/tmp/base/file.txt")
        XCTAssertEqual(base.parent?.path, "/tmp")
    }

    func testDecodeRelativePathWithBase() throws {
        let decoder = JSONDecoder()
        decoder.userInfo[AbsolutePath.decodingBaseUserInfoKey] = "/tmp/base"
        let path = try decoder.decode(AbsolutePath.self, from: Data(#""subdir/file.txt""#.utf8))
        XCTAssertEqual(path.path, "/tmp/base/subdir/file.txt")
    }
}
