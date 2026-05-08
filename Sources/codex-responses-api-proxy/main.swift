import CodexCore
import CodexResponsesAPIProxy
import Darwin
import Foundation

ProcessHardening.preMainHardening()

switch parseArguments(Array(CommandLine.arguments.dropFirst())) {
case .help:
    print(helpText())
    exit(0)
case let .failure(message, exitCode):
    fputs(message + "\n", Darwin.stderr)
    exit(exitCode)
case let .run(options):
    do {
        try ResponsesAPIProxy.run(options: options)
        fputs("server stopped unexpectedly\n", Darwin.stderr)
        exit(1)
    } catch {
        fputs("\(error)\n", Darwin.stderr)
        exit(1)
    }
}

private enum ParsedArguments {
    case run(ResponsesAPIProxyOptions)
    case help
    case failure(String, Int32)
}

private func parseArguments(_ arguments: [String]) -> ParsedArguments {
    var port: UInt16?
    var serverInfoPath: URL?
    var httpShutdown = false
    var upstreamURL = ResponsesAPIProxyOptions.defaultUpstreamURL

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            return .help
        case "--http-shutdown":
            httpShutdown = true
            index += 1
        case "--port":
            guard index + 1 < arguments.count else {
                return .failure("codex-responses-api-proxy: missing value for --port", 2)
            }
            guard let parsedPort = UInt16(arguments[index + 1]) else {
                return .failure("codex-responses-api-proxy: invalid value for --port: \(arguments[index + 1])", 2)
            }
            port = parsedPort
            index += 2
        case let value where value.hasPrefix("--port="):
            let rawPort = String(value.dropFirst("--port=".count))
            guard let parsedPort = UInt16(rawPort) else {
                return .failure("codex-responses-api-proxy: invalid value for --port: \(rawPort)", 2)
            }
            port = parsedPort
            index += 1
        case "--server-info":
            guard index + 1 < arguments.count else {
                return .failure("codex-responses-api-proxy: missing value for --server-info", 2)
            }
            serverInfoPath = URL(fileURLWithPath: arguments[index + 1])
            index += 2
        case let value where value.hasPrefix("--server-info="):
            serverInfoPath = URL(fileURLWithPath: String(value.dropFirst("--server-info=".count)))
            index += 1
        case "--upstream-url":
            guard index + 1 < arguments.count else {
                return .failure("codex-responses-api-proxy: missing value for --upstream-url", 2)
            }
            upstreamURL = arguments[index + 1]
            index += 2
        case let value where value.hasPrefix("--upstream-url="):
            upstreamURL = String(value.dropFirst("--upstream-url=".count))
            index += 1
        case let value where value.hasPrefix("-"):
            return .failure("codex-responses-api-proxy: unsupported option: \(value)", 2)
        default:
            return .failure("codex-responses-api-proxy: unexpected argument: \(argument)", 2)
        }
    }

    return .run(ResponsesAPIProxyOptions(
        port: port,
        serverInfoPath: serverInfoPath,
        httpShutdown: httpShutdown,
        upstreamURL: upstreamURL
    ))
}

private func helpText() -> String {
    """
    Minimal OpenAI responses proxy

    Usage:
      codex-responses-api-proxy [--port <PORT>] [--server-info <FILE>] [--http-shutdown] [--upstream-url <URL>]

    Options:
      --port <PORT>          Port to listen on. If not set, an ephemeral port is used.
      --server-info <FILE>   Path to a JSON file to write startup info.
      --http-shutdown        Enable HTTP shutdown endpoint at GET /shutdown.
      --upstream-url <URL>   Absolute URL the proxy should forward requests to.
      -h, --help             Print help.
    """
}
