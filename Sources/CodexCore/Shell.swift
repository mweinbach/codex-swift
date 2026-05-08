import Foundation

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

    public static func defaultUserShell() -> Shell {
        defaultUserShell(userShellPath: currentUserShellPath())
    }

    public static func defaultUserShell(userShellPath: String?) -> Shell {
        #if os(Windows)
        return getShell(.powerShell) ?? ultimateFallbackShell()
        #else
        let userDefaultShell = userShellPath
            .flatMap(detectShellType(_:))
            .flatMap { getShell($0) }

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
        switch shellType {
        case .zsh:
            return getShell(shellType, providedPath: path, binaryName: "zsh", fallbackPaths: ["/bin/zsh"])
        case .bash:
            return getShell(shellType, providedPath: path, binaryName: "bash", fallbackPaths: ["/bin/bash"])
        case .sh:
            return getShell(shellType, providedPath: path, binaryName: "sh", fallbackPaths: ["/bin/sh"])
        case .powerShell:
            return getShell(
                shellType,
                providedPath: path,
                binaryName: "pwsh",
                fallbackPaths: ["/usr/local/bin/pwsh"]
            )
            ?? getShell(shellType, providedPath: path, binaryName: "powershell", fallbackPaths: [])
        case .cmd:
            return getShell(shellType, providedPath: path, binaryName: "cmd", fallbackPaths: [])
        }
    }

    private static func getShell(
        _ shellType: ShellType,
        providedPath: String?,
        binaryName: String,
        fallbackPaths: [String]
    ) -> Shell? {
        if let providedPath, isFile(providedPath) {
            return Shell(shellType: shellType, shellPath: providedPath)
        }

        if let defaultShellPath = currentUserShellPath(),
           detectShellType(defaultShellPath) == shellType
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
        ProcessInfo.processInfo.environment["SHELL"]
    }

    private static func which(_ binaryName: String) -> String? {
        guard !binaryName.contains("/") else {
            return isFile(binaryName) ? binaryName : nil
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = String(directory) + "/" + binaryName
            if isFile(candidate), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func fileStem(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let lastComponent = normalized.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
            ?? normalized
        let stem = (lastComponent as NSString).deletingPathExtension
        return stem.isEmpty ? nil : stem
    }
}
