import CodexCore
import XCTest

final class DotenvLoaderTests: XCTestCase {
    func testEntriesParseCommonDotenvForms() {
        let entries = DotenvLoader.entries(from: """
        # ignored
        FOO=bar
        export BAR = spaced
        QUOTED="hello\\nworld"
        SINGLE='literal # value'
        HASH=foo#bar
        COMMENTED=foo # comment
        EMPTY=
        """)

        XCTAssertEqual(entries.map(\.key), ["FOO", "BAR", "QUOTED", "SINGLE", "HASH", "COMMENTED", "EMPTY"])
        XCTAssertEqual(entries.map(\.value), [
            "bar",
            "spaced",
            "hello\nworld",
            "literal # value",
            "foo#bar",
            "foo",
            ""
        ])
    }

    func testEntriesSkipMalformedLinesLikeRustFlatten() {
        let entries = DotenvLoader.entries(from: """
        NO_EQUALS
        1BAD=value
        BAD-NAME=value
        OPEN="unterminated
        VALID=value
        """)

        XCTAssertEqual(entries.map(\.key), ["VALID"])
        XCTAssertEqual(entries.map(\.value), ["value"])
    }

    func testLoadCodexDotenvFiltersCodexPrefixedKeysCaseInsensitively() throws {
        let dir = try DotenvTemporaryDirectory()
        try """
        OPENAI_API_KEY=from-env-file
        CODEX_API_KEY=blocked
        codex_home=blocked-too
        OTHER=value
        """.write(to: dir.url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        var written: [String: String] = [:]
        DotenvLoader.loadCodexDotenv(codexHome: dir.url) { key, value in
            written[key] = value
        }

        XCTAssertEqual(written, [
            "OPENAI_API_KEY": "from-env-file",
            "OTHER": "value"
        ])
    }

    func testLoadCodexDotenvIgnoresMissingFile() throws {
        let dir = try DotenvTemporaryDirectory()
        var written: [String: String] = [:]

        DotenvLoader.loadCodexDotenv(codexHome: dir.url) { key, value in
            written[key] = value
        }

        XCTAssertEqual(written, [:])
    }
}

private final class DotenvTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
