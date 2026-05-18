import Foundation
import CodexCore

struct AppServerLiveMultiAgentToolExecutor {
    let currentThreadID: ThreadId
    let currentSessionSource: SessionSource
    let stateStore: SQLiteAgentGraphStore?
    let isTurnRunning: @Sendable (String) async -> Bool
    let agentLastTaskMessage: @Sendable (String) async -> String?
    let queueMailboxCommunications: @Sendable (String, [InterAgentCommunication]) async -> Void
    let recordAgentLastTaskMessage: @Sendable (String, String) async -> Void
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
        case "list_agents":
            return await executeListAgents(arguments: arguments, callID: callID)
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
            await recordAgentLastTaskMessage(target.threadID.description, prompt)
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

    private func executeListAgents(
        arguments: String,
        callID: String
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: ListAgentsToolArguments
        do {
            args = try JSONDecoder().decode(ListAgentsToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse list_agents arguments: \(error)", success: false)
        }

        do {
            let prefix = try resolvedListPrefix(args.pathPrefix)
            let rootPath = AgentPath.root
            var agents: [ListedLiveAgent] = []
            if Self.agentPath(rootPath, matchesPrefix: prefix) {
                agents.append(ListedLiveAgent(
                    agentName: rootPath.description,
                    agentStatus: await status(for: currentThreadID),
                    lastTaskMessage: "Main thread"
                ))
            }
            if let stateStore {
                let threadMetadata = try await stateStore.listThreadsWithAgentPaths()
                for metadata in threadMetadata {
                    guard metadata.id != currentThreadID,
                          let rawPath = metadata.agentPath,
                          let agentPath = try? AgentPath(validating: rawPath),
                          !agentPath.isRoot,
                          Self.agentPath(agentPath, matchesPrefix: prefix)
                    else {
                        continue
                    }
                    agents.append(ListedLiveAgent(
                        agentName: agentPath.description,
                        agentStatus: await status(for: metadata.id),
                        lastTaskMessage: await agentLastTaskMessage(metadata.id.description)
                    ))
                }
            }
            return Self.jsonOutput(callID: callID, value: ListAgentsToolResult(agents: agents), success: true)
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }
    }

    private func resolvedListPrefix(_ pathPrefix: String?) throws -> AgentPath? {
        guard let pathPrefix else {
            return nil
        }
        let currentAgentPath = currentSessionSource.agentPath ?? .root
        do {
            return try currentAgentPath.resolve(pathPrefix)
        } catch {
            throw AppServerLiveMultiAgentToolError(message: String(describing: error))
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

    private func status(for threadID: ThreadId) async -> AgentStatus {
        await isTurnRunning(threadID.description) ? .running : .completed(nil)
    }

    private static func agentPath(_ agentPath: AgentPath, matchesPrefix prefix: AgentPath?) -> Bool {
        guard let prefix else {
            return true
        }
        if agentPath == prefix {
            return true
        }
        return agentPath.description.hasPrefix("\(prefix.description)/")
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

    private static func jsonOutput<T: Encodable>(
        callID: String,
        value: T,
        success: Bool
    ) -> NonInteractiveExec.FunctionCallExecutionResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return output(
                callID: callID,
                content: String(decoding: try encoder.encode(value), as: UTF8.self),
                success: success
            )
        } catch {
            return output(
                callID: callID,
                content: "failed to encode list_agents result: \(error)",
                success: false
            )
        }
    }
}

private struct AgentMessageToolArguments: Decodable {
    let target: String
    let message: String
}

private struct ListAgentsToolArguments: Decodable {
    let pathPrefix: String?

    private enum CodingKeys: String, CodingKey {
        case pathPrefix = "path_prefix"
    }
}

private struct ListAgentsToolResult: Encodable {
    let agents: [ListedLiveAgent]
}

private struct ListedLiveAgent: Encodable, Equatable {
    let agentName: String
    let agentStatus: AgentStatus
    let lastTaskMessage: String?

    private enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case agentStatus = "agent_status"
        case lastTaskMessage = "last_task_message"
    }
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
