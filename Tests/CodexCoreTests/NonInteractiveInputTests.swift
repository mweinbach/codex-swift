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
            readStdin: { Data("from stdin\n".utf8) }
        )

        XCTAssertEqual(resolution, NonInteractivePromptResolution(prompt: "from stdin\n"))
    }

    func testResolvePromptReadsPipedStdinWithStatusMessage() throws {
        let resolution = try NonInteractiveInput.resolvePrompt(
            nil,
            stdinIsTerminal: false,
            readStdin: { Data("piped prompt".utf8) }
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
            readStdin: { Data("unused".utf8) }
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
            readStdin: { Data(" \n\t ".utf8) }
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

    func testDecodePromptBytesStripsUTF8BOMLikeRust() throws {
        XCTAssertEqual(
            try NonInteractiveInput.decodePromptBytes(Data([0xEF, 0xBB, 0xBF]) + Data("hi\n".utf8)),
            "hi\n"
        )
    }

    func testDecodePromptBytesDecodesUTF16LEBOMLikeRust() throws {
        let input = Data([0xFF, 0xFE, UInt8(ascii: "h"), 0x00, UInt8(ascii: "i"), 0x00, 0x0A, 0x00])

        XCTAssertEqual(try NonInteractiveInput.decodePromptBytes(input), "hi\n")
    }

    func testDecodePromptBytesDecodesUTF16BEBOMLikeRust() throws {
        let input = Data([0xFE, 0xFF, 0x00, UInt8(ascii: "h"), 0x00, UInt8(ascii: "i"), 0x00, 0x0A])

        XCTAssertEqual(try NonInteractiveInput.decodePromptBytes(input), "hi\n")
    }

    func testDecodePromptBytesRejectsUTF32BOMLikeRust() {
        XCTAssertThrowsError(try NonInteractiveInput.decodePromptBytes(Data([0xFF, 0xFE, 0x00, 0x00]))) { error in
            XCTAssertEqual(
                String(describing: error),
                "input appears to be UTF-32LE. Convert it to UTF-8 and retry."
            )
        }

        XCTAssertThrowsError(try NonInteractiveInput.decodePromptBytes(Data([0x00, 0x00, 0xFE, 0xFF]))) { error in
            XCTAssertEqual(
                String(describing: error),
                "input appears to be UTF-32BE. Convert it to UTF-8 and retry."
            )
        }
    }

    func testResolvePromptWrapsDecodeErrorsLikeRust() {
        XCTAssertThrowsError(try NonInteractiveInput.resolvePrompt(
            "-",
            stdinIsTerminal: true,
            readStdin: { Data([0xC3, 0x28]) }
        )) { error in
            XCTAssertEqual(
                error as? NonInteractiveInputError,
                .stdinReadFailed("input is not valid UTF-8 (invalid byte at offset 0). Convert it to UTF-8 and retry (e.g., `iconv -f <ENC> -t UTF-8 prompt.txt`).")
            )
            XCTAssertEqual(
                String(describing: error),
                "Failed to read prompt from stdin: input is not valid UTF-8 (invalid byte at offset 0). Convert it to UTF-8 and retry (e.g., `iconv -f <ENC> -t UTF-8 prompt.txt`)."
            )
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

    func testWriteLastMessageWritesContentAndWarnsForMissingMessage() {
        let capture = LastMessageWriteCapture()

        let result = NonInteractiveInput.writeLastMessage(
            nil,
            path: "/tmp/last-message.txt",
            writeFile: { path, contents in
                capture.writes.append((path, contents))
            }
        )

        XCTAssertEqual(capture.writes.count, 1)
        XCTAssertEqual(capture.writes.first?.path, "/tmp/last-message.txt")
        XCTAssertEqual(capture.writes.first?.contents, "")
        XCTAssertEqual(result.stderrMessages, [
            "Warning: no last agent message; wrote empty content to /tmp/last-message.txt"
        ])
    }

    func testWriteLastMessageReportsWriteErrors() {
        let result = NonInteractiveInput.writeLastMessage(
            "final answer",
            path: "/tmp/last-message.txt",
            writeFile: { _, _ in throw TestError("permission denied") }
        )

        XCTAssertEqual(result.stderrMessages, [
            #"Failed to write last message file "/tmp/last-message.txt": permission denied"#
        ])
    }

    func testEnforceGitRepositoryHonorsSkipAndRejectsMissingRepository() throws {
        let cwd = URL(fileURLWithPath: "/tmp/work")
        let capture = GitResolverCapture()

        try NonInteractiveInput.enforceGitRepository(
            cwd: cwd,
            skipGitRepoCheck: true,
            gitRepoRoot: { _ in
                capture.calls += 1
                return nil
            }
        )
        XCTAssertEqual(capture.calls, 0)

        try NonInteractiveInput.enforceGitRepository(
            cwd: cwd,
            skipGitRepoCheck: false,
            gitRepoRoot: { receivedURL in
                XCTAssertEqual(receivedURL, cwd)
                return cwd
            }
        )

        XCTAssertThrowsError(try NonInteractiveInput.enforceGitRepository(
            cwd: cwd,
            skipGitRepoCheck: false,
            gitRepoRoot: { _ in nil }
        )) { error in
            XCTAssertEqual(error as? NonInteractiveInputError, .notInsideTrustedDirectory)
            XCTAssertEqual(
                String(describing: error),
                "Not inside a trusted directory and --skip-git-repo-check was not specified."
            )
        }
    }

    private struct TestError: Error, Equatable, CustomStringConvertible, Sendable {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    private final class LastMessageWriteCapture: @unchecked Sendable {
        var writes: [(path: String, contents: String)] = []
    }

    private final class GitResolverCapture: @unchecked Sendable {
        var calls = 0
    }
}
