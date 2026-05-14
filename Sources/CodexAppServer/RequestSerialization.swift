import Foundation

enum AppServerRequestSerializationScope: Equatable, Sendable {
    case global(String)
    case globalSharedRead(String)
    case thread(threadID: String)
    case threadPath(String)
    case commandExecProcess(connectionID: String, processID: String)
    case process(connectionID: String, processHandle: String)
    case fuzzyFileSearchSession(sessionID: String)
    case fsWatch(connectionID: String, watchID: String)
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

    static func from(scope: AppServerRequestSerializationScope) -> (Self, RequestSerializationAccess) {
        switch scope {
        case let .global(name):
            (.global(name), .exclusive)
        case let .globalSharedRead(name):
            (.global(name), .sharedRead)
        case let .thread(threadID):
            (.thread(threadID: threadID), .exclusive)
        case let .threadPath(path):
            (.threadPath(path), .exclusive)
        case let .commandExecProcess(connectionID, processID):
            (.commandExecProcess(connectionID: connectionID, processID: processID), .exclusive)
        case let .process(connectionID, processHandle):
            (.process(connectionID: connectionID, processHandle: processHandle), .exclusive)
        case let .fuzzyFileSearchSession(sessionID):
            (.fuzzyFileSearchSession(sessionID: sessionID), .exclusive)
        case let .fsWatch(connectionID, watchID):
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
        switch method {
        case "config/read", "plugin/list", "skills/list":
            .globalSharedRead("config")
        case "config/value/write",
             "config/batchWrite",
             "skills/config/write",
             "plugin/install",
             "plugin/uninstall",
             "marketplace/add",
             "marketplace/remove",
             "marketplace/upgrade":
            .global("config")
        default:
            nil
        }
    }
}
