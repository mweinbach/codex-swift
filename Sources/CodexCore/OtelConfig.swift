import Foundation

public enum OtelHttpProtocol: String, Codable, Equatable, Sendable {
    case binary
    case json
}

public struct OtelTlsConfig: Equatable, Sendable {
    public var caCertificate: String?
    public var clientCertificate: String?
    public var clientPrivateKey: String?

    public init(
        caCertificate: String? = nil,
        clientCertificate: String? = nil,
        clientPrivateKey: String? = nil
    ) {
        self.caCertificate = caCertificate
        self.clientCertificate = clientCertificate
        self.clientPrivateKey = clientPrivateKey
    }
}

public enum OtelExporterKind: Equatable, Sendable {
    case none
    case statsig
    case otlpHttp(endpoint: String, headers: [String: String], httpProtocol: OtelHttpProtocol, tls: OtelTlsConfig?)
    case otlpGrpc(endpoint: String, headers: [String: String], tls: OtelTlsConfig?)
}

public struct OtelConfig: Equatable, Sendable {
    public static let defaultEnvironment = "dev"

    public var logUserPrompt: Bool
    public var environment: String
    public var exporter: OtelExporterKind
    public var traceExporter: OtelExporterKind
    public var metricsExporter: OtelExporterKind
    public var spanAttributes: [String: String]
    public var tracestate: [String: [String: String]]

    public init(
        logUserPrompt: Bool = false,
        environment: String = Self.defaultEnvironment,
        exporter: OtelExporterKind = .none,
        traceExporter: OtelExporterKind = .none,
        metricsExporter: OtelExporterKind = .statsig,
        spanAttributes: [String: String] = [:],
        tracestate: [String: [String: String]] = [:]
    ) {
        self.logUserPrompt = logUserPrompt
        self.environment = environment
        self.exporter = exporter
        self.traceExporter = traceExporter
        self.metricsExporter = metricsExporter
        self.spanAttributes = spanAttributes
        self.tracestate = tracestate
    }

    public func validateProviderStartup(traceEnabled: Bool) throws {
        if traceEnabled {
            try Self.validateSpanAttributes(spanAttributes)
        }
        try Self.validateTracestateEntries(tracestate)
    }

    static func validateSpanAttributes(_ attributes: [String: String]) throws {
        if attributes.keys.contains("") {
            throw OtelConfigValidationError(message: "configured span attribute key must not be empty")
        }
    }

    static func validateTracestateEntries(_ entries: [String: [String: String]]) throws {
        for member in entries.keys.sorted() {
            let fields = entries[member] ?? [:]
            try validateTracestateMember(memberKey: member, fields: fields)
        }
        if let message = invalidConfiguredTracestateEntriesMessage(entries) {
            throw OtelConfigValidationError(message: message)
        }
    }

    static func validateTracestateMember(
        memberKey: String,
        fields: [String: String]
    ) throws {
        for fieldKey in fields.keys.sorted() {
            if let message = invalidConfiguredTracestateFieldMessage(
                memberKey: memberKey,
                fieldKey: fieldKey,
                value: fields[fieldKey] ?? ""
            ) {
                throw OtelConfigValidationError(message: message)
            }
        }
        if let message = invalidConfiguredTracestateMemberMessage(memberKey: memberKey, fields: fields) {
            throw OtelConfigValidationError(message: message)
        }
    }

    static func invalidConfiguredTracestateFieldMessage(
        memberKey: String,
        fieldKey: String,
        value: String
    ) -> String? {
        if !isConfiguredTracestateFieldKey(fieldKey) {
            return "invalid configured tracestate field key \(memberKey).\(fieldKey)"
        }
        if !isConfiguredTracestateFieldValue(value) {
            return "invalid configured tracestate value for \(memberKey).\(fieldKey)"
        }
        return nil
    }

    static func invalidConfiguredTracestateMemberMessage(
        memberKey: String,
        fields: [String: String]
    ) -> String? {
        guard isTracestateMemberKey(memberKey) else {
            return "invalid configured tracestate: invalid member key \(memberKey)"
        }
        let encoded = fields.keys.sorted().map { "\($0):\(fields[$0] ?? "")" }.joined(separator: ";")
        if !isHeaderSafeTracestateMemberValue(encoded) {
            return "invalid configured tracestate value for \(memberKey)"
        }
        return nil
    }

    static func invalidConfiguredTracestateEntriesMessage(_ entries: [String: [String: String]]) -> String? {
        guard entries.count <= 32 else {
            return "invalid configured tracestate: list contains more than 32 members"
        }
        return nil
    }

    private static func isConfiguredTracestateFieldKey(_ fieldKey: String) -> Bool {
        guard !fieldKey.isEmpty else {
            return false
        }
        return fieldKey.utf8.allSatisfy { byte in
            (33...126).contains(byte) && byte != 58 && byte != 59 && byte != 44 && byte != 61
        }
    }

    private static func isConfiguredTracestateFieldValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            isTracestateMemberValueByte(byte) && byte != 59
        }
    }

    private static func isHeaderSafeTracestateMemberValue(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return true
        }
        return value.utf8.allSatisfy(isTracestateMemberValueByte) && value.utf8.last != 32
    }

    private static func isTracestateMemberValueByte(_ byte: UInt8) -> Bool {
        (32...126).contains(byte) && byte != 44 && byte != 61
    }

    private static func isTracestateMemberKey(_ key: String) -> Bool {
        let parts = key.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return isTracestateKeyPart(String(parts[0]), maxBytes: 256)
        }
        if parts.count == 2 {
            return isTracestateKeyPart(String(parts[0]), maxBytes: 241)
                && isTracestateKeyPart(String(parts[1]), maxBytes: 14)
        }
        return false
    }

    private static func isTracestateKeyPart(_ key: String, maxBytes: Int) -> Bool {
        let bytes = Array(key.utf8)
        guard !bytes.isEmpty, bytes.count <= maxBytes else {
            return false
        }
        return bytes.allSatisfy { byte in
            (97...122).contains(byte)
                || (48...57).contains(byte)
                || byte == 95
                || byte == 45
                || byte == 42
                || byte == 47
        }
    }
}

public struct OtelConfigValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public var description: String {
        message
    }
}
