import Foundation

public enum TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case http(statusCode: Int, url: String? = nil, headers: [String: String]?, body: String?)
    case retryLimit
    case timeout
    case network(String)
    case build(String)

    public var description: String {
        switch self {
        case let .http(statusCode, _, _, body):
            return "http \(HTTPStatus.description(for: statusCode)): \(Self.debugOptional(body))"
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
        guard case let .http(statusCode, _, _, _) = self else {
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

public enum SsePollResult: Equatable, Sendable {
    case event
    case streamClosed
    case streamError(TransportError)
    case idleTimeout
}

public protocol SseTelemetry: AnyObject {
    func onSSEPoll(result: SsePollResult, duration: Duration)
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
        case let .http(statusCode, _, _, _):
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
