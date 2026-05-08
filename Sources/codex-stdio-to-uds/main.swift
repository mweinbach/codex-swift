import CodexStdioToUDS
import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let socketPath = arguments.first else {
    fputs("Usage: codex-stdio-to-uds <socket-path>\n", stderr)
    exit(1)
}

guard arguments.count == 1 else {
    fputs("Expected exactly one argument: <socket-path>\n", stderr)
    exit(1)
}

do {
    try StdioToUDS.run(socketPath: socketPath)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
