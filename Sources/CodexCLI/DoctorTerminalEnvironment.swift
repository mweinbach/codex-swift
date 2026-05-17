import CodexCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

public struct DoctorTerminalSize: Equatable, Sendable {
    public let columns: UInt16
    public let rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}

public enum DoctorTerminalSizeProbe: Equatable, Sendable {
    case available(DoctorTerminalSize)
    case unavailable(String)
}

public struct DoctorTerminalCheckInputs: Sendable {
    public let terminalInfo: TerminalInfo
    public let environment: [String: String]
    public let presentEnvironment: Set<String>
    public let noColorFlag: Bool
    public let stdinIsTerminal: Bool
    public let stdoutIsTerminal: Bool
    public let stderrIsTerminal: Bool
    public let streamSupportsColor: Bool
    public let terminalSize: DoctorTerminalSizeProbe
    public let tmuxDetails: [String]

    public init(
        terminalInfo: TerminalInfo,
        environment: [String: String],
        presentEnvironment: Set<String>,
        noColorFlag: Bool,
        stdinIsTerminal: Bool,
        stdoutIsTerminal: Bool,
        stderrIsTerminal: Bool,
        streamSupportsColor: Bool,
        terminalSize: DoctorTerminalSizeProbe,
        tmuxDetails: [String] = []
    ) {
        self.terminalInfo = terminalInfo
        self.environment = environment
        self.presentEnvironment = presentEnvironment
        self.noColorFlag = noColorFlag
        self.stdinIsTerminal = stdinIsTerminal
        self.stdoutIsTerminal = stdoutIsTerminal
        self.stderrIsTerminal = stderrIsTerminal
        self.streamSupportsColor = streamSupportsColor
        self.terminalSize = terminalSize
        self.tmuxDetails = tmuxDetails
    }

    public static func detect(
        noColorFlag: Bool,
        environment rawEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DoctorTerminalCheckInputs {
        var environment: [String: String] = [:]
        var presentEnvironment = Set<String>()
        for name in DoctorCommandRuntime.terminalEnvironmentNames {
            guard let rawValue = rawEnvironment[name] else { continue }
            presentEnvironment.insert(name)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                environment[name] = value
            }
        }

        let info = Terminal.terminalInfo(environment: rawEnvironment)
        let stdoutIsTerminal = DoctorCommandRuntime.standardOutputIsTerminal
        return DoctorTerminalCheckInputs(
            terminalInfo: info,
            environment: environment,
            presentEnvironment: presentEnvironment,
            noColorFlag: noColorFlag,
            stdinIsTerminal: DoctorCommandRuntime.standardInputIsTerminal,
            stdoutIsTerminal: stdoutIsTerminal,
            stderrIsTerminal: DoctorCommandRuntime.standardErrorIsTerminal,
            streamSupportsColor: DoctorCommandRuntime.streamSupportsColor(
                environment: environment,
                stdoutIsTerminal: stdoutIsTerminal
            ),
            terminalSize: DoctorCommandRuntime.detectTerminalSize(environment: environment),
            tmuxDetails: []
        )
    }
}

