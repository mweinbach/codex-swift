import CodexCore
import XCTest

final class BashPlainCommandParserTests: XCTestCase {
    func testAcceptsSingleSimpleCommand() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("ls -1"),
            [["ls", "-1"]]
        )
    }

    func testAcceptsMultipleCommandsWithAllowedOperators() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("ls && pwd; echo 'hi there' | wc -l"),
            [["ls"], ["pwd"], ["echo", "hi there"], ["wc", "-l"]]
        )
    }

    func testAcceptsNewlineSeparatedCommands() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("pwd\ncat README.md\nrg --files"),
            [["pwd"], ["cat", "README.md"], ["rg", "--files"]]
        )
    }

    func testAcceptsLineContinuationsLikeRustTreeSitterParser() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("cat \\\nREADME.md"),
            [["cat", "README.md"]]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("rg foo\\\nbar src"),
            [["rg", "foobar", "src"]]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("pwd && \\\nls -1"),
            [["pwd"], ["ls", "-1"]]
        )
    }

    func testExtractsDoubleAndSingleQuotedStrings() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo "hello world""#),
            [["echo", "hello world"]]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("echo 'hi there'"),
            [["echo", "hi there"]]
        )
    }

    func testAcceptsDoubleQuotedStringsWithNewlinesLikeRust() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("git commit -m \"line1\nline2\""),
            [["git", "commit", "-m", "line1\nline2"]]
        )
    }

    func testAcceptsMixedQuoteConcatenationLikeRust() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo "/usr"'/'"local"/bin"#),
            [["echo", "/usr/local/bin"]]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo '/usr'"/"'local'/bin"#),
            [["echo", "/usr/local/bin"]]
        )
    }

    func testAcceptsEscapedSpecialsInDoubleQuotedStringsLikeRust() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo "\$HOME" "\`literal\`""#),
            [["echo", #"\$HOME"#, #"\`literal\`"#]]
        )
    }

    func testAcceptsEscapedSpecialsInPlainWordsLikeRust() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg \$HOME foo\ bar"#),
            [["rg", #"\$HOME"#, #"foo\ bar"#]]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo \`literal\`"#),
            [["echo", #"\`literal\`"#]]
        )
    }

    func testAcceptsNumbersAsWords() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("echo 123 456"),
            [["echo", "123", "456"]]
        )
    }

    func testRejectsParenthesesAndSubshells() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("(ls)"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls || (pwd && echo hi)"))
    }

    func testRejectsRedirectionsAndUnsupportedOperators() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls > out.txt"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("echo hi & echo bye"))
    }

    func testRejectsCommandAndProcessSubstitutionsAndExpansions() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("echo $(pwd)"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("echo `pwd`"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("echo $HOME"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence(#"echo "hi $USER""#))
    }

    func testRejectsBashCommentsLikeRustTreeSitterParser() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("# comment"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("echo hi # comment"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls && # comment\npwd"))
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("echo foo#bar \\#literal"),
            [["echo", "foo#bar", "\\#literal"]]
        )
    }

    func testRejectsVariableAssignmentPrefix() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("FOO=bar ls"))
    }

    func testRejectsTrailingOperatorParseError() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls &&"))
    }

    func testRejectsEmptyCommandPositionsLikeRust() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("&& ls"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls ;; pwd"))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence("ls | | wc"))
    }

    func testParseZshLcPlainCommands() {
        XCTAssertEqual(
            BashPlainCommandParser.parseShellLcPlainCommands(["zsh", "-lc", "ls"]),
            [["ls"]]
        )
    }

    func testAcceptsConcatenatedFlagAndValue() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg -n "foo" -g"*.py""#),
            [["rg", "-n", "foo", "-g*.py"]]
        )
    }

    func testAcceptsConcatenatedFlagWithSingleQuotes() {
        XCTAssertEqual(
            BashPlainCommandParser.parseWordOnlyCommandsSequence("grep -n 'pattern' -g'*.txt'"),
            [["grep", "-n", "pattern", "-g*.txt"]]
        )
    }

    func testRejectsConcatenationWithVariableSubstitution() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg -g"$VAR" pattern"#))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg -g"${VAR}" pattern"#))
    }

    func testRejectsConcatenationWithCommandSubstitution() {
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg -g"$(pwd)" pattern"#))
        XCTAssertNil(BashPlainCommandParser.parseWordOnlyCommandsSequence(#"rg -g"$(echo '*.py')" pattern"#))
    }

    func testSingleCommandPrefixSupportsSimpleHeredoc() {
        XCTAssertEqual(
            BashPlainCommandParser.parseShellLcSingleCommandPrefix([
                "zsh",
                "-lc",
                "python3 <<'PY'\nprint('hello')\nPY",
            ]),
            ["python3"]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseShellLcSingleCommandPrefix([
                "zsh",
                "-lc",
                "python3 << PY\nprint('hello')\nPY",
            ]),
            ["python3"]
        )
        XCTAssertEqual(
            BashPlainCommandParser.parseShellLcSingleCommandPrefix([
                "bash",
                "-lc",
                "python3 <<-PY\n\tprint('hello')\n\tPY",
            ]),
            ["python3"]
        )
    }

    func testSingleCommandPrefixRejectsUnsafeHeredocShapes() {
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "python3 <<'PY'\nprint('hello')\nPY\necho done",
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "python3 <<'PY' > /tmp/out.txt\nprint('hello')\nPY",
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "PATH=/tmp/evil:$PATH cat <<'EOF'\nhello\nEOF",
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            #"python3 <<< "$(rm -rf /)""#,
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "python3 'quoted-arg' <<'PY'\nprint('hello')\nPY",
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            #"python3 escaped\ arg <<'PY'\nprint('hello')\nPY"#,
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "echo $((1<<2))",
        ]))
        XCTAssertNil(BashPlainCommandParser.parseShellLcSingleCommandPrefix([
            "bash",
            "-lc",
            "python3 $((1<<2)) <<'PY'\nprint('hello')\nPY",
        ]))
    }
}
