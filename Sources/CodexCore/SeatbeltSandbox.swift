import Foundation

public enum SeatbeltSandboxError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidCurrentDirectory(String)
    case launchFailed(String)

    public var description: String {
        switch self {
        case let .invalidCurrentDirectory(path):
            return "invalid sandbox cwd: \(path)"
        case let .launchFailed(message):
            return "failed to launch sandbox-exec: \(message)"
        }
    }
}

public enum SeatbeltSandbox {
    public static let executablePath = "/usr/bin/sandbox-exec"
    public static let sandboxEnvironmentValue = "seatbelt"

    public static func sandboxPolicy(fullAuto: Bool) -> SandboxPolicy {
        fullAuto ? .newWorkspaceWritePolicy() : .newReadOnlyPolicy()
    }

    public static func run(
        command: [String],
        fullAuto: Bool,
        cwd: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executablePath: String = Self.executablePath,
        logDenials: Bool = false,
        fileManager: FileManager = .default
    ) throws -> Int32 {
        try run(
            command: command,
            sandboxPolicy: sandboxPolicy(fullAuto: fullAuto),
            cwd: cwd,
            environment: environment,
            executablePath: executablePath,
            logDenials: logDenials,
            fileManager: fileManager
        )
    }

    public static func run(
        command: [String],
        sandboxPolicy policy: SandboxPolicy,
        cwd: URL,
        allowUnixSockets: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executablePath: String = Self.executablePath,
        logDenials: Bool = false,
        fileManager: FileManager = .default
    ) throws -> Int32 {
        let cwdPath = cwd.standardizedFileURL.path
        guard let absoluteCwd = try? AbsolutePath(absolutePath: cwdPath) else {
            throw SeatbeltSandboxError.invalidCurrentDirectory(cwdPath)
        }
        let args = commandArguments(
            command: command,
            sandboxPolicy: policy,
            sandboxPolicyCwd: absoluteCwd,
            allowUnixSockets: allowUnixSockets,
            environment: environment,
            fileManager: fileManager
        )
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)
        childEnvironment["CODEX_SANDBOX"] = sandboxEnvironmentValue
        if !policy.hasFullNetworkAccess {
            childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
        }

