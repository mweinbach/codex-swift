import CodexCore
import XCTest

final class AgentJobCSVTests: XCTestCase {
    func testParseCSVSupportsQuotesCommasBOMAndBlankRowsLikeRust() throws {
        let input = "\u{feff}id,name,notes\n1,\"alpha, beta\",\"line one\nline two\"\n,,\n2,gamma,\"has \"\"quote\"\"\"\n"
        let document = try AgentJobCSV.parse(input)

        XCTAssertEqual(document.headers, ["id", "name", "notes"])
        XCTAssertEqual(document.rows, [
            ["1", "alpha, beta", "line one\nline two"],
            ["2", "gamma", "has \"quote\""],
        ])
    }

    func testEnsureUniqueHeadersRejectsDuplicatesWithRustMessage() {
        XCTAssertThrowsError(try AgentJobCSV.ensureUniqueHeaders(["path", "path"])) { error in
            XCTAssertEqual(error as? FunctionCallError, .respondToModel("csv header path is duplicated"))
        }
    }

    func testMakeItemsUsesIDColumnAndDedupesItemIDsLikeRust() throws {
        let items = try AgentJobCSV.makeItems(
            headers: ["id", "path"],
            rows: [
                ["alpha", "a.swift"],
                ["alpha", "b.swift"],
                ["", "c.swift"],
            ],
            idColumn: "id"
        )

        XCTAssertEqual(items.map(\.itemID), ["alpha", "alpha-2", "row-3"])
        XCTAssertEqual(items.map(\.sourceID), ["alpha", "alpha", nil])
        XCTAssertEqual(items.map(\.rowIndex), [0, 1, 2])
        XCTAssertEqual(items[0].rowJSON, .object(["id": .string("alpha"), "path": .string("a.swift")]))
    }

    func testMakeItemsRejectsMissingIDColumnAndRaggedRowsLikeRust() {
        XCTAssertThrowsError(try AgentJobCSV.makeItems(headers: ["id"], rows: [], idColumn: "missing")) { error in
            XCTAssertEqual(
                error as? FunctionCallError,
                .respondToModel("id_column missing was not found in csv headers")
            )
        }
        XCTAssertThrowsError(try AgentJobCSV.makeItems(headers: ["id", "path"], rows: [["1"]], idColumn: nil)) { error in
            XCTAssertEqual(
                error as? FunctionCallError,
                .respondToModel("csv row 2 has 1 fields but header has 2")
            )
        }
    }

    func testRenderInstructionTemplateExpandsPlaceholdersAndEscapedBraces() {
        let rendered = AgentJobCSV.renderInstructionTemplate(
            "Review {path} in {area}. Also see {file path}. Use {{literal}}. Keep {missing}.",
            rowJSON: .object([
                "path": .string("src/lib.rs"),
                "area": .string("test"),
                "file path": .string("docs/readme.md"),
            ])
        )

        XCTAssertEqual(
            rendered,
            "Review src/lib.rs in test. Also see docs/readme.md. Use {literal}. Keep {missing}."
        )
    }

    func testRenderJobCSVAddsResultColumnsAndEscapesValuesLikeRust() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = AgentJobItem(
            jobID: "job-1",
            itemID: "item-1",
            rowIndex: 0,
            sourceID: "source,1",
            rowJSON: .object([
                "id": .string("1"),
                "name": .string("alpha, beta"),
            ]),
            status: .completed,
            assignedThreadID: nil,
            attemptCount: 2,
            resultJSON: .object(["ok": .bool(true), "count": .integer(3)]),
            lastError: "needs \"quote\"",
            createdAt: date,
            updatedAt: date,
            completedAt: date,
            reportedAt: date
        )

        let csv = try AgentJobCSV.renderJobCSV(inputHeaders: ["id", "name"], items: [item])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(
            String(lines[0]),
            "id,name,job_id,item_id,row_index,source_id,status,attempt_count,last_error,result_json,reported_at,completed_at"
        )
        XCTAssertTrue(String(lines[1]).contains(#"1,"alpha, beta",job-1,item-1,0,"source,1",completed,2"#))
        XCTAssertTrue(String(lines[1]).contains(#""needs ""quote""""#))
        XCTAssertTrue(String(lines[1]).contains(#""{""count"":3,""ok"":true}""#))
    }

    func testDefaultOutputCSVPathUsesInputStemAndJobSuffix() {
        XCTAssertEqual(
            AgentJobCSV.defaultOutputCSVPath(
                inputCSVPath: "/tmp/agent_jobs_input.csv",
                jobID: "1234567890abcdef"
            ),
            "/tmp/agent_jobs_input.agent-job-12345678.csv"
        )
    }
}
