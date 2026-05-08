import CodexCore
import XCTest

final class ReadinessTests: XCTestCase {
    func testSubscribeAndMarkReadyRoundTrip() async throws {
        let flag = ReadinessFlag()
        let token = try await flag.subscribe()

        let markedReady = try await flag.markReady(token)
        XCTAssertTrue(markedReady)
        XCTAssertTrue(flag.isReady())
    }

    func testSubscribeAfterReadyThrows() async throws {
        let flag = ReadinessFlag()
        let token = try await flag.subscribe()
        let markedReady = try await flag.markReady(token)
        XCTAssertTrue(markedReady)

        do {
            _ = try await flag.subscribe()
            XCTFail("expected already-ready flag to reject new subscriptions")
        } catch ReadinessError.flagAlreadyReady {
            XCTAssertEqual(
                ReadinessError.flagAlreadyReady.description,
                "Flag is already ready. Impossible to subscribe"
            )
        }
    }

    func testMarkReadyRejectsUnknownAndZeroTokens() async throws {
        let flag = ReadinessFlag()

        let unknownMarkedReady = try await flag.markReady(ReadinessToken(rawValue: 42))
        XCTAssertFalse(unknownMarkedReady)
        XCTAssertTrue(flag.isReady())
        let zeroMarkedReady = try await flag.markReady(ReadinessToken(rawValue: 0))
        XCTAssertFalse(zeroMarkedReady)
    }

    func testWaitReadyUnblocksAfterMarkReady() async throws {
        let flag = ReadinessFlag()
        let token = try await flag.subscribe()

        let waiter = Task {
            await flag.waitReady()
            return true
        }

        let markedReady = try await flag.markReady(token)
        XCTAssertTrue(markedReady)
        let waiterResult = await waiter.value
        XCTAssertTrue(waiterResult)
    }

    func testMarkReadyTwiceUsesSingleToken() async throws {
        let flag = ReadinessFlag()
        let token = try await flag.subscribe()

        let firstMarkedReady = try await flag.markReady(token)
        let secondMarkedReady = try await flag.markReady(token)
        XCTAssertTrue(firstMarkedReady)
        XCTAssertFalse(secondMarkedReady)
    }

    func testIsReadyWithoutSubscribersMarksFlagReady() async throws {
        let flag = ReadinessFlag()

        XCTAssertTrue(flag.isReady())
        XCTAssertTrue(flag.isReady())

        do {
            _ = try await flag.subscribe()
            XCTFail("expected already-ready flag to reject subscriptions")
        } catch ReadinessError.flagAlreadyReady {
            // Expected.
        }
    }

    func testReadinessErrorDescriptionsMatchRust() {
        XCTAssertEqual(
            ReadinessError.tokenLockFailed.description,
            "Failed to acquire readiness token lock"
        )
        XCTAssertEqual(
            ReadinessError.flagAlreadyReady.description,
            "Flag is already ready. Impossible to subscribe"
        )
    }
}
