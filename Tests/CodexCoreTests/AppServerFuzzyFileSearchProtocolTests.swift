import CodexCore
import XCTest

final class AppServerFuzzyFileSearchProtocolTests: XCTestCase {
    func testFuzzyFileSearchParamsEncodeRustCamelCaseShape() throws {
        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchParams(query: "abc", roots: ["/repo"], cancellationToken: nil),
            [
                "query": "abc",
                "roots": ["/repo"],
                "cancellationToken": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchParams(query: "abc", roots: ["/repo", "/tmp"], cancellationToken: "token-1"),
            [
                "query": "abc",
                "roots": ["/repo", "/tmp"],
                "cancellationToken": "token-1"
            ]
        )
    }

    func testFuzzyFileSearchResponseAndResultEncodeRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchResponse(files: [
                FuzzyFileSearchResult(
                    root: "/repo",
                    path: "Sources/CodexCore/App.swift",
                    matchType: .file,
                    fileName: "App.swift",
                    score: 42,
                    indices: [0, 4, 8]
                ),
                FuzzyFileSearchResult(
                    root: "/repo",
                    path: "Sources/CodexCore",
                    matchType: .directory,
                    fileName: "CodexCore",
                    score: 7,
                    indices: nil
                )
            ]),
            [
                "files": [
                    [
                        "root": "/repo",
                        "path": "Sources/CodexCore/App.swift",
                        "matchType": "file",
                        "fileName": "App.swift",
                        "score": 42,
                        "indices": [0, 4, 8]
                    ],
                    [
                        "root": "/repo",
                        "path": "Sources/CodexCore",
                        "matchType": "directory",
                        "fileName": "CodexCore",
                        "score": 7,
                        "indices": NSNull()
                    ]
                ]
            ]
        )
    }

    func testFuzzyFileSearchSessionPayloadsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchSessionStartParams(sessionID: "session-1", roots: ["/repo"]),
            [
                "sessionId": "session-1",
                "roots": ["/repo"]
            ]
        )
        try XCTAssertJSONObjectEqual(FuzzyFileSearchSessionStartResponse(), [:])

        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchSessionUpdateParams(sessionID: "session-1", query: "lib"),
            [
                "sessionId": "session-1",
                "query": "lib"
            ]
        )
        try XCTAssertJSONObjectEqual(FuzzyFileSearchSessionUpdateResponse(), [:])

        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchSessionStopParams(sessionID: "session-1"),
            ["sessionId": "session-1"]
        )
        try XCTAssertJSONObjectEqual(FuzzyFileSearchSessionStopResponse(), [:])
    }

    func testFuzzyFileSearchSessionNotificationsEncodeRustWireShapes() throws {
        let result = FuzzyFileSearchResult(
            root: "/repo",
            path: "Sources/CodexCore/App.swift",
            matchType: .file,
            fileName: "App.swift",
            score: 42,
            indices: [0, 4, 8]
        )

        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchSessionUpdatedNotification(
                sessionID: "session-1",
                query: "app",
                files: [result]
            ),
            [
                "sessionId": "session-1",
                "query": "app",
                "files": [
                    [
                        "root": "/repo",
                        "path": "Sources/CodexCore/App.swift",
                        "matchType": "file",
                        "fileName": "App.swift",
                        "score": 42,
                        "indices": [0, 4, 8]
                    ]
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            FuzzyFileSearchSessionCompletedNotification(sessionID: "session-1"),
            ["sessionId": "session-1"]
        )
    }

    func testFuzzyFileSearchDecodesRustPayloads() throws {
        let params = try JSONDecoder().decode(
            FuzzyFileSearchParams.self,
            from: Data(#"{"query":"abc","roots":["/repo"]}"#.utf8)
        )
        XCTAssertEqual(params, FuzzyFileSearchParams(query: "abc", roots: ["/repo"]))

        let response = try JSONDecoder().decode(
            FuzzyFileSearchResponse.self,
            from: Data(#"{"files":[{"root":"/repo","path":"Sources/App.swift","matchType":"file","fileName":"App.swift","score":9,"indices":null}]}"#.utf8)
        )
        XCTAssertEqual(response.files.first?.indices, nil)
        XCTAssertEqual(response.files.first?.matchType, .file)

        let update = try JSONDecoder().decode(
            FuzzyFileSearchSessionUpdatedNotification.self,
            from: Data(#"{"sessionId":"session-1","query":"app","files":[]}"#.utf8)
        )
        XCTAssertEqual(update.sessionID, "session-1")
        XCTAssertEqual(update.query, "app")
        XCTAssertEqual(update.files, [])
    }
}
