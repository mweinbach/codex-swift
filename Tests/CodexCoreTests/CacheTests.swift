import CodexCore
import Foundation
import XCTest

final class CacheTests: XCTestCase {
    func testStoresAndRetrievesValues() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)

        XCTAssertNil(cache.get("first"))
        cache.insert("first", 1)
        XCTAssertEqual(cache.get("first"), 1)
    }

    func testEvictsLeastRecentlyUsed() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)
        cache.insert("a", 1)
        cache.insert("b", 2)
        XCTAssertEqual(cache.get("a"), 1)

        cache.insert("c", 3)

        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testGetOrInsertComputesOnce() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)
        var calls = 0

        XCTAssertEqual(cache.getOrInsertWith("first") {
            calls += 1
            return 7
        }, 7)
        XCTAssertEqual(cache.getOrInsertWith("first") {
            calls += 1
            return 9
        }, 7)
        XCTAssertEqual(calls, 1)
    }

    func testInsertRemoveAndClearMatchRustHelpers() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)

        XCTAssertNil(cache.insert("first", 1))
        XCTAssertEqual(cache.insert("first", 2), 1)
        XCTAssertEqual(cache.get("first"), 2)
        XCTAssertEqual(cache.remove("first"), 2)
        XCTAssertNil(cache.get("first"))

        cache.insert("a", 1)
        cache.insert("b", 2)
        cache.clear()
        XCTAssertNil(cache.get("a"))
        XCTAssertNil(cache.get("b"))
    }

    func testGetOrTryInsertDoesNotCacheThrownValue() {
        enum SampleError: Error {
            case boom
        }

        let cache = BlockingLruCache<String, Int>(capacity: 2)
        XCTAssertThrowsError(try cache.getOrTryInsertWith("first") {
            throw SampleError.boom
        })
        XCTAssertNil(cache.get("first"))

        XCTAssertEqual(cache.getOrTryInsertWith("first") { 11 }, 11)
        XCTAssertEqual(cache.get("first"), 11)
    }

    func testTryWithCapacityRejectsZero() {
        XCTAssertNil(BlockingLruCache<String, Int>.tryWithCapacity(0))
        XCTAssertNotNil(BlockingLruCache<String, Int>.tryWithCapacity(1))
    }

    func testWithMutExposesUnderlyingLru() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)

        let value = cache.withMut { inner in
            inner.put("tmp", 3)
            return inner.get("tmp")
        }

        XCTAssertEqual(value, 3)
        XCTAssertEqual(cache.get("tmp"), 3)
    }

    func testSha1DigestMatchesRustHelper() {
        XCTAssertEqual(
            CacheUtils.sha1Digest(Data("abc".utf8)).hexString,
            "a9993e364706816aba3e25717850c26c9cd0d89d"
        )
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
