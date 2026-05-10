import Foundation

public enum ExecServerOutboundMessage: Equatable, Sendable {
    case response(requestID: RequestID, result: JSONValue)
    case error(requestID: RequestID, error: ExecServerJSONRPCErrorDetail)
    case notification(ExecServerJSONRPCNotification)

    public var jsonRPCMessage: ExecServerJSONRPCMessage {
        switch self {
        case let .response(requestID, result):
            return ExecServerRPC.response(id: requestID, result: result)
        case let .error(requestID, error):
            return ExecServerRPC.error(id: requestID, error: error)
        case let .notification(notification):
            return .notification(notification)
        }
    }
}

public struct ExecServerRouter: Sendable {
    public init() {}

    public func handleRequest(
        _ request: ExecServerJSONRPCRequest,
        using handler: ExecServerHandler
    ) async -> ExecServerOutboundMessage? {
        do {
            let result = try await routeRequest(request, using: handler)
            return result.map { .response(requestID: request.id, result: $0) }
        } catch let error as ExecServerJSONRPCErrorDetail {
            return .error(requestID: request.id, error: error)
        } catch let error as ExecServerFileSystemError {
            return .error(requestID: request.id, error: error.rpcError)
        } catch {
            return .error(requestID: request.id, error: ExecServerRPC.internalError(String(describing: error)))
        }
    }

    public func handleNotification(
        _ notification: ExecServerJSONRPCNotification,
        using handler: ExecServerHandler
    ) async throws {
        switch notification.method {
        case execServerInitializedMethod:
            try await handler.markInitialized()
        default:
            throw ExecServerRouterNotificationError(
                "unexpected exec-server notification: \(notification.method)"
            )
        }
    }

    private func routeRequest(
        _ request: ExecServerJSONRPCRequest,
        using handler: ExecServerHandler
    ) async throws -> JSONValue? {
        switch request.method {
        case execServerInitializeMethod:
            let params = try decodeRequest(request.params, as: ExecServerInitializeParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.initialize(params))
        case execServerHttpRequestMethod:
            _ = try decodeRequest(request.params, as: ExecServerHttpRequestParams.self)
            _ = try await handler.requireInitialized(for: "http")
            throw methodPending(request.method)
        case execServerProcessStartMethod:
            let params = try decodeRequest(request.params, as: ExecServerExecParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.startProcess(params))
        case execServerProcessReadMethod:
            let params = try decodeRequest(request.params, as: ExecServerReadParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.readProcess(params))
        case execServerProcessWriteMethod:
            let params = try decodeRequest(request.params, as: ExecServerWriteParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.writeProcess(params))
        case execServerProcessTerminateMethod:
            let params = try decodeRequest(request.params, as: ExecServerTerminateParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.terminateProcess(params))
        case execServerFsReadFileMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsReadFileParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.readFile(params))
        case execServerFsWriteFileMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsWriteFileParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.writeFile(params))
        case execServerFsCreateDirectoryMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsCreateDirectoryParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.createDirectory(params))
        case execServerFsGetMetadataMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsGetMetadataParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.getMetadata(params))
        case execServerFsReadDirectoryMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsReadDirectoryParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.readDirectory(params))
        case execServerFsRemoveMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsRemoveParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.remove(params))
        case execServerFsCopyMethod:
            let params = try decodeRequest(request.params, as: ExecServerFsCopyParams.self)
            return try ExecServerRPC.jsonValue(from: try await handler.copy(params))
        default:
            throw methodPending(request.method)
        }
    }

    private func decodeRequest<T: Decodable>(_ params: JSONValue?, as type: T.Type) throws -> T {
        do {
            return try ExecServerRPC.decodeRequestParams(params, as: type)
        } catch {
            throw ExecServerRPC.invalidParams(String(describing: error))
        }
    }

    private func methodPending(_ method: String) -> ExecServerJSONRPCErrorDetail {
        ExecServerRPC.methodNotFound("exec-server stub does not implement `\(method)` yet")
    }
}

public struct ExecServerRouterNotificationError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}
