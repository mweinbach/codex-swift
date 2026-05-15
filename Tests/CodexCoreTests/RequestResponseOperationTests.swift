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

    func testRequestUserInputModelsRejectExplicitNullForRustDefaultedFields() {
        XCTAssertThrowsError(try JSONDecoder().decode(RequestUserInputQuestion.self, from: Data(#"""
        {
          "id": "choice",
          "header": "Choice",
          "question": "Pick one",
          "isOther": null
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestUserInputQuestion.self, from: Data(#"""
        {
          "id": "choice",
          "header": "Choice",
          "question": "Pick one",
          "isSecret": null
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestUserInputEvent.self, from: Data(#"""
        {
          "call_id": "call-1",
          "turn_id": null,
          "questions": [
            {
              "id": "name",
              "header": "Name",
              "question": "What name?"
            }
          ]
        }
        """#.utf8)))
    }

    func testRequestUserInputAvailableModesAndDescriptionsMatchRust() {
        let defaultModes = RequestUserInputToolConfig.availableModes(features: .withDefaults())
        XCTAssertEqual(defaultModes, [.plan])
        XCTAssertNil(RequestUserInputToolConfig.unavailableMessage(mode: .plan, availableModes: defaultModes))
        XCTAssertEqual(
            RequestUserInputToolConfig.unavailableMessage(mode: .defaultMode, availableModes: defaultModes),
            "request_user_input is unavailable in Default mode"
        )
        XCTAssertEqual(
            RequestUserInputToolConfig.toolDescription(availableModes: defaultModes),
            "Request user input for one to three short questions and wait for the response. This tool is only available in Plan mode."
        )

        var features = FeatureStates.withDefaults()
        features.set(.defaultModeRequestUserInput, enabled: true)
        let defaultModeEnabled = RequestUserInputToolConfig.availableModes(features: features)
        XCTAssertEqual(defaultModeEnabled, [.defaultMode, .plan])
        XCTAssertNil(RequestUserInputToolConfig.unavailableMessage(mode: .defaultMode, availableModes: defaultModeEnabled))
        XCTAssertEqual(
            RequestUserInputToolConfig.toolDescription(availableModes: defaultModeEnabled),
            "Request user input for one to three short questions and wait for the response. This tool is only available in Default or Plan mode."
        )
    }

    func testRequestUserInputNormalizationRequiresOptionsAndEnablesOtherLikeRust() throws {
        let args = RequestUserInputArgs(questions: [
            RequestUserInputQuestion(
                id: "choice",
                header: "Choice",
                question: "Pick one",
                isOther: false,
                isSecret: true,
                options: [RequestUserInputQuestionOption(label: "Manual", description: "Type it")]
            )
        ])

        let normalized = try args.normalized()
        XCTAssertEqual(normalized.questions.count, 1)
        XCTAssertTrue(normalized.questions[0].isOther)
        XCTAssertTrue(normalized.questions[0].isSecret)
        XCTAssertEqual(normalized.questions[0].options, args.questions[0].options)

        XCTAssertThrowsError(try RequestUserInputArgs(questions: [
            RequestUserInputQuestion(id: "missing", header: "Missing", question: "No options")
        ]).normalized()) { error in
            XCTAssertEqual(
                String(describing: error),
                "request_user_input requires non-empty options for every question"
            )
        }

        XCTAssertThrowsError(try RequestUserInputArgs(questions: [
            RequestUserInputQuestion(
                id: "empty",
                header: "Empty",
                question: "No options",
                options: []
            )
        ]).normalized()) { error in
            XCTAssertEqual(error as? RequestUserInputNormalizationError, .missingOptions)
        }
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
                    fileSystem: FileSystemPermissions(read: ["/repo"])
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

    func testRequestPermissionModelsRejectExplicitNullForRustDefaultedFields() {
        XCTAssertThrowsError(try JSONDecoder().decode(RequestPermissionsResponse.self, from: Data(#"""
        {
          "permissions": {
            "network": {
              "enabled": false
            }
          },
          "scope": null
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestPermissionsResponse.self, from: Data(#"""
        {
          "permissions": {
            "network": {
              "enabled": false
            }
          },
          "strict_auto_review": null
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestPermissionsEvent.self, from: Data(#"""
        {
          "call_id": "perm-1",
          "turn_id": null,
          "started_at_ms": 1000,
          "permissions": {
            "network": {
              "enabled": true
            }
          }
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestPermissionsEvent.self, from: Data(#"""
        {
          "call_id": "perm-1",
          "permissions": {
            "network": {
              "enabled": true
            }
          }
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RequestPermissionsEvent.self, from: Data(#"""
        {
          "call_id": "perm-1",
          "started_at_ms": null,
          "permissions": {
            "network": {
              "enabled": true
            }
          }
        }
        """#.utf8)))
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
                    "text": "deploy",
                    "text_elements": []
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
