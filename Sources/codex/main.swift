import CodexChatGPT
import CodexCLI
import CodexCore
import Darwin
import Foundation

let cli = CodexCLI()
let exitCode = await cli.runAsync(arguments: Array(CommandLine.arguments.dropFirst()), applyRunner: { request in
    let codexHome = try CodexHome.find()
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        overrides: request.configOverrides
    )
    let client = ChatGPTTaskClient(configuration: ChatGPTClientConfiguration(
        chatgptBaseURL: settings.chatgptBaseURL,
        codexHome: codexHome,
        authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode
    ))
    _ = try await client.applyTask(taskID: request.taskID)
    return "Successfully applied diff"
})
exit(exitCode)
