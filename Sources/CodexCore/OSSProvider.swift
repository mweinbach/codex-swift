import Foundation

public enum OSSProvider {
    public static let lmStudioProviderID = "lmstudio"
    public static let ollamaProviderID = "ollama"
    public static let missingProviderMessage = "No default OSS provider configured. Use --local-provider=provider or set oss_provider to one of: lmstudio, ollama in config.toml"

    public static let lmStudioDefaultModel = "openai/gpt-oss-20b"
    public static let ollamaDefaultModel = "gpt-oss:20b"

    public typealias ReadinessCheck = () async throws -> Void
    public typealias ProviderReadinessCheck = (ModelProviderInfo, String) async throws -> Void
    public typealias ProviderVersionCheck = (ModelProviderInfo) async throws -> Void

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

    public static func resolveProviderID(explicitProvider: String?, settings: CodexRuntimeConfig) -> String? {
        explicitProvider ?? settings.ossProvider
    }

    public static func defaultModelOverride(providerID: String?, cliModel: String?) -> String? {
        cliModel ?? providerID.flatMap(defaultModel(for:))
    }

    public static func ensureProviderReady(
        providerID: String,
        providerInfo: ModelProviderInfo,
        model: String
    ) async throws {
        try await ensureProviderReady(
            providerID: providerID,
            providerInfo: providerInfo,
            model: model,
            lmStudioReadiness: ensureLMStudioReady,
            ollamaVersionReadiness: { try await OllamaClient.ensureResponsesSupported(provider: $0) },
            ollamaReadiness: ensureOllamaReady
        )
    }

    public static func ensureProviderReady(
        providerID: String,
        providerInfo: ModelProviderInfo,
        model: String,
        lmStudioReadiness: ProviderReadinessCheck,
        ollamaVersionReadiness: ProviderVersionCheck,
        ollamaReadiness: ProviderReadinessCheck
    ) async throws {
        switch providerID {
        case lmStudioProviderID:
            do {
                try await lmStudioReadiness(providerInfo, model)
            } catch {
                throw OSSProviderReadinessError(underlying: error)
            }
        case ollamaProviderID:
            do {
                try await ollamaVersionReadiness(providerInfo)
                try await ollamaReadiness(providerInfo, model)
            } catch {
                throw OSSProviderReadinessError(underlying: error)
            }
        default:
            return
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

    private static func ensureLMStudioReady(providerInfo: ModelProviderInfo, model: String) async throws {
        let client = try await LMStudioClient.tryFromProvider(providerInfo)
        let models: [String]?
        do {
            models = try await client.fetchModels()
        } catch {
            // Rust treats model-list failures as non-fatal and lets later model use surface the error.
            models = nil
        }

        if let models, !models.contains(model) {
            try client.downloadModel(model)
        }

        Task {
            try? await client.loadModel(model)
        }
    }

    private static func ensureOllamaReady(providerInfo: ModelProviderInfo, model: String) async throws {
        let client = try await OllamaClient.tryFromProvider(providerInfo)
        let models: [String]?
        do {
            models = try await client.fetchModels()
        } catch {
            // Rust treats model-list failures as non-fatal and lets later model use surface the error.
            models = nil
        }

        if let models, !models.contains(model) {
            try await client.pullModel(model) { event in
                if let line = event.cliLine {
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
            }
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

private extension OllamaPullEvent {
    var cliLine: String? {
        switch self {
        case let .status(message):
            return message
        case let .chunkProgress(digest, total, completed):
            let totalText = total.map { "/\($0)" } ?? ""
            let completedText = completed.map(String.init) ?? "0"
            return "\(digest) \(completedText)\(totalText)"
        case let .error(message):
            return message
        case .success:
            return "Model pull complete."
        }
    }
}
