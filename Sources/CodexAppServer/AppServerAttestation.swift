import CodexCore
import Foundation

typealias AppServerConnectionID = Int64

struct AppServerConnectionCapabilities: Equatable, Sendable {
    let requestAttestation: Bool
    let optOutNotificationMethods: Set<String>

    init(requestAttestation: Bool, optOutNotificationMethods: Set<String> = []) {
        self.requestAttestation = requestAttestation
        self.optOutNotificationMethods = optOutNotificationMethods
    }
}

enum AppServerElicitationCounterResult: Equatable, Sendable {
    case success(Int)
    case threadNotFound
    case alreadyZero
    case overflow
}

actor AppServerThreadStateManager {
    private var liveConnections: [AppServerConnectionID: AppServerConnectionCapabilities] = [:]
    private var threadConnectionIDs: [String: Set<AppServerConnectionID>] = [:]
    private var threadIDsByConnection: [AppServerConnectionID: Set<String>] = [:]
    private var loadedThreadIDs: Set<String> = []
    private var outOfBandElicitationCounts: [String: Int] = [:]

    func connectionInitialized(
        _ connectionID: AppServerConnectionID,
        capabilities: AppServerConnectionCapabilities
    ) {
        liveConnections[connectionID] = capabilities
    }

    func firstAttestationCapableConnection(forThreadID threadID: String) -> AppServerConnectionID? {
        threadConnectionIDs[threadID]?
            .filter { connectionID in
                liveConnections[connectionID]?.requestAttestation == true
            }
            .min()
    }

    func subscribedConnectionIDs(forThreadID threadID: String) -> [AppServerConnectionID] {
        Array(threadConnectionIDs[threadID] ?? []).sorted()
    }

    func isThreadLoaded(_ threadID: String) -> Bool {
        loadedThreadIDs.contains(threadID)
    }

    func listLoadedThreadIDs() -> [String] {
        loadedThreadIDs.sorted()
    }

    func incrementOutOfBandElicitationCount(threadID: String) -> AppServerElicitationCounterResult {
        guard loadedThreadIDs.contains(threadID) else {
            return .threadNotFound
        }
        let current = outOfBandElicitationCounts[threadID] ?? 0
        guard current < Int.max else {
            return .overflow
        }
        let count = current + 1
        outOfBandElicitationCounts[threadID] = count
        return .success(count)
    }

    func decrementOutOfBandElicitationCount(threadID: String) -> AppServerElicitationCounterResult {
        guard loadedThreadIDs.contains(threadID) else {
            return .threadNotFound
        }
        let current = outOfBandElicitationCounts[threadID] ?? 0
        guard current > 0 else {
            return .alreadyZero
        }
        let count = current - 1
        if count == 0 {
            outOfBandElicitationCounts.removeValue(forKey: threadID)
        } else {
            outOfBandElicitationCounts[threadID] = count
        }
        return .success(count)
    }

    @discardableResult
    func tryAddConnectionToThread(
        threadID: String,
        connectionID: AppServerConnectionID
    ) -> Bool {
        guard liveConnections[connectionID] != nil else {
            return false
        }
        loadedThreadIDs.insert(threadID)
        threadConnectionIDs[threadID, default: []].insert(connectionID)
        threadIDsByConnection[connectionID, default: []].insert(threadID)
        return true
    }

    @discardableResult
    func unsubscribeConnectionFromThread(
        threadID: String,
        connectionID: AppServerConnectionID
    ) -> Bool {
        guard threadConnectionIDs[threadID]?.contains(connectionID) == true else {
            return false
        }
        threadConnectionIDs[threadID]?.remove(connectionID)
        if threadConnectionIDs[threadID]?.isEmpty == true {
            threadConnectionIDs.removeValue(forKey: threadID)
        }
        threadIDsByConnection[connectionID]?.remove(threadID)
        if threadIDsByConnection[connectionID]?.isEmpty == true {
            threadIDsByConnection.removeValue(forKey: connectionID)
        }
        return true
    }

    @discardableResult
    func removeConnection(_ connectionID: AppServerConnectionID) -> [String] {
        liveConnections.removeValue(forKey: connectionID)
        let threadIDs = threadIDsByConnection.removeValue(forKey: connectionID) ?? []
        for threadID in threadIDs {
            threadConnectionIDs[threadID]?.remove(connectionID)
            if threadConnectionIDs[threadID]?.isEmpty == true {
                threadConnectionIDs.removeValue(forKey: threadID)
            }
        }
        return Array(threadIDs).sorted()
    }
}

enum AppServerAttestationRequestResult: Equatable, Sendable {
    case success(Attestation.GenerateResponse)
    case timeout
    case requestFailed
    case requestCanceled
    case malformedResponse
}

enum AppServerExternalAuthRefreshRequestResult: Equatable, Sendable {
    case success(AppServerProtocol.ChatGPTAuthTokensRefreshResponse)
    case timeout
    case requestFailed(code: Int64?, message: String?)
    case requestCanceled
    case malformedResponse
}

