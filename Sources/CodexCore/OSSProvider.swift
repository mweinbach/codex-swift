import Foundation

public enum OSSProvider {
    public static let lmStudioProviderID = "lmstudio"
    public static let ollamaProviderID = "ollama"

    public static let lmStudioDefaultModel = "openai/gpt-oss-20b"
    public static let ollamaDefaultModel = "gpt-oss:20b"

    public typealias ReadinessCheck = () async throws -> Void

    public static func defaultModel(for providerID: String) -> String? {
        switch providerID {
        case lmStudioProviderID:
            return lmStudioDefaultModel
        case ollamaProviderID:
            return ollamaDefaultModel
        default:
            return nil
        }
    }

    public static func ensureProviderReady(
        providerID: String,
        lmStudioReadiness: ReadinessCheck,
        ollamaReadiness: ReadinessCheck
    ) async throws {
        switch providerID {
        case lmStudioProviderID:
            do {
                try await lmStudioReadiness()
            } catch {
                throw OSSProviderReadinessError(underlying: error)
            }
        case ollamaProviderID:
            do {
                try await ollamaReadiness()
            } catch {
                throw OSSProviderReadinessError(underlying: error)
            }
        default:
            return
        }
    }
}

public struct OSSProviderReadinessError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    public let underlyingDescription: String

    public init(underlying: Error) {
        self.underlyingDescription = Self.describe(underlying)
    }

    public var description: String {
        "OSS setup failed: \(underlyingDescription)"
    }

    public var errorDescription: String? {
        description
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
