import CodexCore
import Foundation

public struct AppExitInfo: Equatable, Sendable {
    public var tokenUsage: TokenUsage
    public var threadName: String?
    public var conversationID: ConversationId?
    public var updateAction: UpdateAction?

    public init(
        tokenUsage: TokenUsage,
        threadName: String? = nil,
        conversationID: ConversationId? = nil,
        updateAction: UpdateAction? = nil
    ) {
        self.tokenUsage = tokenUsage
        self.threadName = threadName
        self.conversationID = conversationID
        self.updateAction = updateAction
    }
}

public enum ExitMessages {
    public static func formatExitMessages(_ exitInfo: AppExitInfo, colorEnabled: Bool) -> [String] {
        var lines: [String] = []
        if !exitInfo.tokenUsage.isZero {
            lines.append(FinalOutput(exitInfo.tokenUsage).description)
        }

        if let resumeCommand = resumeCommand(threadName: exitInfo.threadName, conversationID: exitInfo.conversationID) {
            let command = colorEnabled ? cyan(resumeCommand) : resumeCommand
            lines.append("To continue this session, run \(command)")
        }
        return lines
    }

    public static func resumeCommand(threadName: String?, conversationID: ConversationId?) -> String? {
        let target = threadName
            .flatMap { name in
                name.isEmpty ? nil : name
            }
            ?? conversationID?.description
        guard let target else {
            return nil
        }

        let escaped = shellJoinResumeTarget(target)
        if target.hasPrefix("-") {
            return "codex resume -- \(escaped)"
        }
        return "codex resume \(escaped)"
    }

    private static func cyan(_ text: String) -> String {
        "\u{1B}[36m\(text)\u{1B}[0m"
    }

    private static func shellJoinResumeTarget(_ target: String) -> String {
        if target.contains("\0") {
            return "<command included NUL byte>"
        }

        return shellQuoteResumeTarget(target)
    }

    private static func shellQuoteResumeTarget(_ target: String) -> String {
        if target.isEmpty {
            return "''"
        }

        let bytes = Array(target.utf8)
        var output: [UInt8] = []
        var remainingStart = 0
        while remainingStart < bytes.count {
            let slice = Array(bytes[remainingStart...])
            let (length, strategy) = resumeQuotingStrategy(slice)
            let chunk = Array(slice.prefix(length))
            if length == bytes.count && strategy == .unquoted && output.isEmpty {
                return target
            }
            appendResumeQuotedChunk(chunk, strategy: strategy, to: &output)
            remainingStart += length
        }
        return String(decoding: output, as: UTF8.self)
    }

    private enum ResumeQuotingStrategy {
        case unquoted
        case singleQuoted
        case doubleQuoted
    }

    private static func resumeQuotingStrategy(_ bytes: [UInt8]) -> (Int, ResumeQuotingStrategy) {
        let unquoted: UInt8 = 1
        let singleQuoted: UInt8 = 2
        let doubleQuoted: UInt8 = 4

        var previous = unquoted | singleQuoted | doubleQuoted
        var index = 0

        if bytes[0] == UInt8(ascii: "^") {
            previous = singleQuoted
            index = 1
        }

        while index < bytes.count {
            let byte = bytes[index]
            var current = previous

            if byte >= 0x80 {
                current &= ~unquoted
            } else {
                if !resumeUnquotedOK(byte) {
                    current &= ~unquoted
                }
                if !resumeSingleQuotedOK(byte) {
                    current &= ~singleQuoted
                }
                if !resumeDoubleQuotedOK(byte) {
                    current &= ~doubleQuoted
                }
            }

            if current == 0 {
                break
            }

            previous = current
            index += 1
        }

        if previous & unquoted != 0 {
            return (index, .unquoted)
        }
        if previous & singleQuoted != 0 {
            return (index, .singleQuoted)
        }
        return (index, .doubleQuoted)
    }

    private static func appendResumeQuotedChunk(
        _ chunk: [UInt8],
        strategy: ResumeQuotingStrategy,
        to output: inout [UInt8]
    ) {
        switch strategy {
        case .unquoted:
            output.append(contentsOf: chunk)
        case .singleQuoted:
            output.append(UInt8(ascii: "'"))
            output.append(contentsOf: chunk)
            output.append(UInt8(ascii: "'"))
        case .doubleQuoted:
            output.append(UInt8(ascii: "\""))
            for byte in chunk {
                if byte == UInt8(ascii: "$")
                    || byte == UInt8(ascii: "`")
                    || byte == UInt8(ascii: "\"")
                    || byte == UInt8(ascii: "\\")
                {
                    output.append(UInt8(ascii: "\\"))
                }
                output.append(byte)
            }
            output.append(UInt8(ascii: "\""))
        }
    }

    private static func resumeUnquotedOK(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"),
             UInt8(ascii: ":"), UInt8(ascii: "@"), UInt8(ascii: "]"), UInt8(ascii: "_"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"):
            return true
        default:
            return false
        }
    }

    private static func resumeSingleQuotedOK(_ byte: UInt8) -> Bool {
        byte != UInt8(ascii: "'")
            && byte != UInt8(ascii: "^")
            && byte != UInt8(ascii: "\\")
    }

    private static func resumeDoubleQuotedOK(_ byte: UInt8) -> Bool {
        byte != UInt8(ascii: "`")
            && byte != UInt8(ascii: "$")
            && byte != UInt8(ascii: "!")
            && byte != UInt8(ascii: "^")
    }
}