actor AppServerOutgoingRequestBroker {
    private let notificationSink: AppServerNotificationSink?
    private var nextRequestID: Int64 = 1
    private var pendingAttestationRequests: [String: CheckedContinuation<AppServerAttestationRequestResult, Never>] = [:]
    private var pendingExternalAuthRefreshRequests: [String: CheckedContinuation<AppServerExternalAuthRefreshRequestResult, Never>] = [:]

    init(notificationSink: AppServerNotificationSink?) {
        self.notificationSink = notificationSink
    }

    func requestAttestationGenerate(
        to _: AppServerConnectionID,
        timeoutNanoseconds: UInt64
    ) async -> AppServerAttestationRequestResult {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.attestationGenerate(
            requestID: requestID,
            params: Attestation.GenerateParams()
        )
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingAttestationRequests[key] = continuation
            Task {
                await notificationSink(data)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self.resolveAttestationRequest(key: key, result: .timeout)
            }
        }
    }

    func requestChatGPTAuthTokensRefresh(
        previousAccountID: String?,
        timeoutNanoseconds: UInt64
    ) async -> AppServerExternalAuthRefreshRequestResult {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.chatGPTAuthTokensRefresh(
            requestID: requestID,
            params: AppServerProtocol.ChatGPTAuthTokensRefreshParams(
                reason: .unauthorized,
                previousAccountID: previousAccountID
            )
        )
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingExternalAuthRefreshRequests[key] = continuation
            Task {
                await notificationSink(data)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self.resolveExternalAuthRefreshRequest(key: key, result: .timeout)
            }
        }
    }

    func receiveResponse(id: RequestID, resultData: Data) {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingExternalAuthRefreshRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(AppServerProtocol.ChatGPTAuthTokensRefreshResponse.self, from: resultData)
            resolveExternalAuthRefreshRequest(
                key: key,
                result: decoded.map(AppServerExternalAuthRefreshRequestResult.success) ?? .malformedResponse
            )
            return
        }

        let decoded = try? JSONDecoder().decode(Attestation.GenerateResponse.self, from: resultData)
        resolveAttestationRequest(
            key: key,
            result: decoded.map(AppServerAttestationRequestResult.success) ?? .malformedResponse
        )
    }

    func receiveMalformedResponse(id: RequestID) {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingExternalAuthRefreshRequests[key] != nil {
            resolveExternalAuthRefreshRequest(key: key, result: .malformedResponse)
        } else {
            resolveAttestationRequest(key: key, result: .malformedResponse)
        }
    }

    func receiveError(id: RequestID, code: Int64?, message: String?) {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingExternalAuthRefreshRequests[key] != nil {
            resolveExternalAuthRefreshRequest(key: key, result: .requestFailed(code: code, message: message))
        } else {
            resolveAttestationRequest(key: key, result: .requestFailed)
        }
    }

    func cancelRequest(id: RequestID) {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingExternalAuthRefreshRequests[key] != nil {
            resolveExternalAuthRefreshRequest(key: key, result: .requestCanceled)
        } else {
            resolveAttestationRequest(key: key, result: .requestCanceled)
        }
    }

    private func resolveAttestationRequest(key: String, result: AppServerAttestationRequestResult) {
        guard let continuation = pendingAttestationRequests.removeValue(forKey: key) else {
            return
        }
        continuation.resume(returning: result)
    }

    private func resolveExternalAuthRefreshRequest(key: String, result: AppServerExternalAuthRefreshRequestResult) {
        guard let continuation = pendingExternalAuthRefreshRequests.removeValue(forKey: key) else {
            return
        }
        continuation.resume(returning: result)
    }

}

final class AppServerAttestationProvider: AttestationProvider {
    static let defaultTimeoutNanoseconds: UInt64 = 100_000_000

    private let outgoing: AppServerOutgoingRequestBroker
    private let threadStateManager: AppServerThreadStateManager
    private let timeoutNanoseconds: UInt64

    init(
        outgoing: AppServerOutgoingRequestBroker,
        threadStateManager: AppServerThreadStateManager,
        timeoutNanoseconds: UInt64 = AppServerAttestationProvider.defaultTimeoutNanoseconds
    ) {
        self.outgoing = outgoing
        self.threadStateManager = threadStateManager
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func header(for context: Attestation.Context) async -> String? {
        guard let connectionID = await threadStateManager.firstAttestationCapableConnection(
            forThreadID: context.threadID
        ) else {
            return nil
        }

        let result = await outgoing.requestAttestationGenerate(
            to: connectionID,
            timeoutNanoseconds: timeoutNanoseconds
        )
        switch result {
        case let .success(response):
            return Attestation.appServerHeaderValue(status: .ok, token: response.token)
        case .timeout:
            return Attestation.appServerHeaderValue(status: .timeout)
        case .requestFailed:
            return Attestation.appServerHeaderValue(status: .requestFailed)
        case .requestCanceled:
            return Attestation.appServerHeaderValue(status: .requestCanceled)
        case .malformedResponse:
            return Attestation.appServerHeaderValue(status: .malformedResponse)
        }
    }
}

enum AppServerRequestIDCodec {
    static func requestID(from value: Any) -> RequestID? {
        if let string = value as? String {
            return .string(string)
        }
        if let number = value as? NSNumber, !(value is Bool) {
            return .integer(number.int64Value)
        }
        if let integer = value as? Int64 {
            return .integer(integer)
        }
        if let integer = value as? Int {
            return .integer(Int64(integer))
        }
        return nil
    }

    static func key(for id: RequestID) -> String {
        switch id {
        case let .string(value):
            return "s:\(value)"
        case let .integer(value):
            return "i:\(value)"
        }
    }
}
