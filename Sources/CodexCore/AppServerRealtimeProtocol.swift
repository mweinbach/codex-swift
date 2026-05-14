import Foundation

public struct ThreadRealtimeAudioChunk: Equatable, Sendable {
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

    public init(_ frame: RealtimeAudioFrame) {
        self.init(
            data: frame.data,
            sampleRate: frame.sampleRate,
            numChannels: frame.numChannels,
            samplesPerChannel: frame.samplesPerChannel,
            itemID: frame.itemID
        )
    }

    public var coreFrame: RealtimeAudioFrame {
        RealtimeAudioFrame(
            data: data,
            sampleRate: sampleRate,
            numChannels: numChannels,
            samplesPerChannel: samplesPerChannel,
            itemID: itemID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case sampleRate
        case numChannels
        case samplesPerChannel
        case itemID = "itemId"
    }
}

extension ThreadRealtimeAudioChunk: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(String.self, forKey: .data)
        self.sampleRate = try container.decode(UInt32.self, forKey: .sampleRate)
        self.numChannels = try container.decode(UInt16.self, forKey: .numChannels)
        self.samplesPerChannel = try container.decodeIfPresent(UInt32.self, forKey: .samplesPerChannel)
        self.itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(numChannels, forKey: .numChannels)
        try container.encodeNilOrValue(samplesPerChannel, forKey: .samplesPerChannel)
        try container.encodeNilOrValue(itemID, forKey: .itemID)
    }
}

public enum ThreadRealtimeStartTransport: Equatable, Sendable {
    case websocket
    case webrtc(sdp: String)

    public init(_ transport: ConversationStartTransport) {
        switch transport {
        case .websocket:
            self = .websocket
        case let .webrtc(sdp):
            self = .webrtc(sdp: sdp)
        }
    }

    public var coreTransport: ConversationStartTransport {
        switch self {
        case .websocket:
            return .websocket
        case let .webrtc(sdp):
            return .webrtc(sdp: sdp)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
    }

    private enum TransportType: String, Codable {
        case websocket
        case webrtc
    }
}

extension ThreadRealtimeStartTransport: Codable {
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

public struct ThreadRealtimeStartParams: Equatable, Sendable {
    public let threadID: String
    public let outputModality: RealtimeOutputModality
    public let prompt: ConversationStartPrompt
    public let realtimeSessionID: String?
    public let transport: ThreadRealtimeStartTransport?
    public let voice: RealtimeVoice?

    public init(
        threadID: String,
        outputModality: RealtimeOutputModality,
        prompt: ConversationStartPrompt = .omitted,
        realtimeSessionID: String? = nil,
        transport: ThreadRealtimeStartTransport? = nil,
        voice: RealtimeVoice? = nil
    ) {
        self.threadID = threadID
        self.outputModality = outputModality
        self.prompt = prompt
        self.realtimeSessionID = realtimeSessionID
        self.transport = transport
        self.voice = voice
    }

    public var coreParams: ConversationStartParams {
        ConversationStartParams(
            outputModality: outputModality,
            prompt: prompt,
            realtimeSessionID: realtimeSessionID,
            transport: transport?.coreTransport,
            voice: voice
        )
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case outputModality
        case prompt
        case realtimeSessionID = "realtimeSessionId"
        case transport
        case voice
    }
}

extension ThreadRealtimeStartParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
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
        self.transport = try container.decodeIfPresent(ThreadRealtimeStartTransport.self, forKey: .transport)
        self.voice = try container.decodeIfPresent(RealtimeVoice.self, forKey: .voice)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(outputModality, forKey: .outputModality)
        switch prompt {
        case .omitted:
            break
        case .null:
            try container.encodeNil(forKey: .prompt)
        case let .value(prompt):
            try container.encode(prompt, forKey: .prompt)
        }
        try container.encodeNilOrValue(realtimeSessionID, forKey: .realtimeSessionID)
        try container.encodeNilOrValue(transport, forKey: .transport)
        try container.encodeNilOrValue(voice, forKey: .voice)
    }
}

public struct ThreadRealtimeStartResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRealtimeAppendAudioParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let audio: ThreadRealtimeAudioChunk

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case audio
    }

    public init(threadID: String, audio: ThreadRealtimeAudioChunk) {
        self.threadID = threadID
        self.audio = audio
    }
}

public struct ThreadRealtimeAppendAudioResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRealtimeAppendTextParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case text
    }

    public init(threadID: String, text: String) {
        self.threadID = threadID
        self.text = text
    }
}

public struct ThreadRealtimeAppendTextResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRealtimeStopParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadRealtimeStopResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRealtimeListVoicesParams: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRealtimeListVoicesResponse: Equatable, Codable, Sendable {
    public let voices: RealtimeVoicesList

    public init(voices: RealtimeVoicesList) {
        self.voices = voices
    }
}

public struct ThreadRealtimeStartedNotification: Equatable, Sendable {
    public let threadID: String
    public let realtimeSessionID: String?
    public let version: RealtimeConversationVersion

    public init(threadID: String, realtimeSessionID: String?, version: RealtimeConversationVersion) {
        self.threadID = threadID
        self.realtimeSessionID = realtimeSessionID
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case realtimeSessionID = "realtimeSessionId"
        case version
    }
}

extension ThreadRealtimeStartedNotification: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
        self.realtimeSessionID = try container.decodeIfPresent(String.self, forKey: .realtimeSessionID)
        self.version = try container.decode(RealtimeConversationVersion.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeNilOrValue(realtimeSessionID, forKey: .realtimeSessionID)
        try container.encode(version, forKey: .version)
    }
}

public struct ThreadRealtimeItemAddedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let item: JSONValue

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case item
    }

    public init(threadID: String, item: JSONValue) {
        self.threadID = threadID
        self.item = item
    }
}

public struct ThreadRealtimeTranscriptDeltaNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let role: String
    public let delta: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case role
        case delta
    }

    public init(threadID: String, role: String, delta: String) {
        self.threadID = threadID
        self.role = role
        self.delta = delta
    }
}

public struct ThreadRealtimeTranscriptDoneNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let role: String
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case role
        case text
    }

    public init(threadID: String, role: String, text: String) {
        self.threadID = threadID
        self.role = role
        self.text = text
    }
}

public struct ThreadRealtimeOutputAudioDeltaNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let audio: ThreadRealtimeAudioChunk

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case audio
    }

    public init(threadID: String, audio: ThreadRealtimeAudioChunk) {
        self.threadID = threadID
        self.audio = audio
    }
}

public struct ThreadRealtimeSdpNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let sdp: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case sdp
    }

    public init(threadID: String, sdp: String) {
        self.threadID = threadID
        self.sdp = sdp
    }
}

public struct ThreadRealtimeErrorNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case message
    }

    public init(threadID: String, message: String) {
        self.threadID = threadID
        self.message = message
    }
}

public struct ThreadRealtimeClosedNotification: Equatable, Sendable {
    public let threadID: String
    public let reason: String?

    public init(threadID: String, reason: String? = nil) {
        self.threadID = threadID
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case reason
    }
}

extension ThreadRealtimeClosedNotification: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeNilOrValue(reason, forKey: .reason)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
