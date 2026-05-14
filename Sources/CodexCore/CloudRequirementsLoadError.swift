import Foundation

public enum CloudRequirementsLoadErrorCode: String, Sendable {
    case auth = "Auth"
    case timeout = "Timeout"
    case parse = "Parse"
    case requestFailed = "RequestFailed"
    case internalError = "Internal"
}

public struct CloudRequirementsLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    public let code: CloudRequirementsLoadErrorCode
    public let statusCode: Int?
    public let detail: String

    public init(
        code: CloudRequirementsLoadErrorCode,
        statusCode: Int?,
        detail: String
    ) {
        self.code = code
        self.statusCode = statusCode
        self.detail = detail
    }

    public var description: String {
        detail
    }
}

public final class CloudRequirementsLoader: Sendable {
    private let task: Task<Result<ConfigRequirementsToml?, CloudRequirementsLoadError>, Never>

    public convenience init() {
        self.init {
            .success(nil)
        }
    }

    public init(
        operation: @escaping @Sendable () async -> Result<ConfigRequirementsToml?, CloudRequirementsLoadError>
    ) {
        self.task = Task {
            await operation()
        }
    }

    public func get() async throws -> ConfigRequirementsToml? {
        try await task.value.get()
    }
}
