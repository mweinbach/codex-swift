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
                limitID: "codex",
                primary: update.primary,
                secondary: update.secondary,
                credits: previous.credits,
                planType: previous.planType
            )
        )
    }

    func testMergeRateLimitFieldsKeepsNewCreditsAndPlanWhenPresent() {
        let previous = RateLimitSnapshot(
            limitID: "codex",
            primary: nil,
            secondary: nil,
            credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
            planType: .free
        )
        let update = RateLimitSnapshot(
            limitID: "codex_other",
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
                limitID: "codex",
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
                limitID: "codex",
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
            RateLimitSnapshot(limitID: "codex", primary: nil, secondary: nil, credits: nil, planType: nil)
        )
    }

    func testMergeRateLimitFieldsDefaultsMissingLimitIDToCodexLikeRustSessionState() {
        let previous = RateLimitSnapshot(
            limitID: "codex_other",
            limitName: "gpt-5.2-codex-sonic",
            primary: RateLimitWindow(usedPercent: 20, windowMinutes: 60, resetsAt: 200),
            secondary: nil,
            credits: nil,
            planType: nil
        )
        let update = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 30, windowMinutes: 60, resetsAt: 300),
            secondary: nil,
            credits: nil,
            planType: nil
        )

        XCTAssertEqual(
            RateLimitSnapshot.mergeRateLimitFields(previous: previous, snapshot: update).limitID,
            "codex"
        )
    }

    func testParseAllRateLimitsReadsNamedHeaderFamiliesLikeRustParser() {
        let updates = RateLimitSnapshot.parseAllRateLimits(headers: [
            "x-codex-primary-used-percent": "12.5",
            "x-codex-secondary-primary-used-percent": "80",
            "x-codex-secondary-primary-window-minutes": "1440",
            "x-codex-bengalfox-primary-used-percent": "50",
            "x-codex-bengalfox-limit-name": " gpt-5.2-codex-sonic "
        ])

        XCTAssertEqual(updates.count, 3)
        XCTAssertEqual(updates[0].limitID, "codex")
        XCTAssertEqual(updates[0].primary?.usedPercent, 12.5)
        XCTAssertEqual(updates[1].limitID, "codex_bengalfox")
        XCTAssertEqual(updates[1].limitName, "gpt-5.2-codex-sonic")
        XCTAssertEqual(updates[1].primary?.usedPercent, 50)
        XCTAssertEqual(updates[2].limitID, "codex_secondary")
        XCTAssertEqual(updates[2].primary?.usedPercent, 80)
        XCTAssertEqual(updates[2].primary?.windowMinutes, 1440)
    }

    func testParseAllRateLimitsIncludesDefaultCodexSnapshotWhenNoHeadersLikeRustParser() {
        XCTAssertEqual(
            RateLimitSnapshot.parseAllRateLimits(headers: [:]),
            [RateLimitSnapshot(limitID: "codex", primary: nil, secondary: nil, credits: nil, planType: nil)]
        )
    }

    func testParseRateLimitEventMapsCodexRateLimitPayloadLikeRustWebsocketParser() {
        let payload = """
        {
          "type": "codex.rate_limits",
          "plan_type": "plus",
          "metered_limit_name": "codex-sonic",
          "rate_limits": {
            "primary": {
              "used_percent": 88.5,
              "window_minutes": 60,
              "reset_at": 1704069000
            },
            "secondary": null
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": "42"
          }
        }
        """

        XCTAssertEqual(
            RateLimitSnapshot.parseRateLimitEvent(payload: payload),
            RateLimitSnapshot(
                limitID: "codex_sonic",
                primary: RateLimitWindow(usedPercent: 88.5, windowMinutes: 60, resetsAt: 1_704_069_000),
                secondary: nil,
                credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "42"),
                planType: .plus
            )
        )
    }

    func testParseRateLimitEventIgnoresNonRateLimitEventAndDefaultsLimitIDLikeRust() {
        XCTAssertNil(RateLimitSnapshot.parseRateLimitEvent(payload: #"{"type":"response.created"}"#))

        XCTAssertEqual(
            RateLimitSnapshot.parseRateLimitEvent(payload: #"{"type":"codex.rate_limits"}"#),
            RateLimitSnapshot(limitID: "codex", primary: nil, secondary: nil, credits: nil, planType: nil)
        )
    }
}
