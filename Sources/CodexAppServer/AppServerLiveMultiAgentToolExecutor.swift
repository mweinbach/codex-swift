import Foundation
import CodexCore

struct AppServerLiveMultiAgentToolExecutor {
    let currentThreadID: ThreadId
    let currentSessionSource: SessionSource
    let stateStore: SQLiteAgentGraphStore?
    let isTurnRunning: @Sendable (String) async -> Bool
    let queueMailboxCommunications: @Sendable (String, [InterAgentCommunication]) async -> Void
    let submitPendingWorkTurnIfIdle: @Sendable (String) async -> Bool

    func execute(_ item: ResponseItem) async -> NonInteractiveExec.FunctionCallExecutionResult? {
        guard case let .functionCall(_, name, _, arguments, callID) = item else {
            return nil
        }
        switch name {
        case "send_message":
            return await executeMessageTool(
                name: name,
                arguments: arguments,
                callID: callID,
                triggerTurn: false
            )
        case "followup_task":
            return await executeMessageTool(
                name: name,
                arguments: arguments,
                callID: callID,
                triggerTurn: true
            )
        default:
            return nil
        }
    }

    private func executeMessageTool(
        name: String,
        arguments: String,
        callID: String,
        triggerTurn: Bool
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: AgentMessageToolArguments
        do {
            args = try JSONDecoder().decode(AgentMessageToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse \(name) arguments: \(error)", success: false)
        }

        let prompt = args.message
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.output(callID: callID, content: "Empty message can't be sent to an agent", success: false)
        }

        do {
            let target = try await resolveAgentTarget(args.target)
            guard let receiverAgentPath = target.agentPath else {
                return Self.output(callID: callID, content: "target agent is missing an agent_path", success: false)
            }
            if triggerTurn, receiverAgentPath.isRoot {
                return Self.output(callID: callID, content: "Tasks can't be assigned to the root agent", success: false)
            }

            let startedAt = AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch()
            var runtimeEvents: [EventMessage] = [
                .collabAgentInteractionBegin(CollabAgentInteractionBeginEvent(
                    callID: callID,
                    startedAtMilliseconds: startedAt,
                    senderThreadID: currentThreadID,
                    receiverThreadID: target.threadID,
                    prompt: prompt
                ))
            ]
            let communication = InterAgentCommunication(
                author: currentSessionSource.agentPath ?? .root,
                recipient: receiverAgentPath,
                content: prompt,
                triggerTurn: triggerTurn
            )
            await queueMailboxCommunications(target.threadID.description, [communication])
            if triggerTurn {
                _ = await submitPendingWorkTurnIfIdle(target.threadID.description)
            }

            let status: AgentStatus = await isTurnRunning(target.threadID.description)
                ? .running
                : .completed(nil)
            runtimeEvents.append(.collabAgentInteractionEnd(CollabAgentInteractionEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                receiverThreadID: target.threadID,
                receiverAgentNickname: target.metadata?.agentNickname,
                receiverAgentRole: target.metadata?.agentRole,
                prompt: prompt,
                status: status
            )))
            return Self.output(callID: callID, content: "", success: true, runtimeEvents: runtimeEvents)
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }
    }

    private func resolveAgentTarget(_ target: String) async throws -> ResolvedLiveAgentTarget {
        if let threadID = try? ThreadId(string: target) {
            let metadata = try await stateStore?.getThread(threadID: threadID)
            return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata)
        }

        let currentAgentPath = currentSessionSource.agentPath ?? .root
        let agentPath: AgentPath
        do {
            agentPath = try currentAgentPath.resolve(target)
        } catch {
            throw AppServerLiveMultiAgentToolError(message: String(describing: error))
        }
        guard let stateStore else {
            throw AppServerLiveMultiAgentToolError(message: "live agent path `\(agentPath)` not found")
        }
        guard let threadID = try await stateStore.findThreadByAgentPath(agentPath: agentPath) else {
            throw AppServerLiveMultiAgentToolError(message: "live agent path `\(agentPath)` not found")
        }
        let metadata = try await stateStore.getThread(threadID: threadID)
        return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata)
    }

    private static func output(
        callID: String,
        content: String,
        success: Bool,
        runtimeEvents: [EventMessage] = []
    ) -> NonInteractiveExec.FunctionCallExecutionResult {
        NonInteractiveExec.FunctionCallExecutionResult(
            output: .functionCallOutput(
                callID: callID,
                output: FunctionCallOutputPayload(content: content, success: success)
            ),
            runtimeEvents: runtimeEvents
        )
    }
}

private struct AgentMessageToolArguments: Decodable {
    let target: String
    let message: String
}

private struct ResolvedLiveAgentTarget {
    let threadID: ThreadId
    let metadata: ThreadMetadata?

    var agentPath: AgentPath? {
        guard let rawPath = metadata?.agentPath else {
            return nil
        }
        return try? AgentPath(validating: rawPath)
    }
}

private struct AppServerLiveMultiAgentToolError: Error {
    let message: String
}

private enum AppServerLiveMultiAgentToolClock {
    static func millisecondsSinceEpoch() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
