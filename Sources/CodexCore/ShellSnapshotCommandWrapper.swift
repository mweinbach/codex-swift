import Foundation

public enum ShellSnapshotCommandWrapper {
    public static let proxyActiveEnvKey = "CODEX_NETWORK_PROXY_ACTIVE"
    public static let proxyGitSSHCommandEnvKey = "GIT_SSH_COMMAND"
    public static let codexProxyGitSSHCommandMarker = "CODEX_PROXY_GIT_SSH_COMMAND=1 "
    public static let proxyEnvKeys = [
        proxyActiveEnvKey,
        "CODEX_NETWORK_ALLOW_LOCAL_BINDING",
        "ELECTRON_GET_USE_PROXY",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "http_proxy",
        "https_proxy",
        "YARN_HTTP_PROXY",
        "YARN_HTTPS_PROXY",
        "npm_config_http_proxy",
        "npm_config_https_proxy",
        "npm_config_proxy",
        "NPM_CONFIG_HTTP_PROXY",
        "NPM_CONFIG_HTTPS_PROXY",
        "NPM_CONFIG_PROXY",
        "BUNDLE_HTTP_PROXY",
        "BUNDLE_HTTPS_PROXY",
        "PIP_PROXY",
        "DOCKER_HTTP_PROXY",
        "DOCKER_HTTPS_PROXY",
        "WS_PROXY",
        "WSS_PROXY",
        "ws_proxy",
        "wss_proxy",
        "NO_PROXY",
        "no_proxy",
        "npm_config_noproxy",
        "NPM_CONFIG_NOPROXY",
        "YARN_NO_PROXY",
        "BUNDLE_NO_PROXY",
        "ALL_PROXY",
        "all_proxy",
        "FTP_PROXY",
        "ftp_proxy"
    ]

    public static func maybeWrapShellLCWithSnapshot(
        command: [String],
        sessionShell: Shell,
        cwd: URL,
        explicitEnvOverrides: [String: String],
        environment: [String: String]
    ) -> [String] {
        #if os(Windows)
        return command
        #else
        guard let snapshot = sessionShell.shellSnapshot,
              FileManager.default.fileExists(atPath: snapshot.path.path),
              pathsMatchAfterNormalization(snapshot.cwd, cwd),
              command.count >= 3,
              command[1] == "-lc"
        else {
            return command
        }

        let snapshotPath = shellSingleQuote(snapshot.path.path)
        let originalShell = shellSingleQuote(command[0])
        let originalScript = shellSingleQuote(command[2])
        let trailingArgs = command.dropFirst(3)
            .map { " '\(shellSingleQuote($0))'" }
            .joined()

        var overrideEnv = explicitEnvOverrides
        if let threadID = environment["CODEX_THREAD_ID"] {
            overrideEnv["CODEX_THREAD_ID"] = threadID
        }
        let (overrideCaptures, overrideExports) = buildOverrideExports(overrideEnv)
        let (proxyCaptures, proxyExports) = buildProxyEnvExports()
        let captures = joinShellBlocks([overrideCaptures, proxyCaptures])
        let exports = joinShellBlocks([overrideExports, proxyExports])

        let rewrittenScript: String
        if exports.isEmpty {
            rewrittenScript = """
            if . '\(snapshotPath)' >/dev/null 2>&1; then :; fi

            exec '\(originalShell)' -c '\(originalScript)'\(trailingArgs)
            """
        } else {
            rewrittenScript = """
            \(captures)

            if . '\(snapshotPath)' >/dev/null 2>&1; then :; fi

            \(exports)

            exec '\(originalShell)' -c '\(originalScript)'\(trailingArgs)
            """
        }

        return [sessionShell.shellPath, "-c", rewrittenScript]
        #endif
    }

