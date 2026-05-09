import CodexCore
import XCTest

final class HookOutputSpillerTests: XCTestCase {
    func testSmallHookOutputRemainsInline() throws {
        let dir = try HookOutputSpillerTemporaryDirectory()
        let outputDir = dir.url.appendingPathComponent(HookOutputSpiller.outputsDirectoryName, isDirectory: true)
        let spiller = HookOutputSpiller(outputDirectory: outputDir)

        let output = spiller.maybeSpillText(threadID: ThreadId(), text: "short")

        XCTAssertEqual(output, "short")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir.path))
    }

    func testLargeHookOutputSpillsToFile() throws {
        let dir = try HookOutputSpillerTemporaryDirectory()
        let text = String(repeating: "hook output ", count: 1_000)
        let spiller = HookOutputSpiller(
            outputDirectory: dir.url.appendingPathComponent(HookOutputSpiller.outputsDirectoryName, isDirectory: true)
        )

        let output = spiller.maybeSpillText(threadID: ThreadId(), text: text)

        XCTAssertTrue(output.contains("tokens truncated"), "expected truncation marker in \(output)")
        let savedPath: String? = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let prefix = "Full hook output saved to: "
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
            }
            .first
        let path = try XCTUnwrap(savedPath)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), text)
    }

    func testHookPromptFragmentsSpillTextAndPreserveRunIDs() throws {
        let dir = try HookOutputSpillerTemporaryDirectory()
        let text = String(repeating: "hook output ", count: 1_000)
        let spiller = HookOutputSpiller(
            outputDirectory: dir.url.appendingPathComponent(HookOutputSpiller.outputsDirectoryName, isDirectory: true)
        )

        let output = spiller.maybeSpillPromptFragments(
            threadID: ThreadId(),
            fragments: [
                HookPromptFragment(text: "short", hookRunID: "run-1"),
                HookPromptFragment(text: text, hookRunID: "run-2")
            ]
        )

        XCTAssertEqual(output[0], HookPromptFragment(text: "short", hookRunID: "run-1"))
        XCTAssertEqual(output[1].hookRunID, "run-2")
        XCTAssertTrue(output[1].text.contains("Full hook output saved to: "))
    }
}

private final class HookOutputSpillerTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
