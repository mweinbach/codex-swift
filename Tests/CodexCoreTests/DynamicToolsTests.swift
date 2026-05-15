import CodexCore
import XCTest

final class DynamicToolsTests: XCTestCase {
    func testDynamicToolSpecDecodesCanonicalDeferLoadingLikeRust() throws {
        let spec = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {
              "id": { "type": "string" }
            }
          },
          "deferLoading": true
        }
        """#)

        XCTAssertEqual(
            spec,
            DynamicToolSpec(
                name: "lookup_ticket",
                description: "Fetch a ticket",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                deferLoading: true
            )
        )
    }

    func testDynamicToolSpecDecodesLegacyExposeToContextLikeRust() throws {
        let hidden = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "exposeToContext": false
        }
        """#)
        XCTAssertTrue(hidden.deferLoading)

        let visible = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "exposeToContext": true
        }
        """#)
        XCTAssertFalse(visible.deferLoading)

        let explicitDeferLoading = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "deferLoading": false,
          "exposeToContext": false
        }
        """#)
        XCTAssertFalse(explicitDeferLoading.deferLoading)

        let defaulted = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          }
        }
        """#)
        XCTAssertFalse(defaulted.deferLoading)
    }

    func testDynamicToolSpecAcceptsNullLegacyVisibilityLikeRust() throws {
        let defaultedNullDeferLoading = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "deferLoading": null
        }
        """#)
        XCTAssertFalse(defaultedNullDeferLoading.deferLoading)

        let legacyFallback = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "deferLoading": null,
          "exposeToContext": false
        }
        """#)
        XCTAssertTrue(legacyFallback.deferLoading)

        let defaultedNullExposeToContext = try decodeDynamicTool(#"""
        {
          "name": "lookup_ticket",
          "description": "Fetch a ticket",
          "inputSchema": {
            "type": "object",
            "properties": {}
          },
          "exposeToContext": null
        }
        """#)
        XCTAssertFalse(defaultedNullExposeToContext.deferLoading)
    }

    func testDynamicToolSpecEncodesCanonicalDeferLoadingLikeRust() throws {
        try XCTAssertJSONObjectEqual(DynamicToolSpec(
            namespace: "codex_app",
            name: "lookup_ticket",
            description: "Fetch a ticket",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string")
                    ])
                ])
            ])
        ), [
            "namespace": "codex_app",
            "name": "lookup_ticket",
            "description": "Fetch a ticket",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string"
                    ]
                ]
            ],
            "deferLoading": false
        ])
    }

    func testDynamicToolCallRequestDefaultsMissingStartedAtLikeRust() throws {
        let decoded = try JSONDecoder().decode(DynamicToolCallRequest.self, from: Data("""
        {
          "callId": "dyn-1",
          "turnId": "turn-1",
          "tool": "lookup",
          "arguments": {}
        }
        """.utf8))

        XCTAssertEqual(decoded.startedAtMilliseconds, 0)
    }

    func testDynamicToolCallRequestRejectsNullRustDefaultedStartedAt() {
        let payload = """
        {
          "callId": "dyn-1",
          "turnId": "turn-1",
          "startedAtMs": null,
          "tool": "lookup",
          "arguments": {}
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(DynamicToolCallRequest.self, from: Data(payload.utf8))
        )
    }

    func testDynamicToolResponseSerializesTextAndImageContentItemsLikeRust() throws {
        try XCTAssertJSONObjectEqual(
            DynamicToolResponse(
                contentItems: [
                    .text("dynamic-ok"),
                    .imageURL("data:image/png;base64,AAA")
                ],
                success: true
            ),
            [
                "contentItems": [
                    [
                        "type": "inputText",
                        "text": "dynamic-ok"
                    ],
                    [
                        "type": "inputImage",
                        "imageUrl": "data:image/png;base64,AAA"
                    ]
                ],
                "success": true
            ]
        )
    }

    func testDynamicToolCallResponseDefaultsMissingCompletedAtLikeRust() throws {
        let decoded = try JSONDecoder().decode(DynamicToolCallResponseEvent.self, from: Data("""
        {
          "call_id": "dyn-1",
          "turn_id": "turn-1",
          "tool": "lookup",
          "arguments": {},
          "content_items": [],
          "success": true,
          "duration": { "secs": 0, "nanos": 0 }
        }
        """.utf8))

        XCTAssertEqual(decoded.completedAtMilliseconds, 0)
    }

    func testDynamicToolCallResponseRejectsNullRustDefaultedCompletedAt() {
        let payload = """
        {
          "call_id": "dyn-1",
          "turn_id": "turn-1",
          "completed_at_ms": null,
          "tool": "lookup",
          "arguments": {},
          "content_items": [],
          "success": true,
          "duration": { "secs": 0, "nanos": 0 }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(DynamicToolCallResponseEvent.self, from: Data(payload.utf8))
        )
    }

    func testValidateDynamicToolsAcceptsRustSupportedSchemasAndIdentifiers() throws {
        try DynamicToolSpec.validate([
            dynamicTool(
                namespace: "Codex-App_2",
                name: "lookup-ticket_2",
                inputSchema: .object([
                    "properties": .object([:])
                ])
            ),
            dynamicTool(
                namespace: "codex_app",
                name: "shared_name",
                inputSchema: objectSchema(),
                deferLoading: true
            ),
            dynamicTool(
                namespace: "other_app",
                name: "shared_name",
                inputSchema: objectSchema(),
                deferLoading: true
            ),
            dynamicTool(
                name: "nullable_field",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .array([.string("string"), .string("null")])
                        ])
                    ]),
                    "required": .array([.string("query")]),
                    "additionalProperties": .bool(false)
                ])
            )
        ])
    }

    func testValidateDynamicToolsRejectsRustInvalidNames() {
        assertValidationError(
            dynamicTool(name: "", inputSchema: objectSchema()),
            "dynamic tool name must not be empty"
        )
        assertValidationError(
            dynamicTool(name: " lookup", inputSchema: objectSchema()),
            "dynamic tool name has leading/trailing whitespace:  lookup"
        )
        assertValidationError(
            dynamicTool(name: "lookup.ticket", inputSchema: objectSchema()),
            "dynamic tool name must match ^[a-zA-Z0-9_-]+$ to match Responses API: lookup.ticket"
        )
        assertValidationError(
            dynamicTool(name: "lookup🙂", inputSchema: objectSchema()),
            "dynamic tool name must match ^[a-zA-Z0-9_-]+$ to match Responses API: lookup\\u{1f642}"
        )
        assertValidationError(
            dynamicTool(name: "lookup\"ticket", inputSchema: objectSchema()),
            "dynamic tool name must match ^[a-zA-Z0-9_-]+$ to match Responses API: lookup\\\"ticket"
        )
        let longName = String(repeating: "a", count: 129)
        assertValidationError(
            dynamicTool(name: longName, inputSchema: objectSchema()),
            "dynamic tool name must be at most 128 characters to match Responses API: \(longName)"
        )
        assertValidationError(
            dynamicTool(name: "mcp", inputSchema: objectSchema()),
            "dynamic tool name is reserved: mcp"
        )
        assertValidationError(
            dynamicTool(name: "mcp__lookup", inputSchema: objectSchema()),
            "dynamic tool name is reserved: mcp__lookup"
        )
    }

    func testValidateDynamicToolsRejectsRustInvalidNamespaces() {
        assertValidationError(
            dynamicTool(namespace: "", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace must not be empty for lookup"
        )
        assertValidationError(
            dynamicTool(namespace: "codex_app ", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace has leading/trailing whitespace for lookup: codex_app"
        )
        assertValidationError(
            dynamicTool(namespace: "codex.app", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace must match ^[a-zA-Z0-9_-]+$ to match Responses API: codex.app"
        )
        assertValidationError(
            dynamicTool(namespace: "codex\u{7}app", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace must match ^[a-zA-Z0-9_-]+$ to match Responses API: codex\\u{7}app"
        )
        let longNamespace = String(repeating: "a", count: 65)
        assertValidationError(
            dynamicTool(namespace: longNamespace, name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace must be at most 64 characters to match Responses API: \(longNamespace)"
        )
        assertValidationError(
            dynamicTool(namespace: "mcp__server__", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace is reserved for lookup: mcp__server__"
        )
        assertValidationError(
            dynamicTool(namespace: "functions", name: "lookup", inputSchema: objectSchema()),
            "dynamic tool namespace collides with a reserved Responses API namespace for lookup: functions"
        )
    }

    func testValidateDynamicToolsRejectsRustDuplicateAndDeferredToolRules() {
        assertValidationError(
            [
                dynamicTool(name: "lookup", inputSchema: objectSchema()),
                dynamicTool(name: "lookup", inputSchema: objectSchema())
            ],
            "duplicate dynamic tool name: lookup"
        )
        assertValidationError(
            [
                dynamicTool(namespace: "codex_app", name: "lookup", inputSchema: objectSchema()),
                dynamicTool(namespace: "codex_app", name: "lookup", inputSchema: objectSchema())
            ],
            "duplicate dynamic tool name in namespace codex_app: lookup"
        )
        assertValidationError(
            dynamicTool(name: "hidden_tool", inputSchema: objectSchema(), deferLoading: true),
            "deferred dynamic tool must include a namespace: hidden_tool"
        )
    }

    func testValidateDynamicToolsRejectsRustUnsupportedSingletonNullSchema() {
        assertValidationError(
            dynamicTool(name: "my_tool", inputSchema: .object(["type": .string("null")])),
            "dynamic tool input schema is not supported for my_tool: singleton null schema is not supported"
        )
    }

    private func dynamicTool(
        namespace: String? = nil,
        name: String,
        inputSchema: JSONValue,
        deferLoading: Bool = false
    ) -> DynamicToolSpec {
        DynamicToolSpec(
            namespace: namespace,
            name: name,
            description: "test",
            inputSchema: inputSchema,
            deferLoading: deferLoading
        )
    }

    private func objectSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ])
    }

    private func assertValidationError(
        _ tool: DynamicToolSpec,
        _ expectedDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertValidationError([tool], expectedDescription, file: file, line: line)
    }

    private func assertValidationError(
        _ tools: [DynamicToolSpec],
        _ expectedDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DynamicToolSpec.validate(tools), file: file, line: line) { error in
            XCTAssertEqual(
                (error as? DynamicToolValidationError)?.description,
                expectedDescription,
                file: file,
                line: line
            )
        }
    }

    private func decodeDynamicTool(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DynamicToolSpec {
        do {
            return try JSONDecoder().decode(DynamicToolSpec.self, from: Data(json.utf8))
        } catch {
            XCTFail("Failed to decode dynamic tool: \(error)", file: file, line: line)
            throw error
        }
    }
}
