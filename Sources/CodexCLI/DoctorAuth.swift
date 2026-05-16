import CodexCore
import Foundation

public enum DoctorStoredAuthProbe: Equatable, Sendable {
    case loaded(AuthDotJSON?)
    case failed(String)
}

public struct DoctorAuthCheckInputs: Equatable, Sendable {
    public let codexHomePath: String
    public let authStorageMode: AuthCredentialsStoreMode
    public let environment: [String: String]
    public let providerRequiresOpenAIAuth: Bool
    public let providerEnvKey: String?
    public let providerEnvKeyInstructions: String?
    public let storedAuth: DoctorStoredAuthProbe

    public init(
        codexHomePath: String,
        authStorageMode: AuthCredentialsStoreMode,
        environment: [String: String],
        providerRequiresOpenAIAuth: Bool,
        providerEnvKey: String?,
        providerEnvKeyInstructions: String?,
        storedAuth: DoctorStoredAuthProbe
    ) {
        self.codexHomePath = codexHomePath
        self.authStorageMode = authStorageMode
        self.environment = environment
        self.providerRequiresOpenAIAuth = providerRequiresOpenAIAuth
        self.providerEnvKey = providerEnvKey
        self.providerEnvKeyInstructions = providerEnvKeyInstructions
        self.storedAuth = storedAuth
    }
}

