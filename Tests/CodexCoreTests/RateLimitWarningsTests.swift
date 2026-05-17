import CodexCore
import XCTest

final class RateLimitWarningsTests: XCTestCase {
    func testDurationLabelsMatchRustSupportedWindows() {
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: -10), "1h")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 57), "1h")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 299), "5h")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 1_443), "24h")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 1_444), "weekly")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 10_083), "weekly")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 10_084), "monthly")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 43_203), "monthly")
        XCTAssertEqual(RateLimitWarningLabels.durationLabel(windowMinutes: 43_204), "annual")
    }

    func testWarningsEmitHighestCrossedThresholdsLikeRust() {
        var state = RateLimitWarningState()
        var warnings: [String] = []

        warnings += state.takeWarnings(
            secondaryUsedPercent: 10.0,
            secondaryWindowMinutes: 10_079,
            primaryUsedPercent: 55.0,
            primaryWindowMinutes: 299
        )
        warnings += state.takeWarnings(
            secondaryUsedPercent: 55.0,
            secondaryWindowMinutes: 10_081,
            primaryUsedPercent: 10.0,
            primaryWindowMinutes: 299
        )
        warnings += state.takeWarnings(
            secondaryUsedPercent: 10.0,
            secondaryWindowMinutes: 10_081,
            primaryUsedPercent: 80.0,
            primaryWindowMinutes: 299
        )
        warnings += state.takeWarnings(
            secondaryUsedPercent: 80.0,
            secondaryWindowMinutes: 10_081,
            primaryUsedPercent: 10.0,
            primaryWindowMinutes: 299
        )
        warnings += state.takeWarnings(
            secondaryUsedPercent: 10.0,
            secondaryWindowMinutes: 10_081,
            primaryUsedPercent: 95.0,
            primaryWindowMinutes: 299
        )
        warnings += state.takeWarnings(
            secondaryUsedPercent: 95.0,
            secondaryWindowMinutes: 10_079,
            primaryUsedPercent: 10.0,
            primaryWindowMinutes: 299
        )

        XCTAssertEqual(warnings, [
            "Heads up, you have less than 25% of your 5h limit left. Run /status for a breakdown.",
            "Heads up, you have less than 25% of your weekly limit left. Run /status for a breakdown.",
            "Heads up, you have less than 5% of your 5h limit left. Run /status for a breakdown.",
            "Heads up, you have less than 5% of your weekly limit left. Run /status for a breakdown.",
        ])
    }

    func testWarningsUseMonthlyAndAnnualLabelsLikeRust() {
        var state = RateLimitWarningState()

        XCTAssertEqual(
            state.takeWarnings(
                secondaryUsedPercent: 75.0,
                secondaryWindowMinutes: 43_199,
                primaryUsedPercent: nil,
                primaryWindowMinutes: nil
            ),
            [
                "Heads up, you have less than 25% of your monthly limit left. Run /status for a breakdown.",
            ]
        )

        var annualState = RateLimitWarningState()
        XCTAssertEqual(
            annualState.takeWarnings(
                secondaryUsedPercent: nil,
                secondaryWindowMinutes: nil,
                primaryUsedPercent: 75.0,
                primaryWindowMinutes: 365 * 24 * 60
            ),
            [
                "Heads up, you have less than 25% of your annual limit left. Run /status for a breakdown.",
            ]
        )
    }

    func testReachedCapSuppressesWarningsLikeRust() {
        var state = RateLimitWarningState()

        XCTAssertTrue(state.takeWarnings(
            secondaryUsedPercent: 100.0,
            secondaryWindowMinutes: 10_080,
            primaryUsedPercent: 80.0,
            primaryWindowMinutes: 300
        ).isEmpty)
    }
}
