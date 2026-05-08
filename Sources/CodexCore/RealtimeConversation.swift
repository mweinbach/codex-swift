import Foundation

public enum RealtimeOutputModality: String, Codable, Equatable, Sendable {
    case text
    case audio
}

public enum ConversationStartTransport: Equatable, Sendable {
    case websocket
    case webrtc(sdp: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
    }

    private enum TransportType: String, Codable {
        case websocket
        case webrtc
    }
}

extension ConversationStartTransport: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(TransportType.self, forKey: .type) {
        case .websocket:
            self = .websocket
        case .webrtc:
            self = .webrtc(sdp: try container.decode(String.self, forKey: .sdp))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .websocket:
            try container.encode(TransportType.websocket, forKey: .type)
        case let .webrtc(sdp):
            try container.encode(TransportType.webrtc, forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        }
    }
}

public enum ConversationStartPrompt: Equatable, Sendable {
    case omitted
    case null
    case value(String)
}

public enum RealtimeVoice: String, Codable, CaseIterable, Comparable, Equatable, Sendable {
    case alloy
    case arbor
    case ash
    case ballad
    case breeze
    case cedar
    case coral
    case cove
    case echo
    case ember
    case juniper
    case maple
    case marin
    case sage
    case shimmer
    case sol
    case spruce
    case vale
    case verse

    public var wireName: String { rawValue }

    public static func < (lhs: RealtimeVoice, rhs: RealtimeVoice) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct RealtimeVoicesList: Codable, Equatable, Sendable {
    public let v1: [RealtimeVoice]
    public let v2: [RealtimeVoice]
    public let defaultV1: RealtimeVoice
    public let defaultV2: RealtimeVoice

    public init(
        v1: [RealtimeVoice],
        v2: [RealtimeVoice],
        defaultV1: RealtimeVoice,
        defaultV2: RealtimeVoice
    ) {
        self.v1 = v1
        self.v2 = v2
        self.defaultV1 = defaultV1
        self.defaultV2 = defaultV2
    }

    public static func builtin() -> RealtimeVoicesList {
        RealtimeVoicesList(
            v1: [.juniper, .maple, .spruce, .ember, .vale, .breeze, .arbor, .sol, .cove],
            v2: [.alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse, .marin, .cedar],
            defaultV1: .cove,
            defaultV2: .marin
        )
    }

    private enum CodingKeys: String, CodingKey {
        case v1
        case v2
        case defaultV1
        case defaultV2
    }
}

public struct ConversationStartParams: Equatable, Sendable {
    public let outputModality: RealtimeOutputModality
    public let prompt: ConversationStartPrompt
    public let realtimeSessionID: String?
    public let transport: ConversationStartTransport?
    public let voice: RealtimeVoice?

    public init(
        outputModality: RealtimeOutputModality,
        prompt: ConversationStartPrompt = .omitted,
        realtimeSessionID: String? = nil,
        transport: ConversationStartTransport? = nil,
        voice: RealtimeVoice? = nil
    ) {
        self.outputModality = outputModality
        self.prompt = prompt
        self.realtimeSessionID = realtimeSessionID
        self.transport = transport
        self.voice = voice
    }

    private enum CodingKeys: String, CodingKey {
        case outputModality = "output_modality"
        case prompt
        case realtimeSessionID = "realtime_session_id"
        case transport
        case voice
    }
}

extension ConversationStartParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.outputModality = try container.decode(RealtimeOutputModality.self, forKey: .outputModality)
        if container.contains(.prompt) {
            if try container.decodeNil(forKey: .prompt) {
                self.prompt = .null
            } else {
                self.prompt = .value(try container.decode(String.self, forKey: .prompt))
            }
        } else {
            self.prompt = .omitted
        }
        self.realtimeSessionID = try container.decodeIfPresent(String.self, forKey: .realtimeSessionID)
        self.transport = try container.decodeIfPresent(ConversationStartTransport.self, forKey: .transport)
        self.voice = try container.decodeIfPresent(RealtimeVoice.self, forKey: .voice)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputModality, forKey: .outputModality)
        switch prompt {
        case .omitted:
            break
        case .null:
            try container.encodeNil(forKey: .prompt)
        case let .value(prompt):
            try container.encode(prompt, forKey: .prompt)
        }
        try container.encodeIfPresent(realtimeSessionID, forKey: .realtimeSessionID)
        try container.encodeIfPresent(transport, forKey: .transport)
        try container.encodeIfPresent(voice, forKey: .voice)
    }
}

