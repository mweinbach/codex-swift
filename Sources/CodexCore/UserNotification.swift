import Foundation

public enum UserNotification: Equatable, Codable, Sendable {
    case agentTurnComplete(
        threadID: String,
        turnID: String,
        cwd: String,
        client: String? = nil,
        inputMessages: [String],
        lastAssistantMessage: String?
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread-id"
        case turnID = "turn-id"
        case cwd
        case client
        case inputMessages = "input-messages"
        case lastAssistantMessage = "last-assistant-message"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "agent-turn-complete":
            self = .agentTurnComplete(
                threadID: try container.decode(String.self, forKey: .threadID),
                turnID: try container.decode(String.self, forKey: .turnID),
                cwd: try container.decode(String.self, forKey: .cwd),
                client: try container.decodeIfPresent(String.self, forKey: .client),
                inputMessages: try container.decode([String].self, forKey: .inputMessages),
                lastAssistantMessage: try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown user notification type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .agentTurnComplete(threadID, turnID, cwd, client, inputMessages, lastAssistantMessage):
            try container.encode("agent-turn-complete", forKey: .type)
            try container.encode(threadID, forKey: .threadID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeIfPresent(client, forKey: .client)
            try container.encode(inputMessages, forKey: .inputMessages)
            try container.encode(lastAssistantMessage, forKey: .lastAssistantMessage)
        }
    }
}

public struct UserNotifier: Sendable {
    public let notifyCommand: [String]?

    public init(notifyCommand: [String]? = nil) {
        self.notifyCommand = notifyCommand
    }

    public func invocationArguments(for notification: UserNotification) -> [String]? {
        guard let notifyCommand,
              !notifyCommand.isEmpty,
              let json = try? String(data: JSONEncoder().encode(notification), encoding: .utf8)
        else {
            return nil
        }

        return notifyCommand + [json]
    }

    public func notify(_ notification: UserNotification) {
        guard let process = process(for: notification) else {
            return
        }

        try? process.run()
    }

    func process(for notification: UserNotification) -> Process? {
        guard let invocation = invocationArguments(for: notification),
              let executable = invocation.first
        else {
            return nil
        }

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(invocation.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = invocation
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return process
    }
}
