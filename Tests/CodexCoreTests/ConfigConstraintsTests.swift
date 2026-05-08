import CodexCore
import XCTest

final class ConfigConstraintsTests: XCTestCase {
    func testConstrainedAllowAnyAcceptsAnyValue() throws {
        var constrained = Constrained.allowAny(5)
        try constrained.set(-10)
        XCTAssertEqual(constrained.value, -10)
    }

    func testConstrainedAllowAnyDefaultUsesDefaultValue() {
        let constrained = Constrained<Int>.allowAnyFromDefault()
        XCTAssertEqual(constrained.value, 0)
    }

    func testConstrainedNewRejectsInvalidInitialValue() {
        XCTAssertThrowsError(try Constrained(0) { value in
            value > 0 ? .success(()) : .failure(.invalidValue("\(value)", "positive values"))
        }) { error in
            XCTAssertEqual(error as? ConstraintError, .invalidValue(candidate: "0", allowed: "positive values"))
        }
    }

    func testConstrainedSetRejectsInvalidValueAndLeavesPrevious() throws {
        var constrained = try Constrained(1) { value in
            value > 0 ? .success(()) : .failure(.invalidValue("\(value)", "positive values"))
        }

        XCTAssertThrowsError(try constrained.set(-5)) { error in
            XCTAssertEqual(error as? ConstraintError, .invalidValue(candidate: "-5", allowed: "positive values"))
        }
        XCTAssertEqual(constrained.value, 1)
    }

    func testConstrainedCanSetAllowsProbeWithoutSetting() throws {
        let constrained = try Constrained(1) { value in
            value > 0 ? .success(()) : .failure(.invalidValue("\(value)", "positive values"))
        }

        XCTAssertNoThrow(try constrained.canSet(2).get())
        XCTAssertConstraintFailure(
            constrained.canSet(-1),
            .invalidValue(candidate: "-1", allowed: "positive values")
        )
        XCTAssertEqual(constrained.value, 1)
    }

    func testConstraintErrorDescriptionsMatchRustThisErrorMessages() {
        XCTAssertEqual(
            ConstraintError.invalidValue("0", "positive values").description,
            "value `0` is not in the allowed set positive values"
        )
        XCTAssertEqual(
            ConstraintError.emptyField("allowed_approval_policies").description,
            "field `allowed_approval_policies` cannot be empty"
        )
    }
}

private func XCTAssertConstraintFailure(
    _ result: ConstraintResult<Void>,
    _ expected: ConstraintError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("expected constraint failure", file: file, line: line)
    case let .failure(error):
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}
