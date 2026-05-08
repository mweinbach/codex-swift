import CodexCore
import XCTest

final class EnvDisplayTests: XCTestCase {
    func testReturnsDashWhenEmpty() {
        XCTAssertEqual(EnvDisplay.formatEnvDisplay(env: nil, envVars: []), "-")
        XCTAssertEqual(EnvDisplay.formatEnvDisplay(env: [:], envVars: []), "-")
    }

    func testFormatsSortedEnvPairs() {
        let env = [
            "B": "two",
            "A": "one"
        ]

        XCTAssertEqual(EnvDisplay.formatEnvDisplay(env: env, envVars: []), "A=*****, B=*****")
    }

    func testFormatsEnvVarsInInputOrder() {
        let vars = ["TOKEN", "PATH"]

        XCTAssertEqual(EnvDisplay.formatEnvDisplay(env: nil, envVars: vars), "TOKEN=*****, PATH=*****")
    }

    func testCombinesEnvPairsAndVars() {
        let env = ["HOME": "/tmp"]
        let vars = ["TOKEN"]

        XCTAssertEqual(EnvDisplay.formatEnvDisplay(env: env, envVars: vars), "HOME=*****, TOKEN=*****")
    }
}