extension DoctorCommandRuntime {
    public static func terminalEnvironmentCheck(
        noColorFlag: Bool,
        inputs: DoctorTerminalCheckInputs? = nil
    ) -> DoctorCheck {
        let inputs = inputs ?? DoctorTerminalCheckInputs.detect(noColorFlag: noColorFlag)
        let info = inputs.terminalInfo
        var details = ["terminal: \(terminalName(info))"]
        if let termProgram = info.termProgram {
            details.append("TERM_PROGRAM: \(termProgram)")
        }
        if let version = info.version {
            details.append("terminal version: \(version)")
        }
        if let term = info.term {
            details.append("TERM: \(term)")
        }
        if let multiplexer = info.multiplexer {
            details.append("multiplexer: \(multiplexerName(multiplexer))")
        }
        details.append("stdin is terminal: \(inputs.stdinIsTerminal)")
        details.append("stdout is terminal: \(inputs.stdoutIsTerminal)")
        details.append("stderr is terminal: \(inputs.stderrIsTerminal)")
        switch inputs.terminalSize {
        case let .available(size):
            details.append("terminal size: \(size.columns)x\(size.rows)")
        case let .unavailable(error):
            details.append("terminal size: unavailable (\(error))")
        }
        pushTerminalEnvironmentValues(&details, inputs: inputs, names: terminalDimensionEnvironmentVariables)
        details.append("color output: \(colorOutputSummary(inputs))")
        pushTerminalEnvironmentValues(&details, inputs: inputs, names: colorEnvironmentVariables)
        let terminfoWarning = pushTerminfoDetails(&details, inputs: inputs)
        if let locale = effectiveLocale(inputs) {
            details.append("effective locale: \(locale)")
        }
        pushPresenceEnvironmentValues(&details, inputs: inputs, names: remoteTerminalEnvironmentVariables)
        details.append(contentsOf: inputs.tmuxDetails)

        var issues: [DoctorIssue] = []
        if info.name == .dumb {
            issues.append(DoctorIssue(
                severity: .fail,
                cause: "TERM=dumb - colors and cursor control are disabled",
                measured: "TERM=dumb",
                expected: "TERM=xterm-256color or another real terminal type",
                remedy: "set TERM to a real value, for example xterm-256color",
                fields: ["TERM"]
            ))
        }
        if let locale = effectiveLocale(inputs), isNonUTF8Locale(locale) {
            issues.append(DoctorIssue(
                severity: .warning,
                cause: "locale is not UTF-8 - unicode glyphs may render incorrectly",
                measured: locale,
                expected: "UTF-8 locale, for example en_US.UTF-8",
                remedy: "export LANG=en_US.UTF-8 or another UTF-8 locale",
                fields: ["effective locale"]
            ))
        }
        if terminfoWarning {
            issues.append(DoctorIssue(
                severity: .fail,
                cause: "TERMINFO unreadable - terminal capabilities are unknown",
                expected: "readable terminfo file or directory",
                remedy: "check that $TERMINFO points to a readable directory",
                fields: ["TERMINFO", "TERMINFO_DIRS entry"]
            ))
        }
        issues.append(contentsOf: terminalSizeIssues(inputs))

        let status = issues.reduce(DoctorCheckStatus.ok) { current, issue in
            if current == .fail || issue.severity == .fail {
                return .fail
            }
            if current == .warning || issue.severity == .warning {
                return .warning
            }
            return .ok
        }
        return DoctorCheck(
            id: "terminal.env",
            category: "terminal",
            status: status,
            summary: issues.first?.cause ?? "terminal metadata was detected",
            details: details,
            issues: issues
        )
    }

    fileprivate static let colorEnvironmentVariables = [
        "COLORTERM",
        "NO_COLOR",
        "CLICOLOR",
        "CLICOLOR_FORCE",
        "FORCE_COLOR",
        "COLORFGBG"
    ]

    fileprivate static let terminalDimensionEnvironmentVariables = ["COLUMNS", "LINES"]
    fileprivate static let terminfoEnvironmentVariables = ["TERMINFO", "TERMINFO_DIRS"]
    fileprivate static let localeEnvironmentVariables = ["LC_ALL", "LC_CTYPE", "LANG"]
    fileprivate static let remoteTerminalEnvironmentVariables = [
        "SSH_TTY",
        "SSH_CONNECTION",
        "SSH_CLIENT",
        "MOSH_IP",
        "WSL_DISTRO_NAME",
        "WSL_INTEROP",
        "VSCODE_INJECTION",
        "VSCODE_IPC_HOOK_CLI",
        "WAYLAND_DISPLAY",
        "DISPLAY",
        "WT_SESSION"
    ]

    fileprivate static var terminalEnvironmentNames: Set<String> {
        var names = Set(["TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"])
        names.formUnion(colorEnvironmentVariables)
        names.formUnion(terminalDimensionEnvironmentVariables)
        names.formUnion(terminfoEnvironmentVariables)
        names.formUnion(localeEnvironmentVariables)
        names.formUnion(remoteTerminalEnvironmentVariables)
        return names
    }

