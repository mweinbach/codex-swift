import CodexApplyPatch
import CodexCore
import XCTest

final class PatchSafetyTests: XCTestCase {
    func testWritableRootsConstraintMatchesRustWorkspaceDefaults() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let parent = try XCTUnwrap(cwd.parent)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let outsidePath = try parent.joined("outside.txt").path

        XCTAssertTrue(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: "inner.txt", contents: "")],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
        XCTAssertFalse(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: outsidePath, contents: "")],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
    }

    func testExplicitWritableRootAllowsOutsideWorkspaceWrite() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.appendingPathComponent("repo").path)
        try FileManager.default.createDirectory(atPath: cwd.path, withIntermediateDirectories: true)
        let parent = try XCTUnwrap(cwd.parent)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [parent],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let outsidePath = try parent.joined("outside.txt").path

        XCTAssertTrue(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: outsidePath, contents: "")],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
    }

    func testMovePatchRequiresSourceAndDestinationWritable() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let parent = try XCTUnwrap(cwd.parent)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let outsidePath = try parent.joined("outside.txt").path

        XCTAssertFalse(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.updateFile(path: "inner.txt", movePath: outsidePath, chunks: [
                UpdateFileChunk(changeContext: nil, oldLines: ["a"], newLines: ["b"], isEndOfFile: false)
            ])],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
    }

    func testGitAndCodexSubpathsRemainReadOnlyUnderWritableRoot() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        try FileManager.default.createDirectory(atPath: cwd.join(".git").path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: cwd.join(".codex").path, withIntermediateDirectories: true)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertFalse(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: ".git/hooks/pre-commit", contents: "")],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
        XCTAssertFalse(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: ".codex/config.toml", contents: "")],
            sandboxPolicy: policy,
            cwd: cwd,
            environment: [:]
        ))
    }

    func testReadOnlyNeverAllowsConstrainedPatch() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)

        XCTAssertFalse(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: "inner.txt", contents: "")],
            sandboxPolicy: .readOnly,
            cwd: cwd,
            environment: [:]
        ))
    }

    func testDangerAndExternalSandboxTreatPatchAsConstrained() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)

        XCTAssertTrue(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: "/outside.txt", contents: "")],
            sandboxPolicy: .dangerFullAccess,
            cwd: cwd,
            environment: [:]
        ))
        XCTAssertTrue(PatchSafety.isWritePatchConstrainedToWritablePaths(
            hunks: [.addFile(path: "/outside.txt", contents: "")],
            sandboxPolicy: .externalSandbox(networkAccess: .enabled),
            cwd: cwd,
            environment: [:]
        ))
    }

    func testAssessPatchSafetyDecisionMatrix() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let parent = try XCTUnwrap(cwd.parent)
        let inside = [Hunk.addFile(path: "inner.txt", contents: "")]
        let outsidePath = try parent.joined("outside.txt").path
        let outside = [Hunk.addFile(path: outsidePath, contents: "")]
        let workspacePolicy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [],
                approvalPolicy: .onRequest,
                sandboxPolicy: workspacePolicy,
                cwd: cwd,
                environment: [:]
            ),
            .reject(reason: "empty patch")
        )
        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: inside,
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: workspacePolicy,
                cwd: cwd,
                environment: [:]
            ),
            .askUser
        )
        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: outside,
                approvalPolicy: .never,
                sandboxPolicy: workspacePolicy,
                cwd: cwd,
                environment: [:]
            ),
            .reject(reason: "writing outside of the project; rejected by user approval settings")
        )
        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: outside,
                approvalPolicy: .onRequest,
                sandboxPolicy: workspacePolicy,
                cwd: cwd,
                environment: [:]
            ),
            .askUser
        )
    }

    func testGranularSandboxApprovalDisabledRejectsOutsidePatchLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let parent = try XCTUnwrap(cwd.parent)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let outsidePath = try parent.joined("outside.txt").path

        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [.addFile(path: outsidePath, contents: "")],
                approvalPolicy: .granular(GranularApprovalConfig(
                    sandboxApproval: false,
                    rules: true,
                    mcpElicitations: true
                )),
                sandboxPolicy: policy,
                cwd: cwd,
                environment: [:]
            ),
            .reject(reason: "writing outside of the project; rejected by user approval settings")
        )
    }

    func testReadOnlySandboxRejectionUsesRustReason() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)

        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [.addFile(path: "inner.txt", contents: "")],
                approvalPolicy: .never,
                sandboxPolicy: .readOnly,
                cwd: cwd,
                environment: [:]
            ),
            .reject(reason: "writing is blocked by read-only sandbox; rejected by user approval settings")
        )
        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [.addFile(path: "inner.txt", contents: "")],
                approvalPolicy: .granular(GranularApprovalConfig(
                    sandboxApproval: false,
                    rules: true,
                    mcpElicitations: true
                )),
                sandboxPolicy: .readOnlyWithNetworkAccess,
                cwd: cwd,
                environment: [:]
            ),
            .reject(reason: "writing is blocked by read-only sandbox; rejected by user approval settings")
        )
    }

    func testExternalSandboxAutoApprovesInOnRequestWithoutNestedSandbox() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)

        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [.addFile(path: "inner.txt", contents: "")],
                approvalPolicy: .onRequest,
                sandboxPolicy: .externalSandbox(networkAccess: .enabled),
                cwd: cwd,
                environment: [:]
            ),
            .autoApprove(sandboxType: .none, userExplicitlyApproved: false)
        )
    }

    func testWorkspaceOnFailureAutoApprovesWithPlatformSandboxEvenOutsideWorkspace() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let parent = try XCTUnwrap(cwd.parent)
        let policy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )
        let outsidePath = try parent.joined("outside.txt").path

        guard let platformSandbox = PatchSafety.getPlatformSandbox() else {
            return
        }

        XCTAssertEqual(
            PatchSafety.assessPatchSafety(
                hunks: [.addFile(path: outsidePath, contents: "")],
                approvalPolicy: .onFailure,
                sandboxPolicy: policy,
                cwd: cwd,
                environment: [:]
            ),
            .autoApprove(sandboxType: platformSandbox, userExplicitlyApproved: false)
        )
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private extension AbsolutePath {
    func joined(_ component: String) throws -> AbsolutePath {
        try join(component)
    }
}
