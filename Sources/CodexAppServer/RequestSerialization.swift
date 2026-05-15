import Foundation

enum AppServerRequestSerializationScope: Equatable, Sendable {
    case global(String)
    case globalSharedRead(String)
    case thread(threadID: String)
    case threadPath(String)
    case commandExecProcess(processID: String)
    case process(processHandle: String)
    case fuzzyFileSearchSession(sessionID: String)
    case fsWatch(watchID: String)
    case mcpOauth(serverName: String)
}

enum RequestSerializationAccess: Equatable, Sendable {
    case exclusive
    case sharedRead
}

enum RequestSerializationQueueKey: Equatable, Hashable, Sendable {
    case global(String)
    case thread(threadID: String)
    case threadPath(String)
    case commandExecProcess(connectionID: String, processID: String)
    case process(connectionID: String, processHandle: String)
    case fuzzyFileSearchSession(sessionID: String)
    case fsWatch(connectionID: String, watchID: String)
    case mcpOauth(serverName: String)

    static func from(
        scope: AppServerRequestSerializationScope,
        connectionID: String = ""
    ) -> (Self, RequestSerializationAccess) {
        switch scope {
        case let .global(name):
            (.global(name), .exclusive)
        case let .globalSharedRead(name):
            (.global(name), .sharedRead)
        case let .thread(threadID):
            (.thread(threadID: threadID), .exclusive)
        case let .threadPath(path):
            (.threadPath(path), .exclusive)
        case let .commandExecProcess(processID):
            (.commandExecProcess(connectionID: connectionID, processID: processID), .exclusive)
        case let .process(processHandle):
            (.process(connectionID: connectionID, processHandle: processHandle), .exclusive)
        case let .fuzzyFileSearchSession(sessionID):
            (.fuzzyFileSearchSession(sessionID: sessionID), .exclusive)
        case let .fsWatch(watchID):
            (.fsWatch(connectionID: connectionID, watchID: watchID), .exclusive)
        case let .mcpOauth(serverName):
            (.mcpOauth(serverName: serverName), .exclusive)
        }
    }
}

actor RequestSerializationQueues {
    typealias Operation = @Sendable () async -> Void

    private struct QueuedRequest: Sendable {
        let access: RequestSerializationAccess
        let operation: Operation
    }

    private var queues: [RequestSerializationQueueKey: [QueuedRequest]] = [:]

    func enqueue(
        key: RequestSerializationQueueKey,
        access: RequestSerializationAccess,
        operation: @escaping Operation
    ) {
        let request = QueuedRequest(access: access, operation: operation)
        let shouldStartDraining = queues[key] == nil
        queues[key, default: []].append(request)

        if shouldStartDraining {
            Task {
                await self.drain(key: key)
            }
        }
    }

    private func nextBatch(for key: RequestSerializationQueueKey) -> [QueuedRequest]? {
        guard var queue = queues[key] else {
            return nil
        }
        guard !queue.isEmpty else {
            queues.removeValue(forKey: key)
            return nil
        }

        let first = queue.removeFirst()
        var batch = [first]
        if first.access == .sharedRead {
            while queue.first?.access == .sharedRead {
                batch.append(queue.removeFirst())
            }
        }
        queues[key] = queue
        return batch
    }

    private func drain(key: RequestSerializationQueueKey) async {
        while let batch = nextBatch(for: key) {
            await withTaskGroup(of: Void.self) { group in
                for request in batch {
                    group.addTask {
                        await request.operation()
                    }
                }
            }
        }
    }
}

extension CodexAppServer {
    static func requestSerializationScope(forMethod method: String) -> AppServerRequestSerializationScope? {
        requestSerializationScope(forMethod: method, params: nil)
    }

    static func requestSerializationScope(
        forMethod method: String,
        params: [String: Any]?
    ) -> AppServerRequestSerializationScope? {
        switch method {
        case "thread/resume", "thread/fork":
            if let threadID = stringScopeParam(params?["threadId"]), !threadID.isEmpty {
                return .thread(threadID: threadID)
            }
            if let path = stringScopeParam(params?["path"]) {
                return .threadPath(path)
            }
            return .thread(threadID: "")
        case "thread/archive",
             "thread/unsubscribe",
             "thread/increment_elicitation",
             "thread/decrement_elicitation",
             "thread/name/set",
             "thread/goal/set",
             "thread/goal/get",
             "thread/goal/clear",
             "thread/metadata/update",
             "thread/memoryMode/set",
             "thread/unarchive",
             "thread/compact/start",
             "thread/shellCommand",
             "thread/approveGuardianDeniedAction",
             "thread/backgroundTerminals/clean",
             "thread/rollback",
             "thread/read",
             "thread/inject_items",
             "turn/start",
             "turn/steer",
             "turn/interrupt",
             "thread/realtime/start",
             "thread/realtime/appendAudio",
             "thread/realtime/appendText",
             "thread/realtime/stop",
             "review/start",
             "mcpServer/tool/call":
            return stringScopeParam(params?["threadId"]).map { .thread(threadID: $0) }
        case "config/read", "plugin/list", "skills/list":
            return .globalSharedRead("config")
        case "config/value/write",
             "config/batchWrite",
             "configRequirements/read",
             "externalAgentConfig/detect",
             "externalAgentConfig/import",
             "experimentalFeature/list",
             "experimentalFeature/enablement/set",
             "hooks/list",
             "skills/config/write",
             "plugin/read",
             "plugin/skill/read",
             "plugin/share/save",
             "plugin/share/updateTargets",
             "plugin/share/list",
             "plugin/share/delete",
             "plugin/install",
             "plugin/uninstall",
             "marketplace/add",
             "marketplace/remove",
             "marketplace/upgrade",
             "windowsSandbox/readiness":
            return .global("config")
        case "memory/reset":
            return .global("memory")
        case "config/mcpServer/reload", "mcpServerStatus/list":
            return .global("mcp-registry")
        case "windowsSandbox/setupStart":
            return .global("windows-sandbox-setup")
        case "account/login/start",
             "account/login/cancel",
             "account/logout",
             "account/read",
             "account/sendAddCreditsNudgeEmail",
             "getAuthStatus":
            return .global("account-auth")
        case "mcpServer/oauth/login":
            return stringScopeParam(params?["name"]).map { .mcpOauth(serverName: $0) }
        case "mcpServer/resource/read":
            return stringScopeParam(params?["threadId"]).map { .thread(threadID: $0) }
        case "command/exec":
            return stringScopeParam(params?["processId"]).map {
                .commandExecProcess(processID: $0)
            }
        case "command/exec/write", "command/exec/terminate", "command/exec/resize":
            return stringScopeParam(params?["processId"]).map {
                .commandExecProcess(processID: $0)
            }
        case "process/spawn", "process/writeStdin", "process/kill", "process/resizePty":
            return stringScopeParam(params?["processHandle"]).map {
                .process(processHandle: $0)
            }
        case "fs/watch", "fs/unwatch":
            return stringScopeParam(params?["watchId"]).map {
                .fsWatch(watchID: $0)
            }
        case "fuzzyFileSearch/sessionStart",
             "fuzzyFileSearch/sessionUpdate",
             "fuzzyFileSearch/sessionStop":
            return stringScopeParam(params?["sessionId"]).map {
                .fuzzyFileSearchSession(sessionID: $0)
            }
        default:
            return nil
        }
    }

    private static func stringScopeParam(_ value: Any?) -> String? {
        value as? String
    }
}
