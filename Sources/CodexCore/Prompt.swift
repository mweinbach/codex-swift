import CodexApplyPatch
import Foundation

public struct Prompt: Equatable, Sendable {
    public var input: [ResponseItem]
    public var tools: [ToolSpec]
    public var parallelToolCalls: Bool
    public var baseInstructionsOverride: String?
    public var outputSchema: JSONValue?

    public init(
        input: [ResponseItem] = [],
        tools: [ToolSpec] = [],
        parallelToolCalls: Bool = false,
        baseInstructionsOverride: String? = nil,
        outputSchema: JSONValue? = nil
    ) {
        self.input = input
        self.tools = tools
        self.parallelToolCalls = parallelToolCalls
        self.baseInstructionsOverride = baseInstructionsOverride
        self.outputSchema = outputSchema
    }

    public func fullInstructions(for model: ModelFamily) -> String {
        let base = baseInstructionsOverride ?? model.baseInstructions
        let hasApplyPatchTool = tools.contains { tool in
            switch tool {
            case let .function(function):
                return function.name == "apply_patch"
            case let .freeform(freeform):
                return freeform.name == "apply_patch"
            case .namespace, .localShell, .webSearch:
                return false
            }
        }

        if baseInstructionsOverride == nil,
           model.needsSpecialApplyPatchInstructions,
           !hasApplyPatchTool
        {
            return "\(base)\n\(ApplyPatchToolInstructions.text)"
        }

        return base
    }
}
