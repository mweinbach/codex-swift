import XCTest
#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif
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
        #if os(Windows)
        XCTAssertEqual(ShellResolver.detectShellType(#"C:\Program Files\PowerShell\7\pwsh.exe"#), .powerShell)
        #else
        XCTAssertEqual(ShellResolver.detectShellType(#"C:\Program Files\PowerShell\7\pwsh.exe"#), nil)
        #endif
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
        let windowsStylePath = [#"C:\Program Files\PowerShell\7\pwsh.exe"#, "-c", "Write-Host hi"]
        #if os(Windows)
        XCTAssertEqual(
            ShellResolver.prefixPowerShellScriptWithUTF8(windowsStylePath),
            [#"C:\Program Files\PowerShell\7\pwsh.exe"#, "-c", prefix + "Write-Host hi"]
        )
        #else
        XCTAssertEqual(ShellResolver.prefixPowerShellScriptWithUTF8(windowsStylePath), windowsStylePath)
        #endif
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

    func testGetShellIgnoresMissingDefaultShellPath() {
        let shell = ShellResolver.getShell(.bash, defaultShellPath: "/definitely/not/bash")

        XCTAssertEqual(shell?.shellType, .bash)
        XCTAssertNotEqual(shell?.shellPath, "/definitely/not/bash")
        XCTAssertEqual((shell?.shellPath as NSString?)?.lastPathComponent, "bash")
    }

    func testPowerShellFallbackPathsMatchRustPlatformConstants() {
        #if os(Windows)
        XCTAssertEqual(ShellResolver.pwshFallbackPaths, [#"C:\Program Files\PowerShell\7\pwsh.exe"#])
        XCTAssertEqual(ShellResolver.powerShellFallbackPaths, [#"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#])
        #else
        XCTAssertEqual(ShellResolver.pwshFallbackPaths, ["/usr/local/bin/pwsh"])
        XCTAssertEqual(ShellResolver.powerShellFallbackPaths, [])
        #endif
    }

    #if os(Linux) || os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    func testDefaultUserShellUsesUnixAccountShellLikeRust() throws {
        guard let accountShellPath = currentAccountShellPathForTest(),
              let accountShellType = ShellResolver.detectShellType(accountShellPath)
        else {
            throw XCTSkip("current account shell is unavailable or not recognized by Codex")
        }
        guard FileManager.default.fileExists(atPath: accountShellPath) else {
            throw XCTSkip("current account shell path does not exist")
        }

        XCTAssertEqual(
            ShellResolver.defaultUserShell(),
            Shell(shellType: accountShellType, shellPath: accountShellPath)
        )
    }
    #endif

    #if os(macOS)
    func testMacOSFishFallbackPrefersZsh() {
        let shell = ShellResolver.defaultUserShell(userShellPath: "/bin/fish")

        XCTAssertEqual(shell, Shell(shellType: .zsh, shellPath: "/bin/zsh"))
    }

    func testMacOSMissingDefaultShellFallsBackToZsh() {
        let shell = ShellResolver.defaultUserShell(userShellPath: "/definitely/not/zsh")

        XCTAssertEqual(shell, Shell(shellType: .zsh, shellPath: "/bin/zsh"))
    }
    #endif
}

#if os(Linux) || os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
private func currentAccountShellPathForTest() -> String? {
    var passwdEntry = passwd()
    var bufferLength = Int(sysconf(Int32(_SC_GETPW_R_SIZE_MAX)))
    if bufferLength <= 0 {
        bufferLength = 1024
    }

    while bufferLength <= 1024 * 1024 {
        var buffer = [CChar](repeating: 0, count: bufferLength)
        var result: UnsafeMutablePointer<passwd>?
        let status = getpwuid_r(getuid(), &passwdEntry, &buffer, buffer.count, &result)
        if status == 0 {
            guard result != nil, let shell = passwdEntry.pw_shell else {
                return nil
            }
            return String(cString: shell)
        }
        guard status == ERANGE else {
            return nil
        }
        bufferLength *= 2
    }

    return nil
}
#endif