    fileprivate static func streamSupportsColor(environment: [String: String], stdoutIsTerminal: Bool) -> Bool {
        if !stdoutIsTerminal {
            return false
        }
        if environment["NO_COLOR"] != nil || environment["TERM"] == "dumb" {
            return false
        }
        return environment["COLORTERM"] != nil
            || environment["CLICOLOR_FORCE"] != nil
            || environment["FORCE_COLOR"] != nil
            || environment["TERM"]?.contains("color") == true
            || environment["TERM_PROGRAM"] != nil
    }

    fileprivate static func detectTerminalSize(environment: [String: String]) -> DoctorTerminalSizeProbe {
        if let columns = environment["COLUMNS"].flatMap(UInt16.init),
           let rows = environment["LINES"].flatMap(UInt16.init)
        {
            return .available(DoctorTerminalSize(columns: columns, rows: rows))
        }
        return .unavailable("terminal size unavailable")
    }

    fileprivate static var standardInputIsTerminal: Bool {
        #if canImport(Darwin) || canImport(Glibc)
            isatty(STDIN_FILENO) != 0
        #else
            false
        #endif
    }

    fileprivate static var standardOutputIsTerminal: Bool {
        #if canImport(Darwin) || canImport(Glibc)
            isatty(STDOUT_FILENO) != 0
        #else
            false
        #endif
    }

    fileprivate static var standardErrorIsTerminal: Bool {
        #if canImport(Darwin) || canImport(Glibc)
            isatty(STDERR_FILENO) != 0
        #else
            false
        #endif
    }

    private static func terminalName(_ info: TerminalInfo) -> String {
        switch info.name {
        case .appleTerminal:
            return "Apple Terminal"
        case .ghostty:
            return "Ghostty"
        case .iterm2:
            return "iTerm2"
        case .warpTerminal:
            return "Warp"
        case .vsCode:
            return "VS Code"
        case .wezTerm:
            return "WezTerm"
        case .kitty:
            return "kitty"
        case .alacritty:
            return "Alacritty"
        case .konsole:
            return "Konsole"
        case .gnomeTerminal:
            return "GNOME Terminal"
        case .vte:
            return "VTE"
        case .windowsTerminal:
            return "Windows Terminal"
        case .dumb:
            return "dumb"
        case .unknown:
            return "unknown"
        }
    }

    private static func multiplexerName(_ multiplexer: TerminalMultiplexer) -> String {
        switch multiplexer {
        case let .tmux(version):
            if let version {
                return "tmux \(version)"
            }
            return "tmux"
        case let .zellij(version):
            if let version {
                return "zellij \(version)"
            }
            return "zellij"
        }
    }

    private static func pushTerminalEnvironmentValues(
        _ details: inout [String],
        inputs: DoctorTerminalCheckInputs,
        names: [String]
    ) {
        for name in names {
            if let value = inputs.environment[name] {
                details.append("\(name): \(value)")
            } else if inputs.presentEnvironment.contains(name) {
                details.append("\(name): present")
            }
        }
    }

    private static func pushPresenceEnvironmentValues(
        _ details: inout [String],
        inputs: DoctorTerminalCheckInputs,
        names: [String]
    ) {
        for name in names where inputs.presentEnvironment.contains(name) {
            details.append("\(name): present")
        }
    }

    private static func colorOutputSummary(_ inputs: DoctorTerminalCheckInputs) -> String {
        if shouldEnableColor(inputs) {
            return "enabled"
        }
        let reason: String
        if inputs.noColorFlag {
            reason = "--no-color"
        } else if inputs.presentEnvironment.contains("NO_COLOR") {
            reason = "NO_COLOR"
        } else if inputs.environment["TERM"] == "dumb" {
            reason = "TERM=dumb"
        } else if !inputs.stdoutIsTerminal {
            reason = "stdout is not a terminal"
        } else if !inputs.streamSupportsColor {
            reason = "terminal color support not detected"
        } else {
            reason = "disabled"
        }
        return "disabled (\(reason))"
    }

