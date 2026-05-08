import Foundation

public enum TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case http(statusCode: Int, headers: [String: String]?, body: String?)
    case retryLimit
    case timeout
    case network(String)
    case build(String)

    public var description: String {
        switch self {
        case let .http(statusCode, _, body):
            return "http \(Self.statusDescription(statusCode)): \(Self.debugOptional(body))"
        case .retryLimit:
            return "retry limit reached"
        case .timeout:
            return "timeout"
        case let .network(message):
            return "network error: \(message)"
        case let .build(message):
            return "request build error: \(message)"
        }
    }

    public var httpStatusCode: Int? {
        guard case let .http(statusCode, _, _) = self else {
            return nil
        }
        return statusCode
    }

    private static func debugOptional(_ value: String?) -> String {
        guard let value else {
            return "None"
        }
        return "Some(\(debugString(value)))"
    }

    private static func debugString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return #""""#
        }
        return encoded
    }

    private static func statusDescription(_ statusCode: Int) -> String {
        "\(statusCode) \(canonicalReason(for: statusCode) ?? "<unknown status code>")"
    }

    private static func canonicalReason(for statusCode: Int) -> String? {
        switch statusCode {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 102: return "Processing"
        case 103: return "Early Hints"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 207: return "Multi-Status"
        case 208: return "Already Reported"
        case 226: return "IM Used"
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 418: return "I'm a teapot"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Entity"
        case 423: return "Locked"
        case 424: return "Failed Dependency"
        case 425: return "Too Early"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 506: return "Variant Also Negotiates"
        case 507: return "Insufficient Storage"
        case 508: return "Loop Detected"
        case 510: return "Not Extended"
        case 511: return "Network Authentication Required"
        default: return nil
        }
    }
}

public enum StreamError: Error, Equatable, CustomStringConvertible, Sendable {
    case stream(String)
    case timeout

    public var description: String {
        switch self {
        case let .stream(message):
            return "stream failed: \(message)"
        case .timeout:
            return "timeout"
        }
    }
}

public protocol ResponseWithStatus {
    var statusCode: Int { get }
}

public struct APIResponse: Equatable, Sendable, ResponseWithStatus {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol RequestTelemetry: AnyObject {
    func onRequest(
        attempt: UInt64,
        statusCode: Int?,
        error: TransportError?,
        duration: Duration
    )
}

public enum TransportRetry {
    public static func runWithRetry<T>(
        policy: ProviderRetryPolicy,
        makeRequest: () -> APIRequest,
        sleep: (UInt64) async -> Void = { milliseconds in
            let nanoseconds = milliseconds.multipliedReportingOverflow(by: 1_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds.overflow ? UInt64.max : nanoseconds.partialValue)
        },
        operation: (APIRequest, UInt64) async -> Result<T, TransportError>
    ) async -> Result<T, TransportError> {
        for attempt in 0...policy.maxAttempts {
            let request = makeRequest()
            let result = await operation(request, attempt)
            switch result {
            case .success:
                return result
            case let .failure(error) where policy.retryOn.shouldRetry(error, attempt: attempt, maxAttempts: policy.maxAttempts):
                await sleep(policy.backoffMilliseconds(attempt: attempt + 1))
            case .failure:
                return result
            }
        }

        return .failure(.retryLimit)
    }

    public static func runWithRequestTelemetry<T: ResponseWithStatus>(
        policy: ProviderRetryPolicy,
        telemetry: RequestTelemetry?,
        makeRequest: @escaping () -> APIRequest,
        sleep: (UInt64) async -> Void = { milliseconds in
            let nanoseconds = milliseconds.multipliedReportingOverflow(by: 1_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds.overflow ? UInt64.max : nanoseconds.partialValue)
        },
        send: @escaping (APIRequest) async -> Result<T, TransportError>
    ) async -> Result<T, TransportError> {
        await runWithRetry(
            policy: policy,
            makeRequest: makeRequest,
            sleep: sleep
        ) { request, attempt in
            let start = ContinuousClock.now
            let result = await send(request)
            let statusCode: Int?
            let error: TransportError?
            switch result {
            case let .success(response):
                statusCode = response.statusCode
                error = nil
            case let .failure(transportError):
                statusCode = transportError.httpStatusCode
                error = transportError
            }
            telemetry?.onRequest(
                attempt: attempt,
                statusCode: statusCode,
                error: error,
                duration: start.duration(to: .now)
            )
            return result
        }
    }
}

public extension ProviderRetryOn {
    func shouldRetry(_ error: TransportError, attempt: UInt64, maxAttempts: UInt64) -> Bool {
        guard attempt < maxAttempts else {
            return false
        }

        switch error {
        case let .http(statusCode, _, _):
            return (retry429 && statusCode == 429)
                || (retry5xx && (500..<600).contains(statusCode))
        case .timeout, .network:
            return retryTransport
        case .build, .retryLimit:
            return false
        }
    }
}

public extension ProviderRetryPolicy {
    func backoffMilliseconds(attempt: UInt64, jitter: () -> Double = {
        Double.random(in: 0.9..<1.1)
    }) -> UInt64 {
        if attempt == 0 {
            return baseDelayMilliseconds
        }

        let exponent = attempt.saturatingSubtracting(1)
        let multiplier = UInt64.saturatingPowerOfTwo(exponent)
        let raw = baseDelayMilliseconds.multipliedReportingOverflow(by: multiplier)
        let milliseconds = raw.overflow ? UInt64.max : raw.partialValue
        let value = Double(milliseconds) * jitter()
        guard value.isFinite, value < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(max(0, value))
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ value: UInt64) -> UInt64 {
        self > value ? self - value : 0
    }

    static func saturatingPowerOfTwo(_ exponent: UInt64) -> UInt64 {
        guard exponent < UInt64.bitWidth else {
            return UInt64.max
        }
        return 1 << exponent
    }
}
