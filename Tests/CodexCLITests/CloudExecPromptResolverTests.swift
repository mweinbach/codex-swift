import CodexCLI
import Foundation
import XCTest

final class CloudExecPromptResolverTests: XCTestCase {
    func testResolveUsesQueryArgumentWithoutReadingStdinLikeRust() throws {
        var didReadStdin = false

        let prompt = try CloudExecPromptResolver.resolve(
            query: "ship it",
            stdinIsTerminal: true,
            readStdin: {
                didReadStdin = true
                return Data()
            }
        )

        XCTAssertEqual(prompt, CloudExecPrompt(prompt: "ship it", stderrMessage: nil))
        XCTAssertFalse(didReadStdin)
    }

    func testResolveReadsForcedStdinWithoutStatusMessageLikeRust() throws {
        let prompt = try CloudExecPromptResolver.resolve(
            query: "-",
            stdinIsTerminal: true,
            readStdin: { Data("ship it\n".utf8) }
        )

        XCTAssertEqual(prompt, CloudExecPrompt(prompt: "ship it\n", stderrMessage: nil))
    }

    func testResolveReadsPipedStdinWithStatusMessageLikeRust() throws {
        let prompt = try CloudExecPromptResolver.resolve(
            query: nil,
            stdinIsTerminal: false,
            readStdin: { Data("ship it from stdin\n".utf8) }
        )

        XCTAssertEqual(prompt, CloudExecPrompt(
            prompt: "ship it from stdin\n",
            stderrMessage: "Reading query from stdin..."
        ))
    }

    func testResolveRejectsMissingTerminalInputLikeRust() {
        XCTAssertThrowsError(try CloudExecPromptResolver.resolve(
            query: nil,
            stdinIsTerminal: true,
            readStdin: { Data("unused".utf8) }
        )) { error in
            XCTAssertEqual(
                (error as? CloudExecPromptError)?.description,
                "no query provided. Pass one as an argument or pipe it via stdin."
            )
        }
    }

    func testResolveRejectsEmptyAndInvalidStdinLikeRust() {
        XCTAssertThrowsError(try CloudExecPromptResolver.resolve(
            query: "-",
            stdinIsTerminal: true,
            readStdin: { Data(" \n\t".utf8) }
        )) { error in
            XCTAssertEqual(
                (error as? CloudExecPromptError)?.description,
                "no query provided via stdin (received empty input)."
            )
        }

        XCTAssertThrowsError(try CloudExecPromptResolver.resolve(
            query: "-",
            stdinIsTerminal: true,
            readStdin: { Data([0xFF]) }
        )) { error in
            XCTAssertEqual(
                (error as? CloudExecPromptError)?.description,
                "failed to read query from stdin: stream did not contain valid UTF-8"
            )
        }
    }
}
