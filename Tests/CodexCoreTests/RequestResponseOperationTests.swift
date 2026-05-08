import CodexCore
import XCTest

final class RequestResponseOperationTests: XCTestCase {
    func testRequestUserInputModelsUseRustDefaultsAndWireNames() throws {
        let decoded = try JSONDecoder().decode(RequestUserInputQuestion.self, from: Data(#"""
        {
          "id": "choice",
          "header": "Choice",
          "question": "Pick one"
        }
        """#.utf8))

        XCTAssertFalse(decoded.isOther)
        XCTAssertFalse(decoded.isSecret)
        XCTAssertNil(decoded.options)

        let question = RequestUserInputQuestion(
            id: "api_key",
            header: "API Key",
            question: "Enter key",
            isOther: true,
            isSecret: true,
            options: [RequestUserInputQuestionOption(label: "Manual", description: "Type it")]
        )

        try XCTAssertJSONObjectEqual(question, [
            "id": "api_key",
            "header": "API Key",
            "question": "Enter key",
            "isOther": true,
            "isSecret": true,
            "options": [
                [
                    "label": "Manual",
                    "description": "Type it"
                ]
            ]
        ])

        let event = try JSONDecoder().decode(RequestUserInputEvent.self, from: Data(#"""
        {
          "call_id": "call-1",
          "questions": [
            {
              "id": "name",
              "header": "Name",
              "question": "What name?"
            }
          ]
        }
        """#.utf8))

        XCTAssertEqual(event.turnID, "")
    }

    func testResponseOperationsWireShapes() throws {
        let userInput = Op.userInputAnswer(
            id: "turn-1",
            response: RequestUserInputResponse(answers: [
                "choice": RequestUserInputAnswer(answers: ["A", "B"])
            ])
        )

        try XCTAssertJSONObjectEqual(userInput, [
            "type": "user_input_answer",
            "id": "turn-1",
            "response": [
                "answers": [
                    "choice": [
                        "answers": ["A", "B"]
                    ]
                ]
            ]
        ])

        let legacy = try JSONDecoder().decode(Op.self, from: Data(#"""
        {
          "type": "request_user_input_response",
          "id": "turn-1",
          "response": {
            "answers": {
              "choice": {
                "answers": ["A"]
              }
            }
          }
        }
        """#.utf8))
        XCTAssertEqual(
            legacy,
            .userInputAnswer(
                id: "turn-1",
                response: RequestUserInputResponse(answers: [
                    "choice": RequestUserInputAnswer(answers: ["A"])
                ])
            )
        )

        let permissions = Op.requestPermissionsResponse(
            id: "call-2",
            response: RequestPermissionsResponse(
                permissions: RequestPermissionProfile(
                    network: RequestPermissionNetworkPermissions(enabled: true),
                    fileSystem: .object([
                        "read": .array([.string("/repo")])
                    ])
                ),
                scope: .session,
                strictAutoReview: true
            )
        )

        try XCTAssertJSONObjectEqual(permissions, [
            "type": "request_permissions_response",
            "id": "call-2",
            "response": [
                "permissions": [
                    "network": [
                        "enabled": true
                    ],
                    "file_system": [
                        "read": ["/repo"]
                    ]
                ],
                "scope": "session",
                "strict_auto_review": true
            ]
        ])
    }

    func testRequestPermissionResponseDefaultsMatchSerde() throws {
        let decoded = try JSONDecoder().decode(RequestPermissionsResponse.self, from: Data(#"""
        {
          "permissions": {
            "network": {
              "enabled": false
            }
          }
        }
        """#.utf8))

        XCTAssertEqual(decoded.scope, .turn)
        XCTAssertFalse(decoded.strictAutoReview)

        try XCTAssertJSONObjectEqual(decoded, [
            "permissions": [
                "network": [
                    "enabled": false
                ]
            ],
            "scope": "turn"
        ])
    }

    func testDynamicToolModelsUseCamelCaseWireShapeAndCompatibilityFlag() throws {
        let spec = try JSONDecoder().decode(DynamicToolSpec.self, from: Data(#"""
        {
          "namespace": "linear",
          "name": "lookup",
          "description": "Lookup an issue",
          "inputSchema": {
            "type": "object"
          },
          "exposeToContext": false
        }
        """#.utf8))

        XCTAssertTrue(spec.deferLoading)

        let response = Op.dynamicToolResponse(
            id: "call-3",
            response: DynamicToolResponse(
                contentItems: [
                    .text("done"),
                    .imageURL("https://example.test/image.png")
                ],
                success: true
            )
        )

        try XCTAssertJSONObjectEqual(response, [
            "type": "dynamic_tool_response",
            "id": "call-3",
            "response": [
                "contentItems": [
                    [
                        "type": "inputText",
                        "text": "done"
                    ],
                    [
                        "type": "inputImage",
                        "imageUrl": "https://example.test/image.png"
                    ]
                ],
                "success": true
            ]
        ])
    }

    func testUserInputOptionalContextAndMcpRefreshWireShapes() throws {
        let input = Op.userInput(
            items: [.text("deploy")],
            environments: [TurnEnvironmentSelection(environmentID: "env-1", cwd: "/repo")],
            finalOutputJSONSchema: .object(["type": .string("object")]),
            responsesAPIClientMetadata: ["origin": "app"]
        )

        try XCTAssertJSONObjectEqual(input, [
            "type": "user_input",
            "items": [
                [
                    "type": "text",
                    "text": "deploy"
                ]
            ],
            "environments": [
                [
                    "environment_id": "env-1",
                    "cwd": "/repo"
                ]
            ],
            "final_output_json_schema": [
                "type": "object"
            ],
            "responsesapi_client_metadata": [
                "origin": "app"
            ]
        ])

        let refresh = Op.refreshMcpServers(config: McpServerRefreshConfig(
            mcpServers: .object([
                "filesystem": .object([
                    "command": .string("mcp-server-filesystem")
                ])
            ]),
            mcpOAuthCredentialsStoreMode: .string("chatgpt")
        ))

        try XCTAssertJSONObjectEqual(refresh, [
            "type": "refresh_mcp_servers",
            "config": [
                "mcp_servers": [
                    "filesystem": [
                        "command": "mcp-server-filesystem"
                    ]
                ],
                "mcp_oauth_credentials_store_mode": "chatgpt"
            ]
        ])

        for op in [input, refresh] {
            let data = try JSONEncoder().encode(op)
            XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
        }
    }
}
