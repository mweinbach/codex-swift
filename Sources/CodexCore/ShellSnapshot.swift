import Foundation

public final class ShellSnapshot {
    public static let directoryName = "shell_snapshots"

    static let snapshotTimeout: TimeInterval = 10
    static let retention: TimeInterval = 60 * 60 * 24 * 3
    static let excludedExportVariables = ["PWD", "OLDPWD"]

    public let path: URL
    public let cwd: URL

    public init(path: URL, cwd: URL) {
        self.path = path
        self.cwd = cwd
    }

    deinit {
        try? FileManager.default.removeItem(at: path)
    }

    public static func tryNew(codexHome: URL, sessionID: ThreadId, sessionCwd: URL, shell: Shell) throws -> ShellSnapshot {
        let fileExtension = shell.shellType == .powerShell ? "ps1" : "sh"
        let nonce = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let snapshotDirectory = codexHome.appendingPathComponent(directoryName, isDirectory: true)
        let path = snapshotDirectory.appendingPathComponent("\(sessionID).\(nonce).\(fileExtension)")
        let tempPath = snapshotDirectory.appendingPathComponent("\(sessionID).tmp-\(nonce)")

        try cleanupStaleSnapshots(codexHome: codexHome, activeSessionID: sessionID)

        do {
            try writeShellSnapshot(shellType: shell.shellType, outputPath: tempPath, cwd: sessionCwd)
            do {
                try validateSnapshot(shell: shell, snapshotPath: tempPath, cwd: sessionCwd)
            } catch {
                throw ShellSnapshotError.validationFailed(underlyingDescription: String(describing: error))
            }
            try FileManager.default.moveItem(at: tempPath, to: path)
            return ShellSnapshot(path: path, cwd: sessionCwd)
        } catch let error as ShellSnapshotError {
            try? FileManager.default.removeItem(at: tempPath)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempPath)
            throw ShellSnapshotError.writeFailed(underlying: error)
        }
    }

    public static func writeShellSnapshot(shellType: ShellType, outputPath: URL, cwd: URL) throws {
        guard shellType != .powerShell, shellType != .cmd else {
            throw ShellSnapshotError.unsupportedShell(shellType)
        }
        guard let shell = ShellResolver.getShell(shellType) else {
            throw ShellSnapshotError.noAvailableShell(shellType)
        }

        let rawSnapshot = try captureSnapshot(shell: shell, cwd: cwd)
        let snapshot = try stripSnapshotPreamble(rawSnapshot)
        let parent = outputPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try snapshot.write(to: outputPath, atomically: true, encoding: .utf8)
    }

    static func captureSnapshot(shell: Shell, cwd: URL) throws -> String {
        switch shell.shellType {
        case .zsh:
            return try runShellScript(shell: shell, script: zshSnapshotScript(), cwd: cwd)
        case .bash:
            return try runShellScript(shell: shell, script: bashSnapshotScript(), cwd: cwd)
        case .sh:
            return try runShellScript(shell: shell, script: shSnapshotScript(), cwd: cwd)
        case .powerShell:
            return try runShellScript(shell: shell, script: powerShellSnapshotScript(), cwd: cwd)
        case .cmd:
            throw ShellSnapshotError.unsupportedShell(shell.shellType)
        }
    }

    public static func stripSnapshotPreamble(_ snapshot: String) throws -> String {
        let marker = "# Snapshot file"
        guard let range = snapshot.range(of: marker) else {
            throw ShellSnapshotError.missingMarker(marker)
        }
        return String(snapshot[range.lowerBound...])
    }

    static func validateSnapshot(shell: Shell, snapshotPath: URL, cwd: URL) throws {
        let script = #"set -e; . "\#(snapshotPath.path)""#
        _ = try runScriptWithTimeout(shell: shell, script: script, timeout: snapshotTimeout, useLoginShell: false, cwd: cwd)
    }

    static func runShellScript(shell: Shell, script: String, cwd: URL) throws -> String {
        try runScriptWithTimeout(shell: shell, script: script, timeout: snapshotTimeout, useLoginShell: true, cwd: cwd)
    }

    static func runScriptWithTimeout(
        shell: Shell,
        script: String,
        timeout: TimeInterval,
        useLoginShell: Bool,
        cwd: URL
    ) throws -> String {
        let args = shell.deriveExecArgs(command: script, useLoginShell: useLoginShell)
        guard let executable = args.first else {
            throw ShellSnapshotError.executionFailed("missing shell executable")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(args.dropFirst())
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let output = LockedProcessOutput()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            output.appendStdout(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            output.appendStderr(handle.availableData)
        }
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning {
                process.interrupt()
            }
            throw ShellSnapshotError.timedOut(shell.name)
        }

        output.appendStdout(stdout.fileHandleForReading.availableData)
        output.appendStderr(stderr.fileHandleForReading.availableData)
        guard process.terminationStatus == 0 else {
            let stderrText = String(decoding: output.stderrData, as: UTF8.self)
            throw ShellSnapshotError.nonZeroExit(status: process.terminationStatus, stderr: stderrText)
        }
        return String(decoding: output.stdoutData, as: UTF8.self)
    }

    public static func cleanupStaleSnapshots(codexHome: URL, activeSessionID: ThreadId) throws {
        let snapshotDirectory = codexHome.appendingPathComponent(directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: snapshotDirectory.path) else {
            return
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )

        let now = Date()
        for entry in entries {
            let resourceValues = try entry.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }
            guard let sessionID = snapshotSessionID(fromFileName: entry.lastPathComponent) else {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            if sessionID == activeSessionID.description {
                continue
            }
            guard let rolloutPath = try RolloutListing.findConversationPathByIDString(codexHome: codexHome, idString: sessionID) else {
                try? FileManager.default.removeItem(at: entry)
                continue
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: rolloutPath)
            guard let modifiedAt = attributes[.modificationDate] as? Date else {
                continue
            }
            if now.timeIntervalSince(modifiedAt) >= retention {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    public static func snapshotSessionID(fromFileName fileName: String) -> String? {
        guard let dotIndex = fileName.lastIndex(of: ".") else {
            return nil
        }
        let stem = String(fileName[..<dotIndex])
        let fileExtension = String(fileName[fileName.index(after: dotIndex)...])
        switch fileExtension {
        case "sh", "ps1":
            return stem.split(separator: ".", maxSplits: 1).first.map(String.init)
        case let suffix where suffix.hasPrefix("tmp-"):
            return stem
        default:
            return nil
        }
    }

    static func zshSnapshotScript() -> String {
        let excluded = excludedExportsRegex()
        let script = ##"""
if [[ -n "$ZDOTDIR" ]]; then
  rc="$ZDOTDIR/.zshrc"
else
  rc="$HOME/.zshrc"
fi
[[ -r "$rc" ]] && . "$rc"
print '# Snapshot file'
print '# Unset all aliases to avoid conflicts with functions'
print 'unalias -a 2>/dev/null || true'
print '# Functions'
functions
print ''
setopt_count=$(setopt | wc -l | tr -d ' ')
print "# setopts $setopt_count"
setopt | sed 's/^/setopt /'
print ''
alias_count=$(alias -L | wc -l | tr -d ' ')
print "# aliases $alias_count"
alias -L
print ''
export_lines=$(export -p | awk '
/^(export|declare -x|typeset -x) / {
  line=$0
  name=line
  sub(/^(export|declare -x|typeset -x) /, "", name)
  sub(/=.*/, "", name)
  if (name ~ /^(EXCLUDED_EXPORTS)$/) {
    next
  }
  if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
    print line
  }
}')
export_count=$(printf '%s\n' "$export_lines" | sed '/^$/d' | wc -l | tr -d ' ')
print "# exports $export_count"
if [[ -n "$export_lines" ]]; then
  print -r -- "$export_lines"
fi
"""##
        return script.replacingOccurrences(of: "EXCLUDED_EXPORTS", with: excluded)
    }

    static func bashSnapshotScript() -> String {
        let excluded = excludedExportsRegex()
        let script = ##"""
if [ -z "$BASH_ENV" ] && [ -r "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
echo '# Snapshot file'
echo '# Unset all aliases to avoid conflicts with functions'
unalias -a 2>/dev/null || true
echo '# Functions'
declare -f
echo ''
bash_opts=$(set -o | awk '$2=="on"{print $1}')
bash_opt_count=$(printf '%s\n' "$bash_opts" | sed '/^$/d' | wc -l | tr -d ' ')
echo "# setopts $bash_opt_count"
if [ -n "$bash_opts" ]; then
  printf 'set -o %s\n' $bash_opts
fi
echo ''
alias_count=$(alias -p | wc -l | tr -d ' ')
echo "# aliases $alias_count"
alias -p
echo ''
export_lines=$(
  while IFS= read -r name; do
    if [[ "$name" =~ ^(EXCLUDED_EXPORTS)$ ]]; then
      continue
    fi
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      continue
    fi
    declare -xp "$name" 2>/dev/null || true
  done < <(compgen -e)
)
export_count=$(printf '%s\n' "$export_lines" | sed '/^$/d' | wc -l | tr -d ' ')
echo "# exports $export_count"
if [ -n "$export_lines" ]; then
  printf '%s\n' "$export_lines"
fi
"""##
        return script.replacingOccurrences(of: "EXCLUDED_EXPORTS", with: excluded)
    }

    static func shSnapshotScript() -> String {
        let excluded = excludedExportsRegex()
        let script = ##"""
if [ -n "$ENV" ] && [ -r "$ENV" ]; then
  . "$ENV"
fi
echo '# Snapshot file'
echo '# Unset all aliases to avoid conflicts with functions'
unalias -a 2>/dev/null || true
echo '# Functions'
if command -v typeset >/dev/null 2>&1; then
  typeset -f
elif command -v declare >/dev/null 2>&1; then
  declare -f
fi
echo ''
if set -o >/dev/null 2>&1; then
  sh_opts=$(set -o | awk '$2=="on"{print $1}')
  sh_opt_count=$(printf '%s\n' "$sh_opts" | sed '/^$/d' | wc -l | tr -d ' ')
  echo "# setopts $sh_opt_count"
  if [ -n "$sh_opts" ]; then
    printf 'set -o %s\n' $sh_opts
  fi
else
  echo '# setopts 0'
fi
echo ''
if alias >/dev/null 2>&1; then
  alias_count=$(alias | wc -l | tr -d ' ')
  echo "# aliases $alias_count"
  alias
  echo ''
else
  echo '# aliases 0'
fi
if export -p >/dev/null 2>&1; then
  export_lines=$(export -p | awk '
/^(export|declare -x|typeset -x) / {
  line=$0
  name=line
  sub(/^(export|declare -x|typeset -x) /, "", name)
  sub(/=.*/, "", name)
  if (name ~ /^(EXCLUDED_EXPORTS)$/) {
    next
  }
  if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
    print line
  }
}')
  export_count=$(printf '%s\n' "$export_lines" | sed '/^$/d' | wc -l | tr -d ' ')
  echo "# exports $export_count"
  if [ -n "$export_lines" ]; then
    printf '%s\n' "$export_lines"
  fi
else
  export_count=$(env | sort | awk -F= '$1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ { count++ } END { print count }')
  echo "# exports $export_count"
  env | sort | while IFS='=' read -r key value; do
    case "$key" in
      ""|[0-9]*|*[!A-Za-z0-9_]*|EXCLUDED_EXPORTS) continue ;;
    esac
    escaped=$(printf "%s" "$value" | sed "s/'/'\"'\"'/g")
    printf "export %s='%s'\n" "$key" "$escaped"
  done
fi
"""##
        return script.replacingOccurrences(of: "EXCLUDED_EXPORTS", with: excluded)
    }

    static func powerShellSnapshotScript() -> String {
        ##"""
$ErrorActionPreference = 'Stop'
Write-Output '# Snapshot file'
Write-Output '# Unset all aliases to avoid conflicts with functions'
Write-Output 'Remove-Item Alias:* -ErrorAction SilentlyContinue'
Write-Output '# Functions'
Get-ChildItem Function: | ForEach-Object {
    "function {0} {{`n{1}`n}}" -f $_.Name, $_.Definition
}
Write-Output ''
$aliases = Get-Alias
Write-Output ("# aliases " + $aliases.Count)
$aliases | ForEach-Object {
    "Set-Alias -Name {0} -Value {1}" -f $_.Name, $_.Definition
}
Write-Output ''
$envVars = Get-ChildItem Env:
Write-Output ("# exports " + $envVars.Count)
$envVars | ForEach-Object {
    $escaped = $_.Value -replace "'", "''"
    "`$env:{0}='{1}'" -f $_.Name, $escaped
}
"""##
    }

    static func excludedExportsRegex() -> String {
        excludedExportVariables.joined(separator: "|")
    }
}

// Process readability handlers can run concurrently on Foundation-managed queues;
// the lock is the invariant that makes the narrow unchecked Sendable capture safe.
private final class LockedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    var stdoutData: Data {
        lock.withLock { stdout }
    }

    var stderrData: Data {
        lock.withLock { stderr }
    }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.withLock {
            stdout.append(data)
        }
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.withLock {
            stderr.append(data)
        }
    }
}

public enum ShellSnapshotError: Error, Equatable, CustomStringConvertible {
    case unsupportedShell(ShellType)
    case noAvailableShell(ShellType)
    case missingMarker(String)
    case executionFailed(String)
    case timedOut(String)
    case nonZeroExit(status: Int32, stderr: String)
    case validationFailed(underlyingDescription: String)
    case writeFailed(underlyingDescription: String)

    public static func == (lhs: ShellSnapshotError, rhs: ShellSnapshotError) -> Bool {
        lhs.description == rhs.description
    }

    static func writeFailed(underlying: Error) -> ShellSnapshotError {
        .writeFailed(underlyingDescription: String(describing: underlying))
    }

    public var description: String {
        switch self {
        case let .unsupportedShell(shellType):
            return "Shell snapshot not supported yet for \(shellType)"
        case let .noAvailableShell(shellType):
            return "No available shell for \(shellType)"
        case let .missingMarker(marker):
            return "Snapshot output missing marker \(marker)"
        case let .executionFailed(message):
            return message
        case let .timedOut(shellName):
            return "Snapshot command timed out for \(shellName)"
        case let .nonZeroExit(status, stderr):
            return "Snapshot command exited with status \(status): \(stderr)"
        case let .validationFailed(underlyingDescription):
            return "Shell snapshot validation failed: \(underlyingDescription)"
        case let .writeFailed(underlyingDescription):
            return "Failed to create shell snapshot: \(underlyingDescription)"
        }
    }
}
