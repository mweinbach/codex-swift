import CodexCore
import XCTest

final class InterAgentCommunicationTests: XCTestCase {
    func testInterAgentCommunicationWireShapeAndDefaults() throws {
        let communication = InterAgentCommunication(
            author: .root,
            recipient: try AgentPath.root.join("reviewer"),
            otherRecipients: [try AgentPath.root.join("worker")],
            content: "review the diff",
            triggerTurn: true
        )

        try XCTAssertJSONObjectEqual(communication, [
            "author": "/root",
            "recipient": "/root/reviewer",
            "other_recipients": ["/root/worker"],
            "content": "review the diff",
            "trigger_turn": true
        ])

        let missingOtherRecipients = try JSONDecoder().decode(InterAgentCommunication.self, from: Data(#"""
        {
          "author": "/root",
          "recipient": "/root/reviewer",
          "content": "review the diff",
          "trigger_turn": true
        }
        """#.utf8))
        XCTAssertEqual(missingOtherRecipients.otherRecipients, [])
    }

    func testInterAgentCommunicationOperationWireShape() throws {
        let op = Op.interAgentCommunication(communication: InterAgentCommunication(
            author: .root,
            recipient: try AgentPath.root.join("reviewer"),
            otherRecipients: [try AgentPath.root.join("worker")],
            content: "review the diff",
            triggerTurn: true
        ))

        try XCTAssertJSONObjectEqual(op, [
            "type": "inter_agent_communication",
            "communication": [
                "author": "/root",
                "recipient": "/root/reviewer",
                "other_recipients": ["/root/worker"],
                "content": "review the diff",
                "trigger_turn": true
            ]
        ])

        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
    }

    func testInterAgentCommunicationDetectsMessageContent() throws {
        let communication = InterAgentCommunication(
            author: .root,
            recipient: try AgentPath.root.join("reviewer"),
            content: "review the diff",
            triggerTurn: false
        )
        let text = String(data: try JSONEncoder().encode(communication), encoding: .utf8)!

        XCTAssertEqual(
            InterAgentCommunication.fromMessageContent([.outputText(text: text)]),
            communication
        )
        XCTAssertTrue(InterAgentCommunication.isMessageContent([.inputText(text: text)]))
        XCTAssertFalse(InterAgentCommunication.isMessageContent([.inputImage(imageURL: "file:///tmp/a.png")]))
        XCTAssertFalse(InterAgentCommunication.isMessageContent([.outputText(text: "{}"), .outputText(text: "{}")]))
    }

    func testInterAgentCommunicationResponseInputItemPreservesCommentaryPhase() throws {
        let communication = InterAgentCommunication(
            author: .root,
            recipient: try AgentPath.root.join("reviewer"),
            otherRecipients: [try AgentPath.root.join("worker")],
            content: "review the diff",
            triggerTurn: true
        )

        let item = communication.toResponseInputItem()
        guard case let .message(role, content, phase) = item else {
            return XCTFail("expected assistant message")
        }
        XCTAssertEqual(role, "assistant")
        XCTAssertEqual(phase, .commentary)
        XCTAssertEqual(InterAgentCommunication.fromMessageContent(content), communication)

        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(item)) as? [String: Any]
        XCTAssertEqual(encoded?["type"] as? String, "message")
        XCTAssertEqual(encoded?["role"] as? String, "assistant")
        XCTAssertEqual(encoded?["phase"] as? String, "commentary")
        let encodedContent = try XCTUnwrap(encoded?["content"] as? [[String: Any]])
        XCTAssertEqual(encodedContent.first?["type"] as? String, "output_text")
        let encodedText = try XCTUnwrap(encodedContent.first?["text"] as? String)
        XCTAssertEqual(
            InterAgentCommunication.fromMessageContent([.outputText(text: encodedText)]),
            communication
        )
    }
}
