import Foundation

public struct TuiKeybindingSpec: Equatable, Sendable {
    public var value: String

    public init(_ rawValue: String) throws {
        value = try Self.normalized(rawValue)
    }

    private static func normalized(_ raw: String) throws -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else {
            throw CodexConfigLoadError.invalidConfig(
                "keybinding cannot be empty. Use values like `ctrl-a` or `shift-enter`.\nSee the Codex keymap documentation for supported actions and examples."
            )
        }

        let segments = lower.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard !segments.isEmpty else {
            throw CodexConfigLoadError.invalidConfig(
                "invalid keybinding `\(raw)`. Use values like `ctrl-a`, `shift-enter`, or `page-down`."
            )
        }

        var modifiers: Set<String> = []
        var keySegments: [String] = []
        var sawKey = false

        for segment in segments {
            let modifier: String?
            switch segment {
            case "ctrl", "control":
                modifier = "ctrl"
            case "alt", "option":
                modifier = "alt"
            case "shift":
                modifier = "shift"
            default:
                modifier = nil
            }

            if !sawKey, let modifier {
                guard !modifiers.contains(modifier) else {
                    throw CodexConfigLoadError.invalidConfig(
                        "duplicate modifier in keybinding `\(raw)`. Use each modifier at most once."
                    )
                }
                modifiers.insert(modifier)
                continue
            }

            sawKey = true
            keySegments.append(segment)
        }

        guard !keySegments.isEmpty else {
            throw CodexConfigLoadError.invalidConfig(
                "missing key in keybinding `\(raw)`. Add a key name like `a`, `enter`, or `page-down`."
            )
        }

        if keySegments.contains(where: { ["ctrl", "control", "alt", "option", "shift"].contains($0) }) {
            throw CodexConfigLoadError.invalidConfig(
                "invalid keybinding `\(raw)`: modifiers must come before the key (for example `ctrl-a`)."
            )
        }

        let key = try normalizedKeyName(keySegments.joined(separator: "-"), original: raw)
        var normalized: [String] = []
        if modifiers.contains("ctrl") { normalized.append("ctrl") }
        if modifiers.contains("alt") { normalized.append("alt") }
        if modifiers.contains("shift") { normalized.append("shift") }
        normalized.append(key)
        return normalized.joined(separator: "-")
    }

    private static func normalizedKeyName(_ key: String, original: String) throws -> String {
        let alias: String
        switch key {
        case "escape":
            alias = "esc"
        case "return":
            alias = "enter"
        case "spacebar":
            alias = "space"
        case "pgup", "pageup":
            alias = "page-up"
        case "pgdn", "pagedown":
            alias = "page-down"
        case "del":
            alias = "delete"
        default:
            alias = key
        }

        if alias.count == 1,
           let character = alias.unicodeScalars.first,
           character.isASCII,
           !CharacterSet.controlCharacters.contains(character),
           character != "-"
        {
            return alias
        }

        if [
            "enter", "tab", "backspace", "esc", "delete", "up", "down", "left", "right",
            "home", "end", "page-up", "page-down", "space"
        ].contains(alias) {
            return alias
        }

        if alias.first == "f",
           let number = UInt8(alias.dropFirst()),
           (1...12).contains(number)
        {
            return alias
        }

        throw CodexConfigLoadError.invalidConfig(
            "unknown key `\(key)` in keybinding `\(original)`. Use a printable character (for example `a`), function keys (`f1`-`f12`), or one of: enter, tab, backspace, esc, delete, arrows, home/end, page-up/page-down, space.\nSee the Codex keymap documentation for supported actions and examples."
        )
    }
}

public enum TuiKeybindingsSpec: Equatable, Sendable {
    case one(TuiKeybindingSpec)
    case many([TuiKeybindingSpec])

    public var specs: [TuiKeybindingSpec] {
        switch self {
        case let .one(spec):
            return [spec]
        case let .many(specs):
            return specs
        }
    }
}

public enum TuiKeymapContext: String, CaseIterable, Sendable {
    case global
    case chat
    case composer
    case editor
    case vimNormal = "vim_normal"
    case vimOperator = "vim_operator"
    case pager
    case list
    case approval
}

