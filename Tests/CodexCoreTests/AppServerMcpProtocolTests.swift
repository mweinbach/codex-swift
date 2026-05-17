import XCTest
@testable import CodexCore

final class AppServerMcpProtocolTests: XCTestCase {
    func testMcpServerStatusParamsAndResponseUseRustNullAndCamelCaseRules() throws {
        try XCTAssertJSONObjectEqual(AppServerProtocol.ListMcpServerStatusParams(), [
            "cursor": NSNull(),
            "limit": NSNull(),
            "detail": NSNull()
        ])
        try XCTAssertJSONObjectEqual(
            AppServerProtocol.ListMcpServerStatusParams(cursor: "cursor-1", limit: 25, detail: .toolsAndAuthOnly),
            [
                "cursor": "cursor-1",
                "limit": 25,
                "detail": "toolsAndAuthOnly"
            ]
        )

        let response = AppServerProtocol.ListMcpServerStatusResponse(
            data: [
                AppServerProtocol.McpServerStatus(
                    name: "docs",
                    tools: [
                        "search": McpTool(
                            name: "search",
                            inputSchema: McpToolInputSchema(),
                            description: "Search docs"
                        )
                    ],
                    resources: [
                        McpResource(
                            name: "Guide",
                            uri: "file:///guide.md",
                            mimeType: "text/markdown",
                            title: "Guide"
                        )
                    ],
                    resourceTemplates: [
                        McpResourceTemplate(
                            name: "doc",
                            uriTemplate: "file:///{name}.md",
                            mimeType: "text/markdown"
                        )
                    ],
                    authStatus: .oAuth
                )
            ],
            nextCursor: nil
        )

        try XCTAssertJSONObjectEqual(response, [
            "data": [[
                "name": "docs",
                "tools": [
                    "search": [
                        "name": "search",
                        "description": "Search docs",
                        "inputSchema": [
                            "type": "object"
                        ]
                    ]
                ],
                "resources": [[
                    "mimeType": "text/markdown",
                    "name": "Guide",
                    "title": "Guide",
                    "uri": "file:///guide.md"
                ]],
                "resourceTemplates": [[
                    "mimeType": "text/markdown",
                    "name": "doc",
                    "uriTemplate": "file:///{name}.md"
                ]],
                "authStatus": "oAuth"
            ]],
            "nextCursor": NSNull()
        ])
    }