        let denialLogger = logDenials ? SeatbeltDenialLogger.start() : nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = childEnvironment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw SeatbeltSandboxError.launchFailed(String(describing: error))
        }
        denialLogger?.onChildSpawn(process.processIdentifier)
        process.waitUntilExit()
        if let denialLogger {
            FileHandle.standardError.write(SeatbeltDenialLogger.formatSummary(denials: denialLogger.finish()))
        }
        return process.terminationStatus
    }

    public static func run(
        command: [String],
        permissionProfile: PermissionProfile,
        cwd: URL,
        allowUnixSockets: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executablePath: String = Self.executablePath,
        logDenials: Bool = false
    ) throws -> Int32 {
        let cwdPath = cwd.standardizedFileURL.path
        guard let absoluteCwd = try? AbsolutePath(absolutePath: cwdPath) else {
            throw SeatbeltSandboxError.invalidCurrentDirectory(cwdPath)
        }
        let args = commandArguments(
            command: command,
            permissionProfile: permissionProfile,
            sandboxPolicyCwd: absoluteCwd,
            allowUnixSockets: allowUnixSockets
        )
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)
        childEnvironment["CODEX_SANDBOX"] = sandboxEnvironmentValue
        if !permissionProfile.networkSandboxPolicy.isEnabled {
            childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
        }

        let denialLogger = logDenials ? SeatbeltDenialLogger.start() : nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = childEnvironment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw SeatbeltSandboxError.launchFailed(String(describing: error))
        }
        denialLogger?.onChildSpawn(process.processIdentifier)
        process.waitUntilExit()
        if let denialLogger {
            FileHandle.standardError.write(SeatbeltDenialLogger.formatSummary(denials: denialLogger.finish()))
        }
        return process.terminationStatus
    }

    public static func commandArguments(
        command: [String],
        sandboxPolicy: SandboxPolicy,
        sandboxPolicyCwd: AbsolutePath,
        allowUnixSockets: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String] {
        let (fileWritePolicy, fileWriteDirParams) = fileWritePolicyAndParams(
            sandboxPolicy: sandboxPolicy,
            sandboxPolicyCwd: sandboxPolicyCwd,
            environment: environment,
            fileManager: fileManager
        )
        let fileReadPolicy = sandboxPolicy.hasFullDiskReadAccess
            ? "; allow read-only file operations\n(allow file-read*)"
            : ""
        let networkPolicy = sandboxPolicy.hasFullNetworkAccess ? macOSSeatbeltNetworkPolicy : ""
        let (unixSocketPolicy, unixSocketParams) = unixSocketPolicyAndParams(
            allowUnixSockets: allowUnixSockets
        )
        let fullPolicy = """
        \(macOSSeatbeltBasePolicy)
        \(fileReadPolicy)
        \(fileWritePolicy)
        \(networkPolicy)
        \(unixSocketPolicy)
        """

        let dirParams = fileWriteDirParams + unixSocketParams
        var args = ["-p", fullPolicy]
        args.append(contentsOf: dirParams.map { key, value in "-D\(key)=\(value)" })
        args.append("--")
        args.append(contentsOf: command)
        return args
    }

    public static func commandArguments(
        command: [String],
        permissionProfile: PermissionProfile,
        sandboxPolicyCwd: AbsolutePath,
        allowUnixSockets: [String] = []
    ) -> [String] {
        commandArguments(
            command: command,
            fileSystemSandboxPolicy: permissionProfile.fileSystemSandboxPolicy,
            networkSandboxPolicy: permissionProfile.networkSandboxPolicy,
            sandboxPolicyCwd: sandboxPolicyCwd,
            allowUnixSockets: allowUnixSockets
        )
    }

    public static func commandArguments(
        command: [String],
        fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        networkSandboxPolicy: NetworkSandboxPolicy,
        sandboxPolicyCwd: AbsolutePath,
        allowUnixSockets: [String] = []
    ) -> [String] {
        let cwd = sandboxPolicyCwd.path
        let unreadableRoots = fileSystemSandboxPolicy.getUnreadableRootsWithCwd(cwd)
        let (fileWritePolicy, fileWriteDirParams) = directFileWritePolicyAndParams(
            fileSystemSandboxPolicy: fileSystemSandboxPolicy,
            unreadableRoots: unreadableRoots,
            cwd: cwd
        )
        let (fileReadPolicy, fileReadDirParams) = directFileReadPolicyAndParams(
            fileSystemSandboxPolicy: fileSystemSandboxPolicy,
            unreadableRoots: unreadableRoots,
            cwd: cwd
        )
        let networkPolicy = networkSandboxPolicy.isEnabled ? macOSSeatbeltNetworkPolicy : ""
        let (unixSocketPolicy, unixSocketParams) = unixSocketPolicyAndParams(allowUnixSockets: allowUnixSockets)
        let denyReadRootPolicy = unreadableRootPolicy(unreadableRoots)
        let denyReadPolicy = unreadableGlobPolicy(fileSystemSandboxPolicy: fileSystemSandboxPolicy, cwd: cwd)
        let platformDefaultsPolicy = fileSystemSandboxPolicy.includePlatformDefaults
            ? macOSRestrictedReadOnlyPlatformDefaults
            : ""
        let fullPolicy = """
        \(macOSSeatbeltBasePolicy)
        \(fileReadPolicy)
        \(fileWritePolicy)
        \(denyReadRootPolicy)
        \(denyReadPolicy)
        \(networkPolicy)
        \(unixSocketPolicy)
        \(platformDefaultsPolicy)
        """

        let dirParams = fileReadDirParams + fileWriteDirParams + unixSocketParams
        var args = ["-p", fullPolicy]
        args.append(contentsOf: dirParams.map { key, value in "-D\(key)=\(value)" })
        args.append("--")
        args.append(contentsOf: command)
        return args
    }

    private struct SeatbeltAccessRoot {
        var root: AbsolutePath
        var excludedSubpaths: [AbsolutePath]
        var protectedMetadataNames: [String]
    }

    private static func directFileWritePolicyAndParams(
        fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        unreadableRoots: [AbsolutePath],
        cwd: String
    ) -> (String, [(String, String)]) {
        if fileSystemSandboxPolicy.hasFullDiskWriteAccess {
            if unreadableRoots.isEmpty {
                return (#"(allow file-write* (regex #"^/"))"#, [])
            }
            return accessPolicyAndParams(
                action: "file-write*",
                paramPrefix: "WRITABLE_ROOT",
                roots: [SeatbeltAccessRoot(
                    root: rootAbsolutePath(),
                    excludedSubpaths: unreadableRoots,
                    protectedMetadataNames: []
                )]
            )
        }

        var writableRoots = fileSystemSandboxPolicy.getWritableRootsWithCwd(cwd)
        if let cwdPath = try? AbsolutePath(absolutePath: cwd),
           fileSystemSandboxPolicy.canWritePathWithCwd(cwdPath.path, cwd: cwd),
           !writableRoots.contains(where: { $0.root == cwdPath })
        {
            writableRoots.append(WritableRoot(
                root: cwdPath,
                protectedMetadataNames: [".git", ".agents", ".codex"]
            ))
        }
        for alias in writableRoots.flatMap({ writableRootAliases(for: $0.root) }) {
            guard !writableRoots.contains(where: { $0.root == alias }) else {
                continue
            }
            writableRoots.append(WritableRoot(
                root: alias,
                protectedMetadataNames: [".git", ".agents", ".codex"]
            ))
        }
        let roots = writableRoots.map {
            SeatbeltAccessRoot(
                root: $0.root,
                excludedSubpaths: $0.readOnlySubpaths,
                protectedMetadataNames: $0.protectedMetadataNames
            )
        }
        return accessPolicyAndParams(action: "file-write*", paramPrefix: "WRITABLE_ROOT", roots: roots)
    }

    private static func writableRootAliases(for root: AbsolutePath) -> [AbsolutePath] {
        let path = root.path
        let aliases: [String]
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            aliases = ["/private\(path)"]
        } else if path == "/private/tmp" || path.hasPrefix("/private/tmp/") {
            aliases = [String(path.dropFirst("/private".count))]
        } else {
            aliases = []
        }
        return aliases.compactMap { try? AbsolutePath(absolutePath: $0) }
    }

    private static func directFileReadPolicyAndParams(
        fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        unreadableRoots: [AbsolutePath],
        cwd: String
    ) -> (String, [(String, String)]) {
        if fileSystemSandboxPolicy.hasFullDiskReadAccess {
            if unreadableRoots.isEmpty {
                return ("; allow read-only file operations\n(allow file-read*)", [])
            }
            let (policy, params) = accessPolicyAndParams(
                action: "file-read*",
                paramPrefix: "READABLE_ROOT",
                roots: [SeatbeltAccessRoot(
                    root: rootAbsolutePath(),
                    excludedSubpaths: unreadableRoots,
                    protectedMetadataNames: []
                )]
            )
            return ("; allow read-only file operations\n\(policy)", params)
        }

        let roots = fileSystemSandboxPolicy.getReadableRootsWithCwd(cwd).map { root in
            SeatbeltAccessRoot(
                root: root,
                excludedSubpaths: unreadableRoots.filter { absolutePath($0, isUnderOrEqual: root) },
                protectedMetadataNames: []
            )
        }
        let (policy, params) = accessPolicyAndParams(
            action: "file-read*",
            paramPrefix: "READABLE_ROOT",
            roots: roots
        )
        guard !policy.isEmpty else {
            return ("", params)
        }
        return ("; allow read-only file operations\n\(policy)", params)
    }

    private static func accessPolicyAndParams(
        action: String,
        paramPrefix: String,
        roots: [SeatbeltAccessRoot]
    ) -> (String, [(String, String)]) {
        var rootPolicies: [String] = []
        var params: [(String, String)] = []

        for (index, root) in roots.enumerated() {
            let rootParam = "\(paramPrefix)_\(index)"
            params.append((rootParam, canonicalPath(root.root.path)))

            if root.excludedSubpaths.isEmpty && root.protectedMetadataNames.isEmpty {
                rootPolicies.append(#"(subpath (param "\#(rootParam)"))"#)
                continue
            }

            var requireParts = [#"(subpath (param "\#(rootParam)"))"#]
            for (excludedIndex, excludedSubpath) in root.excludedSubpaths.enumerated() {
                let excludedParam = "\(rootParam)_EXCLUDED_\(excludedIndex)"
                params.append((excludedParam, canonicalPath(excludedSubpath.path)))
                requireParts.append(#"(require-not (literal (param "\#(excludedParam)")))"#)
                requireParts.append(#"(require-not (subpath (param "\#(excludedParam)")))"#)
            }
            for metadataName in root.protectedMetadataNames {
                let regex = protectedMetadataNameRegex(root: root.root.path, name: metadataName)
                requireParts.append(#"(require-not (regex #"\#(regex)"))"#)
            }
            rootPolicies.append("(require-all \(requireParts.joined(separator: " ")) )")
        }

        guard !rootPolicies.isEmpty else {
            return ("", [])
        }
        return ("(allow \(action)\n\(rootPolicies.joined(separator: " "))\n)", params)
    }

    private static func unreadableGlobPolicy(
        fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        cwd: String
    ) -> String {
        let regexes = fileSystemSandboxPolicy
            .getUnreadableGlobsWithCwd(cwd)
            .flatMap { pattern -> [String] in
                var values = [seatbeltRegexForUnreadableGlob(pattern)]
                let canonicalPattern = canonicalizedStaticPrefixGlob(pattern)
                if canonicalPattern != pattern {
                    values.append(seatbeltRegexForUnreadableGlob(canonicalPattern))
                }
                return values
            }
        let uniqueRegexes = Set(regexes).sorted()
        guard !uniqueRegexes.isEmpty else {
            return ""
        }

        return uniqueRegexes.map { regex in
            #"(deny file-read* (regex #"\#(regex)"))"# + "\n" +
                #"(deny file-write-unlink (regex #"\#(regex)"))"#
        }.joined(separator: "\n")
    }

    private static func unreadableRootPolicy(_ unreadableRoots: [AbsolutePath]) -> String {
        guard !unreadableRoots.isEmpty else {
            return ""
        }
        return unreadableRoots.map { root in
            let escapedRoot = canonicalPath(root.path).map(escapedRegexLiteral).joined()
            let regex = "^\(escapedRoot)(/.*)?$"
            return #"(deny file-read* (regex #"\#(regex)"))"# + "\n" +
                #"(deny file-write-unlink (regex #"\#(regex)"))"#
        }.joined(separator: "\n")
    }

    private static func canonicalizedStaticPrefixGlob(_ pattern: String) -> String {
        guard let globIndex = pattern.firstIndex(where: { "*?[".contains($0) }) else {
            return canonicalPath(pattern)
        }
        let prefix = String(pattern[..<globIndex])
        let suffix = String(pattern[globIndex...])
        let directoryPrefix: String
        let staticFilePrefix: String
        if let lastSlash = prefix.lastIndex(of: "/") {
            directoryPrefix = String(prefix[...lastSlash])
            staticFilePrefix = String(prefix[prefix.index(after: lastSlash)...])
        } else {
            directoryPrefix = ""
            staticFilePrefix = prefix
        }
        let canonicalDirectory = directoryPrefix.isEmpty ? "" : canonicalPath(String(directoryPrefix.dropLast())) + "/"
        return canonicalDirectory + staticFilePrefix + suffix
    }

    static func seatbeltRegexForUnreadableGlob(_ pattern: String) -> String {
        let characters = Array(pattern)
        var regex = "^"
        var sawGlob = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                sawGlob = true
                if index + 2 < characters.count,
                   characters[index + 1] == "*",
                   characters[index + 2] == "/" {
                    regex += "(.*/)?"
                    index += 3
                } else {
                    regex += "[^/]*"
                    index += 1
                }
            case "?":
                sawGlob = true
                regex += "[^/]"
                index += 1
            case "[":
                if let closingIndex = characters[(index + 1)...].firstIndex(of: "]") {
                    sawGlob = true
                    let body = String(characters[(index + 1)..<closingIndex])
                    regex += translatedCharacterClass(body)
                    index = closingIndex + 1
                } else {
                    regex += "\\["
                    index += 1
                }
            case "]":
                regex += "\\]"
                index += 1
            default:
                regex += escapedRegexLiteral(character)
                index += 1
            }
        }

        if !sawGlob {
            regex += "(/.*)?"
        }
        regex += "$"
        return regex
    }

    private static func translatedCharacterClass(_ body: String) -> String {
        guard let first = body.first else {
            return "[]"
        }

        var result = "["
        switch first {
        case "!":
            result += "^"
        case "^":
            result += "\\^"
        default:
            result += String(first)
        }
        for character in body.dropFirst() {
            if character == "\\" {
                result += "\\\\"
            } else {
                result += String(character)
            }
        }
        return result + "]"
    }

    private static func protectedMetadataNameRegex(root: String, name: String) -> String {
        let escapedName = name.map(escapedRegexLiteral).joined()
        guard root != "/" else {
            return "^/\(escapedName)(/.*)?$"
        }
        let escapedRoot = root.map(escapedRegexLiteral).joined()
        return "^\(escapedRoot)/\(escapedName)(/.*)?$"
    }

    private static func escapedRegexLiteral(_ character: Character) -> String {
        switch character {
        case "\\", ".", "+", "*", "?", "(", ")", "|", "{", "}", "[", "]", "^", "$":
            return "\\\(character)"
        default:
            return String(character)
        }
    }

    private static func absolutePath(_ child: AbsolutePath, isUnderOrEqual root: AbsolutePath) -> Bool {
        child.path == root.path || child.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    private static func rootAbsolutePath() -> AbsolutePath {
        try! AbsolutePath(absolutePath: "/")
    }

    private static func fileWritePolicyAndParams(
        sandboxPolicy: SandboxPolicy,
        sandboxPolicyCwd: AbsolutePath,
        environment: [String: String],
        fileManager: FileManager
    ) -> (String, [(String, String)]) {
        if sandboxPolicy.hasFullDiskWriteAccess {
            return (#"(allow file-write* (regex #"^/"))"#, [])
        }

        guard case .workspaceWrite = sandboxPolicy else {
            return ("", [])
        }

        let writableRoots = PatchSafety.writableRootsWithCwd(
            sandboxPolicy: sandboxPolicy,
            cwd: sandboxPolicyCwd,
            environment: environment,
            fileManager: fileManager
        )
        var folderPolicies: [String] = []
        var params: [(String, String)] = []

        for (index, writableRoot) in writableRoots.enumerated() {
            let rootParam = "WRITABLE_ROOT_\(index)"
            params.append((rootParam, canonicalPath(writableRoot.root.path)))

            let protectedMetadataSubpaths = writableRoot.protectedMetadataNames.compactMap {
                try? writableRoot.root.join($0)
            }
            let readOnlySubpaths = writableRoot.readOnlySubpaths + protectedMetadataSubpaths

            if readOnlySubpaths.isEmpty {
                folderPolicies.append(#"(subpath (param "\#(rootParam)"))"#)
            } else {
                var requireParts = [#"(subpath (param "\#(rootParam)"))"#]
                for (subpathIndex, readOnlyPath) in readOnlySubpaths.enumerated() {
                    let readOnlyParam = "WRITABLE_ROOT_\(index)_RO_\(subpathIndex)"
                    requireParts.append(#"(require-not (subpath (param "\#(readOnlyParam)")))"#)
                    params.append((readOnlyParam, canonicalPath(readOnlyPath.path)))
                }
                folderPolicies.append("(require-all \(requireParts.joined(separator: " ")) )")
            }
        }

        guard !folderPolicies.isEmpty else {
            return ("", [])
        }
        return ("(allow file-write*\n\(folderPolicies.joined(separator: " "))\n)", params)
    }

    private static func unixSocketPolicyAndParams(allowUnixSockets: [String]) -> (String, [(String, String)]) {
        let canonicalSocketPaths = Set(
            allowUnixSockets.compactMap { socketPath -> String? in
                guard socketPath.hasPrefix("/") else {
                    return nil
                }
                return canonicalPath(socketPath)
            }
        ).sorted()

        guard !canonicalSocketPaths.isEmpty else {
            return ("", [])
        }

        var policyLines = [
            "; allow unix domain sockets for local IPC",
            "(allow system-socket (socket-domain AF_UNIX))"
        ]
        var params: [(String, String)] = []
        for (index, socketPath) in canonicalSocketPaths.enumerated() {
            let param = "UNIX_SOCKET_PATH_\(index)"
            params.append((param, socketPath))
            policyLines.append(#"(allow network-bind (local unix-socket (subpath (param "\#(param)"))))"#)
            policyLines.append(#"(allow network-outbound (remote unix-socket (subpath (param "\#(param)"))))"#)
        }
        return (policyLines.joined(separator: "\n") + "\n", params)
    }

    private static func canonicalPath(_ path: String) -> String {
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        guard let absolutePath = try? AbsolutePath(absolutePath: path),
              let canonicalPath = canonicalizeSymlinks(absolutePath)
        else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return canonicalPath.path
    }

    private static func canonicalizeSymlinks(_ path: AbsolutePath) -> AbsolutePath? {
        var current = "/"
        for component in path.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            let candidate = current == "/" ? "/\(component)" : "\(current)/\(component)"
            if isSymbolicLink(atPath: candidate),
               let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate)
            {
                if destination.hasPrefix("/") {
                    if let destinationPath = try? AbsolutePath(absolutePath: destination),
                       destinationPath != path,
                       let canonicalDestination = canonicalizeSymlinks(destinationPath)
                    {
                        current = canonicalDestination.path
                    } else {
                        current = (try? AbsolutePath(absolutePath: destination))?.path ?? destination
                    }
                } else {
                    let parent = (candidate as NSString).deletingLastPathComponent
                    let base = parent.isEmpty ? "/" : parent
                    current = (try? AbsolutePath.resolve(destination, against: base))?.path ?? candidate
                }
            } else {
                current = candidate
            }
        }
        return try? AbsolutePath(absolutePath: current)
    }

    private static func isSymbolicLink(atPath path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}

private let macOSSeatbeltBasePolicy = #"""
(version 1)

; inspired by Chrome's sandbox policy:
; https://source.chromium.org/chromium/chromium/src/+/main:sandbox/policy/mac/common.sb;l=273-319;drc=7b3962fe2e5fc9e2ee58000dc8fbf3429d84d3bd
; https://source.chromium.org/chromium/chromium/src/+/main:sandbox/policy/mac/renderer.sb;l=64;drc=7b3962fe2e5fc9e2ee58000dc8fbf3429d84d3bd

; start with closed-by-default
(deny default)

; child processes inherit the policy of their parent
(allow process-exec)
(allow process-fork)
(allow signal (target same-sandbox))

; Allow cf prefs to work.
(allow user-preference-read)

; process-info
(allow process-info* (target same-sandbox))

(allow file-write-data
  (require-all
    (path "/dev/null")
    (vnode-type CHARACTER-DEVICE)))

; sysctls permitted.
(allow sysctl-read
  (sysctl-name "hw.activecpu")
  (sysctl-name "hw.busfrequency_compat")
  (sysctl-name "hw.byteorder")
  (sysctl-name "hw.cacheconfig")
  (sysctl-name "hw.cachelinesize_compat")
  (sysctl-name "hw.cpufamily")
  (sysctl-name "hw.cpufrequency_compat")
  (sysctl-name "hw.cputype")
  (sysctl-name "hw.l1dcachesize_compat")
  (sysctl-name "hw.l1icachesize_compat")
  (sysctl-name "hw.l2cachesize_compat")
  (sysctl-name "hw.l3cachesize_compat")
  (sysctl-name "hw.logicalcpu_max")
  (sysctl-name "hw.machine")
  (sysctl-name "hw.memsize")
  (sysctl-name "hw.ncpu")
  (sysctl-name "hw.nperflevels")
  ; Chrome locks these CPU feature detection down a bit more tightly,
  ; but mostly for fingerprinting concerns which isn't an issue for codex.
  (sysctl-name-prefix "hw.optional.arm.")
  (sysctl-name-prefix "hw.optional.armv8_")
  (sysctl-name "hw.packages")
  (sysctl-name "hw.pagesize_compat")
  (sysctl-name "hw.pagesize")
  (sysctl-name "hw.physicalcpu")
  (sysctl-name "hw.physicalcpu_max")
  (sysctl-name "hw.tbfrequency_compat")
  (sysctl-name "hw.vectorunit")
  (sysctl-name "kern.argmax")
  (sysctl-name "kern.hostname")
  (sysctl-name "kern.maxfilesperproc")
  (sysctl-name "kern.maxproc")
  (sysctl-name "kern.osproductversion")
  (sysctl-name "kern.osrelease")
  (sysctl-name "kern.ostype")
  (sysctl-name "kern.osvariant_status")
  (sysctl-name "kern.osversion")
  (sysctl-name "kern.secure_kernel")
  (sysctl-name "kern.usrstack64")
  (sysctl-name "kern.version")
  (sysctl-name "sysctl.proc_cputype")
  (sysctl-name "vm.loadavg")
  (sysctl-name-prefix "hw.perflevel")
  (sysctl-name-prefix "kern.proc.pgrp.")
  (sysctl-name-prefix "kern.proc.pid.")
  (sysctl-name-prefix "net.routetable.")
)

; Allow Java to read some CPU info. This is misclassified as a "write" because
; userspace passes a memory buffer to the sysctl, but conceptually it is a read.
(allow sysctl-write
  (sysctl-name "kern.grade_cputype"))

; IOKit
(allow iokit-open
  (iokit-registry-entry-class "RootDomainUserClient")
)

; needed to look up user info, see https://crbug.com/792228
(allow mach-lookup
  (global-name "com.apple.system.opendirectoryd.libinfo")
)

; Needed for python multiprocessing on MacOS for the SemLock
(allow ipc-posix-sem)

(allow mach-lookup
  (global-name "com.apple.PowerManagement.control")
)

; allow openpty()
(allow pseudo-tty)
(allow file-read* file-write* file-ioctl (literal "/dev/ptmx"))
(allow file-read* file-write*
  (require-all
    (regex #"^/dev/ttys[0-9]+")
    (extension "com.apple.sandbox.pty")))
; PTYs created before entering seatbelt may lack the extension; allow ioctl
; on those slave ttys so interactive shells detect a TTY and remain functional.
(allow file-ioctl (regex #"^/dev/ttys[0-9]+"))
"""#

private let macOSRestrictedReadOnlyPlatformDefaults = #"""
; macOS platform defaults included when a split filesystem policy requests `:minimal`.

; Read access to standard system paths
(allow file-read* file-test-existence
  (subpath "/Library/Apple")
  (subpath "/Library/Filesystems/NetFSPlugins")
  (subpath "/Library/Preferences/Logging")
  (subpath "/private/var/db/DarwinDirectory/local/recordStore.data")
  (subpath "/private/var/db/timezone")
  (subpath "/usr/lib")
  (subpath "/usr/share")
  (subpath "/Library/Preferences")
  (subpath "/var/db")
  (subpath "/private/var/db"))

; Map system frameworks + dylibs for loader.
(allow file-map-executable
  (subpath "/Library/Apple/System/Library/Frameworks")
  (subpath "/Library/Apple/System/Library/PrivateFrameworks")
  (subpath "/Library/Apple/usr/lib")
  (subpath "/System/Library/Extensions")
  (subpath "/System/Library/Frameworks")
  (subpath "/System/Library/PrivateFrameworks")
  (subpath "/System/Library/SubFrameworks")
  (subpath "/System/iOSSupport/System/Library/Frameworks")
  (subpath "/System/iOSSupport/System/Library/PrivateFrameworks")
  (subpath "/System/iOSSupport/System/Library/SubFrameworks")
  (subpath "/usr/lib"))

; System Framework and AppKit resources
(allow file-read* file-test-existence
  (subpath "/Library/Apple/System/Library/Frameworks")
  (subpath "/Library/Apple/System/Library/PrivateFrameworks")
  (subpath "/Library/Apple/usr/lib")
  (subpath "/System/Library/Frameworks")
  (subpath "/System/Library/PrivateFrameworks")
  (subpath "/System/Library/SubFrameworks")
  (subpath "/System/iOSSupport/System/Library/Frameworks")
  (subpath "/System/iOSSupport/System/Library/PrivateFrameworks")
  (subpath "/System/iOSSupport/System/Library/SubFrameworks")
  (subpath "/usr/lib"))

; Allow guarded vnodes.
(allow system-mac-syscall (mac-policy-name "vnguard"))

; Determine whether a container is expected.
(allow system-mac-syscall
  (require-all
    (mac-policy-name "Sandbox")
    (mac-syscall-number 67)))

; Allow resolution of standard system symlinks.
(allow file-read-metadata file-test-existence
  (literal "/etc")
  (literal "/tmp")
  (literal "/var")
  (literal "/private/etc/localtime"))

; Allow stat'ing of firmlink parent path components.
(allow file-read-metadata file-test-existence
  (path-ancestors "/System/Volumes/Data/private"))

; Allow processes to get their current working directory.
(allow file-read* file-test-existence
  (literal "/"))

; Allow FSIOC_CAS_BSDFLAGS as alternate chflags.
(allow system-fsctl (fsctl-command FSIOC_CAS_BSDFLAGS))

; Allow access to standard special files.
(allow file-read* file-test-existence
  (literal "/dev/autofs_nowait")
  (literal "/dev/random")
  (literal "/dev/urandom")
  (literal "/private/etc/master.passwd")
  (literal "/private/etc/passwd")
  (literal "/private/etc/protocols")
  (literal "/private/etc/services"))

; Allow null/zero read/write.
(allow file-read* file-test-existence file-write-data
  (literal "/dev/null")
  (literal "/dev/zero"))

; Allow read/write access to the file descriptors.
(allow file-read-data file-test-existence file-write-data
  (subpath "/dev/fd"))

; Provide access to debugger helpers.
(allow file-read* file-test-existence file-write-data file-ioctl
  (literal "/dev/dtracehelper"))

; Scratch space so tools can create temp files.
(allow file-read* file-test-existence file-write* (subpath "/tmp"))
(allow file-read* file-write* (subpath "/private/tmp"))
(allow file-read* file-write* (subpath "/var/tmp"))
(allow file-read* file-write* (subpath "/private/var/tmp"))

; Allow reading standard config directories.
(allow file-read* (subpath "/etc"))
(allow file-read* (subpath "/private/etc"))

(allow file-read* file-test-existence
  (literal "/System/Library/CoreServices")
  (literal "/System/Library/CoreServices/.SystemVersionPlatform.plist")
  (literal "/System/Library/CoreServices/SystemVersion.plist"))

; Some processes read /var metadata during startup.
(allow file-read-metadata (subpath "/var"))
(allow file-read-metadata (subpath "/private/var"))

; IOKit access for root domain services.
(allow iokit-open
  (iokit-registry-entry-class "RootDomainUserClient"))

; macOS Standard library queries opendirectoryd at startup
(allow mach-lookup (global-name "com.apple.system.opendirectoryd.libinfo"))

; Allow IPC to analytics, logging, trust, and other system agents.
(allow mach-lookup
  (global-name "com.apple.analyticsd")
  (global-name "com.apple.analyticsd.messagetracer")
  (global-name "com.apple.appsleep")
  (global-name "com.apple.bsd.dirhelper")
  (global-name "com.apple.cfprefsd.agent")
  (global-name "com.apple.cfprefsd.daemon")
  (global-name "com.apple.diagnosticd")
  (global-name "com.apple.dt.automationmode.reader")
  (global-name "com.apple.espd")
  (global-name "com.apple.logd")
  (global-name "com.apple.logd.events")
  (global-name "com.apple.runningboard")
  (global-name "com.apple.secinitd")
  (global-name "com.apple.system.DirectoryService.libinfo_v1")
  (global-name "com.apple.system.logger")
  (global-name "com.apple.system.notification_center")
  (global-name "com.apple.system.opendirectoryd.membership")
  (global-name "com.apple.trustd")
  (global-name "com.apple.trustd.agent")
  (global-name "com.apple.xpc.activity.unmanaged")
  (local-name "com.apple.cfprefsd.agent"))

; Allow IPC to the syslog socket for logging.
(allow network-outbound (literal "/private/var/run/syslog"))

; macOS Notifications
(allow ipc-posix-shm-read*
  (ipc-posix-name "apple.shm.notification_center"))

; Regulatory domain support.
(allow file-read*
  (literal "/private/var/db/eligibilityd/eligibility.plist"))

; Audio and power management services.
(allow mach-lookup (global-name "com.apple.audio.audiohald"))
(allow mach-lookup (global-name "com.apple.audio.AudioComponentRegistrar"))
(allow mach-lookup (global-name "com.apple.PowerManagement.control"))

; Allow reading the minimum system runtime so exec works.
(allow file-read-data (subpath "/bin"))
(allow file-read-metadata (subpath "/bin"))
(allow file-read-data (subpath "/sbin"))
(allow file-read-metadata (subpath "/sbin"))
(allow file-read-data (subpath "/usr/bin"))
(allow file-read-metadata (subpath "/usr/bin"))
(allow file-read-data (subpath "/usr/sbin"))
(allow file-read-metadata (subpath "/usr/sbin"))
(allow file-read-data (subpath "/usr/libexec"))
(allow file-read-metadata (subpath "/usr/libexec"))

(allow file-read* (subpath "/Library/Preferences"))
(allow file-read* (subpath "/opt/homebrew/lib"))
(allow file-read* (subpath "/usr/local/lib"))
(allow file-read* (subpath "/Applications"))

; Terminal basics and device handles.
(allow file-read* (regex "^/dev/fd/(0|1|2)$"))
(allow file-write* (regex "^/dev/fd/(1|2)$"))
(allow file-read* file-write* (literal "/dev/null"))
(allow file-read* file-write* (literal "/dev/tty"))
(allow file-read-metadata (literal "/dev"))
(allow file-read-metadata (regex "^/dev/.*$"))
(allow file-read-metadata (literal "/dev/stdin"))
(allow file-read-metadata (literal "/dev/stdout"))
(allow file-read-metadata (literal "/dev/stderr"))
(allow file-read-metadata (regex "^/dev/tty[^/]*$"))
(allow file-read-metadata (regex "^/dev/pty[^/]*$"))
(allow file-read* file-write* (regex "^/dev/ttys[0-9]+$"))
(allow file-read* file-write* (literal "/dev/ptmx"))
(allow file-ioctl (regex "^/dev/ttys[0-9]+$"))

; Allow metadata traversal for firmlink parents.
(allow file-read-metadata (literal "/System/Volumes") (vnode-type DIRECTORY))
(allow file-read-metadata (literal "/System/Volumes/Data") (vnode-type DIRECTORY))
(allow file-read-metadata (literal "/System/Volumes/Data/Users") (vnode-type DIRECTORY))

; App sandbox extensions
(allow file-read* (extension "com.apple.app-sandbox.read"))
(allow file-read* file-write* (extension "com.apple.app-sandbox.read-write"))
"""#

private let macOSSeatbeltNetworkPolicy = #"""
; when network access is enabled, these policies are added after those in seatbelt_base_policy.sbpl
; Ref https://source.chromium.org/chromium/chromium/src/+/main:sandbox/policy/mac/network.sb;drc=f8f264d5e4e7509c913f4c60c2639d15905a07e4

(allow network-outbound)
(allow network-inbound)
(allow system-socket)

(allow mach-lookup
    ; Used by platform helpers that resolve user directory locations.
    (global-name "com.apple.bsd.dirhelper")
    (global-name "com.apple.system.opendirectoryd.membership")

    ; Communicate with the security server for TLS certificate information.
    (global-name "com.apple.SecurityServer")
    (global-name "com.apple.networkd")
    (global-name "com.apple.ocspd")
    (global-name "com.apple.trustd.agent")

    ; Read network configuration.
    (global-name "com.apple.SystemConfiguration.DNSConfiguration")
    (global-name "com.apple.SystemConfiguration.configd")
)

(allow sysctl-read
  (sysctl-name-regex #"^net.routetable")
)
"""#
