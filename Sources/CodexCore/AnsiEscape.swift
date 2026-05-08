import Foundation

public enum AnsiEscape {
    public static func expandTabs(_ text: String) -> String {
        guard text.contains("\t") else {
            return text
        }
        return text.replacingOccurrences(of: "\t", with: "    ")
    }

    /// Port of codex-rs/ansi-escape `ansi_escape_line`.
    public static func ansiEscapeLine(_ text: String) -> AnsiLine {
        let expanded = expandTabs(text)
        let parsed = ansiEscape(expanded)
        return parsed.lines.first ?? .empty
    }

    /// Port of codex-rs/ansi-escape `ansi_escape`.
    public static func ansiEscape(_ text: String) -> AnsiText {
        var parser = AnsiParser(text: text)
        return parser.parse()
    }
}

public struct AnsiText: Equatable, Sendable {
    public var lines: [AnsiLine]

    public init(lines: [AnsiLine]) {
        self.lines = lines
    }

    public var plainText: String {
        lines.map(\.plainText).joined(separator: "\n")
    }
}

public struct AnsiLine: Equatable, Sendable {
    public static let empty = AnsiLine(spans: [])

    public var spans: [AnsiSpan]

    public init(spans: [AnsiSpan]) {
        self.spans = Self.coalesced(spans)
    }

    public var plainText: String {
        spans.map(\.text).joined()
    }

    private static func coalesced(_ spans: [AnsiSpan]) -> [AnsiSpan] {
        var result: [AnsiSpan] = []
        for span in spans where !span.text.isEmpty {
            if let last = result.last, last.style == span.style {
                result[result.count - 1].text += span.text
            } else {
                result.append(span)
            }
        }
        return result
    }
}

public struct AnsiSpan: Equatable, Sendable {
    public var text: String
    public var style: AnsiStyle

    public init(text: String, style: AnsiStyle = .default) {
        self.text = text
        self.style = style
    }
}

public struct AnsiStyle: Equatable, Sendable {
    public static let `default` = AnsiStyle()

    public var foreground: AnsiColor?
    public var background: AnsiColor?
    public var modifiers: AnsiTextModifiers

    public init(
        foreground: AnsiColor? = nil,
        background: AnsiColor? = nil,
        modifiers: AnsiTextModifiers = []
    ) {
        self.foreground = foreground
        self.background = background
        self.modifiers = modifiers
    }
}

public enum AnsiColor: Equatable, Sendable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case indexed(UInt8)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

public struct AnsiTextModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold = AnsiTextModifiers(rawValue: 1 << 0)
    public static let dim = AnsiTextModifiers(rawValue: 1 << 1)
    public static let italic = AnsiTextModifiers(rawValue: 1 << 2)
    public static let underlined = AnsiTextModifiers(rawValue: 1 << 3)
    public static let slowBlink = AnsiTextModifiers(rawValue: 1 << 4)
    public static let rapidBlink = AnsiTextModifiers(rawValue: 1 << 5)
    public static let reversed = AnsiTextModifiers(rawValue: 1 << 6)
    public static let hidden = AnsiTextModifiers(rawValue: 1 << 7)
    public static let crossedOut = AnsiTextModifiers(rawValue: 1 << 8)
}

private struct AnsiParser {
    private let scalars: String.UnicodeScalarView
    private var index: String.UnicodeScalarView.Index
    private var style: AnsiStyle = .default
    private var lines: [AnsiLine] = []
    private var currentSpans: [AnsiSpan] = []
    private var currentText = ""
    private var endedWithLineBreak = false

    init(text: String) {
        scalars = text.unicodeScalars
        index = scalars.startIndex
    }

    mutating func parse() -> AnsiText {
        guard !scalars.isEmpty else {
            return AnsiText(lines: [])
        }

        while index != scalars.endIndex {
            let scalar = scalars[index]
            switch scalar {
            case "\u{1B}":
                if !consumeEscapeSequence() {
                    currentText.unicodeScalars.append(scalar)
                    scalars.formIndex(after: &index)
                }
                endedWithLineBreak = false
            case "\u{9B}":
                consumeCSISequence()
                endedWithLineBreak = false
            case "\n":
                finishLine()
                scalars.formIndex(after: &index)
            case "\r":
                finishLine()
                scalars.formIndex(after: &index)
                if index != scalars.endIndex, scalars[index] == "\n" {
                    scalars.formIndex(after: &index)
                }
            default:
                currentText.unicodeScalars.append(scalar)
                scalars.formIndex(after: &index)
                endedWithLineBreak = false
            }
        }

        if !endedWithLineBreak || !currentText.isEmpty || !currentSpans.isEmpty {
            flushText()
            lines.append(AnsiLine(spans: currentSpans))
        }

        return AnsiText(lines: lines)
    }

    private mutating func flushText() {
        guard !currentText.isEmpty else {
            return
        }
        currentSpans.append(AnsiSpan(text: currentText, style: style))
        currentText = ""
    }

    private mutating func finishLine() {
        flushText()
        lines.append(AnsiLine(spans: currentSpans))
        currentSpans = []
        currentText = ""
        endedWithLineBreak = true
    }

    private mutating func consumeEscapeSequence() -> Bool {
        let escapeIndex = index
        scalars.formIndex(after: &index)
        guard index != scalars.endIndex else {
            index = escapeIndex
            return false
        }

        switch scalars[index] {
        case "[":
            scalars.formIndex(after: &index)
            consumeCSISequenceBody()
            return true
        case "]":
            scalars.formIndex(after: &index)
            consumeOSCSequenceBody()
            return true
        default:
            consumeSingleEscapeBody()
            return true
        }
    }

