import XCTest
@testable import CodexCore

final class ShellTests: XCTestCase {
    func testDetectShellType() {
        XCTAssertEqual(ShellResolver.detectShellType("zsh"), .zsh)
        XCTAssertEqual(ShellResolver.detectShellType("bash"), .bash)
        XCTAssertEqual(ShellResolver.detectShellType("pwsh"), .powerShell)
        XCTAssertEqual(ShellResolver.detectShellType("powershell"), .powerShell)
        XCTAssertEqual(ShellResolver.detectShellType("fish"), nil)
        XCTAssertEqual(ShellResolver.detectShellType("other"), nil)
        XCTAssertEqual(ShellResolver.detectShellType("/bin/zsh"), .zsh)
        XCTAssertEqual(ShellResolver.detectShellType("/bin/bash"), .bash)
        XCTAssertEqual(ShellResolver.detectShellType("powershell.exe"), .powerShell)
        XCTAssertEqual(ShellResolver.detectShellType("/usr/local/bin/pwsh"), .powerShell)
        XCTAssertEqual(ShellResolver.detectShellType("pwsh.exe"), .powerShell)
        XCTAssertEqual(ShellResolver.detectShellType("/bin/sh"), .sh)
        XCTAssertEqual(ShellResolver.detectShellType("sh"), .sh)
        XCTAssertEqual(ShellResolver.detectShellType("cmd"), .cmd)
        XCTAssertEqual(ShellResolver.detectShellType("cmd.exe"), .cmd)
    }

    func testShellNameUsesRustLowercaseNames() {
        XCTAssertEqual(ShellType.zsh.name, "zsh")
        XCTAssertEqual(ShellType.bash.name, "bash")
        XCTAssertEqual(ShellType.powerShell.name, "powershell")
        XCTAssertEqual(ShellType.sh.name, "sh")
        XCTAssertEqual(ShellType.cmd.name, "cmd")
    }

    func testDeriveExecArgs() {
        let bash = Shell(shellType: .bash, shellPath: "/bin/bash")
        XCTAssertEqual(bash.deriveExecArgs(command: "echo hello", useLoginShell: false), [
            "/bin/bash", "-c", "echo hello"
        ])
        XCTAssertEqual(bash.deriveExecArgs(command: "echo hello", useLoginShell: true), [
            "/bin/bash", "-lc", "echo hello"
        ])

        let zsh = Shell(shellType: .zsh, shellPath: "/bin/zsh")
        XCTAssertEqual(zsh.deriveExecArgs(command: "echo hello", useLoginShell: false), [
            "/bin/zsh", "-c", "echo hello"
        ])
        XCTAssertEqual(zsh.deriveExecArgs(command: "echo hello", useLoginShell: true), [
            "/bin/zsh", "-lc", "echo hello"
        ])

        let powershell = Shell(shellType: .powerShell, shellPath: "pwsh.exe")
        XCTAssertEqual(powershell.deriveExecArgs(command: "echo hello", useLoginShell: false), [
            "pwsh.exe", "-NoProfile", "-Command", "echo hello"
        ])
        XCTAssertEqual(powershell.deriveExecArgs(command: "echo hello", useLoginShell: true), [
            "pwsh.exe", "-Command", "echo hello"
        ])

        let cmd = Shell(shellType: .cmd, shellPath: "cmd.exe")
        XCTAssertEqual(cmd.deriveExecArgs(command: "echo hello", useLoginShell: false), [
            "cmd.exe", "/c", "echo hello"
        ])
    }

    func testPowerShellUTF8PrefixMatchesRustHelper() {
        let prefix = ShellResolver.powerShellUTF8OutputPrefix
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(["pwsh", "-NoProfile", "-Command", "Write-Host hi"]),
            ["pwsh", "-NoProfile", "-Command", prefix + "Write-Host hi"]
        )
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(["powershell.exe", "-c", "Write-Host hi"]),
            ["powershell.exe", "-c", prefix + "Write-Host hi"]
        )
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(["pwsh", "-Command", "  \(prefix)Write-Host hi"]),
            ["pwsh", "-Command", "  \(prefix)Write-Host hi"]
        )
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(["bash", "-lc", "echo hi"]),
            ["bash", "-lc", "echo hi"]
        )
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(["pwsh", "-EncodedCommand", "abc"]),
            ["pwsh", "-EncodedCommand", "abc"]
        )
    }

    func testShellCodableShapeMatchesRustSerde() throws {
        let shell = Shell(shellType: .powerShell, shellPath: "pwsh.exe")

        try XCTAssertJSONObjectEqual(shell, [
            "shell_type": "PowerShell",
            "shell_path": "pwsh.exe"
        ])

        let decoded = try JSONDecoder().decode(Shell.self, from: Data("""
        {"shell_type":"Bash","shell_path":"/bin/bash"}
        """.utf8))
        XCTAssertEqual(decoded, Shell(shellType: .bash, shellPath: "/bin/bash"))
    }

    func testModelProvidedPathFallsBackWhenUnknown() {
        XCTAssertEqual(
            ShellResolver.getShellByModelProvidedPath("/definitely/not/fish").shellType,
            .sh
        )
    }

    #if os(macOS)
    func testMacOSFishFallbackPrefersZsh() {
        let shell = ShellResolver.defaultUserShell(userShellPath: "/bin/fish")

        XCTAssertEqual(shell, Shell(shellType: .zsh, shellPath: "/bin/zsh"))
    }
    #endif
}
