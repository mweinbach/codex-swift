import CodexChatGPT
import CodexCLI
import CodexCore
import Darwin

private struct ApplyRuntimeSettings {
    var chatgptBaseURL = ChatGPTClientConfiguration.defaultBaseURL
    var authStoreMode = AuthCredentialsStoreMode.file

    init(overrides: CliConfigOverrides) throws {
        for (path, value) in try overrides.parseOverrides() {
            switch path {
            case "chatgpt_base_url":
                guard case let .string(baseURL) = value else {
                    throw ApplyRuntimeError.invalidOverrideValue(path)
                }
                chatgptBaseURL = baseURL
            case "cli_auth_credentials_store":
                guard case let .string(rawMode) = value,
                      let mode = AuthCredentialsStoreMode(rawValue: rawMode)
                else {
                    throw ApplyRuntimeError.invalidAuthStoreMode
                }
                authStoreMode = mode
            default:
                continue
            }
        }
    }
}

private enum ApplyRuntimeError: Error, CustomStringConvertible {
    case invalidOverrideValue(String)
    case invalidAuthStoreMode

    var description: String {
        switch self {
        case let .invalidOverrideValue(path):
            return "Invalid override value for \(path)"
        case .invalidAuthStoreMode:
            return "Invalid override value for cli_auth_credentials_store"
        }
    }
}

let cli = CodexCLI()
let exitCode = await cli.runAsync(arguments: Array(CommandLine.arguments.dropFirst()), applyRunner: { request in
    let settings = try ApplyRuntimeSettings(overrides: request.configOverrides)
    let codexHome = try CodexHome.find()
    let client = ChatGPTTaskClient(configuration: ChatGPTClientConfiguration(
        chatgptBaseURL: settings.chatgptBaseURL,
        codexHome: codexHome,
        authCredentialsStoreMode: settings.authStoreMode
    ))
    _ = try await client.applyTask(taskID: request.taskID)
    return "Successfully applied diff"
})
exit(exitCode)
