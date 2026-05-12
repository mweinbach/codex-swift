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

enum AppServerDynamicToolCallRequestResult: Equatable, Sendable {
    case success(requestID: RequestID, response: AppServerProtocol.DynamicToolCallResponse)
    case malformedResponse(requestID: RequestID)
    case requestFailed(requestID: RequestID, code: Int64?, message: String?, data: JSONValue?)
    case requestCanceled
}

enum AppServerOutgoingRequestResult<Response: Equatable & Sendable>: Equatable, Sendable {
    case success(requestID: RequestID, response: Response)
    case malformedResponse(requestID: RequestID)
    case requestFailed(requestID: RequestID, code: Int64?, message: String?, data: JSONValue?)
    case requestCanceled

    var requestID: RequestID? {
        switch self {
        case let .success(requestID, _),
             let .malformedResponse(requestID),
             let .requestFailed(requestID, _, _, _):
            return requestID
        case .requestCanceled:
            return nil
        }
    }
}

actor AppServerThreadStateManager {
    private var liveConnections: [AppServerConnectionID: AppServerConnectionCapabilities] = [:]
    private var threadConnectionIDs: [String: Set<AppServerConnectionID>] = [:]
    private var threadIDsByConnection: [AppServerConnectionID: Set<String>] = [:]
    private var loadedThreadIDs: Set<String> = []
    private var outOfBandElicitationCounts: [String: Int] = [:]
    private var pendingMcpServerRefreshConfigs: [String: McpServerRefreshConfig] = [:]
    private var pendingUserConfigRefreshes: [String: ConfigValue] = [:]

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
    func queueMcpServerRefresh(threadID: String, config: McpServerRefreshConfig) -> Bool {
        guard loadedThreadIDs.contains(threadID) else {
            return false
        }
        pendingMcpServerRefreshConfigs[threadID] = config
        return true
    }

    func pendingMcpServerRefreshConfig(threadID: String) -> McpServerRefreshConfig? {
        pendingMcpServerRefreshConfigs[threadID]
    }

    @discardableResult
    func queueUserConfigRefresh(threadID: String, effectiveConfig: ConfigValue) -> Bool {
        guard loadedThreadIDs.contains(threadID) else {
            return false
        }
        pendingUserConfigRefreshes[threadID] = effectiveConfig
        return true
    }

    func pendingUserConfigRefresh(threadID: String) -> ConfigValue? {
        pendingUserConfigRefreshes[threadID]
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
    private var pendingDynamicToolCallRequests: [String: CheckedContinuation<AppServerDynamicToolCallRequestResult, Never>] = [:]
    private var pendingFileChangeApprovalRequests: [String: CheckedContinuation<AppServerOutgoingRequestResult<AppServerProtocol.FileChangeRequestApprovalResponse>, Never>] = [:]
    private var pendingCommandExecutionApprovalRequests: [String: CheckedContinuation<AppServerOutgoingRequestResult<AppServerProtocol.CommandExecutionRequestApprovalResponse>, Never>] = [:]
    private var pendingToolRequestUserInputRequests: [String: CheckedContinuation<AppServerOutgoingRequestResult<AppServerProtocol.ToolRequestUserInputResponse>, Never>] = [:]
    private var pendingPermissionsApprovalRequests: [String: CheckedContinuation<AppServerOutgoingRequestResult<AppServerProtocol.PermissionsRequestApprovalResponse>, Never>] = [:]
    private var pendingServerRequestThreadIDs: [String: String] = [:]

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

    func requestDynamicToolCall(
        params: AppServerProtocol.DynamicToolCallParams
    ) async -> AppServerDynamicToolCallRequestResult {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.dynamicToolCall(requestID: requestID, params: params)
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse(requestID: requestID)
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingDynamicToolCallRequests[key] = continuation
            Task {
                await notificationSink(data)
            }
        }
    }

    func requestFileChangeApproval(
        params: AppServerProtocol.FileChangeRequestApprovalParams
    ) async -> AppServerOutgoingRequestResult<AppServerProtocol.FileChangeRequestApprovalResponse> {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.fileChangeRequestApproval(requestID: requestID, params: params)
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse(requestID: requestID)
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingFileChangeApprovalRequests[key] = continuation
            pendingServerRequestThreadIDs[key] = params.threadID
            Task {
                await notificationSink(data)
            }
        }
    }

    func requestCommandExecutionApproval(
        params: AppServerProtocol.CommandExecutionRequestApprovalParams
    ) async -> AppServerOutgoingRequestResult<AppServerProtocol.CommandExecutionRequestApprovalResponse> {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.commandExecutionRequestApproval(requestID: requestID, params: params)
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse(requestID: requestID)
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingCommandExecutionApprovalRequests[key] = continuation
            pendingServerRequestThreadIDs[key] = params.threadID
            Task {
                await notificationSink(data)
            }
        }
    }

    func requestToolUserInput(
        params: AppServerProtocol.ToolRequestUserInputParams
    ) async -> AppServerOutgoingRequestResult<AppServerProtocol.ToolRequestUserInputResponse> {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.toolRequestUserInput(requestID: requestID, params: params)
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse(requestID: requestID)
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingToolRequestUserInputRequests[key] = continuation
            pendingServerRequestThreadIDs[key] = params.threadID
            Task {
                await notificationSink(data)
            }
        }
    }

    func requestPermissionsApproval(
        params: AppServerProtocol.PermissionsRequestApprovalParams
    ) async -> AppServerOutgoingRequestResult<AppServerProtocol.PermissionsRequestApprovalResponse> {
        guard let notificationSink else {
            return .requestCanceled
        }

        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let request = AppServerProtocol.ServerRequest.permissionsRequestApproval(requestID: requestID, params: params)
        guard let data = try? JSONEncoder().encode(request) else {
            return .malformedResponse(requestID: requestID)
        }

        let key = AppServerRequestIDCodec.key(for: requestID)
        return await withCheckedContinuation { continuation in
            pendingPermissionsApprovalRequests[key] = continuation
            pendingServerRequestThreadIDs[key] = params.threadID
            Task {
                await notificationSink(data)
            }
        }
    }

    func receiveResponse(id: RequestID, resultData: Data) async {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingDynamicToolCallRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(AppServerProtocol.DynamicToolCallResponse.self, from: resultData)
            resolveDynamicToolCallRequest(
                key: key,
                result: decoded
                    .map { .success(requestID: id, response: $0) }
                    ?? .malformedResponse(requestID: id)
            )
            return
        }

        if pendingFileChangeApprovalRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(
                AppServerProtocol.FileChangeRequestApprovalResponse.self,
                from: resultData
            )
            await resolveFileChangeApprovalRequest(
                key: key,
                result: decoded
                    .map { .success(requestID: id, response: $0) }
                    ?? .malformedResponse(requestID: id)
            )
            return
        }

        if pendingCommandExecutionApprovalRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(
                AppServerProtocol.CommandExecutionRequestApprovalResponse.self,
                from: resultData
            )
            await resolveCommandExecutionApprovalRequest(
                key: key,
                result: decoded
                    .map { .success(requestID: id, response: $0) }
                    ?? .malformedResponse(requestID: id)
            )
            return
        }

        if pendingToolRequestUserInputRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(
                AppServerProtocol.ToolRequestUserInputResponse.self,
                from: resultData
            )
            await resolveToolRequestUserInputRequest(
                key: key,
                result: decoded
                    .map { .success(requestID: id, response: $0) }
                    ?? .malformedResponse(requestID: id)
            )
            return
        }

        if pendingPermissionsApprovalRequests[key] != nil {
            let decoded = try? JSONDecoder().decode(
                AppServerProtocol.PermissionsRequestApprovalResponse.self,
                from: resultData
            )
            await resolvePermissionsApprovalRequest(
                key: key,
                result: decoded
                    .map { .success(requestID: id, response: $0) }
                    ?? .malformedResponse(requestID: id)
            )
            return
        }

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

    func receiveMalformedResponse(id: RequestID) async {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingDynamicToolCallRequests[key] != nil {
            resolveDynamicToolCallRequest(key: key, result: .malformedResponse(requestID: id))
        } else if pendingFileChangeApprovalRequests[key] != nil {
            await resolveFileChangeApprovalRequest(key: key, result: .malformedResponse(requestID: id))
        } else if pendingCommandExecutionApprovalRequests[key] != nil {
            await resolveCommandExecutionApprovalRequest(key: key, result: .malformedResponse(requestID: id))
        } else if pendingToolRequestUserInputRequests[key] != nil {
            await resolveToolRequestUserInputRequest(key: key, result: .malformedResponse(requestID: id))
        } else if pendingPermissionsApprovalRequests[key] != nil {
            await resolvePermissionsApprovalRequest(key: key, result: .malformedResponse(requestID: id))
        } else if pendingExternalAuthRefreshRequests[key] != nil {
            resolveExternalAuthRefreshRequest(key: key, result: .malformedResponse)
        } else {
            resolveAttestationRequest(key: key, result: .malformedResponse)
        }
    }

    func receiveError(id: RequestID, code: Int64?, message: String?, data: JSONValue? = nil) async {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingDynamicToolCallRequests[key] != nil {
            resolveDynamicToolCallRequest(
                key: key,
                result: .requestFailed(requestID: id, code: code, message: message, data: data)
            )
        } else if pendingFileChangeApprovalRequests[key] != nil {
            await resolveFileChangeApprovalRequest(
                key: key,
                result: .requestFailed(requestID: id, code: code, message: message, data: data)
            )
        } else if pendingCommandExecutionApprovalRequests[key] != nil {
            await resolveCommandExecutionApprovalRequest(
                key: key,
                result: .requestFailed(requestID: id, code: code, message: message, data: data)
            )
        } else if pendingToolRequestUserInputRequests[key] != nil {
            await resolveToolRequestUserInputRequest(
                key: key,
                result: .requestFailed(requestID: id, code: code, message: message, data: data)
            )
        } else if pendingPermissionsApprovalRequests[key] != nil {
            await resolvePermissionsApprovalRequest(
                key: key,
                result: .requestFailed(requestID: id, code: code, message: message, data: data)
            )
        } else if pendingExternalAuthRefreshRequests[key] != nil {
            resolveExternalAuthRefreshRequest(key: key, result: .requestFailed(code: code, message: message))
        } else {
            resolveAttestationRequest(key: key, result: .requestFailed)
        }
    }

    func cancelRequest(id: RequestID) async {
        let key = AppServerRequestIDCodec.key(for: id)
        if pendingDynamicToolCallRequests[key] != nil {
            resolveDynamicToolCallRequest(key: key, result: .requestCanceled)
        } else if pendingFileChangeApprovalRequests[key] != nil {
            await resolveFileChangeApprovalRequest(key: key, result: .requestCanceled)
        } else if pendingCommandExecutionApprovalRequests[key] != nil {
            await resolveCommandExecutionApprovalRequest(key: key, result: .requestCanceled)
        } else if pendingToolRequestUserInputRequests[key] != nil {
            await resolveToolRequestUserInputRequest(key: key, result: .requestCanceled)
        } else if pendingPermissionsApprovalRequests[key] != nil {
            await resolvePermissionsApprovalRequest(key: key, result: .requestCanceled)
        } else if pendingExternalAuthRefreshRequests[key] != nil {
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

    private func resolveDynamicToolCallRequest(key: String, result: AppServerDynamicToolCallRequestResult) {
        guard let continuation = pendingDynamicToolCallRequests.removeValue(forKey: key) else {
            return
        }
        continuation.resume(returning: result)
    }

    private func resolveFileChangeApprovalRequest(
        key: String,
        result: AppServerOutgoingRequestResult<AppServerProtocol.FileChangeRequestApprovalResponse>
    ) async {
        guard let continuation = pendingFileChangeApprovalRequests.removeValue(forKey: key) else {
            return
        }
        await sendServerRequestResolvedNotification(key: key, requestID: result.requestID)
        continuation.resume(returning: result)
    }

    private func resolveCommandExecutionApprovalRequest(
        key: String,
        result: AppServerOutgoingRequestResult<AppServerProtocol.CommandExecutionRequestApprovalResponse>
    ) async {
        guard let continuation = pendingCommandExecutionApprovalRequests.removeValue(forKey: key) else {
            return
        }
        await sendServerRequestResolvedNotification(key: key, requestID: result.requestID)
        continuation.resume(returning: result)
    }

    private func resolveToolRequestUserInputRequest(
        key: String,
        result: AppServerOutgoingRequestResult<AppServerProtocol.ToolRequestUserInputResponse>
    ) async {
        guard let continuation = pendingToolRequestUserInputRequests.removeValue(forKey: key) else {
            return
        }
        await sendServerRequestResolvedNotification(key: key, requestID: result.requestID)
        continuation.resume(returning: result)
    }

    private func resolvePermissionsApprovalRequest(
        key: String,
        result: AppServerOutgoingRequestResult<AppServerProtocol.PermissionsRequestApprovalResponse>
    ) async {
        guard let continuation = pendingPermissionsApprovalRequests.removeValue(forKey: key) else {
            return
        }
        await sendServerRequestResolvedNotification(key: key, requestID: result.requestID)
        continuation.resume(returning: result)
    }

    private func sendServerRequestResolvedNotification(key: String, requestID: RequestID?) async {
        guard let notificationSink,
              let requestID,
              let threadID = pendingServerRequestThreadIDs.removeValue(forKey: key)
        else {
            pendingServerRequestThreadIDs.removeValue(forKey: key)
            return
        }
        let notification: [String: Any] = [
            "method": "serverRequest/resolved",
            "params": [
                "threadId": threadID,
                "requestId": requestID.jsonObject
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: notification) else {
            return
        }
        await notificationSink(data)
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

extension RequestID {
    var jsonObject: Any {
        switch self {
        case let .string(value):
            return value
        case let .integer(value):
            return value
        }
    }
}
