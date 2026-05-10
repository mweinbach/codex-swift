import Foundation
#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

public enum ShellType: String, Codable, CaseIterable, Equatable, Sendable {
    case zsh = "Zsh"
    case bash = "Bash"
    case powerShell = "PowerShell"
    case sh = "Sh"
    case cmd = "Cmd"

    public var name: String {
        switch self {
        case .zsh:
            return "zsh"
        case .bash:
            return "bash"
        case .powerShell:
            return "powershell"
        case .sh:
            return "sh"
        case .cmd:
            return "cmd"
        }
    }
}

public struct Shell: Equatable, Codable, Sendable {
    public let shellType: ShellType
    public let shellPath: String

    private enum CodingKeys: String, CodingKey {
        case shellType = "shell_type"
        case shellPath = "shell_path"
    }

    public init(shellType: ShellType, shellPath: String) {
        self.shellType = shellType
        self.shellPath = shellPath
    }

    public var name: String {
        shellType.name
    }

    public func deriveExecArgs(command: String, useLoginShell: Bool) -> [String] {
        switch shellType {
        case .zsh, .bash, .sh:
            [shellPath, useLoginShell ? "-lc" : "-c", command]
        case .powerShell:
            if useLoginShell {
                [shellPath, "-Command", command]
            } else {
                [shellPath, "-NoProfile", "-Command", command]
            }
        case .cmd:
            [shellPath, "/c", command]
        }
    }
}

public enum ShellResolver {
    public static let powerShellUTF8OutputPrefix = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;\n"

    public static func detectShellType(_ shellPath: String) -> ShellType? {
        switch shellPath {
        case "zsh":
            return .zsh
        case "sh":
            return .sh
        case "cmd":
            return .cmd
        case "bash":
            return .bash
        case "pwsh", "powershell":
            return .powerShell
        default:
            guard let stem = fileStem(shellPath), stem != shellPath else {
                return nil
            }
            return detectShellType(stem)
        }
    }

    public static func prefixPowerShellScriptWithUTF8(_ command: [String]) -> [String] {
        guard command.count >= 3,
              detectShellType(command[0]) == .powerShell
        else {
            return command
        }

        var output = command
        var index = 1
        while index + 1 < command.count {
            let flag = command[index].lowercased()
            guard ["-nologo", "-noprofile", "-command", "-c"].contains(flag) else {
                return command
            }
            if flag == "-command" || flag == "-c" {
                let script = command[index + 1]
                if script.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(powerShellUTF8OutputPrefix) {
                    return command
                }
                output[index + 1] = powerShellUTF8OutputPrefix + script
                return output
            }
            index += 1
        }

        return command
    }

    public static func extractPowerShellCommand(_ command: [String]) -> (shell: String, script: String)? {
        guard command.count >= 3,
              detectShellType(command[0]) == .powerShell
        else {
            return nil
        }

        var index = 1
        while index + 1 < command.count {
            let flag = command[index].lowercased()
            guard ["-nologo", "-noprofile", "-command", "-c"].contains(flag) else {
                return nil
            }
            if flag == "-command" || flag == "-c" {
                return (command[0], command[index + 1])
            }
            index += 1
        }

        return nil
    }

    public static func defaultUserShell() -> Shell {
        defaultUserShell(userShellPath: currentUserShellPath())
    }

    public static func defaultUserShell(userShellPath: String?) -> Shell {
        #if os(Windows)
        return getShell(.powerShell) ?? ultimateFallbackShell()
        #else
        let userDefaultShell = userShellPath
            .flatMap(detectShellType(_:))
            .flatMap { getShell($0, defaultShellPath: userShellPath) }

        #if os(macOS)
        let shellWithFallback = userDefaultShell
            ?? getShell(.zsh)
            ?? getShell(.bash)
        #else
        let shellWithFallback = userDefaultShell
            ?? getShell(.bash)
            ?? getShell(.zsh)
        #endif

        return shellWithFallback ?? ultimateFallbackShell()
        #endif
    }

