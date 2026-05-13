@testable import CodexCore
import XCTest

final class MemoryWriteExtensionsTests: XCTestCase {
    func testSeedAdHocInstructionsDoesNotOverwriteExistingFile() throws {
        let root = try temporaryDirectory()
        let instructionsPath = memoryExtensionsRoot(root: root)
            .appendingPathComponent(adHocMemoryExtensionName, isDirectory: true)
            .appendingPathComponent(memoryExtensionInstructionsFilename, isDirectory: false)

        try seedAdHocMemoryExtensionInstructions(root: root)

        XCTAssertEqual(
            try String(contentsOf: instructionsPath, encoding: .utf8),
            adHocMemoryExtensionInstructions
        )

        try "custom instructions".write(to: instructionsPath, atomically: true, encoding: .utf8)
        try seedAdHocMemoryExtensionInstructions(root: root)

        XCTAssertEqual(
            try String(contentsOf: instructionsPath, encoding: .utf8),
            "custom instructions"
        )
    }

    func testPruneOldResourcesOnlyFromExtensionsWithInstructions() throws {
        let root = try temporaryDirectory()
        let extensionsRoot = memoryExtensionsRoot(root: root)
        let chronicleResources = extensionsRoot
            .appendingPathComponent("chronicle", isDirectory: true)
            .appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: chronicleResources, withIntermediateDirectories: true)
        try "instructions".write(
            to: extensionsRoot
                .appendingPathComponent("chronicle", isDirectory: true)
                .appendingPathComponent(memoryExtensionInstructionsFilename, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let now = try XCTUnwrap(memoryExtensionResourceTimestamp("2026-04-14T12-00-00-now.md"))
        let oldFile = chronicleResources
            .appendingPathComponent("2026-04-06T11-59-59-abcd-10min-old.md", isDirectory: false)
        let exactCutoffFile = chronicleResources
            .appendingPathComponent("2026-04-07T12-00-00-abcd-10min-cutoff.md", isDirectory: false)
        let recentFile = chronicleResources
            .appendingPathComponent("2026-04-08T12-00-00-abcd-10min-recent.md", isDirectory: false)
        let invalidFile = chronicleResources
            .appendingPathComponent("not-a-timestamp.md", isDirectory: false)
        for file in [oldFile, exactCutoffFile, recentFile, invalidFile] {
            try "resource".write(to: file, atomically: true, encoding: .utf8)
        }

        let ignoredResources = extensionsRoot
            .appendingPathComponent("ignored", isDirectory: true)
            .appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredResources, withIntermediateDirectories: true)
        let ignoredOldFile = ignoredResources
            .appendingPathComponent("2026-04-06T11-59-59-abcd-10min-old.md", isDirectory: false)
        try "ignored".write(to: ignoredOldFile, atomically: true, encoding: .utf8)

        pruneOldMemoryExtensionResources(root: root, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exactCutoffFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignoredOldFile.path))
    }

    func testResourceTimestampParsesRustFilenamePrefix() throws {
        let parsed = try XCTUnwrap(
            memoryExtensionResourceTimestamp("2026-04-06T11-59-59-abcd-10min-old.md")
        )

        XCTAssertEqual(Int(parsed.timeIntervalSince1970), 1_775_476_799)
        XCTAssertNil(memoryExtensionResourceTimestamp("not-a-timestamp.md"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memory-extensions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
