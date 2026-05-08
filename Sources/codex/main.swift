import CodexCLI
import Darwin

let cli = CodexCLI()
let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
