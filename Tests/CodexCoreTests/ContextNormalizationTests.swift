import CodexCore
import XCTest

final class ContextNormalizationTests: XCTestCase {
    func testEnsureCallOutputsPresentAddsMissingFunctionOutput() {
        var items: [ResponseItem] = [
            .functionCall(name: "do_it", arguments: "{}", callID: "call-x")
        ]

        ContextNormalization.ensureCallOutputsPresent(&items)

        XCTAssertEqual(items, [
            .functionCall(name: "do_it", arguments: "{}", callID: "call-x"),
            .functionCallOutput(callID: "call-x", output: FunctionCallOutputPayload(content: "aborted"))
        ])
    }

    func testEnsureCallOutputsPresentAddsMissingToolSearchOutput() {
        var items: [ResponseItem] = [
            .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            )
        ]

        ContextNormalization.ensureCallOutputsPresent(&items)

        XCTAssertEqual(items, [
            .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            ),
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])
        ])
    }

    func testEnsureCallOutputsPresentAddsMissingCustomAndLocalShellOutputs() {
        var items: [ResponseItem] = [
            .customToolCall(callID: "tool-x", name: "custom", input: "{}"),
            .localShellCall(callID: "shell-1", status: .completed, action: shellAction(["echo", "hi"]))
        ]

        ContextNormalization.ensureCallOutputsPresent(&items)

        XCTAssertEqual(items, [
            .customToolCall(callID: "tool-x", name: "custom", input: "{}"),
            .customToolCallOutput(callID: "tool-x", output: "aborted"),
            .localShellCall(callID: "shell-1", status: .completed, action: shellAction(["echo", "hi"])),
            .functionCallOutput(callID: "shell-1", output: FunctionCallOutputPayload(content: "aborted"))
        ])
    }

    func testRemoveOrphanOutputsKeepsFunctionAndLocalShellMatches() {
        var items: [ResponseItem] = [
            .functionCall(name: "f1", arguments: "{}", callID: "c1"),
            .functionCallOutput(callID: "c1", output: FunctionCallOutputPayload(content: "ok")),
            .localShellCall(callID: "s1", status: .completed, action: shellAction(["echo"])),
            .functionCallOutput(callID: "s1", output: FunctionCallOutputPayload(content: "ok")),
            .functionCallOutput(callID: "orphan", output: FunctionCallOutputPayload(content: "drop"))
        ]

        ContextNormalization.removeOrphanOutputs(&items)

        XCTAssertEqual(items, [
            .functionCall(name: "f1", arguments: "{}", callID: "c1"),
            .functionCallOutput(callID: "c1", output: FunctionCallOutputPayload(content: "ok")),
            .localShellCall(callID: "s1", status: .completed, action: shellAction(["echo"])),
            .functionCallOutput(callID: "s1", output: FunctionCallOutputPayload(content: "ok"))
        ])
    }

    func testRemoveOrphanOutputsHandlesCustomToolOutputs() {
        var items: [ResponseItem] = [
            .customToolCall(callID: "t1", name: "tool", input: "{}"),
            .customToolCallOutput(callID: "t1", output: "ok"),
            .customToolCallOutput(callID: "orphan", output: "drop")
        ]

        ContextNormalization.removeOrphanOutputs(&items)

        XCTAssertEqual(items, [
            .customToolCall(callID: "t1", name: "tool", input: "{}"),
            .customToolCallOutput(callID: "t1", output: "ok")
        ])
    }

    func testRemoveOrphanOutputsHandlesToolSearchOutputs() {
        var items: [ResponseItem] = [
            .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            ),
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: []),
            .toolSearchOutput(callID: "orphan", status: "completed", execution: "client", tools: []),
            .toolSearchOutput(callID: nil, status: "completed", execution: "server", tools: []),
            .toolSearchOutput(callID: "server-search", status: "completed", execution: "server", tools: [])
        ]

        ContextNormalization.removeOrphanOutputs(&items)

        XCTAssertEqual(items, [
            .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            ),
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: []),
            .toolSearchOutput(callID: nil, status: "completed", execution: "server", tools: []),
            .toolSearchOutput(callID: "server-search", status: "completed", execution: "server", tools: [])
        ])
    }

    func testNormalizeHistoryInsertsMissingAndRemovesOrphans() {
        var items: [ResponseItem] = [
            .functionCall(name: "f1", arguments: "{}", callID: "c1"),
            .functionCallOutput(callID: "c2", output: FunctionCallOutputPayload(content: "drop")),
            .customToolCall(callID: "t1", name: "tool", input: "{}"),
            .localShellCall(callID: "s1", status: .completed, action: shellAction(["echo"]))
        ]

        ContextNormalization.normalizeHistory(&items)

        XCTAssertEqual(items, [
            .functionCall(name: "f1", arguments: "{}", callID: "c1"),
            .functionCallOutput(callID: "c1", output: FunctionCallOutputPayload(content: "aborted")),
            .customToolCall(callID: "t1", name: "tool", input: "{}"),
            .customToolCallOutput(callID: "t1", output: "aborted"),
            .localShellCall(callID: "s1", status: .completed, action: shellAction(["echo"])),
            .functionCallOutput(callID: "s1", output: FunctionCallOutputPayload(content: "aborted"))
        ])
    }

    func testRemoveCorrespondingForFunctionCallPairs() {
        var outputSide: [ResponseItem] = [
            .functionCallOutput(callID: "c1", output: FunctionCallOutputPayload(content: "ok")),
            .functionCallOutput(callID: "other", output: FunctionCallOutputPayload(content: "keep"))
        ]
        ContextNormalization.removeCorresponding(
            for: .functionCall(name: "f1", arguments: "{}", callID: "c1"),
            from: &outputSide
        )
        XCTAssertEqual(outputSide, [
            .functionCallOutput(callID: "other", output: FunctionCallOutputPayload(content: "keep"))
        ])

        var callSide: [ResponseItem] = [
            .functionCall(name: "f1", arguments: "{}", callID: "c1")
        ]
        ContextNormalization.removeCorresponding(
            for: .functionCallOutput(callID: "c1", output: FunctionCallOutputPayload(content: "ok")),
            from: &callSide
        )
        XCTAssertEqual(callSide, [])
    }

    func testRemoveCorrespondingForToolSearchPairs() {
        var outputSide: [ResponseItem] = [
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: []),
            .toolSearchOutput(callID: "other", status: "completed", execution: "client", tools: [])
        ]
        ContextNormalization.removeCorresponding(
            for: .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            ),
            from: &outputSide
        )
        XCTAssertEqual(outputSide, [
            .toolSearchOutput(callID: "other", status: "completed", execution: "client", tools: [])
        ])

        var callSide: [ResponseItem] = [
            .toolSearchCall(
                callID: "search-1",
                execution: "client",
                arguments: .object(["query": .string("calendar")])
            )
        ]
        ContextNormalization.removeCorresponding(
            for: .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: []),
            from: &callSide
        )
        XCTAssertEqual(callSide, [])
    }

    func testRemoveCorrespondingForLocalShellAndCustomToolPairs() {
        var localShellItems: [ResponseItem] = [
            .functionCallOutput(callID: "s1", output: FunctionCallOutputPayload(content: "ok"))
        ]
        ContextNormalization.removeCorresponding(
            for: .localShellCall(callID: "s1", status: .completed, action: shellAction(["echo"])),
            from: &localShellItems
        )
        XCTAssertEqual(localShellItems, [])

        var customItems: [ResponseItem] = [
            .customToolCall(callID: "t1", name: "tool", input: "{}")
        ]
        ContextNormalization.removeCorresponding(
            for: .customToolCallOutput(callID: "t1", output: "ok"),
            from: &customItems
        )
        XCTAssertEqual(customItems, [])
    }

    func testStripImagesWhenUnsupportedLeavesImageCapableHistoryUnchanged() {
        var items: [ResponseItem] = [
            .message(role: "user", content: [
                .inputText(text: "see"),
                .inputImage(imageURL: "data:image/png;base64,abc", detail: .high)
            ]),
            .imageGenerationCall(id: "ig-1", status: "completed", result: "BASE64")
        ]
        let original = items

        ContextNormalization.stripImagesWhenUnsupported(inputModalities: [.text, .image], items: &items)

        XCTAssertEqual(items, original)
    }

    func testStripImagesWhenUnsupportedReplacesMessageAndToolOutputImagesLikeRust() {
        var items: [ResponseItem] = [
            .message(role: "user", content: [
                .inputText(text: "see"),
                .inputImage(imageURL: "data:image/png;base64,abc", detail: .high),
                .outputText(text: "kept")
            ]),
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputText(text: "caption"),
                        .inputImage(imageURL: "data:image/png;base64,tool", detail: .original)
                    ],
                    success: true
                )
            ),
            .customToolCallOutput(
                callID: "custom-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputImage(imageURL: "data:image/png;base64,custom", detail: .high)
                    ],
                    success: false
                )
            ),
            .imageGenerationCall(
                id: "ig-1",
                status: "completed",
                revisedPrompt: "prompt",
                result: "BASE64"
            )
        ]

        ContextNormalization.stripImagesWhenUnsupported(inputModalities: [.text], items: &items)

        let placeholder = ContextNormalization.imageContentOmittedPlaceholder
        XCTAssertEqual(items, [
            .message(role: "user", content: [
                .inputText(text: "see"),
                .inputText(text: placeholder),
                .outputText(text: "kept")
            ]),
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputText(text: "caption"),
                        .inputText(text: placeholder)
                    ],
                    success: true
                )
            ),
            .customToolCallOutput(
                callID: "custom-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputText(text: placeholder)
                    ],
                    success: false
                )
            ),
            .imageGenerationCall(
                id: "ig-1",
                status: "completed",
                revisedPrompt: "prompt",
                result: ""
            )
        ])
    }

    func testStripUnsupportedMediaReplacesAudioOutputsLikeRust() {
        var items: [ResponseItem] = [
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputText(text: "caption"),
                        .inputAudio(inputAudio: InputAudio(data: "BASE64", format: "wav"))
                    ],
                    success: true
                )
            ),
            .imageGenerationCall(id: "ig-1", status: "completed", result: "BASE64")
        ]

        ContextNormalization.stripUnsupportedMediaContent(inputModalities: [.text, .image], items: &items)

        XCTAssertEqual(items, [
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputText(text: "caption"),
                        .inputText(text: ContextNormalization.audioContentOmittedPlaceholder)
                    ],
                    success: true
                )
            ),
            .imageGenerationCall(id: "ig-1", status: "completed", result: "BASE64")
        ])
    }

    func testStripUnsupportedMediaKeepsAudioWhenModelSupportsItLikeRust() {
        var items: [ResponseItem] = [
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(
                    content: "ignored when content items exist",
                    contentItems: [
                        .inputAudio(inputAudio: InputAudio(data: "BASE64", format: "wav"))
                    ]
                )
            )
        ]
        let original = items

        ContextNormalization.stripUnsupportedMediaContent(inputModalities: [.text, .audio], items: &items)

        XCTAssertEqual(items, original)
    }

    private func shellAction(_ command: [String]) -> LocalShellAction {
        .exec(LocalShellExecAction(command: command))
    }
}
