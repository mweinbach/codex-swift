import CodexCore
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

public enum DoctorCommandOutput: Equatable, Sendable {
    case success(String)
    case failure(String)
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
        diagnosticChecks: () -> [DoctorCheck] = { [] },
        configCheck: () -> DoctorCheck
    ) -> CodexCLI.CommandExecutionResult {
        let report = DoctorReport(
            generatedAt: generatedAt,
            codexVersion: codexVersion,
            checks: diagnosticChecks() + [configCheck()]
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

    public static func runtimeProvenanceCheck(
        codexVersion: String,
        currentExecutablePath: String? = CommandLine.arguments.first,
        osName: String? = nil,
        architecture: String? = nil,
        installMethod: String = "local build",
        installDescription: String = "other",
        buildCommit: String? = nil
    ) -> DoctorCheck {
        let osName = osName ?? defaultOSName
        let architecture = architecture ?? defaultArchitecture
        let buildCommit = buildCommit ?? defaultBuildCommit
        let platform = "\(osName)-\(architecture)"
        var details = [
            "version: \(codexVersion)",
            "platform: \(platform)",
            "install method: \(installDescription)",
            "commit: \(buildCommit)"
        ]
        if let currentExecutablePath, !currentExecutablePath.isEmpty {
            details.append("current executable: \(currentExecutablePath)")
        } else {
            details.append("current executable: unavailable")
        }
        return DoctorCheck(
            id: "runtime.provenance",
            category: "runtime",
            status: .ok,
            summary: "running \(installMethod) on \(platform)",
            details: details
        )
    }

    public static func searchCheck(
        rgCommand: String = "rg",
        searchProvider: String = "system",
        commandOutput: ((String, [String]) -> DoctorCommandOutput)? = nil
    ) -> DoctorCheck {
        let commandOutput = commandOutput ?? runCommand
        var details = [
            "search command: \(rgCommand)",
            "search provider: \(searchProvider)"
        ]
        let readiness: DoctorCommandOutput
        if rgCommand.contains("/") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: rgCommand, isDirectory: &isDirectory), !isDirectory.boolValue {
                readiness = .success("file exists")
            } else if isDirectory.boolValue {
                readiness = .failure("path is not a file")
            } else {
                readiness = .failure("No such file or directory")
            }
        } else {
            switch commandOutput(rgCommand, ["--version"]) {
            case let .success(output):
                let version = output
                    .split(whereSeparator: { $0.isNewline })
                    .first
                    .map(String.init) ?? "rg version unknown"
                readiness = .success(version)
            case let .failure(error):
                readiness = .failure(error)
            }
        }

        let status: DoctorCheckStatus
        switch readiness {
        case let .success(value):
            details.append("search command readiness: \(value)")
            status = .ok
        case let .failure(error):
            details.append("search command readiness: \(error)")
            status = .warning
        }
        let summary = switch status {
        case .ok:
            "search is OK (\(searchProvider))"
        case .warning:
            "search command could not be verified"
        case .fail:
            "search command could not be verified"
        }
        var check = DoctorCheck(
            id: "runtime.search",
            category: "search",
            status: status,
            summary: summary,
            details: details
        )
        if status != .ok {
            check = DoctorCheck(
                id: check.id,
                category: check.category,
                status: check.status,
                summary: check.summary,
                details: check.details,
                issues: check.issues,
                remediation: "Install ripgrep or repair the bundled standalone resources.",
                durationMS: check.durationMS
            )
        }
        return check
    }

    public static func networkEnvironmentCheck(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DoctorCheck {
        var details: [String] = []
        let presentProxyVariables = proxyEnvironmentVariables.filter { name in
            guard let value = environment[name] else { return false }
            return !value.isEmpty
        }
        if presentProxyVariables.isEmpty {
            details.append("proxy env vars: none")
        } else {
            details.append("proxy env vars present: \(presentProxyVariables.joined(separator: ", "))")
        }

        var status = DoctorCheckStatus.ok
        var summary = "network-related environment looks readable"
        for name in customCertificateEnvironmentVariables {
            guard let rawPath = environment[name] else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: rawPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    status = .warning
                    summary = "custom CA env var does not point at a file"
                    details.append("\(name): not a file \(rawPath)")
                } else {
                    do {
                        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: rawPath))
                        _ = try handle.read(upToCount: 1)
                        try handle.close()
                        details.append("\(name): readable file \(rawPath)")
                    } catch {
                        status = .warning
                        summary = "custom CA env var points at an unreadable file"
                        details.append("\(name): \(rawPath) (\(error.localizedDescription))")
                    }
                }
            } else {
                status = .warning
                summary = "custom CA env var points at an unreadable path"
                details.append("\(name): \(rawPath) (No such file or directory)")
            }
        }

        return DoctorCheck(
            id: "network.env",
            category: "network",
            status: status,
            summary: summary,
            details: details
        )
    }

    public static func configLoadedCheck(
        codexHome: String? = nil,
        cwd: String? = nil,
        model: String?,
        modelProviderID: String?,
        logDir: String?,
        sqliteHome: String?,
        mcpServerCount: Int,
        features: FeatureStates = .withDefaults(),
        configTomlPath: String,
        configTomlStatus: String,
        startupWarnings: [String] = []
    ) -> DoctorCheck {
        var details: [String] = []
        if let codexHome {
            details.append("CODEX_HOME: \(codexHome)")
        }
        if let cwd {
            details.append("cwd: \(cwd)")
        }
        details.append(contentsOf: [
            "model: \(model ?? "<default>")",
            "model provider: \(modelProviderID ?? "<default>")",
            "log dir: \(logDir ?? "<unset>")",
            "sqlite home: \(sqliteHome ?? "<unset>")",
            "mcp servers: \(mcpServerCount)"
        ])
        details.append(contentsOf: featureFlagDetails(features: features))
        details.append(contentsOf: [
            "config.toml: \(configTomlPath)",
            "config.toml \(configTomlStatus)"
        ])
        details.append(contentsOf: startupWarnings.map { "startup warning: \($0)" })
        return DoctorCheck(
            id: "config.load",
            category: "config",
            status: startupWarnings.isEmpty ? .ok : .warning,
            summary: "config loaded",
            details: details
        )
    }

    public static func featureFlagDetails(
        features: FeatureStates
    ) -> [String] {
        let enabledFeatures = FeatureRegistry.specs
            .filter { features.isEnabled($0.id) }
            .map(\.key)
        let overrides = FeatureRegistry.specs
            .filter { features.isEnabled($0.id) != $0.defaultEnabled }
            .map { "\($0.key)=\(features.isEnabled($0.id))" }
        var details = [
            "feature flags enabled: \(enabledFeatures.count)",
            "enabled feature flags: \(displayList(enabledFeatures))",
            "feature flag overrides: \(displayList(overrides))"
        ]
        details.append(contentsOf: features.legacyFeatureUsages.map { usage in
            "legacy feature flag: \(usage.alias) -> \(usage.feature.rawValue)"
        })
        return details
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
        var lines = ["Codex Doctor \(report.codexVersion)", ""]
        var wroteGroup = false
        for group in outputGroups {
            let checks = report.checks.filter { group.categories.contains($0.category) }
            guard !checks.isEmpty else { continue }
            if wroteGroup {
                lines.append("")
            }
            wroteGroup = true
            lines.append(group.title)
            for check in checks {
                lines.append("  \(statusMarker(check.status, ascii: ascii)) \(check.category.padding(toLength: 12, withPad: " ", startingAt: 0)) \(check.summary)")
                if !summary {
                    lines.append(contentsOf: check.details.map { "      \($0)" })
                    if let remediation = check.remediation {
                        lines.append("      \(ascii ? "->" : "->") \(remediation)")
                    }
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
            ascii ? "[ok]" : "OK"
        case .warning:
            ascii ? "[!!]" : "WARN"
        case .fail:
            ascii ? "[XX]" : "FAIL"
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

    private static var defaultOSName: String {
        #if os(macOS)
            "darwin"
        #elseif os(Linux)
            "linux"
        #elseif os(Windows)
            "windows"
        #else
            "unknown"
        #endif
    }

    private static var defaultArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #elseif arch(arm)
            "arm"
        #else
            "unknown"
        #endif
    }

    private static var defaultBuildCommit: String {
        ProcessInfo.processInfo.environment["CODEX_BUILD_COMMIT"]
            ?? ProcessInfo.processInfo.environment["GIT_COMMIT"]
            ?? "unknown"
    }

    private static let outputGroups: [(title: String, categories: Set<String>)] = [
        ("Environment", ["runtime", "install", "search", "terminal", "state"]),
        ("Configuration", ["config", "auth", "mcp", "sandbox"]),
        ("Updates", ["updates"]),
        ("Connectivity", ["network", "websocket", "reachability"]),
        ("Background Server", ["app-server"])
    ]

    private static let proxyEnvironmentVariables = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy"
    ]

    private static let customCertificateEnvironmentVariables = [
        "CODEX_CA_CERTIFICATE",
        "SSL_CERT_FILE"
    ]

    private static func displayList(_ items: [String]) -> String {
        if items.isEmpty {
            return "none"
        }
        return items.joined(separator: ", ")
    }

    private static func runCommand(_ command: String, _ arguments: [String]) -> DoctorCommandOutput {
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus == 0 {
            return .success(output)
        }
        let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if error.isEmpty {
            return .failure("exited with status \(process.terminationStatus)")
        }
        return .failure(error)
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