    private static func shouldEnableColor(_ inputs: DoctorTerminalCheckInputs) -> Bool {
        !inputs.noColorFlag
            && !inputs.presentEnvironment.contains("NO_COLOR")
            && inputs.environment["TERM"] != "dumb"
            && inputs.stdoutIsTerminal
            && inputs.streamSupportsColor
    }

    private static func pushTerminfoDetails(
        _ details: inout [String],
        inputs: DoctorTerminalCheckInputs
    ) -> Bool {
        var hasWarning = false
        if let raw = inputs.environment["TERMINFO"] {
            let status = terminalPathReadiness(URL(fileURLWithPath: raw))
            details.append("TERMINFO: \(raw) (\(status.description))")
            hasWarning = hasWarning || status.warning
        }
        if let raw = inputs.environment["TERMINFO_DIRS"] {
            for path in raw.split(separator: pathListSeparator).map(String.init) where !path.isEmpty {
                let status = terminalPathReadiness(URL(fileURLWithPath: path))
                details.append("TERMINFO_DIRS entry: \(path) (\(status.description))")
                hasWarning = hasWarning || status.warning
            }
        } else if inputs.presentEnvironment.contains("TERMINFO_DIRS") {
            details.append("TERMINFO_DIRS: present")
        }
        return hasWarning
    }

    private static var pathListSeparator: Character {
        #if os(Windows)
            ";"
        #else
            ":"
        #endif
    }

    private static func terminalPathReadiness(_ url: URL) -> (description: String, warning: Bool) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                do {
                    _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                    return ("dir", false)
                } catch {
                    return ("dir unreadable: \(error.localizedDescription)", true)
                }
            }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                _ = try handle.read(upToCount: 1)
                try handle.close()
                return ("file", false)
            } catch {
                return ("file unreadable: \(error.localizedDescription)", true)
            }
        }
        return ("missing", true)
    }

    private static func effectiveLocale(_ inputs: DoctorTerminalCheckInputs) -> String? {
        localeEnvironmentVariables.compactMap { inputs.environment[$0] }.first
    }

    private static func isNonUTF8Locale(_ locale: String) -> Bool {
        let lowercased = locale.lowercased()
        return !lowercased.contains("utf-8") && !lowercased.contains("utf8")
    }

    private static func terminalSizeIssues(_ inputs: DoctorTerminalCheckInputs) -> [DoctorIssue] {
        var issues: [DoctorIssue] = []
        if case let .available(size) = inputs.terminalSize {
            if size.columns > 0 && size.columns < 80 {
                issues.append(DoctorIssue(
                    severity: .warning,
                    cause: "width \(size.columns) cols - output may wrap (recommended >=80)",
                    measured: "\(size.columns) x \(size.rows)",
                    expected: ">= 80 columns",
                    remedy: "resize the window to at least 80 columns",
                    fields: ["terminal size"]
                ))
            }
            if size.rows > 0 && size.rows < 24 {
                issues.append(DoctorIssue(
                    severity: .warning,
                    cause: "height \(size.rows) rows - content may scroll off (recommended >=24)",
                    measured: "\(size.columns) x \(size.rows)",
                    expected: ">= 24 rows",
                    remedy: "resize the window to at least 24 rows",
                    fields: ["terminal size"]
                ))
            }
        }

        if let columns = inputs.environment["COLUMNS"].flatMap(UInt16.init), columns > 0 && columns < 80 {
            issues.append(DoctorIssue(
                severity: .warning,
                cause: "COLUMNS=\(columns) - output may wrap (recommended >=80)",
                measured: "\(columns) columns",
                expected: ">= 80 columns",
                remedy: "resize the window to at least 80 columns",
                fields: ["COLUMNS"]
            ))
        }
        if let rows = inputs.environment["LINES"].flatMap(UInt16.init), rows > 0 && rows < 24 {
            issues.append(DoctorIssue(
                severity: .warning,
                cause: "LINES=\(rows) - content may scroll off (recommended >=24)",
                measured: "\(rows) rows",
                expected: ">= 24 rows",
                remedy: "resize the window to at least 24 rows",
                fields: ["LINES"]
            ))
        }
        return issues
    }
}
