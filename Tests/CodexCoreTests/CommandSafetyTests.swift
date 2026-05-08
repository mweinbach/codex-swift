import CodexCore
import XCTest

final class CommandSafetyTests: XCTestCase {
    func testKnownSafeExamples() {
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["ls"]))
        XCTAssertTrue(CommandSafety.isSafeToCallWithExec(["git", "status"]))
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

    func testDangerousCommands() {
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["git", "reset"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["bash", "-lc", "git reset --hard"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["zsh", "-lc", "git reset --hard"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["git", "status"]))
        XCTAssertFalse(CommandSafety.commandMightBeDangerous(["bash", "-lc", "git status"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["sudo", "git", "reset", "--hard"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["/usr/bin/git", "reset", "--hard"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["rm", "-rf", "/"]))
        XCTAssertTrue(CommandSafety.commandMightBeDangerous(["rm", "-f", "/"]))
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
}
