import CodexCore
import XCTest

final class RealtimeConversationTests: XCTestCase {
    func testRealtimeConversationOperationsUseUnnestedRustWireShape() throws {
        let start = Op.realtimeConversationStart(ConversationStartParams(
            outputModality: .audio,
            prompt: .value("be helpful"),
            realtimeSessionID: "conv_1"
        ))

        try XCTAssertJSONObjectEqual(start, [
            "type": "realtime_conversation_start",
            "output_modality": "audio",
            "prompt": "be helpful",
            "realtime_session_id": "conv_1"
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationStart(ConversationStartParams(outputModality: .audio)), [
            "type": "realtime_conversation_start",
            "output_modality": "audio"
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationStart(ConversationStartParams(
            outputModality: .audio,
            prompt: .null
        )), [
            "type": "realtime_conversation_start",
            "output_modality": "audio",
            "prompt": NSNull()
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationStart(ConversationStartParams(
            outputModality: .audio,
            prompt: .value("be helpful"),
            realtimeSessionID: "conv_1",
            transport: .webrtc(sdp: "v=offer\r\n"),
            voice: .cove
        )), [
            "type": "realtime_conversation_start",
            "output_modality": "audio",
            "prompt": "be helpful",
            "realtime_session_id": "conv_1",
            "transport": [
                "type": "webrtc",
                "sdp": "v=offer\r\n"
            ],
            "voice": "cove"
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationAudio(ConversationAudioParams(frame: RealtimeAudioFrame(
            data: "AQID",
            sampleRate: 24_000,
            numChannels: 1,
            samplesPerChannel: 480
        ))), [
            "type": "realtime_conversation_audio",
            "frame": [
                "data": "AQID",
                "sample_rate": 24_000,
                "num_channels": 1,
                "samples_per_channel": 480
            ]
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationText(ConversationTextParams(text: "hello")), [
            "type": "realtime_conversation_text",
            "text": "hello"
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationClose, [
            "type": "realtime_conversation_close"
        ])

        try XCTAssertJSONObjectEqual(Op.realtimeConversationListVoices, [
            "type": "realtime_conversation_list_voices"
        ])
    }

    func testRealtimeConversationOperationsDecodeLikeSerde() throws {
        let defaultPrompt = try JSONDecoder().decode(Op.self, from: Data(#"""
        {"type":"realtime_conversation_start","output_modality":"audio"}
        """#.utf8))
        XCTAssertEqual(defaultPrompt, .realtimeConversationStart(ConversationStartParams(outputModality: .audio)))

        let nullPrompt = try JSONDecoder().decode(Op.self, from: Data(#"""
        {"type":"realtime_conversation_start","output_modality":"audio","prompt":null}
        """#.utf8))
        XCTAssertEqual(nullPrompt, .realtimeConversationStart(ConversationStartParams(
            outputModality: .audio,
            prompt: .null
        )))

        let cases: [Op] = [
            .realtimeConversationAudio(ConversationAudioParams(frame: RealtimeAudioFrame(
                data: "AQID",
                sampleRate: 24_000,
                numChannels: 1,
                samplesPerChannel: 480
            ))),
            .realtimeConversationText(ConversationTextParams(text: "hello")),
            .realtimeConversationClose,
            .realtimeConversationListVoices
        ]

        for op in cases {
            let data = try JSONEncoder().encode(op)
            XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
        }
    }

    func testRealtimeConversationStartedEventKeepsNullSessionID() throws {
        try XCTAssertJSONObjectEqual(RealtimeConversationStartedEvent(realtimeSessionID: "conv_1"), [
            "realtime_session_id": "conv_1",
            "version": "v2"
        ])

        try XCTAssertJSONObjectEqual(RealtimeConversationStartedEvent(realtimeSessionID: nil, version: .v1), [
            "realtime_session_id": NSNull(),
            "version": "v1"
        ])
    }

    func testRealtimeVoicesListIsStable() throws {
        XCTAssertEqual(RealtimeVoicesList.builtin(), RealtimeVoicesList(
            v1: [.juniper, .maple, .spruce, .ember, .vale, .breeze, .arbor, .sol, .cove],
            v2: [.alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse, .marin, .cedar],
            defaultV1: .cove,
            defaultV2: .marin
        ))

        try XCTAssertJSONObjectEqual(RealtimeConversationListVoicesResponseEvent(voices: .builtin()), [
            "voices": [
                "v1": ["juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol", "cove"],
                "v2": ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"],
                "defaultV1": "cove",
                "defaultV2": "marin"
            ]
        ])
    }

    func testRealtimeEventsUseRustExternalTags() throws {
        let sessionUpdated = RealtimeConversationRealtimeEvent(payload: .sessionUpdated(
            realtimeSessionID: "conv_1",
            instructions: nil
        ))
        try XCTAssertJSONObjectEqual(sessionUpdated, [
            "payload": [
                "SessionUpdated": [
                    "realtime_session_id": "conv_1",
                    "instructions": NSNull()
                ]
            ]
        ])

        let speechStarted = RealtimeConversationRealtimeEvent(payload: .inputAudioSpeechStarted(
            RealtimeInputAudioSpeechStarted(itemID: nil)
        ))
        try XCTAssertJSONObjectEqual(speechStarted, [
            "payload": [
                "InputAudioSpeechStarted": [
                    "item_id": NSNull()
                ]
            ]
        ])

        let itemDone = RealtimeConversationRealtimeEvent(payload: .conversationItemDone(itemID: "item_1"))
        try XCTAssertJSONObjectEqual(itemDone, [
            "payload": [
                "ConversationItemDone": [
                    "item_id": "item_1"
                ]
            ]
        ])

        let error = RealtimeConversationRealtimeEvent(payload: .error("boom"))
        try XCTAssertJSONObjectEqual(error, [
            "payload": [
                "Error": "boom"
            ]
        ])

        for event in [sessionUpdated, speechStarted, itemDone, error] {
            let data = try JSONEncoder().encode(event)
            XCTAssertEqual(try JSONDecoder().decode(RealtimeConversationRealtimeEvent.self, from: data), event)
        }
    }
}
