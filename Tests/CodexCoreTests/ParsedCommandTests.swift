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

    func testGitPipeWcCollapsesToWholeUnknownLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "git status | wc -l"]), [
            .unknown(cmd: "git status | wc -l")
        ])
    }

    func testNpmRunBuildIsUnknownLikeRust() {
        XCTAssertEqual(parseCommand(["npm", "run", "build"]), [
            .unknown(cmd: "npm run build")
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

    func testEmptyCdBaseDoesNotCreateAbsoluteReadPathLikeRust() {
        XCTAssertEqual(parseCommand(["cd", "", "&&", "cat", "foo.txt"]), [
            .read(cmd: "cat foo.txt", name: "foo.txt", path: "foo.txt")
        ])

        XCTAssertEqual(parseCommand(["cd", "", "&&", "cd", "bar", "&&", "cat", "foo.txt"]), [
            .read(cmd: "cat foo.txt", name: "foo.txt", path: "bar/foo.txt")
        ])
    }

    func testBashCdThenUnknownCollapsesToWholeUnknownLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd foo && bar"]), [
            .unknown(cmd: "cd foo && bar")
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
            .listFiles(cmd: "rg --files webview/src", path: "webview")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | head -n 50"]), [
            .listFiles(cmd: "rg --files", path: nil)
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
            .unknown(cmd: inner)
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
        XCTAssertEqual(parseCommand([#"C:\Program Files\Git\bin\bash.exe"#, "-lc", "cat README.md"]), [
            .read(cmd: "cat README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "bat --theme TwoDark README.md"]), [
            .read(cmd: "bat --theme TwoDark README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "batcat README.md"]), [
            .read(cmd: "batcat README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "less -p TODO README.md"]), [
            .read(cmd: "less -p TODO README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "more README.md"]), [
            .read(cmd: "more README.md", name: "README.md", path: "README.md")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", "bat README.md CHANGELOG.md"]), [
            .unknown(cmd: "bat README.md CHANGELOG.md")
        ])
    }

    func testSearchVariants() {
        XCTAssertEqual(parseCommand(["fd", "-t", "f", "src/"]), [
            .listFiles(cmd: "fd -t f src/", path: "src")
        ])
        XCTAssertEqual(parseCommand(["fd", "main", "src"]), [
            .search(cmd: "fd main src", query: "main", path: "src")
        ])
        XCTAssertEqual(parseCommand(["find", ".", "-name", "*.rs"]), [
            .search(cmd: "find . -name '*.rs'", query: "*.rs", path: ".")
        ])
        XCTAssertEqual(parseCommand(["find", "src", "-type", "f"]), [
            .listFiles(cmd: "find src -type f", path: "src")
        ])
    }

    func testAdditionalRustParserCommandVariants() {
        XCTAssertEqual(parseCommand(["git", "grep", "-l", "TODO", "src"]), [
            .search(cmd: "git grep -l TODO src", query: "TODO", path: "src")
        ])
        XCTAssertEqual(parseCommand(["git", "ls-files", "--exclude", "target", "src"]), [
            .listFiles(cmd: "git ls-files --exclude target src", path: "src")
        ])
        XCTAssertEqual(parseCommand(["eza", "--color=always", "src"]), [
            .listFiles(cmd: "eza '--color=always' src", path: "src")
        ])
        XCTAssertEqual(parseCommand(["tree", "-L", "2", "src"]), [
            .listFiles(cmd: "tree -L 2 src", path: "src")
        ])
        XCTAssertEqual(parseCommand(["du", "-d", "2", "."]), [
            .listFiles(cmd: "du -d 2 .", path: ".")
        ])
        XCTAssertEqual(parseCommand(["ag", "-l", "TODO", "src"]), [
            .search(cmd: "ag -l TODO src", query: "TODO", path: "src")
        ])
        XCTAssertEqual(parseCommand(["rga", "--files", "docs"]), [
            .listFiles(cmd: "rga --files docs", path: "docs")
        ])
    }

    func testAwkPythonAndMutatingXargsParity() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "awk '{print $1}' Cargo.toml"]), [
            .read(cmd: "awk '{print $1}' Cargo.toml", name: "Cargo.toml", path: "Cargo.toml")
        ])
        XCTAssertEqual(parseCommand(["bash", "-lc", #"python3 -c "import glob; print(glob.glob('*.rs'))""#]), [
            .listFiles(cmd: #"python3 -c 'import glob; print(glob.glob('\''*.rs'\''))'"#, path: nil)
        ])

        let mutatingPipeline = #"rg -l QkBindingController presentation/src/main/java | xargs perl -pi -e 's/QkBindingController/QkController/g'"#
        XCTAssertEqual(parseCommand(["bash", "-lc", mutatingPipeline]), [
            .unknown(cmd: mutatingPipeline)
        ])
    }

    func testStripsTrueInsideBashLc() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files || true"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])

        XCTAssertEqual(parseCommand(["true", "&&", "rg", "--files"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])

        XCTAssertEqual(parseCommand(["rg", "--files", "&&", "true"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])
    }

    func testSupportsCdAndRgFiles() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && rg --files"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])
    }

    func testShellCdDoesNotRebaseSearchAndListPathsLikeRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && rg -n TODO core/src"]), [
            .search(cmd: "rg -n TODO core/src", query: "TODO", path: "core")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "cd codex-rs && ls core/src"]), [
            .listFiles(cmd: "ls core/src", path: "core")
        ])
    }

    func testCdOptionsAndAbsoluteTargetsMatchRust() {
        XCTAssertEqual(parseCommand(["bash", "-lc", "cd -P Sources && cat CodexCore/ParsedCommand.swift"]), [
            .read(
                cmd: "cat CodexCore/ParsedCommand.swift",
                name: "ParsedCommand.swift",
                path: "Sources/CodexCore/ParsedCommand.swift"
            )
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "cd -- Sources && cat CodexCore/ParsedCommand.swift"]), [
            .read(
                cmd: "cat CodexCore/ParsedCommand.swift",
                name: "ParsedCommand.swift",
                path: "Sources/CodexCore/ParsedCommand.swift"
            )
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "cd /tmp/project && cat src/lib.rs"]), [
            .read(cmd: "cat src/lib.rs", name: "lib.rs", path: "/tmp/project/src/lib.rs")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "cd /tmp/project && rg -n TODO src"]), [
            .search(cmd: "rg -n TODO src", query: "TODO", path: "src")
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
            .listFiles(cmd: "rg --files", path: nil)
        ])

        let printfThenCat = #"printf "\n===== ansi-escape/Cargo.toml =====\n"; cat -- ansi-escape/Cargo.toml"#
        XCTAssertEqual(parseCommand(["bash", "-lc", printfThenCat]), [
            .read(cmd: "cat -- ansi-escape/Cargo.toml", name: "Cargo.toml", path: "ansi-escape/Cargo.toml")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | nl -ba"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | tail -c 100"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg --files | tail -c +10"]), [
            .listFiles(cmd: "rg --files", path: nil)
        ])

        XCTAssertEqual(parseCommand(["sed", "-n", "260,640p", "exec/src/event_processor_with_human_output.rs", "|", "nl", "-ba"]), [
            .read(
                cmd: "sed -n '260,640p' exec/src/event_processor_with_human_output.rs",
                name: "event_processor_with_human_output.rs",
                path: "exec/src/event_processor_with_human_output.rs"
            )
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "sed -n -e 10p file.txt | nl -ba"]), [
            .read(cmd: "sed -n -e 10p file.txt | nl -ba", name: "file.txt", path: "file.txt")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "sed -n 10p -- file.txt | nl -ba"]), [
            .read(cmd: "sed -n 10p -- file.txt | nl -ba", name: "file.txt", path: "file.txt")
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
            .unknown(cmd: "rg foo ; echo done")
        ])

        XCTAssertEqual(parseCommand(["bash", "-lc", "rg foo || echo done"]), [
            .unknown(cmd: "rg foo || echo done")
        ])

        let mixed = #"pwd; ls -la; rg --files -g '!target' | wc -l; rg -n '^\[workspace\]' -n Cargo.toml || true; cargo --version"#
        XCTAssertEqual(parseCommand(["bash", "-lc", mixed]), [
            .unknown(cmd: mixed)
        ])

        let fullMixed = #"pwd; ls -la; rg --files -g '!target' | wc -l; rg -n '^\[workspace\]' -n Cargo.toml || true; rg -n '^\[package\]' -n */Cargo.toml || true; cargo --version; rustc --version; cargo clippy --workspace --all-targets --all-features -q"#
        XCTAssertEqual(parseCommand(["bash", "-lc", fullMixed]), [
            .unknown(cmd: fullMixed)
        ])
    }

    func testPathAndFlagEdgeCasesFromRustParser() {
        XCTAssertEqual(parseCommand(["cat", #"pkg\src\main.rs"#]), [
            .read(cmd: ##"cat "pkg\\src\\main.rs""##, name: "main.rs", path: #"pkg\src\main.rs"#)
        ])

        XCTAssertEqual(parseCommand(["bat", "--", "-strange-file-name"]), [
            .read(cmd: "bat -- -strange-file-name", name: "-strange-file-name", path: "-strange-file-name")
        ])

        XCTAssertEqual(parseCommand(["more", "--", "-strange-file-name"]), [
            .read(cmd: "more -- -strange-file-name", name: "-strange-file-name", path: "-strange-file-name")
        ])

        XCTAssertEqual(parseCommand(["ls", "--", "-strange-dir"]), [
            .listFiles(cmd: "ls -- -strange-dir", path: "-strange-dir")
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
