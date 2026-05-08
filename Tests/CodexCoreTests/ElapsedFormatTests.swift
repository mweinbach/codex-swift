import CodexCore
import Foundation
import XCTest

final class ElapsedFormatTests: XCTestCase {
    func testFormatDurationSubsecond() {
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 250), "250ms")
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 0), "0ms")
    }

    func testFormatDurationSeconds() {
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 1_500), "1.50s")
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 59_999), "60.00s")
    }

    func testFormatDurationMinutes() {
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 75_000), "1m 15s")
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 60_000), "1m 00s")
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 3_601_000), "60m 01s")
    }

    func testFormatDurationOneHourHasSpace() {
        XCTAssertEqual(ElapsedFormat.formatDuration(milliseconds: 3_600_000), "60m 00s")
    }

    func testFormatElapsedUsesDateDelta() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_001.25)

        XCTAssertEqual(ElapsedFormat.formatElapsed(since: start, now: now), "1.25s")
    }
}
