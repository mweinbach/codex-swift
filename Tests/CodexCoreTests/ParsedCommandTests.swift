import CodexCore
import XCTest

final class ParsedCommandTests: XCTestCase {
    func testParsedCommandWireShapeMatchesRustSerdeTags() throws {
        try XCTAssertJSONObjectEqual(
            ParsedCommand.read(cmd: "cat README.md", name: "README.md", path: "README.md"),
            [
                "type": "read",
                "cmd": "cat README.md",
                "name": "README.md",
                "path": "README.md"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ParsedCommand.listFiles(cmd: "ls -la", path: nil),
            [
                "type": "list_files",
                "cmd": "ls -la"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ParsedCommand.search(cmd: "rg -n TODO src", query: "TODO", path: "src"),
            [
                "type": "search",
                "cmd": "rg -n TODO src",
                "query": "TODO",
                "path": "src"
            ]
        )
    }

    func testGitStatusIsUnknown() {
        XCTAssertEqual(parseCommand(["git", "status"]), [
            .unknown(cmd: "git status")
        ])
    }

    func testGitPipeWcKeepsPrimaryCommandUnknown() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "git status | wc -l"]), [
            .unknown(cmd: "git status")
        ])
    }

    func testBashRedirectFallsBackToUnknownScript() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "echo foo > bar"]), [
            .unknown(cmd: "echo foo > bar")
        ])
    }

    func testSupportsCat() {
        XCTAssertEqual(parseCommand(["cat", "webview/README.md"]), [
            .read(cmd: "cat webview/README.md", name: "README.md", path: "webview/README.md")
        ])
    }

    func testBashLcSupportsCat() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cat README.md"]), [
            .read(cmd: "cat README.md", name: "README.md", path: "README.md")
        ])

        XCTAssertEqual(parseCommand(["zsh", "-lc", "cat README.md"]), [
            .read(cmd: "cat README.md", name: "README.md", path: "README.md")
        ])
    }

    func testCdThenCatIsSingleRead() {
        XCTAssertEqual(parseCommand(["cd", "foo", "&&", "cat", "foo.txt"]), [
            .read(cmd: "cat foo.txt", name: "foo.txt", path: "foo/foo.txt")
        ])
    }

    func testBashCdThenUnknownDropsLeadingCdLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd foo && bar"]), [
            .unknown(cmd: "bar")
        ])
    }

    func testSupportsLsWithPipe() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "ls -la | sed -n '1,120p'"]), [
            .listFiles(cmd: "ls -la", path: nil)
        ])
    }

    func testSupportsSearchingForNavigateToRoute() {
        XCTAssertEqual(parseCommand(["bash", "-lc", #"rg -n "navigate-to-route" -S"#]), [
            .search(cmd: "rg -n navigate-to-route -S", query: "navigate-to-route", path: nil)
        ])
    }

    func testSupportsRgFilesWithPathAndPipe() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files webview/src | sed -n"]), [
            .search(cmd: "rg --files webview/src", query: nil, path: "webview")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | head -n 50"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])
    }

    func testHandlesComplexSearchPipelineLikeRust() {
        let inner = "rg -n \"BUG|FIXME|TODO|XXX|HACK\" -S | head -n 200"
        XCTAssertEqual(parseCommand(["bash", "-lc", inner]), [
            .search(cmd: "rg -n 'BUG|FIXME|TODO|XXX|HACK' -S", query: "BUG|FIXME|TODO|XXX|HACK", path: nil)
        ])
    }

    func testHandlesComplexBashCommandHead() {
        let inner = "rg --version && node -v && pnpm -v && rg --files | wc -l && rg --files | head -n 40"
        XCTAssertEqual(parseCommand(["bash", "-lc", inner]), [
            .search(cmd: "rg --version", query: nil, path: nil),
            .unknown(cmd: "node -v"),
            .unknown(cmd: "pnpm -v"),
            .search(cmd: "rg --files", query: nil, path: nil)
        ])
    }

    func testSupportsGrepRecursiveCurrentDir() {
        XCTAssertEqual(parseCommand(["grep", "-R", "CODEX_SANDBOX_ENV_VAR", "-n", "."]), [
            .search(
                cmd: "grep -R CODEX_SANDBOX_ENV_VAR -n .",
                query: "CODEX_SANDBOX_ENV_VAR",
                path: "."
            )
        ])
    }

    func testSupportsGrepRecursiveSpecificFileAndPathishQuery() {
        XCTAssertEqual(parseCommand(["grep", "-R", "CODEX_SANDBOX_ENV_VAR", "-n", "core/src/spawn.rs"]), [
            .search(
                cmd: "grep -R CODEX_SANDBOX_ENV_VAR -n core/src/spawn.rs",
                query: "CODEX_SANDBOX_ENV_VAR",
                path: "spawn.rs"
            )
        ])

        XCTAssertEqual(parseCommand(["grep", "-R", "src/main.rs", "-n", "."]), [
            .search(
                cmd: "grep -R src/main.rs -n .",
                query: "src/main.rs",
                path: "."
            )
        ])

        XCTAssertEqual(parseCommand(["grep", "-R", "COD`EX_SANDBOX", "-n"]), [
            .search(
                cmd: "grep -R 'COD`EX_SANDBOX' -n",
                query: "COD`EX_SANDBOX",
                path: nil
            )
        ])
    }

    func testSupportsReadHelpers() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "head -n50 Cargo.toml"]), [
            .read(cmd: "head -n50 Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "head -n 50 Cargo.toml"]), [
            .read(cmd: "head -n 50 Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "head Cargo.toml"]), [
            .read(cmd: "head Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "tail -n+10 README.md"]), [
            .read(cmd: "tail -n+10 README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "tail -n 30 README.md"]), [
            .read(cmd: "tail -n 30 README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "tail README.md"]), [
            .read(cmd: "tail README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "cat tui/Cargo.toml | sed -n '1,200p'"]), [
            .read(
                cmd: "cat tui/Cargo.toml | sed -n '1,200p'",
                name: "Cargo.toml",
                path: "tui/Cargo.toml"
            )
        ])
        XCTAssertEqual(parseCommand(["sed", "-n", "12,20p", "Cargo.toml"]), [
            .read(cmd: "sed -n '12,20p' Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(parseCommand(["cat", "--", "./-strange-file-name"]), [
            .read(cmd: "cat -- ./-strange-file-name", name: "-strange-file-name", path: "./-strange-file-name")
        ])
        XCTAssertEqual(parseCommand(["/bin/bash", "-lc", "sed -n '1,10p' Cargo.toml"]), [
            .read(cmd: "sed -n '1,10p' Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
    }

    func testSearchVariants() {
        XCTAssertEqual(parseCommand(["fd", "-t", "f", "src/"]), [
            .search(cmd: "fd -t f src/", query: nil, path: "src")
        ])
        XCTAssertEqual(parseCommand(["fd", "main", "src"]), [
            .search(cmd: "fd main src", query: "main", path: "src")
        ])
        XCTAssertEqual(parseCommand(["find", ".", "-name", "*.rs"]), [
            .search(cmd: "find . -name '*.rs'", query: "*.rs", path: ".")
        ])
        XCTAssertEqual(parseCommand(["find", "src", "-type", "f"]), [
            .search(cmd: "find src -type f", query: nil, path: "src")
        ])
    }

    func testStripsTrueInsideBashLc() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files || true"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])

        XCTAssertEqual(parseCommand(["true", "&&", "rg", "--files"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])

        XCTAssertEqual(parseCommand(["rg", "--files", "&&", "true"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])
    }

    func testSupportsCdAndRgFiles() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && rg --files"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])
    }

    func testShellCdRebasesSearchAndListPathsLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && rg -n TODO core/src"]), [
            .search(cmd: "rg -n TODO core/src", query: "TODO", path: "codex-rs/core")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && ls core/src"]), [
            .listFiles(cmd: "ls core/src", path: "codex-rs/core")
        ])
    }

    func testSupportsSingleStringScriptWithCdAndPipe() {
        let inner = #"cd /Users/pakrym/code/codex && rg -n "codex_api" codex-rs -S | head -n 50"#
        XCTAssertEqual(parseCommand(["bash", "-lc", inner]), [
            .search(cmd: "rg -n codex_api codex-rs -S", query: "codex_api", path: "codex-rs")
        ])
    }

    func testDropsFormattingCommandsInPipelines() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "yes | rg --files"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])

        let printfThenCat = #"printf "\n===== ansi-escape/Cargo.toml =====\n"; cat -- ansi-escape/Cargo.toml"#
        XCTAssertEqual(parseCommand(["bash", "-lc", printfThenCat]), [
            .read(cmd: "cat -- ansi-escape/Cargo.toml", name: "Cargo.toml", path: "ansi-escape/Cargo.toml")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | nl -ba"]), [
            .search(cmd: "rg --files", query: nil, path: nil)
        ])

        let inner = "nl -ba core/src/parse_command.rs | sed -n '1200,1720p'"
        XCTAssertEqual(parseCommand(["bash", "-lc", inner]), [
            .read(
                cmd: inner,
                name: "parse_command.rs",
                path: "core/src/parse_command.rs"
            )
        ])
    }

    func testSplitsSemicolonAndOrConnectorsLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "rg foo ; echo done"]), [
            .search(cmd: "rg foo", query: "foo", path: nil),
            .unknown(cmd: "echo done")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg foo || echo done"]), [
            .search(cmd: "rg foo", query: "foo", path: nil),
            .unknown(cmd: "echo done")
        ])

        let mixed = #"pwd; ls -la; rg --files -g '!target' | wc -l; rg -n '^\[workspace\]' -n Cargo.toml || true; cargo --version"#
        XCTAssertEqual(parseCommand(["bash", "-lc", mixed]), [
            .unknown(cmd: "pwd"),
            .listFiles(cmd: "ls -la", path: nil),
            .search(cmd: "rg --files -g '!target'", query: nil, path: "!target"),
            .search(cmd: ##"rg -n "^\\[workspace\\]" -n Cargo.toml"##, query: #"^\[workspace\]"#, path: "Cargo.toml"),
            .unknown(cmd: "cargo --version")
        ])
    }

    func testPathAndFlagEdgeCasesFromRustParser() {
        XCTAssertEqual(parseCommand(["cat", #"pkg\src\main.rs"#]), [
            .read(cmd: ##"cat "pkg\\src\\main.rs""##, name: "main.rs", path: #"pkg\src\main.rs"#)
        ])

        XCTAssertEqual(parseCommand(["ls", "--time-style=long-iso", "./dist"]), [
            .listFiles(cmd: "ls '--time-style=long-iso' ./dist", path: ".")
        ])

        XCTAssertEqual(parseCommand(["yes", "|", "rg", "-n", "foo bar", "-S"]), [
            .search(cmd: "rg -n 'foo bar' -S", query: "foo bar", path: nil)
        ])

        XCTAssertEqual(parseCommand(["rg", "--colors=never", "-n", "foo", "src"]), [
            .search(cmd: "rg '--colors=never' -n foo src", query: "foo", path: "src")
        ])
    }

    func testDedupesConsecutiveCommandsAndKeepsCommandParserCompatibility() {
        XCTAssertEqual(CommandParser.parseCommand(["bash", "-lc", "rg foo && rg foo"]), [
            .search(cmd: "rg foo", query: "foo", path: nil)
        ])
        XCTAssertEqual(CommandParser.shlexJoin(["rg", "foo bar"]), "rg 'foo bar'")
    }

    func testPowerShellCommandIsStripped() {
        XCTAssertEqual(parseCommand(["powershell", "-Command", "Get-ChildItem"]), [
            .unknown(cmd: "Get-ChildItem")
        ])

        XCTAssertEqual(parseCommand(["pwsh", "-NoProfile", "-c", "Write-Host hi"]), [
            .unknown(cmd: "Write-Host hi")
        ])

        XCTAssertEqual(parseCommand(["/usr/local/bin/powershell.exe", "-NoProfile", "-c", "Write-Host hi"]), [
            .unknown(cmd: "Write-Host hi")
        ])
    }
}
