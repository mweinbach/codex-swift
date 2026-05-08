import XCTest
@testable import CodexCore

final class AccountTests: XCTestCase {
    func testPlanTypeUsesLowercaseWireValues() throws {
        XCTAssertEqual(try encode(PlanType.free), #""free""#)
        XCTAssertEqual(try encode(PlanType.plus), #""plus""#)
        XCTAssertEqual(try encode(PlanType.pro), #""pro""#)
        XCTAssertEqual(try encode(PlanType.team), #""team""#)
        XCTAssertEqual(try encode(PlanType.business), #""business""#)
        XCTAssertEqual(try encode(PlanType.enterprise), #""enterprise""#)
        XCTAssertEqual(try encode(PlanType.edu), #""edu""#)
        XCTAssertEqual(try encode(PlanType.unknown), #""unknown""#)
    }

    func testPlanTypeDecodesUnknownStringAsUnknown() throws {
        XCTAssertEqual(try JSONDecoder().decode(PlanType.self, from: Data(#""future-plan""#.utf8)), .unknown)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
