import Foundation

/// Describes the output produced by extension-owned tools.
///
/// Registry tool executors implement this contract so callers can derive the
/// Rust-compatible model response item, telemetry preview, hook payloads, and
/// code-mode result from one value. Values crossing executor boundaries must be
/// sendable, and implementations should preserve Rust wire shapes for function
/// and custom tool calls.
public protocol ExtensionToolOutput: Sendable {
    func logPreview() -> String
    func successForLogging() -> Bool
    func toResponseItem(callID: String, isCustomToolCall: Bool, customToolName: String?) -> ResponseItem
    func postToolUseID(callID: String) -> String
    func postToolUseInput(for item: ResponseItem) -> JSONValue?
    func postToolUseResponse(callID: String, for item: ResponseItem) -> JSONValue?
    func codeModeResult(isCustomToolCall: Bool, customToolName: String?) -> JSONValue
}

public extension ExtensionToolOutput {
    func postToolUseID(callID: String) -> String {
        callID
    }

    func postToolUseInput(for item: ResponseItem) -> JSONValue? {
        nil
    }

    func postToolUseResponse(callID: String, for item: ResponseItem) -> JSONValue? {
        nil
    }

    func codeModeResult(isCustomToolCall: Bool, customToolName: String? = nil) -> JSONValue {
        .null
    }
}

public struct JSONToolOutput: ExtensionToolOutput, Equatable {
    public let value: JSONValue
    public let success: Bool?

    public init(_ value: JSONValue, success: Bool? = true) {
        self.value = value
        self.success = success
    }

    public func logPreview() -> String {
        Self.telemetryPreview(jsonString(value))
    }

    public func successForLogging() -> Bool {
        success ?? true
    }

    public func toResponseItem(callID: String, isCustomToolCall: Bool, customToolName: String?) -> ResponseItem {
        let output = FunctionCallOutputPayload(content: jsonString(value), success: success)
        if isCustomToolCall {
            return .customToolCallOutput(callID: callID, name: customToolName, output: output)
        }
        return .functionCallOutput(callID: callID, output: output)
    }

    public func postToolUseResponse(callID: String, for item: ResponseItem) -> JSONValue? {
        value
    }

    public func codeModeResult(isCustomToolCall: Bool, customToolName: String? = nil) -> JSONValue {
        value
    }

    public static func telemetryPreview(_ content: String) -> String {
        let byteLimited = StringByteBoundary.takeBytesAtUnicodeScalarBoundary(
            content,
            maxBytes: telemetryPreviewMaxBytes
        )
        let truncatedByBytes = byteLimited.utf8.count < content.utf8.count
        let lines = byteLimited.split(separator: "\n", omittingEmptySubsequences: false)
        let truncatedByLines = lines.count > telemetryPreviewMaxLines
        guard truncatedByBytes || truncatedByLines else {
            return content
        }

        var preview = lines.prefix(telemetryPreviewMaxLines).joined(separator: "\n")
        if !preview.isEmpty, !preview.hasSuffix("\n") {
            preview.append("\n")
        }
        preview.append(telemetryPreviewTruncationNotice)
        return preview
    }
}

private let telemetryPreviewMaxBytes = 2 * 1024
private let telemetryPreviewMaxLines = 64
private let telemetryPreviewTruncationNotice = "[... telemetry preview truncated ...]"

private func jsonString(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8)
    else {
        return "null"
    }
    return string
}
