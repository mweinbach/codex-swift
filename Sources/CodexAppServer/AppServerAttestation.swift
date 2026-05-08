import CodexCore
import Foundation

typealias AppServerConnectionID = Int64

struct AppServerConnectionCapabilities: Equatable, Sendable {
    let requestAttestation: Bool
}

actor AppServerThreadStateManager {
    private var liveConnections: [AppServerConnectionID: AppServerConnectionCapabilities] = [:]
    private var threadConnectionIDs: [String: Set<AppServerConnectionID>] = [:]
    private var threadIDsByConnection: [AppServerConnectionID: Set<String>] = [:]
    private var loadedThreadIDs: Set<String> = []

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

actor AppServerOutgoingRequestBroker {
    private let notificationSink: AppServerNotificationSink?
    private var nextRequestID: Int64 = 1
    private var pendingRequests: [String: CheckedContinuation<AppServerAttestationRequestResult, Never>] = [:]

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
            pendingRequests[key] = continuation
            Task {
                await notificationSink(data)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self.resolveRequest(key: key, result: .timeout)
            }
        }
    }

    func receiveResponse(id: RequestID, resultData: Data) {
        let decoded = try? JSONDecoder().decode(Attestation.GenerateResponse.self, from: resultData)
        resolveRequest(
            key: AppServerRequestIDCodec.key(for: id),
            result: decoded.map(AppServerAttestationRequestResult.success) ?? .malformedResponse
        )
    }

    func receiveMalformedResponse(id: RequestID) {
        resolveRequest(key: AppServerRequestIDCodec.key(for: id), result: .malformedResponse)
    }

    func receiveError(id: RequestID, code _: Int64?, message _: String?) {
        resolveRequest(key: AppServerRequestIDCodec.key(for: id), result: .requestFailed)
    }

    func cancelRequest(id: RequestID) {
        resolveRequest(key: AppServerRequestIDCodec.key(for: id), result: .requestCanceled)
    }

    private func resolveRequest(key: String, result: AppServerAttestationRequestResult) {
        guard let continuation = pendingRequests.removeValue(forKey: key) else {
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
