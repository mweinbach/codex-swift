import CodexCore
import XCTest

final class TerminalTests: XCTestCase {
    func testDetectsTermProgram() {
        var terminal = detect([
            "TERM_PROGRAM": "iTerm.app",
            "TERM_PROGRAM_VERSION": "3.5.0",
            "WEZTERM_VERSION": "2024.2"
        ])
        XCTAssertEqual(terminal, info(.iterm2, termProgram: "iTerm.app", version: "3.5.0"))
        XCTAssertEqual(terminal.userAgentToken, "iTerm.app/3.5.0")

        terminal = detect([
            "TERM_PROGRAM": "iTerm.app",
            "TERM_PROGRAM_VERSION": ""
        ])
        XCTAssertEqual(terminal, info(.iterm2, termProgram: "iTerm.app"))
        XCTAssertEqual(terminal.userAgentToken, "iTerm.app")

        terminal = detect([
            "TERM_PROGRAM": "iTerm.app",
            "WEZTERM_VERSION": "2024.2"
        ])
        XCTAssertEqual(terminal, info(.iterm2, termProgram: "iTerm.app"))
        XCTAssertEqual(terminal.userAgentToken, "iTerm.app")
    }

    func testDetectsITerm2AndAppleTerminal() {
        var terminal = detect(["ITERM_SESSION_ID": "w0t1p0"])
        XCTAssertEqual(terminal, info(.iterm2))
        XCTAssertEqual(terminal.userAgentToken, "iTerm.app")

        terminal = detect(["TERM_PROGRAM": "Apple_Terminal"])
        XCTAssertEqual(terminal, info(.appleTerminal, termProgram: "Apple_Terminal"))
        XCTAssertEqual(terminal.userAgentToken, "Apple_Terminal")

        terminal = detect(["TERM_SESSION_ID": "A1B2C3"])
        XCTAssertEqual(terminal, info(.appleTerminal))
        XCTAssertEqual(terminal.userAgentToken, "Apple_Terminal")
    }

    func testDetectsTermProgramNames() {
        var terminal = detect(["TERM_PROGRAM": "Ghostty"])
        XCTAssertEqual(terminal, info(.ghostty, termProgram: "Ghostty"))
        XCTAssertEqual(terminal.userAgentToken, "Ghostty")

        terminal = detect([
            "TERM_PROGRAM": "vscode",
            "TERM_PROGRAM_VERSION": "1.86.0"
        ])
        XCTAssertEqual(terminal, info(.vsCode, termProgram: "vscode", version: "1.86.0"))
        XCTAssertEqual(terminal.userAgentToken, "vscode/1.86.0")

        terminal = detect([
            "TERM_PROGRAM": "WarpTerminal",
            "TERM_PROGRAM_VERSION": "v0.2025.12.10.08.12.stable_03"
        ])
        XCTAssertEqual(terminal, info(.warpTerminal, termProgram: "WarpTerminal", version: "v0.2025.12.10.08.12.stable_03"))
        XCTAssertEqual(terminal.userAgentToken, "WarpTerminal/v0.2025.12.10.08.12.stable_03")
    }

    func testDetectsTmuxMultiplexerClientInfo() {
        var terminal = detect(
            [
                "TMUX": "/tmp/tmux-1000/default,123,0",
                "TERM_PROGRAM": "tmux"
            ],
            tmuxClientInfo: TmuxClientInfo(termtype: "xterm-256color", termname: "screen-256color")
        )
        XCTAssertEqual(
            terminal,
            info(
                .unknown,
                termProgram: "xterm-256color",
                term: "screen-256color",
                multiplexer: .tmux(version: nil)
            )
        )
        XCTAssertEqual(terminal.userAgentToken, "xterm-256color")

        terminal = detect(
            [
                "TMUX": "/tmp/tmux-1000/default,123,0",
                "TERM_PROGRAM": "tmux"
            ],
            tmuxClientInfo: TmuxClientInfo(termtype: "WezTerm")
        )
        XCTAssertEqual(
            terminal,
            info(.wezTerm, termProgram: "WezTerm", multiplexer: .tmux(version: nil))
        )
        XCTAssertEqual(terminal.userAgentToken, "WezTerm")

        terminal = detect(
            [
                "TMUX": "/tmp/tmux-1000/default,123,0",
                "TERM_PROGRAM": "tmux"
            ],
            tmuxClientInfo: TmuxClientInfo(termname: "xterm-256color")
        )
        XCTAssertEqual(
            terminal,
            info(.unknown, term: "xterm-256color", multiplexer: .tmux(version: nil))
        )
        XCTAssertEqual(terminal.userAgentToken, "xterm-256color")
    }

