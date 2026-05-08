import XCTest
@testable import CodexCore

final class AccountTests: XCTestCase {
    func testPlanTypeUsesLowercaseWireValues() throws {
        XCTAssertEqual(try encode(PlanType.free), #""free""#)
        XCTAssertEqual(try encode(PlanType.go), #""go""#)
        XCTAssertEqual(try encode(PlanType.plus), #""plus""#)
        XCTAssertEqual(try encode(PlanType.pro), #""pro""#)
        XCTAssertEqual(try encode(PlanType.proLite), #""prolite""#)
        XCTAssertEqual(try encode(PlanType.team), #""team""#)
        XCTAssertEqual(try encode(PlanType.selfServeBusinessUsageBased), #""self_serve_business_usage_based""#)
        XCTAssertEqual(try encode(PlanType.business), #""business""#)
        XCTAssertEqual(try encode(PlanType.enterpriseCbpUsageBased), #""enterprise_cbp_usage_based""#)
        XCTAssertEqual(try encode(PlanType.enterprise), #""enterprise""#)
        XCTAssertEqual(try encode(PlanType.edu), #""edu""#)
        XCTAssertEqual(try encode(PlanType.unknown), #""unknown""#)
    }

    func testPlanTypeDecodesUnknownStringAsUnknown() throws {
        XCTAssertEqual(try JSONDecoder().decode(PlanType.self, from: Data(#""future-plan""#.utf8)), .unknown)
    }

    func testUsageBasedPlanTypesUseRustWireNames() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(PlanType.self, from: Data(#""self_serve_business_usage_based""#.utf8)),
            .selfServeBusinessUsageBased
        )
        XCTAssertEqual(
            try JSONDecoder().decode(PlanType.self, from: Data(#""enterprise_cbp_usage_based""#.utf8)),
            .enterpriseCbpUsageBased
        )
        XCTAssertEqual(
            try JSONDecoder().decode(PlanType.self, from: Data(#""prolite""#.utf8)),
            .proLite
        )
    }

    func testPlanTypeRawAliasesMatchRustAuthPlanType() {
        XCTAssertEqual(PlanType.fromRawValue("FREE"), .free)
        XCTAssertEqual(PlanType.fromRawValue("hc"), .enterprise)
        XCTAssertEqual(PlanType.fromRawValue("education"), .edu)
        XCTAssertEqual(PlanType.fromRawValue("mystery-tier"), .unknown)
    }

    func testDisplayNamesMatchRustKnownPlanNames() {
        XCTAssertEqual(PlanType.free.displayName, "Free")
        XCTAssertEqual(PlanType.go.displayName, "Go")
        XCTAssertEqual(PlanType.plus.displayName, "Plus")
        XCTAssertEqual(PlanType.pro.displayName, "Pro")
        XCTAssertEqual(PlanType.proLite.displayName, "Pro Lite")
        XCTAssertEqual(PlanType.team.displayName, "Team")
        XCTAssertEqual(PlanType.selfServeBusinessUsageBased.displayName, "Self Serve Business Usage Based")
        XCTAssertEqual(PlanType.business.displayName, "Business")
        XCTAssertEqual(PlanType.enterpriseCbpUsageBased.displayName, "Enterprise CBP Usage Based")
        XCTAssertEqual(PlanType.enterprise.displayName, "Enterprise")
        XCTAssertEqual(PlanType.edu.displayName, "Edu")
    }

    func testPlanFamilyHelpersGroupUsageBasedVariantsLikeRust() {
        XCTAssertTrue(PlanType.team.isTeamLike)
        XCTAssertTrue(PlanType.selfServeBusinessUsageBased.isTeamLike)
        XCTAssertFalse(PlanType.business.isTeamLike)

        XCTAssertTrue(PlanType.business.isBusinessLike)
        XCTAssertTrue(PlanType.enterpriseCbpUsageBased.isBusinessLike)
        XCTAssertFalse(PlanType.team.isBusinessLike)
    }

    func testWorkspaceAccountHelperIncludesUsageBasedWorkspacePlans() {
        XCTAssertTrue(PlanType.team.isWorkspaceAccount)
        XCTAssertTrue(PlanType.selfServeBusinessUsageBased.isWorkspaceAccount)
        XCTAssertTrue(PlanType.business.isWorkspaceAccount)
        XCTAssertTrue(PlanType.enterpriseCbpUsageBased.isWorkspaceAccount)
        XCTAssertTrue(PlanType.enterprise.isWorkspaceAccount)
        XCTAssertTrue(PlanType.edu.isWorkspaceAccount)
        XCTAssertFalse(PlanType.pro.isWorkspaceAccount)
        XCTAssertFalse(PlanType.go.isWorkspaceAccount)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
