import Foundation

public enum DoctorCheckStatus: String, Codable, Equatable, Sendable {
    case ok
    case warning
    case fail
}

public struct DoctorIssue: Codable, Equatable, Sendable {
    public let severity: DoctorCheckStatus
    public let cause: String
    public let measured: String?
    public let expected: String?
    public let remedy: String?
    public let fields: [String]

    public init(
        severity: DoctorCheckStatus,
        cause: String,
        measured: String? = nil,
        expected: String? = nil,
        remedy: String? = nil,
        fields: [String] = []
    ) {
        self.severity = severity
        self.cause = cause
        self.measured = measured
        self.expected = expected
        self.remedy = remedy
        self.fields = fields
    }
}

public struct DoctorCheck: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let status: DoctorCheckStatus
    public let summary: String
    public let details: [String]
    public let issues: [DoctorIssue]
    public let remediation: String?
    public let durationMS: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case status
        case summary
        case details
        case issues
        case remediation
        case durationMS = "durationMs"
    }

    public init(
        id: String,
        category: String,
        status: DoctorCheckStatus,
        summary: String,
        details: [String] = [],
        issues: [DoctorIssue] = [],
        remediation: String? = nil,
        durationMS: UInt64 = 0
    ) {
        self.id = id
        self.category = category
        self.status = status
        self.summary = summary
        self.details = details
        self.issues = issues
        self.remediation = remediation
        self.durationMS = durationMS
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let schemaVersion: UInt32
    public let generatedAt: String
    public let overallStatus: DoctorCheckStatus
    public let codexVersion: String
    public let checks: [DoctorCheck]

    public init(
        schemaVersion: UInt32 = 1,
        generatedAt: String,
        overallStatus: DoctorCheckStatus? = nil,
        codexVersion: String,
        checks: [DoctorCheck]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.overallStatus = overallStatus ?? DoctorCommandRuntime.overallStatus(for: checks)
        self.codexVersion = codexVersion
        self.checks = checks
    }
}

public enum DoctorCommandRuntime {
    public static var npmGlobalRootArguments: [String] {
        ["root", "-g"]
    }

    public static func npmGlobalRootCommand() -> String {
        npmGlobalRootCommand(isWindows: currentOSIsWindows)
    }

    public static func npmGlobalRootCommand(isWindows: Bool) -> String {
        isWindows ? "npm.cmd" : "npm"
    }

    public static func run(
        request: CodexCLI.DoctorCommandRequest,
        codexVersion: String,
        generatedAt: String = generatedAt(),
        configCheck: () -> DoctorCheck
    ) -> CodexCLI.CommandExecutionResult {
        let report = DoctorReport(
            generatedAt: generatedAt,
            codexVersion: codexVersion,
            checks: [configCheck()]
        )
        let output: String
        if request.json {
            output = renderJSON(report: report)
        } else {
            output = renderHumanReport(report: report, summary: request.summary, ascii: request.ascii)
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: report.overallStatus == .fail ? 1 : 0,
            stdoutMessage: output
        )
    }

    public static func configLoadedCheck(
        model: String?,
        modelProviderID: String?,
        logDir: String?,
        sqliteHome: String?,
        mcpServerCount: Int,
        configTomlPath: String,
        configTomlStatus: String,
        startupWarnings: [String] = []
    ) -> DoctorCheck {
        var details = [
            "model: \(model ?? "<default>")",
            "model provider: \(modelProviderID ?? "<default>")",
            "log dir: \(logDir ?? "<unset>")",
            "sqlite home: \(sqliteHome ?? "<unset>")",
            "mcp servers: \(mcpServerCount)",
            "config.toml: \(configTomlPath)",
            "config.toml \(configTomlStatus)"
        ]
        details.append(contentsOf: startupWarnings.map { "startup warning: \($0)" })
        return DoctorCheck(
            id: "config.load",
            category: "config",
            status: startupWarnings.isEmpty ? .ok : .warning,
            summary: "config loaded",
            details: details
        )
    }

    public static func configLoadFailedCheck(_ error: Error) -> DoctorCheck {
        DoctorCheck(
            id: "config.load",
            category: "config",
            status: .fail,
            summary: "config could not be loaded",
            details: [String(describing: error)],
            remediation: "Fix the reported config error, then rerun codex doctor."
        )
    }

    public static func overallStatus(for checks: [DoctorCheck]) -> DoctorCheckStatus {
        if checks.contains(where: { $0.status == .fail }) {
            return .fail
        }
        if checks.contains(where: { $0.status == .warning }) {
            return .warning
        }
        return .ok
    }

