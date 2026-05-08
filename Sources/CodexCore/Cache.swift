import CryptoKit
import Foundation

public struct LruCache<Key: Hashable, Value> {
    private let capacity: Int?
    private var values: [Key: Value]
    private var keysLeastToMostRecent: [Key]

    public init(capacity: Int) {
        precondition(capacity > 0, "LRU cache capacity must be non-zero")
        self.capacity = capacity
        self.values = [:]
        self.keysLeastToMostRecent = []
    }

    public static func unbounded() -> LruCache<Key, Value> {
        LruCache(capacity: nil)
    }

    private init(capacity: Int?) {
        self.capacity = capacity
        self.values = [:]
        self.keysLeastToMostRecent = []
    }

    public var count: Int {
        values.count
    }

    public mutating func get(_ key: Key) -> Value? {
        guard let value = values[key] else {
            return nil
        }
        markMostRecent(key)
        return value
    }

    @discardableResult
    public mutating func put(_ key: Key, _ value: Value) -> Value? {
        let previous = values.updateValue(value, forKey: key)
        markMostRecent(key)
        evictIfNeeded()
        return previous
    }

    @discardableResult
    public mutating func pop(_ key: Key) -> Value? {
        removeKeyFromOrder(key)
        return values.removeValue(forKey: key)
    }

    public mutating func clear() {
        values.removeAll()
        keysLeastToMostRecent.removeAll()
    }

    private mutating func markMostRecent(_ key: Key) {
        removeKeyFromOrder(key)
        keysLeastToMostRecent.append(key)
    }

    private mutating func removeKeyFromOrder(_ key: Key) {
        keysLeastToMostRecent.removeAll { $0 == key }
    }

    private mutating func evictIfNeeded() {
        guard let capacity else {
            return
        }

        while values.count > capacity, let key = keysLeastToMostRecent.first {
            keysLeastToMostRecent.removeFirst()
            values.removeValue(forKey: key)
        }
    }
}

public final class BlockingLruCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var inner: LruCache<Key, Value>

    public init(capacity: Int) {
        precondition(capacity > 0, "LRU cache capacity must be non-zero")
        self.inner = LruCache(capacity: capacity)
    }

    public static func tryWithCapacity(_ capacity: Int) -> BlockingLruCache<Key, Value>? {
        guard capacity > 0 else {
            return nil
        }
        return BlockingLruCache(capacity: capacity)
    }

    public func getOrInsertWith(_ key: Key, _ value: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inner.get(key) {
            return cached
        }
        let computed = value()
        inner.put(key, computed)
        return computed
    }

    public func getOrTryInsertWith(_ key: Key, _ value: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inner.get(key) {
            return cached
        }
        let computed = try value()
        inner.put(key, computed)
        return computed
    }

    public func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return inner.get(key)
    }

    @discardableResult
    public func insert(_ key: Key, _ value: Value) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return inner.put(key, value)
    }

    @discardableResult
    public func insert(_ value: Value, forKey key: Key) -> Value? {
        insert(key, value)
    }

    @discardableResult
    public func remove(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return inner.pop(key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        inner.clear()
    }

    public func withMut<R>(_ callback: (inout LruCache<Key, Value>) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return callback(&inner)
    }
}

public enum CacheUtils {
    /// Port of codex-rs/utils/cache/src/lib.rs sha1_digest.
    public static func sha1Digest(_ bytes: Data) -> Data {
        Data(Insecure.SHA1.hash(data: bytes))
    }
}
