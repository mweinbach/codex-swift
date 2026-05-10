import CodexCore
import Foundation

public enum UpdateAction: Equatable, Sendable {
    case npmGlobalLatest
    case bunGlobalLatest
    case brewUpgrade
    case standaloneUnix
    case standaloneWindows

    public func commandArgs() -> (command: String, arguments: [String]) {
        switch self {
        case .npmGlobalLatest:
            return ("npm", ["install", "-g", "@openai/codex"])
        case .bunGlobalLatest:
            return ("bun", ["install", "-g", "@openai/codex"])
        case .brewUpgrade:
            return ("brew", ["upgrade", "--cask", "codex"])
        case .standaloneUnix:
            return ("sh", ["-c", "curl -fsSL https://chatgpt.com/codex/install.sh | sh"])
        case .standaloneWindows:
            return ("powershell", ["-c", "irm https://chatgpt.com/codex/install.ps1|iex"])
        }
    }

    public func commandString() -> String {
        let args = commandArgs()
        return shlexJoin([args.command] + args.arguments)
    }

    public static func detect(
        isMacOS: Bool,
        currentExecutablePath: String,
        managedByNPM: Bool,
        managedByBUN: Bool
    ) -> UpdateAction? {
        if managedByNPM {
            return .npmGlobalLatest
        }
        if managedByBUN {
            return .bunGlobalLatest
        }
        if isMacOS,
           path(currentExecutablePath, startsWith: "/opt/homebrew")
            || path(currentExecutablePath, startsWith: "/usr/local") {
            return .brewUpgrade
        }
        return nil
    }

    public static func detectCurrent(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentExecutablePath: String = CommandLine.arguments.first ?? ""
    ) -> UpdateAction? {
        detectCurrent(
            environment: environment,
            currentExecutablePath: currentExecutablePath,
            isMacOS: currentOSIsMacOS
        )
    }

    public static func detectCurrent(
        environment: [String: String],
        currentExecutablePath: String,
        isMacOS: Bool
    ) -> UpdateAction? {
        detect(
            isMacOS: isMacOS,
            currentExecutablePath: currentExecutablePath,
            managedByNPM: environment["CODEX_MANAGED_BY_NPM"] != nil,
            managedByBUN: environment["CODEX_MANAGED_BY_BUN"] != nil
        )
    }

    public func normalizedCommandArgsForWSL(isWSL: Bool = WSLPath.isWSL()) -> (command: String, arguments: [String]) {
        let args = commandArgs()
        return (
            WSLPath.normalizeForWSL(args.command, isWSL: isWSL),
            args.arguments.map { WSLPath.normalizeForWSL($0, isWSL: isWSL) }
        )
    }

    private static var currentOSIsMacOS: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    private static func path(_ path: String, startsWith root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