public struct RealtimeAudioFrame: Codable, Equatable, Sendable {
    public let data: String
    public let sampleRate: UInt32
    public let numChannels: UInt16
    public let samplesPerChannel: UInt32?
    public let itemID: String?

    public init(
        data: String,
        sampleRate: UInt32,
        numChannels: UInt16,
        samplesPerChannel: UInt32? = nil,
        itemID: String? = nil
    ) {
        self.data = data
        self.sampleRate = sampleRate
        self.numChannels = numChannels
        self.samplesPerChannel = samplesPerChannel
        self.itemID = itemID
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case sampleRate = "sample_rate"
        case numChannels = "num_channels"
        case samplesPerChannel = "samples_per_channel"
        case itemID = "item_id"
    }
}

public struct RealtimeTranscriptDelta: Codable, Equatable, Sendable {
    public let delta: String

    public init(delta: String) {
        self.delta = delta
    }
}

public struct RealtimeTranscriptDone: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct RealtimeTranscriptEntry: Codable, Equatable, Sendable {
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct RealtimeHandoffRequested: Codable, Equatable, Sendable {
    public let handoffID: String
    public let itemID: String
    public let inputTranscript: String
    public let activeTranscript: [RealtimeTranscriptEntry]

    public init(
        handoffID: String,
        itemID: String,
        inputTranscript: String,
        activeTranscript: [RealtimeTranscriptEntry]
    ) {
        self.handoffID = handoffID
        self.itemID = itemID
        self.inputTranscript = inputTranscript
        self.activeTranscript = activeTranscript
    }

    private enum CodingKeys: String, CodingKey {
        case handoffID = "handoff_id"
        case itemID = "item_id"
        case inputTranscript = "input_transcript"
        case activeTranscript = "active_transcript"
    }
}

public struct RealtimeNoopRequested: Codable, Equatable, Sendable {
    public let callID: String
    public let itemID: String

    public init(callID: String, itemID: String) {
        self.callID = callID
        self.itemID = itemID
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case itemID = "item_id"
    }
}

public struct RealtimeInputAudioSpeechStarted: Codable, Equatable, Sendable {
    public let itemID: String?

    public init(itemID: String?) {
        self.itemID = itemID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemID, forKey: .itemID)
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
    }
}

public struct RealtimeResponseCancelled: Codable, Equatable, Sendable {
    public let responseID: String?

    public init(responseID: String?) {
        self.responseID = responseID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responseID, forKey: .responseID)
    }

    private enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
    }
}

public struct RealtimeResponseCreated: Codable, Equatable, Sendable {
    public let responseID: String?

    public init(responseID: String?) {
        self.responseID = responseID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responseID, forKey: .responseID)
    }

    private enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
    }
}

public struct RealtimeResponseDone: Codable, Equatable, Sendable {
    public let responseID: String?

    public init(responseID: String?) {
        self.responseID = responseID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responseID, forKey: .responseID)
    }

    private enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
    }
}

