import Foundation

public struct MemoriesExtensionConfig: Equatable, Sendable {
    public let enabled: Bool
    public let codexHome: URL

    public init(enabled: Bool, codexHome: URL) {
        self.enabled = enabled
        self.codexHome = codexHome
    }

    public static func fromRuntimeConfig(_ config: CodexRuntimeConfig, codexHome: URL) -> Self {
        Self(
            enabled: config.features.isEnabled(.memoryTool) && config.memories.useMemories,
            codexHome: codexHome
        )
    }
}

public struct MemoriesExtension:
    ExtensionThreadLifecycleContributor,
    ExtensionConfigContributor,
    ExtensionContextContributor
{
    private let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    public func onThreadStart(_ input: ExtensionThreadStartInput) {
        input.threadStore.insert(MemoriesExtensionConfig.fromRuntimeConfig(
            input.config,
            codexHome: codexHome
        ))
    }

    public func onConfigChanged(_ input: ExtensionConfigChangedInput) {
        input.threadStore.insert(MemoriesExtensionConfig.fromRuntimeConfig(
            input.newConfig,
            codexHome: codexHome
        ))
    }

    public func contribute(
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) async -> [ExtensionPromptFragment] {
        guard let config = threadStore.get(MemoriesExtensionConfig.self),
              config.enabled,
              let instructions = MemoryToolInstructions.build(codexHome: config.codexHome)
        else {
            return []
        }
        return [.developerPolicy(instructions)]
    }
}

public func installMemoriesExtension(into builder: inout ExtensionRegistryBuilder, codexHome: URL) {
    let memoriesExtension = MemoriesExtension(codexHome: codexHome)
    builder.threadLifecycleContributor(memoriesExtension)
    builder.configContributor(memoriesExtension)
    builder.promptContributor(memoriesExtension)
    // Match Rust's app-server extension state after cccde930ce: prompt injection
    // is extension-owned, while memory read/retrieval tools remain unregistered.
}
