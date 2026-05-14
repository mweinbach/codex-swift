import CodexCore
import XCTest

final class AppServerRealtimeProtocolTests: XCTestCase {
    func testRealtimeStartParamsEncodeRustWireShapeWithOmittedPromptAndNullableFields() throws {
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeStartParams(threadID: "thread-1", outputModality: .text),
            [
                "threadId": "thread-1",
                "outputModality": "text",
                "realtimeSessionId": NSNull(),
                "transport": NSNull(),
                "voice": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            ThreadRealtimeStartParams(
                threadID: "thread-1",
                outputModality: .audio,
                prompt: .null,
                realtimeSessionID: "sess_1",
                transport: .webrtc(sdp: "v=offer\r\n"),
                voice: .marin
            ),
            [
                "threadId": "thread-1",
                "outputModality": "audio",
                "prompt": NSNull(),
                "realtimeSessionId": "sess_1",
                "transport": [
                    "type": "webrtc",
                    "sdp": "v=offer\r\n"
                ],
                "voice": "marin"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ThreadRealtimeStartParams(
                threadID: "thread-1",
                outputModality: .audio,
                prompt: .value("Begin with a hello."),
                transport: .websocket
            ),
            [
                "threadId": "thread-1",
                "outputModality": "audio",
                "prompt": "Begin with a hello.",
                "realtimeSessionId": NSNull(),
                "transport": [
                    "type": "websocket"
                ],
                "voice": NSNull()
            ]
        )
    }

    func testRealtimeStartParamsDecodeDoubleOptionalPromptAndCoreConversion() throws {
        let omitted = try JSONDecoder().decode(
            ThreadRealtimeStartParams.self,
            from: Data(#"{"threadId":"thread-1","outputModality":"text"}"#.utf8)
        )
        XCTAssertEqual(omitted.prompt, .omitted)
        XCTAssertEqual(omitted.coreParams, ConversationStartParams(outputModality: .text))

        let nullPrompt = try JSONDecoder().decode(
            ThreadRealtimeStartParams.self,
            from: Data(
                #"""
                {
                  "threadId": "thread-1",
                  "outputModality": "audio",
                  "prompt": null,
                  "realtimeSessionId": "sess_1",
                  "transport": {
                    "type": "webrtc",
                    "sdp": "v=offer\r\n"
                  },
                  "voice": "marin"
                }
                """#.utf8
            )
        )
        XCTAssertEqual(nullPrompt.prompt, .null)
        XCTAssertEqual(nullPrompt.realtimeSessionID, "sess_1")
        XCTAssertEqual(nullPrompt.transport, .webrtc(sdp: "v=offer\r\n"))
        XCTAssertEqual(nullPrompt.voice, .marin)
        XCTAssertEqual(
            nullPrompt.coreParams,
            ConversationStartParams(
                outputModality: .audio,
                prompt: .null,
                realtimeSessionID: "sess_1",
                transport: .webrtc(sdp: "v=offer\r\n"),
                voice: .marin
            )
        )
    }

    func testRealtimeAudioChunkUsesAppServerCamelCaseAndExplicitNullOptionals() throws {
        let audio = ThreadRealtimeAudioChunk(data: "AA==", sampleRate: 24_000, numChannels: 1)

        try XCTAssertJSONObjectEqual(
            audio,
            [
                "data": "AA==",
                "sampleRate": 24_000,
                "numChannels": 1,
                "samplesPerChannel": NSNull(),
                "itemId": NSNull()
            ]
        )

        let decoded = try JSONDecoder().decode(
            ThreadRealtimeAudioChunk.self,
            from: Data(
                #"""
                {
                  "data": "AA==",
                  "sampleRate": 24000,
                  "numChannels": 1,
                  "samplesPerChannel": 480,
                  "itemId": "item_1"
                }
                """#.utf8
            )
        )
        XCTAssertEqual(decoded.coreFrame, RealtimeAudioFrame(
            data: "AA==",
            sampleRate: 24_000,
            numChannels: 1,
            samplesPerChannel: 480,
            itemID: "item_1"
        ))
    }

    func testRealtimeRequestAndResponsePayloadsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeAppendAudioParams(
                threadID: "thread-1",
                audio: ThreadRealtimeAudioChunk(
                    data: "AA==",
                    sampleRate: 24_000,
                    numChannels: 1,
                    samplesPerChannel: 480,
                    itemID: "item_1"
                )
            ),
            [
                "threadId": "thread-1",
                "audio": [
                    "data": "AA==",
                    "sampleRate": 24_000,
                    "numChannels": 1,
                    "samplesPerChannel": 480,
                    "itemId": "item_1"
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            ThreadRealtimeAppendTextParams(threadID: "thread-1", text: "hello"),
            [
                "threadId": "thread-1",
                "text": "hello"
            ]
        )
        try XCTAssertJSONObjectEqual(ThreadRealtimeAppendAudioResponse(), [:])
        try XCTAssertJSONObjectEqual(ThreadRealtimeAppendTextResponse(), [:])
        try XCTAssertJSONObjectEqual(ThreadRealtimeStartResponse(), [:])
        try XCTAssertJSONObjectEqual(ThreadRealtimeStopParams(threadID: "thread-1"), ["threadId": "thread-1"])
        try XCTAssertJSONObjectEqual(ThreadRealtimeStopResponse(), [:])
        try XCTAssertJSONObjectEqual(ThreadRealtimeListVoicesParams(), [:])
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeListVoicesResponse(voices: .builtin()),
            [
                "voices": [
                    "v1": ["juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol", "cove"],
                    "v2": ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"],
                    "defaultV1": "cove",
                    "defaultV2": "marin"
                ]
            ]
        )
    }

    func testRealtimeNotificationsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeStartedNotification(threadID: "thread-1", realtimeSessionID: nil, version: .v2),
            [
                "threadId": "thread-1",
                "realtimeSessionId": NSNull(),
                "version": "v2"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeItemAddedNotification(threadID: "thread-1", item: .object(["type": .string("response.created")])),
            [
                "threadId": "thread-1",
                "item": [
                    "type": "response.created"
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeTranscriptDeltaNotification(threadID: "thread-1", role: "user", delta: "hel"),
            [
                "threadId": "thread-1",
                "role": "user",
                "delta": "hel"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeTranscriptDoneNotification(threadID: "thread-1", role: "assistant", text: "hello"),
            [
                "threadId": "thread-1",
                "role": "assistant",
                "text": "hello"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeOutputAudioDeltaNotification(
                threadID: "thread-1",
                audio: ThreadRealtimeAudioChunk(data: "AA==", sampleRate: 24_000, numChannels: 1)
            ),
            [
                "threadId": "thread-1",
                "audio": [
                    "data": "AA==",
                    "sampleRate": 24_000,
                    "numChannels": 1,
                    "samplesPerChannel": NSNull(),
                    "itemId": NSNull()
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeSdpNotification(threadID: "thread-1", sdp: "v=answer\r\n"),
            [
                "threadId": "thread-1",
                "sdp": "v=answer\r\n"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeErrorNotification(threadID: "thread-1", message: "realtime failed"),
            [
                "threadId": "thread-1",
                "message": "realtime failed"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ThreadRealtimeClosedNotification(threadID: "thread-1"),
            [
                "threadId": "thread-1",
                "reason": NSNull()
            ]
        )
    }
}
