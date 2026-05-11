import Foundation

public struct ExecToolCallOutput: Equatable, Sendable {
    public var exitCode: Int
    public var stdout: String
    public var stderr: String
    public var aggregatedOutput: String
    public var duration: TimeInterval
    public var timedOut: Bool

    public init(
        exitCode: Int,
        stdout: String,
        stderr: String,
        aggregatedOutput: String,
        duration: TimeInterval,
        timedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.aggregatedOutput = aggregatedOutput
        self.duration = duration
        self.timedOut = timedOut
    }
}

public enum ExecOutputFormatter {
    public static func formatOutputString(
        _ execOutput: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        Truncation.formattedTruncateText(
            buildContentWithTimeout(execOutput),
            policy: truncationPolicy
        )
    }

    public static func buildContentWithTimeout(_ execOutput: ExecToolCallOutput) -> String {
        if execOutput.timedOut {
            let milliseconds = Int((execOutput.duration * 1_000).rounded(.towardZero))
            return "command timed out after \(milliseconds) milliseconds\n\(execOutput.aggregatedOutput)"
        }
        return execOutput.aggregatedOutput
    }
}

public enum UserShellCommand {
    public static let openTag = "<user_shell_command>"
    public static let closeTag = "</user_shell_command>"

    public static func isUserShellCommandText(_ text: String) -> Bool {
        let leadingTrimmed = text.drop { $0.isWhitespace }
        let trailingTrimmed = leadingTrimmed.dropLast(leadingTrimmed.reversed().prefix { $0.isWhitespace }.count)
        let normalized = trailingTrimmed.asciiLowercased()
        return normalized.hasPrefix(openTag) && normalized.hasSuffix(closeTag)
    }

    public static func formatRecord(
        command: String,
        execOutput: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        let body = formatBody(
            command: command,
            execOutput: execOutput,
            truncationPolicy: truncationPolicy
        )
        return "\(openTag)\n\(body)\n\(closeTag)"
    }

    public static func recordItem(
        command: String,
        execOutput: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> ResponseItem {
        .message(
            role: "user",
            content: [
                .inputText(text: formatRecord(
                    command: command,
                    execOutput: execOutput,
                    truncationPolicy: truncationPolicy
                ))
            ]
        )
    }

    private static func formatBody(
        command: String,
        execOutput: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        [
            "<command>",
            command,
            "</command>",
            "<result>",
            "Exit code: \(execOutput.exitCode)",
            formatDurationLine(execOutput.duration),
            "Output:",
            ExecOutputFormatter.formatOutputString(execOutput, truncationPolicy: truncationPolicy),
            "</result>"
        ].joined(separator: "\n")
    }

    private static func formatDurationLine(_ duration: TimeInterval) -> String {
        let seconds = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), duration)
        return "Duration: \(seconds) seconds"
    }
}

private extension Substring {
    func asciiLowercased() -> String {
        String(decoding: utf8.map { byte in
            if (Character("A").asciiValue!...Character("Z").asciiValue!).contains(byte) {
                return byte + 32
            }
            return byte
        }, as: UTF8.self)
    }
}