    private mutating func consumeCSISequence() {
        scalars.formIndex(after: &index)
        consumeCSISequenceBody()
    }

    private mutating func consumeCSISequenceBody() {
        var parameters = ""
        while index != scalars.endIndex {
            let scalar = scalars[index]
            scalars.formIndex(after: &index)
            if isCSIFinalByte(scalar) {
                if scalar == "m" {
                    flushText()
                    applySGR(parseSGRParameters(parameters), to: &style)
                }
                return
            }
            parameters.unicodeScalars.append(scalar)
        }
    }

    private mutating func consumeOSCSequenceBody() {
        while index != scalars.endIndex {
            let scalar = scalars[index]
            scalars.formIndex(after: &index)
            if scalar == "\u{7}" {
                return
            }
            if scalar == "\u{1B}", index != scalars.endIndex, scalars[index] == "\\" {
                scalars.formIndex(after: &index)
                return
            }
        }
    }

    private mutating func consumeSingleEscapeBody() {
        while index != scalars.endIndex {
            let scalar = scalars[index]
            scalars.formIndex(after: &index)
            if isEscapeFinalByte(scalar) {
                return
            }
        }
    }

    private func isCSIFinalByte(_ scalar: Unicode.Scalar) -> Bool {
        (0x40...0x7E).contains(Int(scalar.value))
    }

    private func isEscapeFinalByte(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x7E).contains(Int(scalar.value))
    }

    private func parseSGRParameters(_ raw: String) -> [Int] {
        guard !raw.isEmpty else {
            return [0]
        }

        let pieces: [Substring]
        if raw.contains(":") && !raw.contains(";") {
            pieces = raw.split(separator: ":", omittingEmptySubsequences: true)
        } else {
            pieces = raw.split(separator: ";", omittingEmptySubsequences: false)
        }

        let parsed = pieces.compactMap { piece -> Int? in
            if piece.isEmpty {
                return 0
            }
            return Int(piece)
        }

        return parsed.isEmpty ? [0] : parsed
    }

    private func applySGR(_ parameters: [Int], to style: inout AnsiStyle) {
        var position = 0
        while position < parameters.count {
            let code = parameters[position]
            switch code {
            case 0:
                style = .default
            case 1:
                style.modifiers.insert(.bold)
            case 2:
                style.modifiers.insert(.dim)
            case 3:
                style.modifiers.insert(.italic)
            case 4:
                style.modifiers.insert(.underlined)
            case 5:
                style.modifiers.insert(.slowBlink)
            case 6:
                style.modifiers.insert(.rapidBlink)
            case 7:
                style.modifiers.insert(.reversed)
            case 8:
                style.modifiers.insert(.hidden)
            case 9:
                style.modifiers.insert(.crossedOut)
            case 21, 22:
                style.modifiers.remove([.bold, .dim])
            case 23:
                style.modifiers.remove(.italic)
            case 24:
                style.modifiers.remove(.underlined)
            case 25:
                style.modifiers.remove([.slowBlink, .rapidBlink])
            case 27:
                style.modifiers.remove(.reversed)
            case 28:
                style.modifiers.remove(.hidden)
            case 29:
                style.modifiers.remove(.crossedOut)
            case 30...37:
                style.foreground = standardColor(index: code - 30, bright: false)
            case 38:
                if let parsed = extendedColor(in: parameters, after: position) {
                    style.foreground = parsed.color
                    position = parsed.nextPosition
                    continue
                }
            case 39:
                style.foreground = nil
            case 40...47:
                style.background = standardColor(index: code - 40, bright: false)
            case 48:
                if let parsed = extendedColor(in: parameters, after: position) {
                    style.background = parsed.color
                    position = parsed.nextPosition
                    continue
                }
            case 49:
                style.background = nil
            case 90...97:
                style.foreground = standardColor(index: code - 90, bright: true)
            case 100...107:
                style.background = standardColor(index: code - 100, bright: true)
            default:
                break
            }
            position += 1
        }
    }

    private func extendedColor(
        in parameters: [Int],
        after position: Int
    ) -> (color: AnsiColor, nextPosition: Int)? {
        guard position + 1 < parameters.count else {
            return nil
        }

        let mode = parameters[position + 1]
        switch mode {
        case 5:
            guard position + 2 < parameters.count,
                  let value = UInt8(exactly: parameters[position + 2])
            else {
                return nil
            }
            return (.indexed(value), position + 3)
        case 2:
            guard position + 4 < parameters.count,
                  let red = UInt8(exactly: parameters[position + 2]),
                  let green = UInt8(exactly: parameters[position + 3]),
                  let blue = UInt8(exactly: parameters[position + 4])
            else {
                return nil
            }
            return (.rgb(red: red, green: green, blue: blue), position + 5)
        default:
            return nil
        }
    }

    private func standardColor(index: Int, bright: Bool) -> AnsiColor? {
        switch (index, bright) {
        case (0, false): return .black
        case (1, false): return .red
        case (2, false): return .green
        case (3, false): return .yellow
        case (4, false): return .blue
        case (5, false): return .magenta
        case (6, false): return .cyan
        case (7, false): return .white
        case (0, true): return .brightBlack
        case (1, true): return .brightRed
        case (2, true): return .brightGreen
        case (3, true): return .brightYellow
        case (4, true): return .brightBlue
        case (5, true): return .brightMagenta
        case (6, true): return .brightCyan
        case (7, true): return .brightWhite
        default: return nil
        }
    }
}
