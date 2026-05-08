import CodexCore
import XCTest

final class ReadinessTests: XCTestCase {
    func testSubscribeAndMarkReadyRoundTrip() async throws {
        let flag = ReadinessFlag()
        let token = try flag.subscribe()

        XCTAssertTrue(try flag.markReady(token))
        XCTAssertTrue(flag.isReady)
    }

    func testSubscribeAfterReadyReturnsRustError() async throws {
        let flag = ReadinessFlag()
        let token = try flag.subscribe()
        XCTAssertTrue(try flag.markReady(token))

        do {
            _ = try flag.subscribe()
            XCTFail("subscribe after readiness should fail")
        } catch let error as ReadinessError {
            XCTAssertEqual(error, .flagAlreadyReady)
            XCTAssertEqual(String(describing: error), "Flag is already ready. Impossible to subscribe")
        }
    }

    func testMarkReadyRejectsUnknownAndZeroTokens() async throws {
        let flag = ReadinessFlag()

        XCTAssertFalse(try flag.markReady(ReadinessToken(0)))
        XCTAssertFalse(try flag.markReady(ReadinessToken(42)))
        XCTAssertTrue(flag.isReady)
    }

    func testWaitReadyUnblocksAfterMarkReady() async throws {
        let flag = ReadinessFlag()
        let token = try flag.subscribe()
        let waiter = Task {
            await flag.waitReady()
        }

        XCTAssertTrue(try flag.markReady(token))
        await waiter.value
    }

    func testMarkReadyTwiceUsesSingleToken() async throws {
        let flag = ReadinessFlag()
        let token = try flag.subscribe()

        XCTAssertTrue(try flag.markReady(token))
        XCTAssertFalse(try flag.markReady(token))
    }

    func testIsReadyWithoutSubscribersMarksFlagReady() async throws {
        let flag = ReadinessFlag()

        XCTAssertTrue(flag.isReady)
        XCTAssertTrue(flag.isReady)

        do {
            _ = try flag.subscribe()
            XCTFail("subscribe after no-subscriber readiness should fail")
        } catch let error as ReadinessError {
            XCTAssertEqual(error, .flagAlreadyReady)
        }
    }
}
