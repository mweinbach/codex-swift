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
            "plan_type": "pro"
        ])
    }

    func testRateLimitSnapshotDecodesMissingAndNullOptions() throws {
        let json = """
        {
          "primary": null,
          "secondary": {
            "used_percent": 90,
            "window_minutes": null,
            "resets_at": null
          },
          "credits": null
        }
        """

        let snapshot = try JSONDecoder().decode(RateLimitSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.primary)
        XCTAssertEqual(snapshot.secondary, RateLimitWindow(usedPercent: 90, windowMinutes: nil, resetsAt: nil))
        XCTAssertNil(snapshot.credits)
        XCTAssertNil(snapshot.planType)
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
}
