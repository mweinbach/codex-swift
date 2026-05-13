import CodexCore
import XCTest

final class MemorySummarizeAPITests: XCTestCase {
    func testMemorySummarizeInputWireShapeMatchesRust() throws {
        let input = MemorySummarizeInput(
            model: "gpt-test",
            rawMemories: [
                RawMemory(
                    id: "trace-1",
                    metadata: RawMemoryMetadata(sourcePath: "/tmp/trace.jsonl"),
                    items: [
                        .object([
                            "type": .string("message"),
                            "role": .string("user"),
                            "content": .array([])
                        ])
                    ]
                )
            ]
        )

        let body = try MemorySummarizeAPI.body(for: input)

        XCTAssertEqual(body, .object([
            "model": .string("gpt-test"),
            "traces": .array([
                .object([
                    "id": .string("trace-1"),
                    "metadata": .object([
                        "source_path": .string("/tmp/trace.jsonl")
                    ]),
                    "items": .array([
                        .object([
                            "type": .string("message"),
                            "role": .string("user"),
                            "content": .array([])
                        ])
                    ])
                ])
            ])
        ]))
    }

    func testMemorySummarizeInputIncludesReasoningWhenPresent() throws {
        let body = try MemorySummarizeAPI.body(for: MemorySummarizeInput(
            model: "gpt-test",
            rawMemories: [],
            reasoning: ResponsesAPIReasoning(effort: .medium)
        ))

        XCTAssertEqual(body, .object([
            "model": .string("gpt-test"),
            "traces": .array([]),
            "reasoning": .object([
                "effort": .string("medium")
            ])
        ]))
    }

    func testMemorySummarizeOutputDecodesTraceSummaryAndRawMemoryAlias() throws {
        let data = Data(#"""
        {
          "output": [
            {
              "trace_summary": "trace summary",
              "memory_summary": "memory summary"
            },
            {
              "raw_memory": "legacy raw memory",
              "memory_summary": "legacy memory summary"
            }
          ]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(MemorySummarizeResponse.self, from: data)

        XCTAssertEqual(response.output, [
            MemorySummarizeOutput(rawMemory: "trace summary", memorySummary: "memory summary"),
            MemorySummarizeOutput(rawMemory: "legacy raw memory", memorySummary: "legacy memory summary")
        ])
    }

    func testMemorySummarizePathMatchesRustEndpoint() {
        XCTAssertEqual(MemorySummarizeAPI.path, "memories/trace_summarize")
    }
}
