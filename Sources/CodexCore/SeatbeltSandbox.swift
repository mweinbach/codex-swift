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
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
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
