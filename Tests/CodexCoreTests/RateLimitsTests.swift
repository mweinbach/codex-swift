import CodexCore
import XCTest

final class RateLimitsTests: XCTestCase {
    func testRateLimitSnapshotWireShapeIncludesNullOptionalsLikeRust() throws {
        let snapshot = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 42.5, windowMinutes: nil, resetsAt: 1_717_000_000),
            secondary: nil,
            credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: nil),
            planType: .pro
        )

        try XCTAssertJSONObjectEqual(snapshot, [
            "limit_id": NSNull(),
            "limit_name": NSNull(),
            "primary": [
                "used_percent": 42.5,
                "window_minutes": NSNull(),
                "resets_at": 1_717_000_000
            ],
            "secondary": NSNull(),
            "credits": [
                "has_credits": true,
                "unlimited": false,
                "balance": NSNull()
            ],
            "plan_type": "pro",
            "rate_limit_reached_type": NSNull()
        ])
    }

    func testRateLimitSnapshotDecodesMissingAndNullOptions() throws {
        let json = """
        {
          "limit_id": null,
          "limit_name": " codex_other ",
          "primary": null,
          "secondary": {
            "used_percent": 90,
            "window_minutes": null,
            "resets_at": null
          },
          "credits": null,
          "rate_limit_reached_type": "workspace_owner_usage_limit_reached"
        }
        """

        let snapshot = try JSONDecoder().decode(RateLimitSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.limitID)
        XCTAssertEqual(snapshot.limitName, " codex_other ")
        XCTAssertNil(snapshot.primary)
        XCTAssertEqual(snapshot.secondary, RateLimitWindow(usedPercent: 90, windowMinutes: nil, resetsAt: nil))
        XCTAssertNil(snapshot.credits)
        XCTAssertNil(snapshot.planType)
        XCTAssertEqual(snapshot.rateLimitReachedType, .workspaceOwnerUsageLimitReached)
    }

    func testTokenCountEventWireShapeIncludesNullOptions() throws {
        try XCTAssertJSONObjectEqual(TokenCountEvent(info: nil, rateLimits: nil), [
            "info": NSNull(),
            "rate_limits": NSNull()
        ])
    }

    func testMergeRateLimitFieldsPreservesCreditsAndPlanWhenUpdateOmitsThem() {
        let previous = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 10, windowMinutes: 300, resetsAt: 10),
            secondary: nil,
            credits: CreditsSnapshot(hasCredits: true, unlimited: true, balance: "unlimited"),
            planType: .team
        )
        let update = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 30, windowMinutes: 300, resetsAt: 20),
            secondary: RateLimitWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil),
            credits: nil,
            planType: nil
        )

        XCTAssertEqual(
            RateLimitSnapshot.mergeRateLimitFields(previous: previous, snapshot: update),
            RateLimitSnapshot(
                primary: update.primary,
                secondary: update.secondary,
                credits: previous.credits,
                planType: previous.planType
            )
        )
    }

    func testMergeRateLimitFieldsKeepsNewCreditsAndPlanWhenPresent() {
        let previous = RateLimitSnapshot(
            primary: nil,
            secondary: nil,
            credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
            planType: .free
        )
        let update = RateLimitSnapshot(
            primary: nil,
            secondary: nil,
            credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "10"),
            planType: .pro
        )

        XCTAssertEqual(
            RateLimitSnapshot.mergeRateLimitFields(previous: previous, snapshot: update),
            update
        )
    }

    func testParseRateLimitHeadersBuildsSnapshotLikeRustParser() {
        let snapshot = RateLimitSnapshot.parseRateLimit(headers: [
            "X-Codex-Primary-Used-Percent": "42.5",
            "x-codex-primary-window-minutes": "300",
            "x-codex-primary-reset-at": "1717000000",
            "x-codex-secondary-used-percent": "0",
            "x-codex-secondary-window-minutes": "60",
            "x-codex-credits-has-credits": "TRUE",
            "x-codex-credits-unlimited": "0",
            "x-codex-credits-balance": "  123  "
        ])

        XCTAssertEqual(
            snapshot,
            RateLimitSnapshot(
                primary: RateLimitWindow(usedPercent: 42.5, windowMinutes: 300, resetsAt: 1_717_000_000),
                secondary: RateLimitWindow(usedPercent: 0, windowMinutes: 60, resetsAt: nil),
                credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "123"),
                planType: nil
            )
        )
    }

    func testParseRateLimitHeadersOmitsZeroWindowsAndBlankCreditsBalance() {
        let snapshot = RateLimitSnapshot.parseRateLimit(headers: [
            "x-codex-primary-used-percent": "0",
            "x-codex-primary-window-minutes": "0",
            "x-codex-secondary-used-percent": "0",
            "x-codex-credits-has-credits": "false",
            "x-codex-credits-unlimited": "true",
            "x-codex-credits-balance": "   "
        ])

        XCTAssertEqual(
            snapshot,
            RateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: CreditsSnapshot(hasCredits: false, unlimited: true, balance: nil),
                planType: nil
            )
        )
    }

    func testParseRateLimitHeadersDropsInvalidNumericAndBoolValues() {
        let snapshot = RateLimitSnapshot.parseRateLimit(headers: [
            "x-codex-primary-used-percent": "inf",
            "x-codex-secondary-used-percent": "not-a-number",
            "x-codex-credits-has-credits": "yes",
            "x-codex-credits-unlimited": "no"
        ])

        XCTAssertEqual(
            snapshot,
            RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil)
        )
    }
}
