import CodexCore
import XCTest

final class ParsedCommandTests: XCTestCase {
    func testParsedCommandWireShape() throws {
        try XCTAssertJSONObjectEqual(
            ParsedCommand.read(cmd: "cat README.md", name: "README.md", path: "README.md"),
            [
                "type": "read",
                "cmd": "cat README.md",
                "name": "README.md",
                "path": "README.md"
            ]
        )
    }

    func testGitStatusIsUnknown() {
        XCTAssertEqual(CommandParser.parseCommand(["git", "status"]), [
            .unknown(cmd: "git status")
        ])
    }

    func testHandlesGitPipeWc() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "git status | wc -l"]), [
            .unknown(cmd: "git status")
        ])
    }

    func testSupportsSearchingForNavigateToRoute() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", #"rg -n "navigate-to-route" -S"#]), [
            .search(cmd: "rg -n navigate-to-route -S", query: "navigate-to-route", path: nil)
        ])
    }

    func testHandlesComplexRipgrepPipe() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", #"rg -n "BUG|FIXME|TODO|XXX|HACK" -S | head -n 200"#]), [
            .search(cmd: "rg -n 'BUG|FIXME|TODO|XXX|HACK' -S", query: "BUG|FIXME|TODO|XXX|HACK", path: nil)
        ])
    }

    func testSupportsRipgrepFilesWithPathAndPipe() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "rg --files webview/src | sed -n"]), [
            .search(cmd: "rg --files webview/src", query: nil, path: "webview")
        ])
    }

    func testSupportsCatAndCdContext() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "cd foo && cat foo.txt"]), [
            .read(cmd: "cat foo.txt", name: "foo.txt", path: "foo/foo.txt")
        ])
    }

    func testSupportsLsWithPipe() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", #"ls -la | sed -n '1,120p'"#]), [
            .listFiles(cmd: "ls -la", path: nil)
        ])
    }

    func testSupportsHeadAndTailReads() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "head -n 50 Cargo.toml"]), [
            .read(cmd: "head -n 50 Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "tail -n +522 README.md"]), [
            .read(cmd: "tail -n +522 README.md", name: "README.md", path: "README.md")
        ])
    }

    func testSupportsGrepRecursiveCurrentDir() {
        XCTAssertEqual(CommandParser.parseCommand(["grep", "-R", "CODEX_SANDBOX_ENV_VAR", "-n", "."]), [
            .search(
                cmd: "grep -R CODEX_SANDBOX_ENV_VAR -n .",
                query: "CODEX_SANDBOX_ENV_VAR",
                path: "."
            )
        ])
    }

    func testDedupesConsecutiveCommands() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "rg foo && rg foo"]), [
            .search(cmd: "rg foo", query: "foo", path: nil)
        ])
    }
}
