import Foundation

public protocol Readiness: Sendable {
    func isReady() -> Bool
    func subscribe() async throws -> ReadinessToken
    func markReady(_ token: ReadinessToken) async throws -> Bool
    func waitReady() async
}

public struct ReadinessToken: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public var description: String {
        "Token(\(rawValue))"
    }
}

public enum ReadinessError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    case tokenLockFailed
    case flagAlreadyReady

    public var description: String {
        switch self {
        case .tokenLockFailed:
            "Failed to acquire readiness token lock"
        case .flagAlreadyReady:
            "Flag is already ready. Impossible to subscribe"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public final class ReadinessFlag: Readiness, @unchecked Sendable, CustomDebugStringConvertible {
    private let lock = NSLock()
    private let lockTimeout: TimeInterval
    private var ready = false
    private var nextID: Int32 = 1
    private var tokens: Set<ReadinessToken> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(lockTimeout: TimeInterval = 1.0) {
        self.lockTimeout = lockTimeout
    }

    public var debugDescription: String {
        "ReadinessFlag(ready: \(isReadyLoaded()))"
    }

    public func isReady() -> Bool {
        lock.lock()
        if ready {
            lock.unlock()
            return true
        }

        if tokens.isEmpty {
            ready = true
            let continuations = waiters
            waiters.removeAll()
            lock.unlock()
            continuations.forEach { $0.resume() }
            return true
        }

        lock.unlock()
        return false
    }

    public func subscribe() async throws -> ReadinessToken {
        try withLockedState {
            guard !ready else {
                throw ReadinessError.flagAlreadyReady
            }

            let token = ReadinessToken(rawValue: nextID)
            nextID &+= 1
            if nextID == 0 {
                nextID = 1
            }
            tokens.insert(token)
            return token
        }
    }

    public func markReady(_ token: ReadinessToken) async throws -> Bool {
        if token.rawValue == 0 {
            return false
        }

        let continuations = try withLockedState {
            if ready {
                return nil as [CheckedContinuation<Void, Never>]?
            }
            guard tokens.remove(token) != nil else {
                return nil
            }

            ready = true
            tokens.removeAll()
            let continuations = waiters
            waiters.removeAll()
            return continuations
        }

        guard let continuations else {
            return false
        }
        continuations.forEach { $0.resume() }
        return true
    }

    public func waitReady() async {
        if isReady() {
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if ready {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    private func isReadyLoaded() -> Bool {
        lock.lock()
        let value = ready
        lock.unlock()
        return value
    }

    private func withLockedState<R>(_ body: () throws -> R) throws -> R {
        guard lock.lock(before: Date(timeIntervalSinceNow: lockTimeout)) else {
            throw ReadinessError.tokenLockFailed
        }
        defer {
            lock.unlock()
        }
        return try body()
    }
}
