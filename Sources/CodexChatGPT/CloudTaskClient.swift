import CodexCore
import Foundation

public struct CloudTaskClientConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = CodexConfigDefaults.chatgptBaseURL

    public let chatgptBaseURL: String
    public let codexHome: URL
    public let authCredentialsStoreMode: AuthCredentialsStoreMode

    public init(
        chatgptBaseURL: String = Self.defaultBaseURL,
        codexHome: URL,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.codexHome = codexHome
        self.authCredentialsStoreMode = authCredentialsStoreMode
    }
}

public enum CloudTaskClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case chatGPTTokenNotAvailable
    case chatGPTAccountIDNotAvailable
    case cloudTaskFailed(CloudTaskError)
    case applyDidNotSucceed(CloudApplyOutcome)

    public var description: String {
        switch self {
        case .chatGPTTokenNotAvailable:
            return "ChatGPT token not available"
        case .chatGPTAccountIDNotAvailable:
            return "ChatGPT account ID not available, please re-run `codex login`"
        case let .cloudTaskFailed(error):
            return error.description
        case let .applyDidNotSucceed(outcome):
            return outcome.message
        }
    }
}

public struct CloudTaskClient<Transport: APITransport>: Sendable {
    public typealias TokenLoader = @Sendable () async throws -> AuthTokenData?

    public let configuration: CloudTaskClientConfiguration
    public let transport: Transport

    private let tokenLoader: TokenLoader
    private let currentDirectory: @Sendable () -> URL
    private let applyGitPatch: CloudGitApply
    private let errorLog: CloudTaskErrorLog

    public init(
        configuration: CloudTaskClientConfiguration,
        transport: Transport,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        applyGitPatch: @escaping CloudGitApply = CloudTaskCodexGitApplier.apply,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenLoader = tokenLoader ?? {
            try await CodexAuthStorage.loadFreshTokenData(
                codexHome: configuration.codexHome,
                mode: configuration.authCredentialsStoreMode
            )
        }
        self.currentDirectory = currentDirectory
        self.applyGitPatch = applyGitPatch
        self.errorLog = errorLog
    }

    public func applyTask(taskID: String) async throws -> CloudApplyOutcome {
        guard let token = try await tokenLoader() else {
            throw CloudTaskClientError.chatGPTTokenNotAvailable
        }
        guard let accountID = token.accountID else {
            throw CloudTaskClientError.chatGPTAccountIDNotAvailable
        }

        let client = CloudHTTPClient(
            baseURL: configuration.chatgptBaseURL,
            transport: transport,
            auth: StaticAPIAuthProvider(bearerToken: token.accessToken, accountID: accountID),
            currentDirectory: currentDirectory,
            applyGitPatch: applyGitPatch,
            errorLog: errorLog
        )

        switch await client.applyTask(id: CloudTaskID(taskID), diffOverride: nil) {
        case let .success(outcome):
            guard outcome.applied, outcome.status == .success else {
                throw CloudTaskClientError.applyDidNotSucceed(outcome)
            }
            return outcome
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }
    }
}

public extension CloudTaskClient where Transport == URLSessionAPITransport {
    init(
        configuration: CloudTaskClientConfiguration,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        applyGitPatch: @escaping CloudGitApply = CloudTaskCodexGitApplier.apply,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        self.init(
            configuration: configuration,
            transport: URLSessionAPITransport(),
            tokenLoader: tokenLoader,
            currentDirectory: currentDirectory,
            applyGitPatch: applyGitPatch,
            errorLog: errorLog
        )
    }
}
