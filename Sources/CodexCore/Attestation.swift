import Foundation

public enum Attestation {
    public static let headerName = "x-oai-attestation"
    public static let generateMethod = "attestation/generate"

    public struct Context: Equatable, Sendable {
        public let threadID: String

        public init(threadID: String) {
            self.threadID = threadID
        }
    }

    public enum AppServerStatus: UInt8, Sendable {
        case ok = 0
        case timeout = 1
        case requestFailed = 2
        case requestCanceled = 3
        case malformedResponse = 4
    }

    public struct GenerateParams: Codable, Equatable, Sendable {
        public init() {}
    }

    public struct GenerateResponse: Codable, Equatable, Sendable {
        public let token: String

        public init(token: String) {
            self.token = token
        }
    }

    public static func appServerHeaderValue(status: AppServerStatus, token: String? = nil) -> String? {
        var value = #"{"v":1,"s":\#(status.rawValue)"#
        if let token {
            guard let data = try? JSONEncoder().encode(token),
                  let encodedToken = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            value.append(#","t":\#(encodedToken)"#)
        }
        value.append("}")
        return value
    }
}

public protocol AttestationProvider: Sendable {
    func header(for context: Attestation.Context) async -> String?
}
