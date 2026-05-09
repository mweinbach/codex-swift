import CodexCore
import XCTest

final class CommandSafetyTests: XCTestCase {
    func testKnownSafeExamples() {
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["ls"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["git", "status"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["git", "branch"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["git", "branch", "--show-current"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["base64"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["sed", "-n", "1,5p", "file.txt"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["nl", "-nrz", "Cargo.toml"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["find", ".", "-name", "file.txt"]))

        #if os(Linux)
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["numfmt", "1000"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["tac", "Cargo.toml"]))
        #else
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["numfmt", "1000"]))
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["tac", "Cargo.toml"]))
        #endif
    }

    func testZshLcSafeCommandSequence() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["zsh", "-lc", "ls"]))
    }

    func testUnknownOrPartialCommandsAreUnsafe() {
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["foo"]))
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["git", "fetch"]))
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["git", "checkout", "status"]))
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["cargo", "check"]))
        XCTAssertFalse(CommandSafety.isSafeToCallWithExec(["sed", "-n", "xp", "file.txt"]))

        for args in [
            ["find", ".", "-name", "file.txt", "-exec", "rm", "{}", ";"],
            ["find", ".", "-name", "*.py", "-execdir", "python3", "{}", ";"],
            ["find", ".", "-name", "file.txt", "-ok", "rm", "{}", ";"],
            ["find", ".", "-name", "*.py", "-okdir", "python3", "{}", ";"],
            ["find", ".", "-delete", "-name", "file.txt"],
            ["find", ".", "-fls", "/etc/passwd"],
            ["find", ".", "-fprint", "/etc/passwd"],
            ["find", ".", "-fprint0", "/etc/passwd"],
            ["find", ".", "-fprintf", "/root/suid.txt", "%#m %u %p\n"]
        ] {
            XCTAssertFalse(CommandSafety.isSafeToCallWithExec(args), "expected \(args) to be unsafe")
        }
    }

    func testGitSafetyMatchesRustGlobalAndOutputRules() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["git", "log", "-p", "-1"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["git", "diff", "-p"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["git", "show", "-p", "HEAD"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "git log -p -1"]))

        for args in [
            ["git", "branch", "-d", "feature"],
            ["git", "branch", "new-branch"],
            ["git", "log", "--output=/tmp/git-log-out-test", "-n", "1"],
            ["git", "diff", "--output", "/tmp/git-diff-out-test"],
            ["git", "show", "--output=/tmp/git-show-out-test", "HEAD"],
            ["git", "--paginate", "log", "-1"],
            ["git", "-p", "log", "-1"],
            ["git", "-C", ".", "status"],
            ["git", "-C.", "status"],
            ["git", "-c", "core.pager=cat", "log", "-n", "1"],
            ["git", "-ccore.pager=cat", "status"],
            ["git", "--config-env", "core.pager=PAGER", "show", "HEAD"],
            ["git", "--config-env=core.pager=PAGER", "show", "HEAD"],
            ["git", "--git-dir", ".evil-git", "diff", "HEAD~1..HEAD"],
            ["git", "--git-dir=.evil-git", "diff", "HEAD~1..HEAD"],
            ["git", "--work-tree", ".", "status"],
            ["git", "--work-tree=.", "status"],
            ["git", "--exec-path", ".git/helpers", "show", "HEAD"],
            ["git", "--exec-path=.git/helpers", "show", "HEAD"],
            ["git", "--namespace", "attacker", "show", "HEAD"],
            ["git", "--namespace=attacker", "show", "HEAD"],
            ["git", "--super-prefix", "attacker/", "show", "HEAD"],
            ["git", "--super-prefix=attacker/", "show", "HEAD"],
            ["bash", "-lc", "git --git-dir=.evil-git diff HEAD~1..HEAD"]
        ] {
            XCTAssertFalse(CommandSafety.isKnownSafeCommand(args), "expected \(args) to be unsafe")
        }
    }

    func testBase64OutputOptionsAreUnsafe() {
        for args in [
            ["base64", "-o", "out.bin"],
            ["base64", "--output", "out.bin"],
            ["base64", "--output=out.bin"],
            ["base64", "-ob64.txt"]
        ] {
            XCTAssertFalse(CommandSafety.isSafeToCallWithExec(args), "expected \(args) to be unsafe")
        }
    }

    func testRipgrepRules() {
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["rg", "Cargo.toml", "-n"]))

        for args in [
            ["rg", "--search-zip", "files"],
            ["rg", "-z", "files"],
            ["rg", "--pre", "pwned", "files"],
            ["rg", "--pre=pwned", "files"],
            ["rg", "--hostname-bin", "pwned", "files"],
            ["rg", "--hostname-bin=pwned", "files"]
        ] {
            XCTAssertFalse(CommandSafety.isSafeToCallWithExec(args), "expected \(args) to be unsafe")
        }
    }

    func testBashLcSafeExamples() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls -1"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "git status"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", #"grep -R "Cargo.toml" -n"#]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "sed -n 1,5p file.txt"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "sed -n '1,5p' file.txt"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "find . -name file.txt"]))
    }

    func testBashLcSafeExamplesWithOperators() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", #"grep -R "Cargo.toml" -n || true"#]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls && pwd"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "echo 'hi' ; ls"]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls | wc -l"]))
    }

    func testBashLcUnsafeExamples() {
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "git", "status"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "'git status'"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "find . -name file.txt -delete"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls && rm -rf /"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "(ls)"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls || (pwd && echo hi)"]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand(["bash", "-lc", "ls > out.txt"]))
    }

    func testDangerousCommandsMatchRustShellCommandHeuristics() {
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["git", "reset"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["bash", "-lc", "git reset --hard"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["zsh", "-lc", "git reset --hard"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["git", "status"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["bash", "-lc", "git status"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["sudo", "git", "reset", "--hard"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["/usr/bin/git", "reset", "--hard"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["rm", "-rf", "/"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["rm", "-f", "/"]))
    }

    func testWindowsShellExecuteURLLaunchesAreDangerous() {
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-NoLogo",
            "-Command",
            "Start-Process 'https://example.com'"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "Start-Process('https://example.com');"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell.exe",
            "-Command",
            "Invoke-Item https://example.com"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "(New-Object -ComObject Shell.Application).ShellExecute('https://example.com')"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "rundll32 url.dll,FileProtocolHandler https://example.com"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "cmd",
            "/c",
            "start",
            "https://example.com"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "msedge.exe",
            "https://example.com"
        ]))
    }

    func testWindowsPowerShellForceDeleteMatchesRustDangerHeuristic() {
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "Remove-Item test -Force"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "pwsh",
            "-Command",
            "ri test -Force"
        ]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "Write-Host hi;Remove-Item -Force C:\\tmp"
        ]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "Remove-Item test"
        ]))
    }

    func testWindowsLocalLaunchesAreNotFlaggedAsDangerous() {
        XCTAssertFalse(CommandSafety.commandMightBeDangerous([
            "powershell",
            "-Command",
            "Start-Process notepad.exe"
        ]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous([
            "explorer.exe",
            "."
        ]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous([
            "cmd",
            "/c",
            "dir"
        ]))
    }

    func testWindowsPowerShellSafeWrappers() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-NoLogo",
            "-Command",
            "Get-ChildItem -Path ."
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "git status"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "Get-Content",
            "Cargo.toml"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            #"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#,
            "-Command",
            "Get-Content Cargo.toml"
        ]))
    }

    func testWindowsPowerShellSafePipelinesAndGitUsage() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "rg --files-with-matches foo | Measure-Object | Select-Object -ExpandProperty Count"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-Command",
            "Get-Content foo.rs | Select-Object -Skip 200"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-Command",
            "git show HEAD:foo.rs"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-Command",
            "(Get-Content foo.rs -Raw)"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-Command",
            "Get-Item foo.rs | Select-Object Length"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "pwsh.exe",
            "-Command",
            "pwd && ls"
        ]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "pwd && ls"
        ]))
    }

    func testWindowsPowerShellRejectsSideEffectsAndUnsupportedConstructs() {
        for args in [
            ["powershell.exe", "-NoLogo", "-Command", "Remove-Item foo.txt"],
            ["powershell.exe", "-NoProfile", "-Command", "rg --pre cat"],
            ["powershell.exe", "-Command", "rg --hostname-bin=pwned files"],
            ["powershell.exe", "-Command", "Set-Content foo.txt 'hello'"],
            ["powershell.exe", "-Command", "echo hi > out.txt"],
            ["powershell.exe", "-Command", "Get-Content x | Out-File y"],
            ["powershell.exe", "-Command", "Write-Output foo 2> err.txt"],
            ["powershell.exe", "-Command", "& Remove-Item foo"],
            ["powershell.exe", "-Command", "Get-ChildItem; Remove-Item foo"],
            ["powershell.exe", "-Command", "Write-Output (Set-Content foo6.txt 'abc')"],
            ["powershell.exe", "-Command", "Write-Host (Remove-Item foo.txt)"],
            ["powershell.exe", "-Command", "Get-Content (New-Item bar.txt)"],
            ["powershell.exe", "-Command", "ls @(calc.exe)"],
            ["powershell.exe", "-Command", "ls foo@(calc.exe)"],
            ["powershell.exe", "-Command", "Write-Output $(Get-Content foo)"],
            ["powershell.exe", "-Command", "''"],
            ["powershell.exe", "-Command", "git -c core.pager=cat show HEAD:foo.rs"],
            ["powershell.exe", "-Command", "git --git-dir=.evil-git diff HEAD~1..HEAD"],
            ["powershell.exe", "-Command", "git diff --output codex_poc.txt"],
            ["powershell.exe", "-Command", "-git cat-file -p HEAD:foo.rs"],
            ["powershell.exe", "-EncodedCommand", "RwBlAHQALQBMAG8AYwBhAHQAaQBvAG4A"],
            ["powershell.exe", "-UnknownFlag", "Get-Location"],
            ["powershell.exe", "-Command", "Get-Content", "Cargo.toml"]
        ] {
            XCTAssertFalse(CommandSafety.isKnownSafeCommand(args), "expected \(args) to be unsafe")
        }
    }

    func testWindowsPowerShellAllowsConstantExpressionArguments() {
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "Get-Content 'foo bar'"
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "Get-Content \"foo bar\""
        ]))
        XCTAssertTrue(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "Write-Output 'foo $bar'"
        ]))
    }

    func testWindowsPowerShellRejectsDynamicArguments() {
        XCTAssertFalse(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "Get-Content $foo"
        ]))
        XCTAssertFalse(CommandSafety.isKnownSafeCommand([
            "powershell.exe",
            "-Command",
            "Write-Output \"foo $bar\""
        ]))
    }

    func testExternalSandboxOnlyPromptsForDangerousCommands() {
        let externalPolicy = SandboxPolicy.externalSandbox(networkAccess: .restricted)
        XCTAssertFalse(CommandSafety.requiresInitialApproval(
            policy: .onRequest,
            sandboxPolicy: externalPolicy,
            command: ["ls"],
            sandboxPermissions: .useDefault
        ))
        XCTAssertTrue(CommandSafety.requiresInitialApproval(
            policy: .onRequest,
            sandboxPolicy: externalPolicy,
            command: ["rm", "-rf", "/"],
            sandboxPermissions: .useDefault
        ))
    }

    func testRestrictedSandboxPromptsForEscalatedUnknownCommand() {
        XCTAssertTrue(CommandSafety.requiresInitialApproval(
            policy: .onRequest,
            sandboxPolicy: .readOnly,
            command: ["python3", "script.py"],
            sandboxPermissions: .requireEscalated
        ))
        XCTAssertFalse(CommandSafety.requiresInitialApproval(
            policy: .onFailure,
            sandboxPolicy: .readOnly,
            command: ["python3", "script.py"],
            sandboxPermissions: .requireEscalated
        ))
    }

    func testGranularPolicyMirrorsOnRequestForInitialPromptDetection() {
        XCTAssertTrue(CommandSafety.requiresInitialApproval(
            policy: .granular(GranularApprovalConfig(
                sandboxApproval: true,
                rules: true,
                mcpElicitations: true
            )),
            sandboxPolicy: .readOnly,
            command: ["python3", "script.py"],
            sandboxPermissions: .requireEscalated
        ))
    }
}