public enum RealtimeEvent: Equatable, Sendable {
    case sessionUpdated(realtimeSessionID: String, instructions: String?)
    case inputAudioSpeechStarted(RealtimeInputAudioSpeechStarted)
    case inputTranscriptDelta(RealtimeTranscriptDelta)
    case inputTranscriptDone(RealtimeTranscriptDone)
    case outputTranscriptDelta(RealtimeTranscriptDelta)
    case outputTranscriptDone(RealtimeTranscriptDone)
    case audioOut(RealtimeAudioFrame)
    case responseCreated(RealtimeResponseCreated)
    case responseCancelled(RealtimeResponseCancelled)
    case responseDone(RealtimeResponseDone)
    case conversationItemAdded(JSONValue)
    case conversationItemDone(itemID: String)
    case handoffRequested(RealtimeHandoffRequested)
    case noopRequested(RealtimeNoopRequested)
    case error(String)
}

extension RealtimeEvent: Codable {
    private enum Variant: String, CodingKey {
        case sessionUpdated = "SessionUpdated"
        case inputAudioSpeechStarted = "InputAudioSpeechStarted"
        case inputTranscriptDelta = "InputTranscriptDelta"
        case inputTranscriptDone = "InputTranscriptDone"
        case outputTranscriptDelta = "OutputTranscriptDelta"
        case outputTranscriptDone = "OutputTranscriptDone"
        case audioOut = "AudioOut"
        case responseCreated = "ResponseCreated"
        case responseCancelled = "ResponseCancelled"
        case responseDone = "ResponseDone"
        case conversationItemAdded = "ConversationItemAdded"
        case conversationItemDone = "ConversationItemDone"
        case handoffRequested = "HandoffRequested"
        case noopRequested = "NoopRequested"
        case error = "Error"
    }

    private enum SessionUpdatedCodingKeys: String, CodingKey {
        case realtimeSessionID = "realtime_session_id"
        case instructions
    }

    private enum ConversationItemDoneCodingKeys: String, CodingKey {
        case itemID = "item_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Variant.self)
        guard let variant = container.allKeys.first, container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected one realtime event variant")
            )
        }

        switch variant {
        case .sessionUpdated:
            let payload = try container.nestedContainer(keyedBy: SessionUpdatedCodingKeys.self, forKey: .sessionUpdated)
            self = .sessionUpdated(
                realtimeSessionID: try payload.decode(String.self, forKey: .realtimeSessionID),
                instructions: try payload.decodeIfPresent(String.self, forKey: .instructions)
            )
        case .inputAudioSpeechStarted:
            self = .inputAudioSpeechStarted(
                try container.decode(RealtimeInputAudioSpeechStarted.self, forKey: .inputAudioSpeechStarted)
            )
        case .inputTranscriptDelta:
            self = .inputTranscriptDelta(try container.decode(RealtimeTranscriptDelta.self, forKey: .inputTranscriptDelta))
        case .inputTranscriptDone:
            self = .inputTranscriptDone(try container.decode(RealtimeTranscriptDone.self, forKey: .inputTranscriptDone))
        case .outputTranscriptDelta:
            self = .outputTranscriptDelta(try container.decode(RealtimeTranscriptDelta.self, forKey: .outputTranscriptDelta))
        case .outputTranscriptDone:
            self = .outputTranscriptDone(try container.decode(RealtimeTranscriptDone.self, forKey: .outputTranscriptDone))
        case .audioOut:
            self = .audioOut(try container.decode(RealtimeAudioFrame.self, forKey: .audioOut))
        case .responseCreated:
            self = .responseCreated(try container.decode(RealtimeResponseCreated.self, forKey: .responseCreated))
        case .responseCancelled:
            self = .responseCancelled(try container.decode(RealtimeResponseCancelled.self, forKey: .responseCancelled))
        case .responseDone:
            self = .responseDone(try container.decode(RealtimeResponseDone.self, forKey: .responseDone))
        case .conversationItemAdded:
            self = .conversationItemAdded(try container.decode(JSONValue.self, forKey: .conversationItemAdded))
        case .conversationItemDone:
            let payload = try container.nestedContainer(
                keyedBy: ConversationItemDoneCodingKeys.self,
                forKey: .conversationItemDone
            )
            self = .conversationItemDone(itemID: try payload.decode(String.self, forKey: .itemID))
        case .handoffRequested:
            self = .handoffRequested(try container.decode(RealtimeHandoffRequested.self, forKey: .handoffRequested))
        case .noopRequested:
            self = .noopRequested(try container.decode(RealtimeNoopRequested.self, forKey: .noopRequested))
        case .error:
            self = .error(try container.decode(String.self, forKey: .error))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Variant.self)
        switch self {
        case let .sessionUpdated(realtimeSessionID, instructions):
            var payload = container.nestedContainer(keyedBy: SessionUpdatedCodingKeys.self, forKey: .sessionUpdated)
            try payload.encode(realtimeSessionID, forKey: .realtimeSessionID)
            try payload.encode(instructions, forKey: .instructions)
        case let .inputAudioSpeechStarted(value):
            try container.encode(value, forKey: .inputAudioSpeechStarted)
        case let .inputTranscriptDelta(value):
            try container.encode(value, forKey: .inputTranscriptDelta)
        case let .inputTranscriptDone(value):
            try container.encode(value, forKey: .inputTranscriptDone)
        case let .outputTranscriptDelta(value):
            try container.encode(value, forKey: .outputTranscriptDelta)
        case let .outputTranscriptDone(value):
            try container.encode(value, forKey: .outputTranscriptDone)
        case let .audioOut(value):
            try container.encode(value, forKey: .audioOut)
        case let .responseCreated(value):
            try container.encode(value, forKey: .responseCreated)
        case let .responseCancelled(value):
            try container.encode(value, forKey: .responseCancelled)
        case let .responseDone(value):
            try container.encode(value, forKey: .responseDone)
        case let .conversationItemAdded(value):
            try container.encode(value, forKey: .conversationItemAdded)
        case let .conversationItemDone(itemID):
            var payload = container.nestedContainer(keyedBy: ConversationItemDoneCodingKeys.self, forKey: .conversationItemDone)
            try payload.encode(itemID, forKey: .itemID)
        case let .handoffRequested(value):
            try container.encode(value, forKey: .handoffRequested)
        case let .noopRequested(value):
            try container.encode(value, forKey: .noopRequested)
        case let .error(value):
            try container.encode(value, forKey: .error)
        }
    }
}

