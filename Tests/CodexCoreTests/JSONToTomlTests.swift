import CodexCore
import XCTest

final class JSONToTomlTests: XCTestCase {
    func testJSONNumberToTomlInteger() {
        XCTAssertEqual(
            JSONToToml.convert(.integer(123)),
            .integer(123)
        )
    }

    func testJSONArrayToTomlArray() {
        XCTAssertEqual(
            JSONToToml.convert(.array([.bool(true), .integer(1)])),
            .array([.bool(true), .integer(1)])
        )
    }

    func testJSONBoolToTomlBool() {
        XCTAssertEqual(
            JSONToToml.convert(.bool(false)),
            .bool(false)
        )
    }

    func testJSONFloatToTomlFloat() {
        XCTAssertEqual(
            JSONToToml.convert(.double(1.25)),
            .double(1.25)
        )
    }

    func testJSONNullToTomlEmptyString() {
        XCTAssertEqual(
            JSONToToml.convert(.null),
            .string("")
        )
    }

    func testJSONObjectNested() {
        XCTAssertEqual(
            JSONToToml.convert(.object([
                "outer": .object([
                    "inner": .integer(2)
                ])
            ])),
            .table([
                "outer": .table([
                    "inner": .integer(2)
                ])
            ])
        )
    }
}
