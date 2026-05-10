import Foundation

public enum ExecServerJSONRPCCodec {
    public static func stdioEvent(fromLine line: String, connectionLabel: String) -> ExecServerConnectionEvent? {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return decodeMessage(
            Data(line.utf8),
            malformedPrefix: "failed to parse JSON-RPC message from \(connectionLabel)"
        )
    }

    public static func webSocketTextEvent(_ text: String, connectionLabel: String) -> ExecServerConnectionEvent {
        decodeMessage(
            Data(text.utf8),
            malformedPrefix: "failed to parse websocket JSON-RPC message from \(connectionLabel)"
        )
    }

    public static func webSocketBinaryEvent(_ data: Data, connectionLabel: String) -> ExecServerConnectionEvent {
        decodeMessage(
            data,
            malformedPrefix: "failed to parse websocket JSON-RPC message from \(connectionLabel)"
        )
    }

    public static func disconnected(reason: String? = nil) -> ExecServerConnectionEvent {
        .disconnected(reason: reason)
    }

    public static func encodeLine(_ message: ExecServerJSONRPCMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        return data
    }

    public static func encodeWebSocketText(_ message: ExecServerJSONRPCMessage) throws -> String {
        let data = try JSONEncoder().encode(message)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeMessage(_ data: Data, malformedPrefix: String) -> ExecServerConnectionEvent {
        do {
            return .message(try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: data))
        } catch {
            return .malformedMessage(reason: "\(malformedPrefix): \(error)")
        }
    }
}
