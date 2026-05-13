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
}
