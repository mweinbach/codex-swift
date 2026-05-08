import CodexCore
import Foundation
import XCTest

final class NonInteractiveInputTests: XCTestCase {
    func testResolvePromptUsesExplicitPromptWithoutReadingStdin() throws {
        let resolution = try NonInteractiveInput.resolvePrompt(
            "ship it",
            stdinIsTerminal: true,
            readStdin: {
                throw TestError("stdin should not be read")
            }
        )

        XCTAssertEqual(resolution, NonInteractivePromptResolution(prompt: "ship it"))
    }

    func testResolvePromptReadsForcedStdinWithoutStatusMessage() throws {
        let resolution = try NonInteractiveInput.resolvePrompt(
            "-",
            stdinIsTerminal: true,
            readStdin: { "from stdin\n" }
        )

        XCTAssertEqual(resolution, NonInteractivePromptResolution(prompt: "from stdin\n"))
    }

    func testResolvePromptReadsPipedStdinWithStatusMessage() throws {
        let resolution = try NonInteractiveInput.resolvePrompt(
            nil,
            stdinIsTerminal: false,
            readStdin: { "piped prompt" }
        )

        XCTAssertEqual(resolution, NonInteractivePromptResolution(
            prompt: "piped prompt",
            stderrMessage: "Reading prompt from stdin..."
        ))
    }

    func testResolvePromptRejectsMissingPromptOnTerminal() {
        XCTAssertThrowsError(try NonInteractiveInput.resolvePrompt(
            nil,
            stdinIsTerminal: true,
            readStdin: { "unused" }
        )) { error in
            XCTAssertEqual(error as? NonInteractiveInputError, .missingPrompt)
            XCTAssertEqual(
                String(describing: error),
                "No prompt provided. Either specify one as an argument or pipe the prompt into stdin."
            )
        }
    }

    func testResolvePromptRejectsEmptyStdin() {
        XCTAssertThrowsError(try NonInteractiveInput.resolvePrompt(
            "-",
            stdinIsTerminal: true,
            readStdin: { " \n\t " }
        )) { error in
            XCTAssertEqual(error as? NonInteractiveInputError, .emptyStdinPrompt)
            XCTAssertEqual(String(describing: error), "No prompt provided via stdin.")
        }
    }

    func testResolvePromptWrapsStdinReadErrors() {
        XCTAssertThrowsError(try NonInteractiveInput.resolvePrompt(
            "-",
            stdinIsTerminal: true,
            readStdin: { throw TestError("broken pipe") }
        )) { error in
            XCTAssertEqual(error as? NonInteractiveInputError, .stdinReadFailed("broken pipe"))
            XCTAssertEqual(String(describing: error), "Failed to read prompt from stdin: broken pipe")
        }
    }

    func testLoadOutputSchemaReturnsNilForMissingPath() throws {
        let schema = try NonInteractiveInput.loadOutputSchema(
            path: nil,
            readFile: { _ in throw TestError("file should not be read") }
        )

        XCTAssertNil(schema)
    }

    func testLoadOutputSchemaDecodesJSONValue() throws {
        let schema = try NonInteractiveInput.loadOutputSchema(
            path: "/tmp/schema.json",
            readFile: { _ in Data(#"{"type":"object","properties":{"ok":{"type":"boolean"}}}"#.utf8) }
        )

        XCTAssertEqual(schema, .object([
            "properties": .object([
                "ok": .object(["type": .string("boolean")])
            ]),
            "type": .string("object")
        ]))
    }

    func testLoadOutputSchemaWrapsReadErrors() {
        XCTAssertThrowsError(try NonInteractiveInput.loadOutputSchema(
            path: "/tmp/missing.json",
            readFile: { _ in throw TestError("not found") }
        )) { error in
            XCTAssertEqual(
                error as? NonInteractiveInputError,
                .outputSchemaReadFailed(path: "/tmp/missing.json", message: "not found")
            )
            XCTAssertEqual(
                String(describing: error),
                "Failed to read output schema file /tmp/missing.json: not found"
            )
        }
    }

    func testLoadOutputSchemaWrapsInvalidJSON() {
        XCTAssertThrowsError(try NonInteractiveInput.loadOutputSchema(
            path: "/tmp/bad.json",
            readFile: { _ in Data(#"{"#.utf8) }
        )) { error in
            guard case let .outputSchemaInvalidJSON(path, message) = error as? NonInteractiveInputError else {
                return XCTFail("expected invalid JSON error, got \(error)")
            }
            XCTAssertEqual(path, "/tmp/bad.json")
            XCTAssertTrue(message.contains("data"), message)
            XCTAssertTrue(String(describing: error).hasPrefix(
                "Output schema file /tmp/bad.json is not valid JSON:"
            ))
        }
    }

    private struct TestError: Error, Equatable, CustomStringConvertible, Sendable {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
