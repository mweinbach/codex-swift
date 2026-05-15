import Foundation

public struct TerminalInfo: Equatable, Sendable {
    public let name: TerminalName
    public let termProgram: String?
    public let version: String?
    public let term: String?
    public let multiplexer: TerminalMultiplexer?

    public init(
        name: TerminalName,
        termProgram: String? = nil,
        version: String? = nil,
        term: String? = nil,
        multiplexer: TerminalMultiplexer? = nil
    ) {
        self.name = name
        self.termProgram = termProgram
        self.version = version
        self.term = term
        self.multiplexer = multiplexer
    }

    public var userAgentToken: String {
        let raw: String
        if let termProgram {
            raw = Terminal.formatTerminalVersion(termProgram, version: version)
        } else if let term, !term.isEmpty {
            raw = term
        } else {
            switch name {
            case .appleTerminal:
                raw = Terminal.formatTerminalVersion("Apple_Terminal", version: version)
            case .ghostty:
                raw = Terminal.formatTerminalVersion("Ghostty", version: version)
            case .iterm2:
                raw = Terminal.formatTerminalVersion("iTerm.app", version: version)
            case .warpTerminal:
                raw = Terminal.formatTerminalVersion("WarpTerminal", version: version)
            case .vsCode:
                raw = Terminal.formatTerminalVersion("vscode", version: version)
            case .wezTerm:
                raw = Terminal.formatTerminalVersion("WezTerm", version: version)
            case .kitty:
                raw = "kitty"
            case .alacritty:
                raw = "Alacritty"
            case .konsole:
                raw = Terminal.formatTerminalVersion("Konsole", version: version)
            case .gnomeTerminal:
                raw = "gnome-terminal"
            case .vte:
                raw = Terminal.formatTerminalVersion("VTE", version: version)
            case .windowsTerminal:
                raw = "WindowsTerminal"
            case .dumb:
                raw = "dumb"
            case .unknown:
                raw = "unknown"
            }
        }

        return Terminal.sanitizeHeaderValue(raw)
    }
}

public enum TerminalName: Equatable, Sendable {
    case appleTerminal
    case ghostty
    case iterm2
    case warpTerminal
    case vsCode
    case wezTerm
    case kitty
    case alacritty
    case konsole
    case gnomeTerminal
    case vte
    case windowsTerminal
    case dumb
    case unknown
}

public enum TerminalMultiplexer: Equatable, Sendable {
    case tmux(version: String?)
    case zellij
}

public struct TmuxClientInfo: Equatable, Sendable {
    public let termtype: String?
    public let termname: String?

    public init(termtype: String? = nil, termname: String? = nil) {
        self.termtype = termtype
        self.termname = termname
    }
}

public enum Terminal {
    public static func userAgent(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        terminalInfo(environment: environment).userAgentToken
    }

    public static func terminalInfo(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalInfo {
        let tmuxClientInfo = shouldReadProcessTmuxClientInfo(environment: environment)
            ? processTmuxClientInfo()
            : TmuxClientInfo()
        return detectTerminalInfo(
            environment: environment,
            tmuxClientInfo: tmuxClientInfo
        )
    }

    public static func detectTerminalInfo(
        environment: [String: String],
        tmuxClientInfo: TmuxClientInfo = TmuxClientInfo()
    ) -> TerminalInfo {
        let multiplexer = detectMultiplexer(environment: environment)

        if let termProgram = nonWhitespace(environment["TERM_PROGRAM"]) {
            if isTmuxTermProgram(termProgram),
               case .tmux? = multiplexer,
               let terminal = terminalFromTmuxClientInfo(tmuxClientInfo, multiplexer: multiplexer)
            {
                return terminal
            }

            let version = nonWhitespace(environment["TERM_PROGRAM_VERSION"])
            let name = terminalName(fromTermProgram: termProgram) ?? .unknown
            return TerminalInfo(
                name: name,
                termProgram: termProgram,
                version: version,
                multiplexer: multiplexer
            )
        }

        if environment["WEZTERM_VERSION"] != nil {
            return TerminalInfo(
                name: .wezTerm,
                version: nonWhitespace(environment["WEZTERM_VERSION"]),
                multiplexer: multiplexer
            )
        }

        if environment["ITERM_SESSION_ID"] != nil
            || environment["ITERM_PROFILE"] != nil
            || environment["ITERM_PROFILE_NAME"] != nil
        {
            return TerminalInfo(name: .iterm2, multiplexer: multiplexer)
        }

        if environment["TERM_SESSION_ID"] != nil {
            return TerminalInfo(name: .appleTerminal, multiplexer: multiplexer)
        }

        if environment["KITTY_WINDOW_ID"] != nil
            || environment["TERM"].map({ $0.contains("kitty") }) == true
        {
            return TerminalInfo(name: .kitty, multiplexer: multiplexer)
        }

        if environment["ALACRITTY_SOCKET"] != nil
            || environment["TERM"].map({ $0 == "alacritty" }) == true
        {
            return TerminalInfo(name: .alacritty, multiplexer: multiplexer)
        }

        if environment["KONSOLE_VERSION"] != nil {
            return TerminalInfo(
                name: .konsole,
                version: nonWhitespace(environment["KONSOLE_VERSION"]),
                multiplexer: multiplexer
            )
        }

        if environment["GNOME_TERMINAL_SCREEN"] != nil {
            return TerminalInfo(name: .gnomeTerminal, multiplexer: multiplexer)
        }

        if environment["VTE_VERSION"] != nil {
            return TerminalInfo(
                name: .vte,
                version: nonWhitespace(environment["VTE_VERSION"]),
                multiplexer: multiplexer
            )
        }

        if environment["WT_SESSION"] != nil {
            return TerminalInfo(name: .windowsTerminal, multiplexer: multiplexer)
        }

        if let term = nonWhitespace(environment["TERM"]) {
            return TerminalInfo(
                name: terminalName(fromTerm: term),
                term: term,
                multiplexer: multiplexer
            )
        }

        return TerminalInfo(name: .unknown, multiplexer: multiplexer)
    }

    public static func terminalName(fromTermProgram value: String) -> TerminalName? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { character in
                character != " "
                    && character != "-"
                    && character != "_"
                    && character != "."
            }
            .lowercased()

        switch normalized {
        case "appleterminal":
            return .appleTerminal
        case "ghostty":
            return .ghostty
        case "iterm", "iterm2", "itermapp":
            return .iterm2
        case "warp", "warpterminal":
            return .warpTerminal
        case "vscode":
            return .vsCode
        case "wezterm":
            return .wezTerm
        case "kitty":
            return .kitty
        case "alacritty":
            return .alacritty
        case "konsole":
            return .konsole
        case "gnometerminal":
            return .gnomeTerminal
        case "vte":
            return .vte
        case "windowsterminal":
            return .windowsTerminal
        case "dumb":
            return .dumb
        default:
            return nil
        }
    }

