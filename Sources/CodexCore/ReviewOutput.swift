import Foundation

public enum ReviewDelivery: String, Codable, Equatable, Sendable {
    case inline
    case detached
}

public struct ExitedReviewModeEvent: Codable, Equatable, Sendable {
    public let reviewOutput: ReviewOutputEvent?

    private enum CodingKeys: String, CodingKey {
        case reviewOutput = "review_output"
    }

    public init(reviewOutput: ReviewOutputEvent?) {
        self.reviewOutput = reviewOutput
    }
}

public struct ReviewOutputEvent: Codable, Equatable, Sendable {
    public let findings: [ReviewFinding]
    public let overallCorrectness: String
    public let overallExplanation: String
    public let overallConfidenceScore: Float

    private enum CodingKeys: String, CodingKey {
        case findings
        case overallCorrectness = "overall_correctness"
        case overallExplanation = "overall_explanation"
        case overallConfidenceScore = "overall_confidence_score"
    }

    public init(
        findings: [ReviewFinding] = [],
        overallCorrectness: String = "",
        overallExplanation: String = "",
        overallConfidenceScore: Float = 0.0
    ) {
        self.findings = findings
        self.overallCorrectness = overallCorrectness
        self.overallExplanation = overallExplanation
        self.overallConfidenceScore = overallConfidenceScore
    }
}

public struct ReviewFinding: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let confidenceScore: Float
    public let priority: Int32
    public let codeLocation: ReviewCodeLocation

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case confidenceScore = "confidence_score"
        case priority
        case codeLocation = "code_location"
    }

    public init(
        title: String,
        body: String,
        confidenceScore: Float,
        priority: Int32,
        codeLocation: ReviewCodeLocation
    ) {
        self.title = title
        self.body = body
        self.confidenceScore = confidenceScore
        self.priority = priority
        self.codeLocation = codeLocation
    }
}

public struct ReviewCodeLocation: Codable, Equatable, Sendable {
    public let absoluteFilePath: String
    public let lineRange: ReviewLineRange

    private enum CodingKeys: String, CodingKey {
        case absoluteFilePath = "absolute_file_path"
        case lineRange = "line_range"
    }

    public init(absoluteFilePath: String, lineRange: ReviewLineRange) {
        self.absoluteFilePath = absoluteFilePath
        self.lineRange = lineRange
    }
}

public struct ReviewLineRange: Codable, Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }
}

public enum ReviewFormat {
    public static let fallbackMessage = "Reviewer failed to output a response."

    public static func formatReviewFindingsBlock(
        findings: [ReviewFinding],
        selection: [Bool]? = nil
    ) -> String {
        var lines: [String] = [""]
        lines.append(findings.count > 1 ? "Full review comments:" : "Review comment:")

        for (index, item) in findings.enumerated() {
            lines.append("")

            let location = formatLocation(item)
            if let selection {
                let checked = index < selection.count ? selection[index] : true
                let marker = checked ? "[x]" : "[ ]"
                lines.append("- \(marker) \(item.title) — \(location)")
            } else {
                lines.append("- \(item.title) — \(location)")
            }

            for bodyLine in rustLines(item.body) {
                lines.append("  \(bodyLine)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func renderReviewOutputText(_ output: ReviewOutputEvent) -> String {
        var sections: [String] = []
        let explanation = output.overallExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty {
            sections.append(explanation)
        }

        if !output.findings.isEmpty {
            let findings = formatReviewFindingsBlock(findings: output.findings)
            let trimmed = findings.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append(trimmed)
            }
        }

        return sections.isEmpty ? fallbackMessage : sections.joined(separator: "\n\n")
    }

    private static func formatLocation(_ item: ReviewFinding) -> String {
        let range = item.codeLocation.lineRange
        return "\(item.codeLocation.absoluteFilePath):\(range.start)-\(range.end)"
    }

    private static func rustLines(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        var lines: [String] = []
        var current = ""
        var endedWithLineFeed = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\n" || character == "\r\n" {
                if current.last == "\r" {
                    current.removeLast()
                }
                lines.append(current)
                current.removeAll(keepingCapacity: true)
                endedWithLineFeed = true
            } else {
                current.append(character)
                endedWithLineFeed = false
            }
            index = text.index(after: index)
        }

        if !endedWithLineFeed {
            lines.append(current)
        }

        return lines
    }
}
