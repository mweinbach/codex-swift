import Foundation

public struct ReadinessToken: Hashable, Sendable {
    public let rawValue: Int32

    public init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public enum ReadinessError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    case tokenLockFailed
    case flagAlreadyReady

    public var description: String {
        switch self {
        case .tokenLockFailed:
            return "Failed to acquire readiness token lock"
        case .flagAlreadyReady:
            return "Flag is already ready. Impossible to subscribe"
        }
    }

    public var errorDescription: String? {
        description
    }
}

/// Port of codex-rs/utils/readiness/src/lib.rs.
public final class ReadinessFlag: @unchecked Sendable {
    private static let lockTimeout: TimeInterval = 1.0

    private let lock = NSLock()
    private var ready = false
    private var nextID: Int32 = 1
    private var tokens = Set<ReadinessToken>()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    init(nextID: Int32) {
        self.nextID = nextID
    }

    public var isReady: Bool {
        if lock.try() {
            defer { lock.unlock() }
            if ready {
                return true
            }
            if tokens.isEmpty {
                markReadyLocked()
                return true
            }
            return false
        }

        return false
    }

    public func subscribe() throws -> ReadinessToken {
        try withLock {
            if ready {
                throw ReadinessError.flagAlreadyReady
            }

            while true {
                let token = ReadinessToken(nextID)
                nextID &+= 1
                if token.rawValue != 0, tokens.insert(token).inserted {
                    return token
                }
            }
        }
    }

    @discardableResult
    public func markReady(_ token: ReadinessToken) throws -> Bool {
        try withLock {
            if ready || token.rawValue == 0 {
                return false
            }
            guard tokens.remove(token) != nil else {
                return false
            }

            markReadyLocked()
            return true
        }
    }

    public func waitReady() async {
        if isReady {
            return
        }

        await withCheckedContinuation { continuation in
            addWaiterOrResume(continuation)
        }
    }

    private func lockBeforeDeadline() throws {
        guard lock.lock(before: Date(timeIntervalSinceNow: Self.lockTimeout)) else {
            throw ReadinessError.tokenLockFailed
        }
    }

    private func addWaiterOrResume(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if ready {
            lock.unlock()
            continuation.resume()
            return
        }
        waiters.append(continuation)
        lock.unlock()
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try lockBeforeDeadline()
        defer { lock.unlock() }
        return try body()
    }

    private func markReadyLocked() {
        guard !ready else {
            return
        }
        ready = true
        tokens.removeAll()
        let continuations = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume()
        }
        lock.lock()
    }
}
