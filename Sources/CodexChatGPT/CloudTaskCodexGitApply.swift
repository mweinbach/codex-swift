import CodexCore
import CodexGit
import Foundation

public enum CloudTaskCodexGitApplier {
    public static func apply(_ request: CloudGitApplyRequest) async -> CloudTaskResult<CloudGitApplyResult> {
        do {
            let result = try CodexGit.applyGitPatch(ApplyGitRequest(
                cwd: request.cwd,
                diff: request.diff,
                revert: request.revert,
                preflight: request.preflight
            ))
            return .success(CloudGitApplyResult(
                exitCode: result.exitCode,
                appliedPaths: result.appliedPaths,
                skippedPaths: result.skippedPaths,
                conflictedPaths: result.conflictedPaths,
                stdout: result.stdout,
                stderr: result.stderr,
                commandForLog: result.commandForLog
            ))
        } catch {
            return .failure(.io(String(describing: error)))
        }
    }
}