    private static func renderJSON(report: DoctorReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonReport = JSONDoctorReport(report: report)
        let data = (try? encoder.encode(jsonReport)) ?? Data(#"{"schemaVersion":1}"#.utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func renderHumanReport(report: DoctorReport, summary: Bool, ascii: Bool) -> String {
        var lines = [
            "Codex Doctor \(report.codexVersion)",
            "",
            "Configuration"
        ]
        for check in report.checks where check.category == "config" {
            lines.append("  \(statusMarker(check.status, ascii: ascii)) config      \(check.summary)")
            if !summary {
                lines.append(contentsOf: check.details.map { "      \($0)" })
                if let remediation = check.remediation {
                    lines.append("      \(ascii ? "->" : "->") \(remediation)")
                }
            }
        }
        lines.append("")
        lines.append("-------------------------------------------------------------")
        lines.append(summaryLine(report: report, ascii: ascii))
        lines.append("")
        if summary {
            lines.append("Run codex doctor without --summary for detailed diagnostics.")
            lines.append("--all expand truncated lists       --json redacted report")
        } else {
            lines.append("--summary compact output           --all expand truncated lists")
            lines.append("--json redacted report")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func statusMarker(_ status: DoctorCheckStatus, ascii: Bool) -> String {
        switch status {
        case .ok:
            ascii ? "[OK]" : "OK"
        case .warning:
            ascii ? "[WARN]" : "WARN"
        case .fail:
            ascii ? "[FAIL]" : "FAIL"
        }
    }

    private static func summaryLine(report: DoctorReport, ascii: Bool) -> String {
        let ok = report.checks.filter { $0.status == .ok }.count
        let warning = report.checks.filter { $0.status == .warning }.count
        let fail = report.checks.filter { $0.status == .fail }.count
        let status = switch report.overallStatus {
        case .ok: "ok"
        case .warning: "degraded"
        case .fail: "failed"
        }
        let separator = ascii ? " | " : " · "
        return ["\(ok) ok", "\(warning) warn", "\(fail) fail"].joined(separator: separator) + " \(status)"
    }

    public static func generatedAt() -> String {
        "\(UInt64(Date().timeIntervalSince1970))s since unix epoch"
    }

    private static var currentOSIsWindows: Bool {
        #if os(Windows)
            true
        #else
            false
        #endif
    }
}

private struct JSONDoctorReport: Encodable {
    let schemaVersion: UInt32
    let generatedAt: String
    let overallStatus: DoctorCheckStatus
    let codexVersion: String
    let checks: [String: JSONDoctorCheck]

    init(report: DoctorReport) {
        schemaVersion = report.schemaVersion
        generatedAt = report.generatedAt
        overallStatus = report.overallStatus
        codexVersion = report.codexVersion
        checks = Dictionary(uniqueKeysWithValues: report.checks.map { ($0.id, JSONDoctorCheck(check: $0)) })
    }
}

private struct JSONDoctorCheck: Encodable {
    let id: String
    let category: String
    let status: DoctorCheckStatus
    let summary: String
    let details: [String: JSONDetailValue]
    let issues: [DoctorIssue]
    let notes: [String]
    let remediation: String?
    let durationMS: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case status
        case summary
        case details
        case issues
        case notes
        case remediation
        case durationMS = "durationMs"
    }

    init(check: DoctorCheck) {
        id = check.id
        category = check.category
        status = check.status
        summary = check.summary
        let parsed = parseDetails(check.details)
        details = parsed.details
        notes = parsed.notes
        issues = check.issues
        remediation = check.remediation
        durationMS = check.durationMS
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encode(summary, forKey: .summary)
        try container.encode(details, forKey: .details)
        if !issues.isEmpty {
            try container.encode(issues, forKey: .issues)
        }
        if !notes.isEmpty {
            try container.encode(notes, forKey: .notes)
        }
        try container.encode(remediation, forKey: .remediation)
        try container.encode(durationMS, forKey: .durationMS)
    }
}

private enum JSONDetailValue: Encodable {
    case string(String)
    case array([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .array(values):
            try container.encode(values)
        }
    }
}

private func parseDetails(_ rawDetails: [String]) -> (details: [String: JSONDetailValue], notes: [String]) {
    var details: [String: JSONDetailValue] = [:]
    var notes: [String] = []
    for detail in rawDetails {
        guard let separator = detail.firstIndex(of: ":") else {
            notes.append(redact(detail))
            continue
        }
        let key = String(detail[..<separator])
        let valueStart = detail.index(after: separator)
        let value = redact(String(detail[valueStart...]).trimmingCharacters(in: .whitespaces))
        switch details[key] {
        case nil:
            details[key] = .string(value)
        case let .string(existing):
            details[key] = .array([existing, value])
        case let .array(existing):
            details[key] = .array(existing + [value])
        }
    }
    return (details, notes)
}

private func redact(_ value: String) -> String {
    var redacted = value
    redacted = redacted.replacingOccurrences(
        of: #"sk-[A-Za-z0-9_-]+"#,
        with: "<redacted>",
        options: .regularExpression
    )
    redacted = redacted.replacingOccurrences(
        of: #"https://[^/@\s]+:[^/@\s]+@([^/?\s]+)(?:\?[^)\s]+)?"#,
        with: "https://$1",
        options: .regularExpression
    )
    return redacted
}