extension DoctorCommandRuntime {
    public static func authCredentialsCheck(
        codexHome: URL,
        settings: CodexRuntimeConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DoctorCheck {
        let storedAuth: DoctorStoredAuthProbe
        do {
            storedAuth = .loaded(try CodexAuthStorage.loadAuthDotJSON(
                codexHome: codexHome,
                mode: settings.cliAuthCredentialsStoreMode
            ))
        } catch {
            storedAuth = .failed(String(describing: error))
        }

        let provider = settings.selectedModelProvider
        return authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: codexHome.path,
            authStorageMode: settings.cliAuthCredentialsStoreMode,
            environment: environment,
            providerRequiresOpenAIAuth: provider?.requiresOpenAIAuth ?? true,
            providerEnvKey: provider?.envKey,
            providerEnvKeyInstructions: provider?.envKeyInstructions,
            storedAuth: storedAuth
        ))
    }

    public static func authCredentialsCheck(inputs: DoctorAuthCheckInputs) -> DoctorCheck {
        let envAuthVars = authEnvironmentVariables.filter {
            authEnvironmentVariablePresent($0, in: inputs.environment)
        }
        var details = [
            "auth storage mode: \(authStorageModeDescription(inputs.authStorageMode))",
            "auth file: \(URL(fileURLWithPath: inputs.codexHomePath).appendingPathComponent("auth.json").path)"
        ]
        if !envAuthVars.isEmpty {
            details.append("auth env vars present: \(envAuthVars.joined(separator: ", "))")
        }
        if let providerCheck = providerSpecificAuthCheck(
            requiresOpenAIAuth: inputs.providerRequiresOpenAIAuth,
            providerEnvKey: inputs.providerEnvKey,
            providerEnvKeyInstructions: inputs.providerEnvKeyInstructions,
            details: details,
            environment: inputs.environment
        ) {
            return providerCheck
        }

        switch inputs.storedAuth {
        case let .loaded(auth?):
            details.append("stored auth mode: \(storedAuthMode(auth))")
            details.append("stored API key: \(rustBool(auth.openAIAPIKey != nil))")
            details.append("stored ChatGPT tokens: \(rustBool(auth.tokens != nil))")
            details.append("stored agent identity: \(rustBool(auth.agentIdentity != nil))")
            let authIssues = storedAuthIssues(auth, environment: inputs.environment)
            details.append(contentsOf: authIssues.map { "stored auth issue: \($0)" })

            let status: DoctorCheckStatus
            if !authIssues.isEmpty && envAuthVars.isEmpty {
                status = .fail
            } else if !authIssues.isEmpty || envAuthVars.count > 1 {
                status = .warning
            } else {
                status = .ok
            }
            let summary: String
            switch status {
            case .ok:
                summary = "auth is configured"
            case .warning where !authIssues.isEmpty:
                summary = "auth is provided by environment, but stored credentials are incomplete"
            case .warning:
                summary = "auth is configured, but multiple auth env vars are present"
            case .fail:
                summary = "stored credentials are incomplete"
            }
            return DoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: status,
                summary: summary,
                details: details,
                remediation: status == .fail
                    ? "Run codex login again or provide a supported auth env var."
                    : nil
            )
        case .loaded(nil) where !envAuthVars.isEmpty:
            return DoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: .ok,
                summary: "auth is provided by environment",
                details: details
            )
        case .loaded(nil):
            return DoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: .fail,
                summary: "no Codex credentials were found",
                details: details,
                remediation: "Run codex login or provide an API key through a supported auth env var."
            )
        case let .failed(error):
            return DoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: .fail,
                summary: "stored credentials could not be read",
                details: [error],
                remediation: "Fix auth storage access or run codex login again."
            )
        }
    }

    private static var authEnvironmentVariables: [String] {
        [
            CodexAuthStorage.openAIAPIKeyEnvironmentVariable,
            CodexAuthStorage.codexAPIKeyEnvironmentVariable,
            CodexAuthStorage.codexAccessTokenEnvironmentVariable
        ]
    }

    private static func providerSpecificAuthCheck(
        requiresOpenAIAuth: Bool,
        providerEnvKey: String?,
        providerEnvKeyInstructions: String?,
        details: [String],
        environment: [String: String]
    ) -> DoctorCheck? {
        var details = details
        details.append("model provider requires OpenAI auth: \(rustBool(requiresOpenAIAuth))")
        guard !requiresOpenAIAuth else {
            return nil
        }

        if let providerEnvKey {
            if authEnvironmentVariablePresent(providerEnvKey, in: environment) {
                details.append("provider auth env var: \(providerEnvKey) (present)")
                return DoctorCheck(
                    id: "auth.credentials",
                    category: "auth",
                    status: .ok,
                    summary: "auth is provided by the active model provider",
                    details: details
                )
            }

            details.append("provider auth env var: \(providerEnvKey) (missing)")
            return DoctorCheck(
                id: "auth.credentials",
                category: "auth",
                status: .fail,
                summary: "active model provider auth env var is missing",
                details: details,
                remediation: providerEnvKeyInstructions ?? "Set \(providerEnvKey) for the active model provider."
            )
        }

        return DoctorCheck(
            id: "auth.credentials",
            category: "auth",
            status: .ok,
            summary: "OpenAI auth is not required for the active model provider",
            details: details
        )
    }

    private static func storedAuthMode(_ auth: AuthDotJSON) -> String {
        switch storedAuthModeValue(auth) {
        case .apiKey:
            "api_key"
        case .chatGPT:
            "chatgpt"
        case .chatGPTAuthTokens:
            "chatgpt_auth_tokens"
        case .agentIdentity:
            "agent_identity"
        }
    }

    private static func storedAuthModeValue(_ auth: AuthDotJSON) -> AuthMode {
        if let authMode = auth.authMode {
            return authMode
        }
        return auth.openAIAPIKey != nil ? .apiKey : .chatGPT
    }

    private static func storedAuthIssues(_ auth: AuthDotJSON, environment: [String: String]) -> [String] {
        switch storedAuthModeValue(auth) {
        case .apiKey:
            let storedKeyPresent = auth.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let envKeyPresent = authEnvironmentVariablePresent(
                CodexAuthStorage.openAIAPIKeyEnvironmentVariable,
                in: environment
            ) || authEnvironmentVariablePresent(
                CodexAuthStorage.codexAPIKeyEnvironmentVariable,
                in: environment
            )
            return storedKeyPresent || envKeyPresent ? [] : ["API key auth is missing an API key"]
        case .chatGPT:
            var issues: [String] = []
            if let tokens = auth.tokens {
                if tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("ChatGPT auth is missing an access token")
                }
                if tokens.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("ChatGPT auth is missing a refresh token")
                }
            } else {
                issues.append("ChatGPT auth is missing token data")
            }
            if auth.lastRefresh == nil {
                issues.append("ChatGPT auth is missing refresh metadata")
            }
            return issues
        case .chatGPTAuthTokens:
            var issues: [String] = []
            if let tokens = auth.tokens {
                if tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("external ChatGPT auth is missing an access token")
                }
                if tokens.accountID == nil && tokens.idToken.chatGPTAccountID == nil {
                    issues.append("external ChatGPT auth is missing a ChatGPT account id")
                }
            } else {
                issues.append("external ChatGPT auth is missing token data")
            }
            if auth.lastRefresh == nil {
                issues.append("external ChatGPT auth is missing refresh metadata")
            }
            return issues
        case .agentIdentity:
            if auth.agentIdentity?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return []
            }
            return ["agent identity auth is missing an agent identity token"]
        }
    }

    private static func authStorageModeDescription(_ mode: AuthCredentialsStoreMode) -> String {
        switch mode {
        case .file:
            "File"
        case .keyring:
            "Keyring"
        case .auto:
            "Auto"
        case .ephemeral:
            "Ephemeral"
        }
    }

    private static func authEnvironmentVariablePresent(_ name: String, in environment: [String: String]) -> Bool {
        environment[name]?.isEmpty == false
    }

    private static func rustBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}
