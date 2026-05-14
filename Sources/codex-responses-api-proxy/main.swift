import CodexCore
import CodexResponsesAPIProxy
import Darwin
import Foundation

ProcessHardening.preMainHardening()

switch ResponsesAPIProxyCommandLine.parseArguments(Array(CommandLine.arguments.dropFirst())) {
case .help:
    print(ResponsesAPIProxyCommandLine.helpText())
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