    func testMcpResourceReadUsesExplicitNullableThreadID() throws {
        try XCTAssertJSONObjectEqual(AppServerProtocol.McpResourceReadParams(server: "docs", uri: "file:///guide.md"), [
            "threadId": NSNull(),
            "server": "docs",
            "uri": "file:///guide.md"
        ])

        let decodedNullThread = try JSONDecoder().decode(
            AppServerProtocol.McpResourceReadParams.self,
            from: Data(#"{"threadId":null,"server":"docs","uri":"file:///guide.md"}"#.utf8)
        )
        XCTAssertNil(decodedNullThread.threadID)
        try XCTAssertJSONObjectEqual(decodedNullThread, [
            "threadId": NSNull(),
            "server": "docs",
            "uri": "file:///guide.md"
        ])

        let decodedThread = try JSONDecoder().decode(
            AppServerProtocol.McpResourceReadParams.self,
            from: Data(#"{"threadId":"thr_1","server":"docs","uri":"file:///guide.md"}"#.utf8)
        )
        XCTAssertEqual(decodedThread.threadID, "thr_1")
        try XCTAssertJSONObjectEqual(decodedThread, [
            "threadId": "thr_1",
            "server": "docs",
            "uri": "file:///guide.md"
        ])

        let response = AppServerProtocol.McpResourceReadResponse(contents: [
            .text(McpTextResourceContents(
                text: "# Guide",
                uri: "file:///guide.md",
                mimeType: "text/markdown"
            )),
            .blob(McpBlobResourceContents(
                blob: "AAEC",
                uri: "file:///image.png",
                mimeType: "image/png"
            ))
        ])

        try XCTAssertJSONObjectEqual(response, [
            "contents": [
                [
                    "mimeType": "text/markdown",
                    "text": "# Guide",
                    "uri": "file:///guide.md"
                ],
                [
                    "blob": "AAEC",
                    "mimeType": "image/png",
                    "uri": "file:///image.png"
                ]
            ]
        ])

        let decodedResponse = try JSONDecoder().decode(
            AppServerProtocol.McpResourceReadResponse.self,
            from: Data(#"""
            {
              "contents": [
                {
                  "text": "# Guide",
                  "uri": "file:///guide.md",
                  "mimeType": "text/markdown"
                },
                {
                  "blob": "AAEC",
                  "uri": "file:///image.png",
                  "mimeType": "image/png"
                }
              ]
            }
            """#.utf8)
        )
        XCTAssertEqual(decodedResponse, response)
        try XCTAssertJSONObjectEqual(decodedResponse, [
            "contents": [
                [
                    "mimeType": "text/markdown",
                    "text": "# Guide",
                    "uri": "file:///guide.md"
                ],
                [
                    "blob": "AAEC",
                    "mimeType": "image/png",
                    "uri": "file:///image.png"
                ]
            ]
        ])
    }

    func testMcpToolCallParamsAndResponsesFollowSkipAndNullRules() throws {
        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerToolCallParams(threadID: "thr_1", server: "docs", tool: "search"),
            [
                "threadId": "thr_1",
                "server": "docs",
                "tool": "search"
            ]
        )

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerToolCallParams(
                threadID: "thr_1",
                server: "docs",
                tool: "search",
                arguments: .object(["query": .string("Codex")]),
                meta: .object(["trace": .string("abc")])
            ),
            [
                "threadId": "thr_1",
                "server": "docs",
                "tool": "search",
                "arguments": [
                    "query": "Codex"
                ],
                "_meta": [
                    "trace": "abc"
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerToolCallResponse(
                content: [.object(["type": .string("text"), "text": .string("hello")])]
            ),
            [
                "content": [[
                    "type": "text",
                    "text": "hello"
                ]]
            ]
        )

        let minimalParams = try JSONDecoder().decode(
            AppServerProtocol.McpServerToolCallParams.self,
            from: Data(#"{"threadId":"thr_1","server":"docs","tool":"search"}"#.utf8)
        )
        XCTAssertNil(minimalParams.arguments)
        XCTAssertNil(minimalParams.meta)

        let nullParams = try JSONDecoder().decode(
            AppServerProtocol.McpServerToolCallParams.self,
            from: Data(#"{"threadId":"thr_1","server":"docs","tool":"search","arguments":null,"_meta":null}"#.utf8)
        )
        XCTAssertNil(nullParams.arguments)
        XCTAssertNil(nullParams.meta)

        let minimalResponse = try JSONDecoder().decode(
            AppServerProtocol.McpServerToolCallResponse.self,
            from: Data(#"{"content":[]}"#.utf8)
        )
        XCTAssertEqual(minimalResponse.content, [])
        XCTAssertNil(minimalResponse.structuredContent)
        XCTAssertNil(minimalResponse.isError)
        XCTAssertNil(minimalResponse.meta)

        let nullResponse = try JSONDecoder().decode(
            AppServerProtocol.McpServerToolCallResponse.self,
            from: Data(#"{"content":[],"structuredContent":null,"isError":null,"_meta":null}"#.utf8)
        )
        XCTAssertEqual(nullResponse.content, [])
        XCTAssertNil(nullResponse.structuredContent)
        XCTAssertNil(nullResponse.isError)
        XCTAssertNil(nullResponse.meta)

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpToolCallResult(
                content: [],
                structuredContent: nil,
                meta: nil
            ),
            [
                "content": [Any](),
                "structuredContent": NSNull(),
                "_meta": NSNull()
            ]
        )
    }

    func testMcpRefreshOauthAndNotificationsMatchRustWireShape() throws {
        try XCTAssertJSONObjectEqual(AppServerProtocol.McpServerRefreshParams(), [String: Any]())
        try XCTAssertJSONObjectEqual(AppServerProtocol.McpServerRefreshResponse(), [String: Any]())

        try XCTAssertJSONObjectEqual(AppServerProtocol.McpServerOauthLoginParams(name: "github"), [
            "name": "github"
        ])
        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerOauthLoginParams(
                name: "github",
                scopes: ["repo"],
                timeoutSeconds: 30
            ),
            [
                "name": "github",
                "scopes": ["repo"],
                "timeoutSecs": 30
            ]
        )

        let minimalLogin = try JSONDecoder().decode(
            AppServerProtocol.McpServerOauthLoginParams.self,
            from: Data(#"{"name":"github"}"#.utf8)
        )
        XCTAssertNil(minimalLogin.scopes)
        XCTAssertNil(minimalLogin.timeoutSeconds)

        let nullLogin = try JSONDecoder().decode(
            AppServerProtocol.McpServerOauthLoginParams.self,
            from: Data(#"{"name":"github","scopes":null,"timeoutSecs":null}"#.utf8)
        )
        XCTAssertNil(nullLogin.scopes)
        XCTAssertNil(nullLogin.timeoutSeconds)

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerOauthLoginResponse(authorizationURL: "https://auth.example/authorize"),
            [
                "authorizationUrl": "https://auth.example/authorize"
            ]
        )

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpToolCallProgressNotification(
                threadID: "thr_1",
                turnID: "turn_1",
                itemID: "item_1",
                message: "Working"
            ),
            [
                "threadId": "thr_1",
                "turnId": "turn_1",
                "itemId": "item_1",
                "message": "Working"
            ]
        )
        XCTAssertEqual(
            AppServerProtocol.McpToolCallProgressNotification.method,
            "item/mcpToolCall/progress"
        )
        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerOauthLoginCompletedNotification(name: "github", success: false),
            [
                "name": "github",
                "success": false
            ]
        )
        let nullCompleted = try JSONDecoder().decode(
            AppServerProtocol.McpServerOauthLoginCompletedNotification.self,
            from: Data(#"{"name":"github","success":false,"error":null}"#.utf8)
        )
        XCTAssertNil(nullCompleted.error)

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.McpServerStatusUpdatedNotification(name: "github", status: .failed, error: nil),
            [
                "name": "github",
                "status": "failed",
                "error": NSNull()
            ]
        )
    }

    func testMcpAuthStatusProjectsCoreAuthStatusToAppServerV2Spelling() {
        XCTAssertEqual(AppServerMcpAuthStatus(coreStatus: .unsupported), .unsupported)
        XCTAssertEqual(AppServerMcpAuthStatus(coreStatus: .notLoggedIn), .notLoggedIn)
        XCTAssertEqual(AppServerMcpAuthStatus(coreStatus: .bearerToken), .bearerToken)
        XCTAssertEqual(AppServerMcpAuthStatus(coreStatus: .oauth), .oAuth)
    }
}
