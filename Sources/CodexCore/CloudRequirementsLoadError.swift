import Foundation

public enum CloudRequirementsLoadErrorCode: String, Sendable {
    case auth = "Auth"
    case requestFailed = "RequestFailed"
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