    func testDetectsTmuxTermProgramVersionAndZellij() {
        var terminal = detect(
            [
                "TMUX": "/tmp/tmux-1000/default,123,0",
                "TERM_PROGRAM": "tmux",
                "TERM_PROGRAM_VERSION": "3.6a"
            ],
            tmuxClientInfo: TmuxClientInfo(termtype: "ghostty 1.2.3", termname: "xterm-ghostty")
        )
        XCTAssertEqual(
            terminal,
            info(
                .ghostty,
                termProgram: "ghostty",
                version: "1.2.3",
                term: "xterm-ghostty",
                multiplexer: .tmux(version: "3.6a")
            )
        )
        XCTAssertEqual(terminal.userAgentToken, "ghostty/1.2.3")

        terminal = detect(["ZELLIJ": "1"])
        XCTAssertEqual(terminal, info(.unknown, multiplexer: .zellij))
    }

    func testDetectsWezTermKittyAndAlacritty() {
        var terminal = detect(["WEZTERM_VERSION": "2024.2"])
        XCTAssertEqual(terminal, info(.wezTerm, version: "2024.2"))
        XCTAssertEqual(terminal.userAgentToken, "WezTerm/2024.2")

        terminal = detect([
            "TERM_PROGRAM": "WezTerm",
            "TERM_PROGRAM_VERSION": "2024.2"
        ])
        XCTAssertEqual(terminal, info(.wezTerm, termProgram: "WezTerm", version: "2024.2"))
        XCTAssertEqual(terminal.userAgentToken, "WezTerm/2024.2")

        terminal = detect(["WEZTERM_VERSION": ""])
        XCTAssertEqual(terminal, info(.wezTerm))
        XCTAssertEqual(terminal.userAgentToken, "WezTerm")

        terminal = detect(["KITTY_WINDOW_ID": "1"])
        XCTAssertEqual(terminal, info(.kitty))
        XCTAssertEqual(terminal.userAgentToken, "kitty")

        terminal = detect([
            "TERM": "xterm-kitty",
            "ALACRITTY_SOCKET": "/tmp/alacritty"
        ])
        XCTAssertEqual(terminal, info(.kitty))
        XCTAssertEqual(terminal.userAgentToken, "kitty")

        terminal = detect(["ALACRITTY_SOCKET": "/tmp/alacritty"])
        XCTAssertEqual(terminal, info(.alacritty))
        XCTAssertEqual(terminal.userAgentToken, "Alacritty")

        terminal = detect(["TERM": "alacritty"])
        XCTAssertEqual(terminal, info(.alacritty))
        XCTAssertEqual(terminal.userAgentToken, "Alacritty")
    }

    func testDetectsOtherTerminalsAndFallbacks() {
        var terminal = detect(["KONSOLE_VERSION": "230800"])
        XCTAssertEqual(terminal, info(.konsole, version: "230800"))
        XCTAssertEqual(terminal.userAgentToken, "Konsole/230800")

        terminal = detect(["GNOME_TERMINAL_SCREEN": "1"])
        XCTAssertEqual(terminal, info(.gnomeTerminal))
        XCTAssertEqual(terminal.userAgentToken, "gnome-terminal")

        terminal = detect(["VTE_VERSION": "7000"])
        XCTAssertEqual(terminal, info(.vte, version: "7000"))
        XCTAssertEqual(terminal.userAgentToken, "VTE/7000")

        terminal = detect(["WT_SESSION": "1"])
        XCTAssertEqual(terminal, info(.windowsTerminal))
        XCTAssertEqual(terminal.userAgentToken, "WindowsTerminal")

        terminal = detect(["TERM": "xterm-256color"])
        XCTAssertEqual(terminal, info(.unknown, term: "xterm-256color"))
        XCTAssertEqual(terminal.userAgentToken, "xterm-256color")

        terminal = detect([:])
        XCTAssertEqual(terminal, info(.unknown))
        XCTAssertEqual(terminal.userAgentToken, "unknown")
    }

    func testNameNormalizationAndHeaderSanitization() {
        XCTAssertEqual(Terminal.terminalName(fromTermProgram: "iTerm.app"), .iterm2)
        XCTAssertEqual(Terminal.terminalName(fromTermProgram: "Warp-Terminal"), .warpTerminal)
        XCTAssertEqual(Terminal.terminalName(fromTermProgram: "Windows_Terminal"), .windowsTerminal)
        XCTAssertNil(Terminal.terminalName(fromTermProgram: "Mystery Term"))

        let terminal = info(.unknown, termProgram: "Bad Term", version: "1.0(beta)")
        XCTAssertEqual(terminal.userAgentToken, "Bad_Term/1.0_beta_")
    }

    private func detect(
        _ environment: [String: String],
        tmuxClientInfo: TmuxClientInfo = TmuxClientInfo()
    ) -> TerminalInfo {
        Terminal.detectTerminalInfo(environment: environment, tmuxClientInfo: tmuxClientInfo)
    }

    private func info(
        _ name: TerminalName,
        termProgram: String? = nil,
        version: String? = nil,
        term: String? = nil,
        multiplexer: TerminalMultiplexer? = nil
    ) -> TerminalInfo {
        TerminalInfo(
            name: name,
            termProgram: termProgram,
            version: version,
            term: term,
            multiplexer: multiplexer
        )
    }
}
