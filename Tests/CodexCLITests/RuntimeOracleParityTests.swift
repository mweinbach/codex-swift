import Foundation
import Network
import XCTest

final class RuntimeOracleParityTests: XCTestCase {
    func testCLIHelpMatchesRustOracleModuloBinaryNameAndVersion() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["--help"])
        let swift = try oracle.run(.swift, arguments: ["--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec", "--help"])
        let swift = try oracle.run(.swift, arguments: ["exec", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testReviewHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["review", "--help"])
        let swift = try oracle.run(.swift, arguments: ["review", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testCompletionHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["completion", "--help"])
        let swift = try oracle.run(.swift, arguments: ["completion", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testLoginHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["login", "--help"])
        let swift = try oracle.run(.swift, arguments: ["login", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testLogoutHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["logout", "--help"])
        let swift = try oracle.run(.swift, arguments: ["logout", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testMcpHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["mcp", "--help"])
        let swift = try oracle.run(.swift, arguments: ["mcp", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testPluginHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["plugin", "--help"])
        let swift = try oracle.run(.swift, arguments: ["plugin", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testUpdateHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["update", "--help"])
        let swift = try oracle.run(.swift, arguments: ["update", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testDoctorHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["doctor", "--help"])
        let swift = try oracle.run(.swift, arguments: ["doctor", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testSandboxHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["sandbox", "--help"])
        let swift = try oracle.run(.swift, arguments: ["sandbox", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testDebugHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["debug", "--help"])
        let swift = try oracle.run(.swift, arguments: ["debug", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecPolicyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["execpolicy", "--help"])
        let swift = try oracle.run(.swift, arguments: ["execpolicy", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testApplyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["apply", "--help"])
        let swift = try oracle.run(.swift, arguments: ["apply", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testAppServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["app-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["app-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testRemoteControlHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["remote-control", "--help"])
        let swift = try oracle.run(.swift, arguments: ["remote-control", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testFeaturesHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["features", "--help"])
        let swift = try oracle.run(.swift, arguments: ["features", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testMcpServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["mcp-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["mcp-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testAppHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["app", "--help"])
        let swift = try oracle.run(.swift, arguments: ["app", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["exec-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testResumeHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["resume", "--help"])
        let swift = try oracle.run(.swift, arguments: ["resume", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testForkHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["fork", "--help"])
        let swift = try oracle.run(.swift, arguments: ["fork", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testCloudHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["cloud", "--help"])
        let swift = try oracle.run(.swift, arguments: ["cloud", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testResponsesAPIProxyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["responses-api-proxy", "--help"])
        let swift = try oracle.run(.swift, arguments: ["responses-api-proxy", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testStdioToUDSHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["stdio-to-uds", "--help"])
        let swift = try oracle.run(.swift, arguments: ["stdio-to-uds", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecVersionMatchesRustOracleModuloVersionNumber() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec", "--version"])
        let swift = try oracle.run(.swift, arguments: ["exec", "--version"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedVersionLine(swift.stdout), normalizedVersionLine(rust.stdout))
    }

    func testReviewVersionRejectionMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-home")
        let environment = [
            "CODEX_HOME": codexHome.url.path,
            "NO_COLOR": "1",
            "TERM": "dumb"
        ]

        let rust = try oracle.run(.rust, arguments: ["review", "--version"], environment: environment)
        let swift = try oracle.run(.swift, arguments: ["review", "--version"], environment: environment)

        XCTAssertEqual(rust.exitCode, 2, rust.stderr)
        XCTAssertEqual(swift.exitCode, 2, swift.stderr)
        XCTAssertEqual(swift.stdout, rust.stdout)
        XCTAssertEqual(normalizedCommandError(swift.stderr), normalizedCommandError(rust.stderr))
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

    func testNonInteractiveNoToolsPromptMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let server = try RuntimeOracleResponsesServer(
            responseBodies: [
                noToolsAssistantMessageSSE(text: "oracle says hi"),
                noToolsAssistantMessageSSE(text: "oracle says hi")
            ]
        )

        let rust = try oracle.runNonInteractiveExec(
            .rust,
            responsesBaseURL: server.baseURL,
            prompt: "oracle prompt"
        )
        let swift = try oracle.runNonInteractiveExec(
            .swift,
            responsesBaseURL: server.baseURL,
            prompt: "oracle prompt"
        )

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(
            try normalizedExecJSONLines(swift.stdout),
            try normalizedExecJSONLines(rust.stdout)
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
        currentDirectory: URL? = nil,
        keepStdinOpenAfterWrite: TimeInterval = 0
    ) throws -> RuntimeOracleProcessOutput {
        try runProcess(
            executable: executable(for: kind),
            arguments: arguments,
            stdin: stdin,
            environment: environment,
            currentDirectory: currentDirectory,
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

    func runNonInteractiveExec(
        _ kind: RuntimeOracleProcessKind,
        responsesBaseURL: String,
        prompt: String
    ) throws -> RuntimeOracleProcessOutput {
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-home")
        let cwd = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-cwd")
        let providerOverride = """
        model_providers.oracle={ name = "Oracle", base_url = "\(responsesBaseURL)", env_key = "CODEX_API_KEY", wire_api = "responses", supports_websockets = false, request_max_retries = 0, stream_max_retries = 0 }
        """

        return try run(
            kind,
            arguments: [
                "--disable", "plugins",
                "-c", #"model_provider="oracle""#,
                "-c", providerOverride,
                "exec",
                "--skip-git-repo-check",
                "--json",
                prompt
            ],
            stdin: nil,
            environment: [
                "CODEX_HOME": codexHome.url.path,
                "CODEX_SQLITE_HOME": codexHome.url.path,
                "CODEX_API_KEY": "dummy",
                "NO_COLOR": "1",
                "TERM": "dumb"
            ],
            currentDirectory: cwd.url
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
    currentDirectory: URL?,
    keepStdinOpenAfterWrite: TimeInterval
) throws -> RuntimeOracleProcessOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.currentDirectoryURL = currentDirectory

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
        .replacingOccurrences(of: "\u{2011}", with: "-")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            String(line).replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedVersionLine(_ text: String) -> String {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = normalized.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let commandName = parts.first else {
        return normalized
    }
    return "\(commandName) <version>"
}

private func normalizedCommandError(_ text: String) -> String {
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

private func normalizedExecJSONLines(_ stdout: String) throws -> [String] {
    try stdout
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { line in
            let data = Data(line.utf8)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuntimeOracleError.invalidJSONLine(line)
            }
            if object["thread_id"] is String {
                object["thread_id"] = "<THREAD_ID>"
            }
            let normalizedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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

private func noToolsAssistantMessageSSE(text: String) -> String {
    let encodedText = (try? JSONEncoder().encode(text))
        .flatMap { String(data: $0, encoding: .utf8) } ?? #""""#
    return [
        #"event: response.created"#,
        #"data: {"type":"response.created","response":{"id":"resp-1"}}"#,
        "",
        #"event: response.output_item.done"#,
        #"data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","id":"msg-1","content":[{"type":"output_text","text":\#(encodedText)}]}}"#,
        "",
        #"event: response.completed"#,
        #"data: {"type":"response.completed","response":{"id":"resp-1"}}"#,
        "",
        ""
    ].joined(separator: "\n")
}

// NWListener invokes callbacks as @Sendable closures. This test server keeps
// mutable response state behind a lock and routes network callbacks through one
// serial queue, so sharing the helper across those callbacks is constrained.
private final class RuntimeOracleResponsesServer: @unchecked Sendable {
    private(set) var baseURL = ""

    private let listener: NWListener
    private let queue = DispatchQueue(label: "codex.runtime-oracle.responses-server")
    private let lock = NSLock()
    private var responseBodies: [Data]

    init(responseBodies: [String]) throws {
        self.responseBodies = responseBodies.map { Data($0.utf8) }
        listener = try NWListener(using: .tcp, on: .any)

        let ready = DispatchSemaphore(value: 0)
        let startupState = RuntimeOracleServerStartupState()

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                startupState.setError(error)
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + .seconds(3)) == .success else {
            throw RuntimeOracleError.timeout("start Responses oracle server")
        }
        if let error = startupState.error {
            throw error
        }
        guard let port = listener.port else {
            throw RuntimeOracleError.serverStartup("Responses oracle server did not report a port")
        }
        baseURL = "http://127.0.0.1:\(port.rawValue)/v1"
    }

    deinit {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            guard isComplete || error != nil || self.requestIsComplete(requestData) else {
                self.receiveRequest(on: connection, accumulated: requestData)
                return
            }
            let request = String(decoding: requestData, as: UTF8.self)
            let response = self.httpResponse(for: request)
            connection.send(content: response, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func requestIsComplete(_ data: Data) -> Bool {
        let headerEnd: Int
        if let range = data.range(of: Data([13, 10, 13, 10])) {
            headerEnd = range.upperBound
        } else if let range = data.range(of: Data([10, 10])) {
            headerEnd = range.upperBound
        } else {
            return false
        }

        let headerData = data.prefix(headerEnd)
        let headers = String(decoding: headerData, as: UTF8.self)
        let contentLength = headers
            .split(separator: "\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                let value = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.flatMap(Int.init)
            }

        return data.count >= headerEnd + (contentLength ?? 0)
    }

    private func httpResponse(for request: String) -> Data {
        let contentType: String
        let body: Data
        if request.hasPrefix("GET /v1/models ") {
            contentType = "application/json"
            body = Data(#"{"object":"list","data":[]}"#.utf8)
        } else {
            contentType = "text/event-stream"
            body = nextResponseBody()
        }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func nextResponseBody() -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !responseBodies.isEmpty else {
            return Data(noToolsAssistantMessageSSE(text: "oracle fallback").utf8)
        }
        return responseBodies.removeFirst()
    }
}

// NWListener reports startup through @Sendable callbacks; this tiny locked box
// keeps the cross-queue handoff explicit for the test-only fixture server.
private final class RuntimeOracleServerStartupState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.withLock { storedError }
    }

    func setError(_ error: Error) {
        lock.withLock {
            storedError = error
        }
    }
}

private enum RuntimeOracleError: Error, CustomStringConvertible {
    case invalidJSONLine(String)
    case serverStartup(String)
    case timeout(String)

    var description: String {
        switch self {
        case let .invalidJSONLine(line):
            "invalid JSON line: \(line)"
        case let .serverStartup(message):
            message
        case let .timeout(command):
            "timed out running \(command)"
        }
    }
}