    private static func terminalName(fromTerm value: String) -> TerminalName {
        switch value {
        case "dumb":
            return .dumb
        case "wezterm", "wezterm-mux":
            return .wezTerm
        default:
            return .unknown
        }
    }

    static func formatTerminalVersion(_ name: String, version: String?) -> String {
        guard let version, !version.isEmpty else {
            return name
        }
        return "\(name)/\(version)"
    }

    static func sanitizeHeaderValue(_ value: String) -> String {
        String(value.map { isValidHeaderValueCharacter($0) ? $0 : "_" })
    }

    private static func detectMultiplexer(
        environment: [String: String]
    ) -> TerminalMultiplexer? {
        if nonWhitespace(environment["TMUX"]) != nil
            || nonWhitespace(environment["TMUX_PANE"]) != nil
        {
            return .tmux(version: tmuxVersion(environment: environment))
        }

        if nonWhitespace(environment["ZELLIJ"]) != nil
            || nonWhitespace(environment["ZELLIJ_SESSION_NAME"]) != nil
            || nonWhitespace(environment["ZELLIJ_VERSION"]) != nil
        {
            return .zellij
        }

        return nil
    }

    private static func terminalFromTmuxClientInfo(
        _ clientInfo: TmuxClientInfo,
        multiplexer: TerminalMultiplexer?
    ) -> TerminalInfo? {
        let termtype = nonWhitespace(clientInfo.termtype)
        let termname = nonWhitespace(clientInfo.termname)

        if let termtype {
            let parsed = splitTermProgramAndVersion(termtype)
            let name = terminalName(fromTermProgram: parsed.program) ?? .unknown
            return TerminalInfo(
                name: name,
                termProgram: parsed.program,
                version: parsed.version,
                term: termname,
                multiplexer: multiplexer
            )
        }

        if let termname {
            return TerminalInfo(
                name: terminalName(fromTerm: termname),
                term: termname,
                multiplexer: multiplexer
            )
        }

        return nil
    }

    private static func tmuxVersion(environment: [String: String]) -> String? {
        guard let termProgram = environment["TERM_PROGRAM"],
              isTmuxTermProgram(termProgram)
        else {
            return nil
        }

        return nonWhitespace(environment["TERM_PROGRAM_VERSION"])
    }

    private static func isTmuxTermProgram(_ value: String) -> Bool {
        value.caseInsensitiveCompare("tmux") == .orderedSame
    }

    private static func shouldReadProcessTmuxClientInfo(
        environment: [String: String]
    ) -> Bool {
        guard let termProgram = nonWhitespace(environment["TERM_PROGRAM"]),
              isTmuxTermProgram(termProgram)
        else {
            return false
        }

        return nonWhitespace(environment["TMUX"]) != nil
            || nonWhitespace(environment["TMUX_PANE"]) != nil
    }

    private static func splitTermProgramAndVersion(_ value: String) -> (program: String, version: String?) {
        let parts = value.split(whereSeparator: \.isWhitespace)
        let program = parts.first.map(String.init) ?? ""
        let version = parts.dropFirst().first.map(String.init)
        return (program, version)
    }

    private static func processTmuxClientInfo() -> TmuxClientInfo {
        TmuxClientInfo(
            termtype: tmuxDisplayMessage("#{client_termtype}"),
            termname: tmuxDisplayMessage("#{client_termname}")
        )
    }

    private static func tmuxDisplayMessage(_ format: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "display-message", "-p", format]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return nonWhitespace(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func nonWhitespace(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func isValidHeaderValueCharacter(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1,
              let scalar = scalars.first
        else {
            return false
        }

        return (UnicodeScalar("a")...UnicodeScalar("z")).contains(scalar)
            || (UnicodeScalar("A")...UnicodeScalar("Z")).contains(scalar)
            || (UnicodeScalar("0")...UnicodeScalar("9")).contains(scalar)
            || scalar == "-"
            || scalar == "_"
            || scalar == "."
            || scalar == "/"
    }
}
