import CodexCore
import Foundation

public typealias AppServerDoctorFeedbackReportProvider = @Sendable () async -> AppServerDoctorFeedbackReport?

public struct AppServerDoctorFeedbackReport: Equatable, Sendable {
    public let attachment: FeedbackAttachment
    public let tags: [String: String]

    public init(attachment: FeedbackAttachment, tags: [String: String]) {
        self.attachment = attachment
        self.tags = tags
    }
}

private let doctorFeedbackReportTimeout: TimeInterval = 25
private let maxDoctorTagValueLength = 256
private let doctorReportAttachmentFilename = "codex-doctor-report.json"

public func liveAppServerDoctorFeedbackReport() async -> AppServerDoctorFeedbackReport? {
    guard let executable = Bundle.main.executableURL ?? CommandLine.arguments.first.map(URL.init(fileURLWithPath:)) else {
        return nil
    }
    return appServerDoctorFeedbackReport(
        executable: executable,
        runProcess: runDoctorProcessForFeedback
    )
}

func appServerDoctorFeedbackReport(
    executable: URL,
    runProcess: (URL, [String], TimeInterval) -> AppServerDoctorProcessOutput?
) -> AppServerDoctorFeedbackReport? {
    guard let output = runProcess(executable, ["doctor", "--json"], doctorFeedbackReportTimeout),
          let jsonStart = output.stdout.firstIndex(of: "{")
    else {
        return nil
    }
    let json = output.stdout[jsonStart...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard let jsonData = json.data(using: .utf8),
          let report = try? JSONSerialization.jsonObject(with: jsonData),
          JSONSerialization.isValidJSONObject(report)
    else {
        return nil
    }
    let prettyData = (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])) ?? jsonData
    return AppServerDoctorFeedbackReport(
        attachment: FeedbackAttachment(
            filename: doctorReportAttachmentFilename,
            contentType: "application/json",
            data: prettyData
        ),
        tags: doctorReportTags(report)
    )
}

struct AppServerDoctorProcessOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private func runDoctorProcessForFeedback(
    executable: URL,
    arguments: [String],
    timeout: TimeInterval
) -> AppServerDoctorProcessOutput? {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
        try process.run()
    } catch {
        return nil
    }

    let deadline = DispatchTime.now() + timeout
    guard finished.wait(timeout: deadline) == .success else {
        process.terminate()
        return nil
    }

    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    return AppServerDoctorProcessOutput(
        stdout: String(decoding: stdout, as: UTF8.self),
        stderr: String(decoding: stderr, as: UTF8.self),
        exitCode: process.terminationStatus
    )
}

func doctorReportTags(_ report: Any) -> [String: String] {
    guard let object = report as? [String: Any] else {
        return [
            "doctor_fail_count": "0",
            "doctor_ok_count": "0",
            "doctor_warning_count": "0"
        ]
    }

    var tags: [String: String] = [:]
    if let overallStatus = object["overallStatus"] as? String {
        tags["doctor_overall_status"] = truncateDoctorTagValue(overallStatus)
    }

    var okCount = 0
    var warningCount = 0
    var failCount = 0
    var failedChecks: [String] = []
    var warningChecks: [String] = []
    for check in doctorCheckValues(object["checks"]) {
        guard let checkObject = check as? [String: Any],
              let status = checkObject["status"] as? String
        else {
            continue
        }
        let id = checkObject["id"] as? String ?? "unknown"
        switch status {
        case "ok":
            okCount += 1
        case "warning":
            warningCount += 1
            warningChecks.append(id)
        case "fail":
            failCount += 1
            failedChecks.append(id)
        default:
            continue
        }
    }

    tags["doctor_fail_count"] = String(failCount)
    tags["doctor_ok_count"] = String(okCount)
    tags["doctor_warning_count"] = String(warningCount)
    if !failedChecks.isEmpty {
        tags["doctor_failed_checks"] = truncateDoctorTagValue(failedChecks.joined(separator: ","))
    }
    if !warningChecks.isEmpty {
        tags["doctor_warning_checks"] = truncateDoctorTagValue(warningChecks.joined(separator: ","))
    }
    return tags
}

private func doctorCheckValues(_ checks: Any?) -> [Any] {
    if let values = checks as? [Any] {
        return values
    }
    if let values = checks as? [String: Any] {
        return values.keys.sorted().compactMap { values[$0] }
    }
    return []
}

private func truncateDoctorTagValue(_ value: String) -> String {
    guard value.unicodeScalars.count > maxDoctorTagValueLength else {
        return value
    }
    let prefix = String(String.UnicodeScalarView(value.unicodeScalars.prefix(maxDoctorTagValueLength - 3)))
    return "\(prefix)..."
}
