import Foundation
import Testing
@testable import CodexCore

struct InstallationIDTests {
    @Test
    func resolveGeneratesAndPersistsUUIDLikeRust() throws {
        let temp = try InstallationIDTemporaryDirectory()
        let installationID = try InstallationIDResolver.resolve(codexHome: temp.url)
        let persisted = try String(contentsOf: temp.url.appendingPathComponent(InstallationIDResolver.fileName))

        #expect(UUID(uuidString: installationID) != nil)
        #expect(persisted == installationID)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: temp.url.appendingPathComponent(InstallationIDResolver.fileName).path
        )
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o644)
    }

    @Test
    func resolveReusesExistingUUIDAndNormalizesCaseLikeRust() throws {
        let temp = try InstallationIDTemporaryDirectory()
        let existing = "11111111-2222-4333-8444-555555555555".uppercased()
        try existing.write(
            to: temp.url.appendingPathComponent(InstallationIDResolver.fileName),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try InstallationIDResolver.resolve(codexHome: temp.url)

        #expect(resolved == existing.lowercased())
    }

    @Test
    func resolveRewritesInvalidContentsLikeRust() throws {
        let temp = try InstallationIDTemporaryDirectory()
        let path = temp.url.appendingPathComponent(InstallationIDResolver.fileName)
        try "not-a-uuid".write(to: path, atomically: true, encoding: .utf8)

        let resolved = try InstallationIDResolver.resolve(codexHome: temp.url)
        let persisted = try String(contentsOf: path)

        #expect(UUID(uuidString: resolved) != nil)
        #expect(persisted == resolved)
    }
}

private final class InstallationIDTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-swift-installation-id-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
