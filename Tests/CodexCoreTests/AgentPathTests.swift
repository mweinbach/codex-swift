import CodexCore
import XCTest

final class AgentPathTests: XCTestCase {
    func testRootAndMorpheusNamesMatchRust() {
        XCTAssertEqual(AgentPath.root.rawValue, "/root")
        XCTAssertEqual(AgentPath.root.name, "root")
        XCTAssertTrue(AgentPath.root.isRoot)

        XCTAssertEqual(AgentPath.morpheus.rawValue, "/morpheus")
        XCTAssertEqual(AgentPath.morpheus.name, "morpheus")
        XCTAssertFalse(AgentPath.morpheus.isRoot)
    }

    func testJoinAndResolveMatchRustRules() throws {
        let child = try AgentPath.root.join("researcher")
        XCTAssertEqual(child.rawValue, "/root/researcher")
        XCTAssertEqual(child.name, "researcher")

        XCTAssertEqual(try child.resolve("worker"), try AgentPath(validating: "/root/researcher/worker"))
        XCTAssertEqual(try child.resolve("/root/other"), try AgentPath(validating: "/root/other"))
        XCTAssertEqual(try child.resolve("/morpheus"), .morpheus)
    }

    func testInvalidNamesAndPathsUseRustErrorStrings() throws {
        XCTAssertThrowsError(try AgentPath.root.join("BadName")) { error in
            XCTAssertEqual(String(describing: error), "agent_name must use only lowercase letters, digits, and underscores")
        }
        XCTAssertThrowsError(try AgentPath.root.join("root")) { error in
            XCTAssertEqual(String(describing: error), "agent_name `root` is reserved")
        }
        XCTAssertThrowsError(try AgentPath.root.join(".")) { error in
            XCTAssertEqual(String(describing: error), "agent_name `.` is reserved")
        }
        XCTAssertThrowsError(try AgentPath.root.join("nested/worker")) { error in
            XCTAssertEqual(String(describing: error), "agent_name must not contain `/`")
        }
        XCTAssertThrowsError(try AgentPath(validating: "/not-root")) { error in
            XCTAssertEqual(String(describing: error), "absolute agent paths must start with `/root` or be `/morpheus`")
        }
        XCTAssertThrowsError(try AgentPath(validating: "/root/")) { error in
            XCTAssertEqual(String(describing: error), "absolute agent path must not end with `/`")
        }
        XCTAssertThrowsError(try AgentPath.root.resolve("../sibling")) { error in
            XCTAssertEqual(String(describing: error), "agent_name `..` is reserved")
        }
        XCTAssertThrowsError(try AgentPath.root.resolve("worker/")) { error in
            XCTAssertEqual(String(describing: error), "relative agent path must not end with `/`")
        }
        XCTAssertThrowsError(try AgentPath.root.resolve("")) { error in
            XCTAssertEqual(String(describing: error), "agent path must not be empty")
        }
    }

    func testAgentPathCodableIsStringBacked() throws {
        let encoded = try JSONEncoder().encode(try AgentPath(validating: "/root/researcher"))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: encoded), "/root/researcher")
        XCTAssertEqual(try JSONDecoder().decode(AgentPath.self, from: encoded), try AgentPath(validating: "/root/researcher"))
    }
}
