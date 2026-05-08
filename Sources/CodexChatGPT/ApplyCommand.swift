import CodexGit
import Foundation

public struct GetTaskResponse: Equatable, Decodable, Sendable {
    public let currentDiffTaskTurn: AssistantTurn?

    private enum CodingKeys: String, CodingKey {
        case currentDiffTaskTurn = "current_diff_task_turn"
    }
}

public struct AssistantTurn: Equatable, Decodable, Sendable {
    public let outputItems: [OutputItem]

    private enum CodingKeys: String, CodingKey {
        case outputItems = "output_items"
    }
}

public enum OutputItem: Equatable, Decodable, Sendable {
    case pr(PrOutputItem)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .type) {
        case "pr":
            self = .pr(try PrOutputItem(from: decoder))
        default:
            self = .other
        }
    }
}

public struct PrOutputItem: Equatable, Decodable, Sendable {
    public let outputDiff: OutputDiff

    private enum CodingKeys: String, CodingKey {
        case outputDiff = "output_diff"
    }
}

public struct OutputDiff: Equatable, Decodable, Sendable {
    public let diff: String
}

public enum ApplyTaskDiffError: Error, Equatable, CustomStringConvertible, Sendable {
    case noDiffTurnFound
    case noPROutputItemFound
    case gitApplyFailed(ApplyGitResult)

    public var description: String {
        switch self {
        case .noDiffTurnFound:
            return "No diff turn found"
        case .noPROutputItemFound:
            return "No PR output item found"
        case let .gitApplyFailed(result):
            return """
            Git apply failed (applied=\(result.appliedPaths.count), skipped=\(result.skippedPaths.count), conflicts=\(result.conflictedPaths.count))
            stdout:
            \(result.stdout)
            stderr:
            \(result.stderr)
            """
        }
    }
}

public enum CodexTaskDiffApplier {
    public static func diff(from taskResponse: GetTaskResponse) throws -> String {
        guard let turn = taskResponse.currentDiffTaskTurn else {
            throw ApplyTaskDiffError.noDiffTurnFound
        }
        for item in turn.outputItems {
            if case let .pr(pr) = item {
                return pr.outputDiff.diff
            }
        }
        throw ApplyTaskDiffError.noPROutputItemFound
    }

    public static func applyDiff(from taskResponse: GetTaskResponse, cwd: URL? = nil) throws -> ApplyGitResult {
        let diff = try diff(from: taskResponse)
        let root = cwd ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let result = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: root, diff: diff, revert: false, preflight: false))
        guard result.exitCode == 0 else {
            throw ApplyTaskDiffError.gitApplyFailed(result)
        }
        return result
    }
}