    static func shellSingleQuote(_ input: String) -> String {
        input.replacingOccurrences(of: "'", with: #"'"'"'"#)
    }

    private static func pathsMatchAfterNormalization(_ left: URL, _ right: URL) -> Bool {
        normalizedPath(left) == normalizedPath(right)
    }

    private static func normalizedPath(_ url: URL) -> String {
        if let normalized = try? PathUtils.normalizeForPathComparison(url.path) {
            return normalized
        }
        return PathUtils.normalizeForWSLComparisonPath(url.standardizedFileURL.path)
    }

    private static func buildOverrideExports(_ explicitEnvOverrides: [String: String]) -> (String, String) {
        let keys = explicitEnvOverrides.keys
            .filter(isValidShellVariableName)
            .sorted()
        return buildOverrideExportsForKeys(variablePrefix: "__CODEX_SNAPSHOT_OVERRIDE", keys: keys)
    }

    private static func buildProxyEnvExports() -> (String, String) {
        let keys = Array(Set(proxyEnvKeys.filter(isValidShellVariableName))).sorted()
        let (captures, restores) = buildOverrideExportsForKeys(
            variablePrefix: "__CODEX_SNAPSHOT_PROXY_OVERRIDE",
            keys: keys
        )
        let proxyBlocks = (
            "\(captures)\n__CODEX_SNAPSHOT_PROXY_ENV_SET=\"${\(proxyActiveEnvKey)+x}\"",
            """
            if [ -n "$__CODEX_SNAPSHOT_PROXY_ENV_SET" ] || [ -n "${\(proxyActiveEnvKey)+x}" ]; then
            \(restores)
            fi
            """
        )
        let gitBlocks = buildCodexProxyGitSSHCommandExports()
        return (
            joinShellBlocks([proxyBlocks.0, gitBlocks.0]),
            joinShellBlocks([proxyBlocks.1, gitBlocks.1])
        )
    }

    private static func buildCodexProxyGitSSHCommandExports() -> (String, String) {
        #if os(macOS)
        let key = proxyGitSSHCommandEnvKey
        let markerPattern = "\(codexProxyGitSSHCommandMarker.trimmingCharacters(in: .whitespaces))\\ *"
        return (
            """
            __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_SET="${\(key)+x}"
            __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND="${\(key)-}"
            case "$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND" in
              \(markerPattern)) __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_LIVE_MARKED=1 ;;
              *) __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_LIVE_MARKED= ;;
            esac
            """,
            """
            case "${\(key)-}" in
              \(markerPattern)) __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_AFTER_MARKED=1 ;;
              *) __CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_AFTER_MARKED= ;;
            esac
            if [ -n "$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_LIVE_MARKED" ]; then
              if [ -z "${\(key)+x}" ] || [ -n "$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_AFTER_MARKED" ]; then
                export \(key)="$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND"
              fi
            elif [ -n "$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_AFTER_MARKED" ]; then
              if [ -n "$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND_SET" ]; then
                export \(key)="$__CODEX_SNAPSHOT_PROXY_GIT_SSH_COMMAND"
              else
                unset \(key)
              fi
            fi
            """
        )
        #else
        return ("", "")
        #endif
    }

    private static func buildOverrideExportsForKeys(variablePrefix: String, keys: [String]) -> (String, String) {
        guard !keys.isEmpty else {
            return ("", "")
        }
        let captures = keys.enumerated().map { index, key in
            let setVar = "\(variablePrefix)_SET_\(index)"
            let valueVar = "\(variablePrefix)_\(index)"
            return "\(setVar)=\"${\(key)+x}\"\n\(valueVar)=\"${\(key)-}\""
        }.joined(separator: "\n")
        let restores = keys.enumerated().map { index, key in
            let setVar = "\(variablePrefix)_SET_\(index)"
            let valueVar = "\(variablePrefix)_\(index)"
            return "if [ -n \"${\(setVar)}\" ]; then export \(key)=\"${\(valueVar)}\"; else unset \(key); fi"
        }.joined(separator: "\n")
        return (captures, restores)
    }

    private static func joinShellBlocks(_ blocks: [String]) -> String {
        blocks.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func isValidShellVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else {
            return false
        }
        guard (first == "_" || CharacterSet.letters.contains(first)) && first.isASCII else {
            return false
        }
        return name.unicodeScalars.allSatisfy { scalar in
            (scalar == "_" || CharacterSet.alphanumerics.contains(scalar)) && scalar.isASCII
        }
    }
}