public struct ConversationAudioParams: Codable, Equatable, Sendable {
    public let frame: RealtimeAudioFrame

    public init(frame: RealtimeAudioFrame) {
        self.frame = frame
    }
}

public struct ConversationTextParams: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum RealtimeConversationVersion: String, Codable, Equatable, Sendable {
    case v1
    case v2
}

public struct RealtimeConversationStartedEvent: Codable, Equatable, Sendable {
    public let realtimeSessionID: String?
    public let version: RealtimeConversationVersion

    public init(realtimeSessionID: String?, version: RealtimeConversationVersion = .v2) {
        self.realtimeSessionID = realtimeSessionID
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case realtimeSessionID = "realtime_session_id"
        case version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(realtimeSessionID, forKey: .realtimeSessionID)
        try container.encode(version, forKey: .version)
    }
}

public struct RealtimeConversationRealtimeEvent: Codable, Equatable, Sendable {
    public let payload: RealtimeEvent

    public init(payload: RealtimeEvent) {
        self.payload = payload
    }
}

public struct RealtimeConversationClosedEvent: Codable, Equatable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reason, forKey: .reason)
    }

    private enum CodingKeys: String, CodingKey {
        case reason
    }
}

public struct RealtimeConversationSdpEvent: Codable, Equatable, Sendable {
    public let sdp: String

    public init(sdp: String) {
        self.sdp = sdp
    }
}

public struct RealtimeConversationListVoicesResponseEvent: Codable, Equatable, Sendable {
    public let voices: RealtimeVoicesList

    public init(voices: RealtimeVoicesList) {
        self.voices = voices
    }
}
