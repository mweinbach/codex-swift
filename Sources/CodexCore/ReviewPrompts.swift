import Foundation

public enum ReviewTarget: Equatable, Codable, Sendable {
    case uncommittedChanges
    case baseBranch(branch: String)
    case commit(sha: String, title: String?)
    case custom(instructions: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case branch
        case sha
        case title
        case instructions
    }

    private enum TargetType: String, Codable {
        case uncommittedChanges
        case baseBranch
        case commit
        case custom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(TargetType.self, forKey: .type) {
        case .uncommittedChanges:
            self = .uncommittedChanges
        case .baseBranch:
            self = .baseBranch(branch: try container.decode(String.self, forKey: .branch))
        case .commit:
            self = .commit(
                sha: try container.decode(String.self, forKey: .sha),
                title: try container.decodeIfPresent(String.self, forKey: .title)
            )
        case .custom:
            self = .custom(instructions: try container.decode(String.self, forKey: .instructions))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .uncommittedChanges:
            try container.encode(TargetType.uncommittedChanges, forKey: .type)
        case let .baseBranch(branch):
            try container.encode(TargetType.baseBranch, forKey: .type)
            try container.encode(branch, forKey: .branch)
        case let .commit(sha, title):
            try container.encode(TargetType.commit, forKey: .type)
            try container.encode(sha, forKey: .sha)
            if let title {
                try container.encode(title, forKey: .title)
            } else {
                try container.encodeNil(forKey: .title)
            }
        case let .custom(instructions):
            try container.encode(TargetType.custom, forKey: .type)
            try container.encode(instructions, forKey: .instructions)
        }
    }
}

public struct ReviewRequest: Equatable, Codable, Sendable {
    public let target: ReviewTarget
    public let userFacingHint: String?

    private enum CodingKeys: String, CodingKey {
        case target
        case userFacingHint = "user_facing_hint"
    }

    public init(target: ReviewTarget, userFacingHint: String? = nil) {
        self.target = target
        self.userFacingHint = userFacingHint
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(userFacingHint, forKey: .userFacingHint)
    }
}

public struct ResolvedReviewRequest: Equatable, Sendable {
    public let target: ReviewTarget
    public let prompt: String
    public let userFacingHint: String

    public init(target: ReviewTarget, prompt: String, userFacingHint: String) {
        self.target = target
        self.prompt = prompt
        self.userFacingHint = userFacingHint
    }

    public var reviewRequest: ReviewRequest {
        ReviewRequest(target: target, userFacingHint: userFacingHint)
    }
}

public enum ReviewPromptError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyPrompt

    public var description: String {
        switch self {
        case .emptyPrompt:
            return "Review prompt cannot be empty"
        }
    }
}

public enum ReviewPrompts {
    public typealias MergeBaseWithHead = (_ cwd: String, _ branch: String) throws -> String?

    public static let uncommittedPrompt =
        "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."

    public static let baseBranchPromptBackup =
        "Review the code changes against the base branch '{branch}'. Start by finding the merge diff between the current branch and {branch}'s upstream e.g. (`git merge-base HEAD \"$(git rev-parse --abbrev-ref \"{branch}@{upstream}\")\"`), then run `git diff` against that SHA to see what changes we would merge into the {branch} branch. Provide prioritized, actionable findings."

    public static let baseBranchPrompt =
        "Review the code changes against the base branch '{baseBranch}'. The merge base commit for this comparison is {mergeBaseSha}. Run `git diff {mergeBaseSha}` to inspect the changes relative to {baseBranch}. Provide prioritized, actionable findings."

    public static let commitPromptWithTitle =
        "Review the code changes introduced by commit {sha} (\"{title}\"). Provide prioritized, actionable findings."

    public static let commitPrompt =
        "Review the code changes introduced by commit {sha}. Provide prioritized, actionable findings."

    public static func resolveReviewRequest(
        _ request: ReviewRequest,
        cwd: String,
        mergeBaseWithHead: MergeBaseWithHead = { _, _ in nil }
    ) throws -> ResolvedReviewRequest {
        let prompt = try reviewPrompt(
            target: request.target,
            cwd: cwd,
            mergeBaseWithHead: mergeBaseWithHead
        )
        let hint = request.userFacingHint ?? userFacingHint(target: request.target)
        return ResolvedReviewRequest(target: request.target, prompt: prompt, userFacingHint: hint)
    }

    public static func reviewPrompt(
        target: ReviewTarget,
        cwd: String,
        mergeBaseWithHead: MergeBaseWithHead = { _, _ in nil }
    ) throws -> String {
        switch target {
        case .uncommittedChanges:
            return uncommittedPrompt
        case let .baseBranch(branch):
            if let commit = try mergeBaseWithHead(cwd, branch) {
                return renderReviewPrompt(
                    baseBranchPrompt,
                    variables: [
                        ("baseBranch", branch),
                        ("mergeBaseSha", commit)
                    ]
                )
            }
            return renderReviewPrompt(baseBranchPromptBackup, variables: [("branch", branch)])
        case let .commit(sha, title):
            if let title {
                return renderReviewPrompt(
                    commitPromptWithTitle,
                    variables: [
                        ("sha", sha),
                        ("title", title)
                    ]
                )
            }
            return renderReviewPrompt(commitPrompt, variables: [("sha", sha)])
        case let .custom(instructions):
            let prompt = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                throw ReviewPromptError.emptyPrompt
            }
            return prompt
        }
    }

    public static func userFacingHint(target: ReviewTarget) -> String {
        switch target {
        case .uncommittedChanges:
            return "current changes"
        case let .baseBranch(branch):
            return "changes against '\(branch)'"
        case let .commit(sha, title):
            let shortSHA = String(sha.prefix(7))
            if let title {
                return "commit \(shortSHA): \(title)"
            }
            return "commit \(shortSHA)"
        case let .custom(instructions):
            return instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func renderReviewPrompt(
        _ template: String,
        variables: [(name: String, value: String)]
    ) -> String {
        let markers = variables.map { (marker: "{\($0.name)}", value: $0.value) }
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            if let replacement = markers.first(where: { template[index...].hasPrefix($0.marker) }) {
                output += replacement.value
                index = template.index(index, offsetBy: replacement.marker.count)
            } else {
                output.append(template[index])
                index = template.index(after: index)
            }
        }
        return output
    }
}
