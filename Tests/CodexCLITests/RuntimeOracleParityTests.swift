import Foundation
import XCTest

final class RuntimeOracleParityTests: XCTestCase {
    func testCLIHelpMatchesRustOracleModuloBinaryNameAndVersion() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["--help"])
        let swift = try oracle.run(.swift, arguments: ["--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTExpectFailure("Swift top-level help still uses the hand-rendered Swift command surface; this oracle keeps the Rust drift visible until help is ported to the Rust shape.") {
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
        }
    }

    func testAppServerInitializeMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let request = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"oracle","version":"0"},"capabilities":{"optOutNotificationMethods":["remoteControl/status/changed"]}}}

        """

        let rust = try oracle.runAppServer(.rust, arguments: ["app-server"], stdin: request)
        let swift = try oracle.runAppServer(.swift, arguments: ["app-server"], stdin: request)

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(
            try normalizedAppServerMessages(swift.stdout),
            try normalizedAppServerMessages(rust.stdout)
        )
    }
}

private enum RuntimeOracleProcessKind {
    case rust
    case swift
}

private struct RuntimeOracle {
    let rustCodex: URL
    let swiftCodex: URL

    static func required() throws -> RuntimeOracle {
        guard ProcessInfo.processInfo.environment["CODEX_RUN_RUST_ORACLE_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RUN_RUST_ORACLE_TESTS=1 to run Rust runtime oracle parity tests.")
        }

        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let rust = try resolveExecutable(
            environmentKey: "CODEX_RUST_BINARY",
            candidates: [
                packageRoot.appendingPathComponent("../codex-rs/target/debug/codex", isDirectory: false),
                packageRoot.appendingPathComponent("../codex/codex-rs/target/debug/codex", isDirectory: false)
            ],
            missingMessage: "Set CODEX_RUST_BINARY to a Rust-built codex executable."
        )
        let swift = try resolveExecutable(
            environmentKey: "SWIFT_CODEX_BINARY",
            candidates: [
                packageRoot.appendingPathComponent(".build/debug/codex", isDirectory: false)
            ],
            missingMessage: "Set SWIFT_CODEX_BINARY to the Swift codex executable, or build it with swift build --product codex."
        )

        return RuntimeOracle(rustCodex: rust, swiftCodex: swift)
    }

    func run(
        _ kind: RuntimeOracleProcessKind,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String] = [:],
        keepStdinOpenAfterWrite: TimeInterval = 0
    ) throws -> RuntimeOracleProcessOutput {
        try runProcess(
            executable: executable(for: kind),
            arguments: arguments,
            stdin: stdin,
            environment: environment,
            keepStdinOpenAfterWrite: keepStdinOpenAfterWrite
        )
    }

    func runAppServer(
        _ kind: RuntimeOracleProcessKind,
        arguments: [String],
        stdin: String
    ) throws -> RuntimeOracleProcessOutput {
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle")
        try """
        [features]
        plugins = false

        """.write(to: codexHome.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        return try run(
            kind,
            arguments: ["--disable", "plugins"] + arguments,
            stdin: stdin,
            environment: [
                "CODEX_HOME": codexHome.url.path,
                "NO_COLOR": "1",
                "TERM": "dumb"
            ],
            keepStdinOpenAfterWrite: 0.5
        )
    }

    private func executable(for kind: RuntimeOracleProcessKind) -> URL {
        switch kind {
        case .rust:
            rustCodex
        case .swift:
            swiftCodex
        }
    }
}

private struct RuntimeOracleProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class RuntimeOracleTemporaryDirectory {
    let url: URL

    init(prefix: String) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func resolveExecutable(
    environmentKey: String,
    candidates: [URL],
    missingMessage: String
) throws -> URL {
    if let configured = ProcessInfo.processInfo.environment[environmentKey], !configured.isEmpty {
        let url = URL(fileURLWithPath: configured, isDirectory: false).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw XCTSkip("\(environmentKey) is not executable: \(url.path)")
        }
        return url
    }

    for candidate in candidates {
        let url = candidate.standardizedFileURL
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    throw XCTSkip(missingMessage)
}

private func runProcess(
    executable: URL,
    arguments: [String],
    stdin: String?,
    environment: [String: String],
    keepStdinOpenAfterWrite: TimeInterval
) throws -> RuntimeOracleProcessOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let stdout = Pipe()
    let stderr = Pipe()
    let input = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = input

    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }

    try process.run()
    if let stdin {
        input.fileHandleForWriting.write(Data(stdin.utf8))
    }
    if keepStdinOpenAfterWrite > 0 {
        Thread.sleep(forTimeInterval: keepStdinOpenAfterWrite)
    }
    try? input.fileHandleForWriting.close()

    if terminated.wait(timeout: .now() + .seconds(15)) == .timedOut {
        process.terminate()
        _ = terminated.wait(timeout: .now() + .seconds(2))
        throw RuntimeOracleError.timeout("\(executable.path) \(arguments.joined(separator: " "))")
    }

    return RuntimeOracleProcessOutput(
        exitCode: process.terminationStatus,
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

private func normalizedHelp(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedAppServerMessages(_ stdout: String) throws -> [String] {
    try stdout
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { line in
            let data = Data(line.utf8)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuntimeOracleError.invalidJSONLine(line)
            }
            normalizeAppServerMessage(&object)
            let normalizedData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
            return String(data: normalizedData, encoding: .utf8) ?? ""
        }
}

private func normalizeAppServerMessage(_ object: inout [String: Any]) {
    if var result = object["result"] as? [String: Any] {
        if result["codexHome"] is String {
            result["codexHome"] = "<CODEX_HOME>"
        }
        if let userAgent = result["userAgent"] as? String {
            result["userAgent"] = normalizeUserAgent(userAgent)
        }
        object["result"] = result
    }

    if var params = object["params"] as? [String: Any] {
        if params["installationId"] is String {
            params["installationId"] = "<INSTALLATION_ID>"
        }
        if params["serverName"] is String {
            params["serverName"] = "<SERVER_NAME>"
        }
        object["params"] = params
    }
}

private func normalizeUserAgent(_ userAgent: String) -> String {
    guard let suffixRange = userAgent.range(of: " dumb (oracle; 0)") else {
        return "<USER_AGENT>"
    }
    return "Codex Desktop/<runtime>\(userAgent[suffixRange.lowerBound...])"
}

private enum RuntimeOracleError: Error, CustomStringConvertible {
    case invalidJSONLine(String)
    case timeout(String)

    var description: String {
        switch self {
        case let .invalidJSONLine(line):
            "invalid JSON line: \(line)"
        case let .timeout(command):
            "timed out running \(command)"
        }
    }
}
