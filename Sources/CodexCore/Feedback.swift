import Foundation

private let defaultFeedbackMaxBytes = 4 * 1024 * 1024

public final class CodexFeedback: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: FeedbackRingBuffer

    public convenience init() {
        self.init(capacity: defaultFeedbackMaxBytes)
    }

    init(capacity: Int) {
        self.ring = FeedbackRingBuffer(capacity: capacity)
    }

    public func makeWriter() -> FeedbackWriter {
        FeedbackWriter(feedback: self)
    }

    public func snapshot(sessionID: ConversationId?) -> CodexLogSnapshot {
        let bytes = withLockedRing { $0.snapshotBytes() }
        let threadID = sessionID?.description ?? "no-active-thread-\(ConversationId())"
        return CodexLogSnapshot(bytes: bytes, threadID: threadID)
    }

    fileprivate func write(_ bytes: [UInt8]) -> Int {
        withLockedRing { $0.push(bytes) }
        return bytes.count
    }

    private func withLockedRing<T>(_ body: (inout FeedbackRingBuffer) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&ring)
    }
}

public final class FeedbackWriter: @unchecked Sendable {
    private let feedback: CodexFeedback

    fileprivate init(feedback: CodexFeedback) {
        self.feedback = feedback
    }

    @discardableResult
    public func write(_ data: Data) -> Int {
        feedback.write(Array(data))
    }

    @discardableResult
    public func write(_ bytes: [UInt8]) -> Int {
        feedback.write(bytes)
    }

    public func flush() {}
}

struct FeedbackRingBuffer: Equatable, Sendable {
    private let max: Int
    private var bytes: [UInt8] = []

    init(capacity: Int) {
        self.max = Swift.max(0, capacity)
        self.bytes.reserveCapacity(self.max)
    }

    var count: Int {
        bytes.count
    }

    mutating func push(_ data: [UInt8]) {
        guard !data.isEmpty, max > 0 else {
            return
        }

        if data.count >= max {
            bytes = Array(data.suffix(max))
            return
        }

        let needed = bytes.count + data.count
        if needed > max {
            bytes.removeFirst(needed - max)
        }
        bytes.append(contentsOf: data)
    }

    func snapshotBytes() -> [UInt8] {
        bytes
    }
}

public struct CodexLogSnapshot: Equatable, Sendable {
    public let bytes: [UInt8]
    public let threadID: String

    public init(bytes: [UInt8], threadID: String) {
        self.bytes = bytes
        self.threadID = threadID
    }

    public var data: Data {
        Data(bytes)
    }

    public func saveToTempFile(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let path = temporaryDirectory.appendingPathComponent("codex-feedback-\(threadID).log")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try data.write(to: path)
        return path
    }
}