    public static func getShellByModelProvidedPath(_ shellPath: String) -> Shell {
        detectShellType(shellPath)
            .flatMap { getShell($0, path: shellPath) }
            ?? ultimateFallbackShell()
    }

    public static func getShell(_ shellType: ShellType, path: String? = nil) -> Shell? {
        getShell(shellType, path: path, defaultShellPath: currentUserShellPath())
    }

    static func getShell(_ shellType: ShellType, path: String? = nil, defaultShellPath: String?) -> Shell? {
        switch shellType {
        case .zsh:
            return getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "zsh",
                fallbackPaths: ["/bin/zsh"]
            )
        case .bash:
            return getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "bash",
                fallbackPaths: ["/bin/bash"]
            )
        case .sh:
            return getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "sh",
                fallbackPaths: ["/bin/sh"]
            )
        case .powerShell:
            return getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "pwsh",
                fallbackPaths: pwshFallbackPaths
            )
            ?? getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "powershell",
                fallbackPaths: powerShellFallbackPaths
            )
        case .cmd:
            return getShell(
                shellType,
                providedPath: path,
                defaultShellPath: defaultShellPath,
                binaryName: "cmd",
                fallbackPaths: []
            )
        }
    }

    private static func getShell(
        _ shellType: ShellType,
        providedPath: String?,
        defaultShellPath: String?,
        binaryName: String,
        fallbackPaths: [String]
    ) -> Shell? {
        if let providedPath, isFile(providedPath) {
            return Shell(shellType: shellType, shellPath: providedPath)
        }

        if let defaultShellPath,
           detectShellType(defaultShellPath) == shellType,
           isFile(defaultShellPath)
        {
            return Shell(shellType: shellType, shellPath: defaultShellPath)
        }

        if let path = which(binaryName) {
            return Shell(shellType: shellType, shellPath: path)
        }

        for path in fallbackPaths where isFile(path) {
            return Shell(shellType: shellType, shellPath: path)
        }

        return nil
    }

    private static func ultimateFallbackShell() -> Shell {
        #if os(Windows)
        Shell(shellType: .cmd, shellPath: "cmd.exe")
        #else
        Shell(shellType: .sh, shellPath: "/bin/sh")
        #endif
    }

    private static func currentUserShellPath() -> String? {
        #if os(Linux) || os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        return unixUserShellPath()
        #else
        ProcessInfo.processInfo.environment["SHELL"]
        #endif
    }

    #if os(Linux) || os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    private static func unixUserShellPath() -> String? {
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

    private static func which(_ binaryName: String) -> String? {
        guard !binaryName.contains("/") else {
            return isFile(binaryName) ? binaryName : nil
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: pathListSeparator, omittingEmptySubsequences: true) {
            let directory = String(directory)
            let separator = directory.hasSuffix("/") || directory.hasSuffix("\\") ? "" : pathComponentSeparator
            let candidate = directory + separator + binaryName
            if isFile(candidate), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static var pwshFallbackPaths: [String] {
        #if os(Windows)
        [#"C:\Program Files\PowerShell\7\pwsh.exe"#]
        #else
        ["/usr/local/bin/pwsh"]
        #endif
    }

    static var powerShellFallbackPaths: [String] {
        #if os(Windows)
        [#"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#]
        #else
        []
        #endif
    }

    private static var pathListSeparator: Character {
        #if os(Windows)
        ";"
        #else
        ":"
        #endif
    }

    private static var pathComponentSeparator: String {
        #if os(Windows)
        #"\"#
        #else
        "/"
        #endif
    }

    private static func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func fileStem(_ path: String) -> String? {
        #if os(Windows)
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        #else
        let normalized = path
        #endif
        let lastComponent = normalized.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
            ?? normalized
        let stem = (lastComponent as NSString).deletingPathExtension
        return stem.isEmpty ? nil : stem
    }
}