public struct TuiKeymapConfig: Equatable, Sendable {
    public var contexts: [TuiKeymapContext: [String: TuiKeybindingsSpec]]

    public init(contexts: [TuiKeymapContext: [String: TuiKeybindingsSpec]] = [:]) {
        self.contexts = contexts
    }

    public func bindings(context: TuiKeymapContext, action: String) -> TuiKeybindingsSpec? {
        contexts[context]?[action]
    }

    static func parse(_ value: ConfigValue, key: String) throws -> TuiKeymapConfig {
        guard case let .table(contextTable) = value else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }

        var contexts: [TuiKeymapContext: [String: TuiKeybindingsSpec]] = [:]
        for (rawContext, rawActions) in contextTable {
            guard let context = TuiKeymapContext(rawValue: rawContext) else {
                throw CodexConfigLoadError.invalidConfigLine("\(key).\(rawContext)")
            }
            guard case let .table(actionTable) = rawActions else {
                throw CodexConfigLoadError.invalidConfigLine("\(key).\(rawContext)")
            }

            var actions: [String: TuiKeybindingsSpec] = contexts[context] ?? [:]
            for (action, bindingValue) in actionTable {
                guard Self.validActions[context]?.contains(action) == true else {
                    throw CodexConfigLoadError.invalidConfigLine("\(key).\(rawContext).\(action)")
                }
                actions[action] = try parseBindings(bindingValue, key: "\(key).\(rawContext).\(action)")
            }
            contexts[context] = actions
        }

        return TuiKeymapConfig(contexts: contexts)
    }

    private static func parseBindings(_ value: ConfigValue, key: String) throws -> TuiKeybindingsSpec {
        switch value {
        case let .string(raw):
            return .one(try TuiKeybindingSpec(raw))
        case let .array(values):
            let specs = try values.map { value in
                guard case let .string(raw) = value else {
                    throw CodexConfigLoadError.invalidStringValue(key)
                }
                return try TuiKeybindingSpec(raw)
            }
            return .many(specs)
        default:
            throw CodexConfigLoadError.invalidStringValue(key)
        }
    }

    private static let validActions: [TuiKeymapContext: Set<String>] = [
        .global: [
            "open_transcript", "open_external_editor", "copy", "clear_terminal", "submit", "queue",
            "toggle_shortcuts", "toggle_vim_mode", "toggle_fast_mode", "toggle_raw_output"
        ],
        .chat: [
            "decrease_reasoning_effort", "increase_reasoning_effort", "edit_queued_message"
        ],
        .composer: [
            "submit", "queue", "toggle_shortcuts", "history_search_previous", "history_search_next"
        ],
        .editor: [
            "insert_newline", "move_left", "move_right", "move_up", "move_down", "move_word_left",
            "move_word_right", "move_line_start", "move_line_end", "delete_backward", "delete_forward",
            "delete_backward_word", "delete_forward_word", "kill_line_start", "kill_whole_line",
            "kill_line_end", "yank"
        ],
        .vimNormal: [
            "enter_insert", "append_after_cursor", "append_line_end", "insert_line_start",
            "open_line_below", "open_line_above", "move_left", "move_right", "move_up", "move_down",
            "move_word_forward", "move_word_backward", "move_word_end", "move_line_start",
            "move_line_end", "delete_char", "delete_to_line_end", "yank_line", "paste_after",
            "start_delete_operator", "start_yank_operator", "cancel_operator"
        ],
        .vimOperator: [
            "delete_line", "yank_line", "motion_left", "motion_right", "motion_up", "motion_down",
            "motion_word_forward", "motion_word_backward", "motion_word_end", "motion_line_start",
            "motion_line_end", "cancel"
        ],
        .pager: [
            "scroll_up", "scroll_down", "page_up", "page_down", "half_page_up", "half_page_down",
            "jump_top", "jump_bottom", "close", "close_transcript"
        ],
        .list: [
            "move_up", "move_down", "accept", "cancel"
        ],
        .approval: [
            "open_fullscreen", "open_thread", "approve", "approve_for_session", "approve_for_prefix",
            "deny", "decline", "cancel"
        ]
    ]
}
