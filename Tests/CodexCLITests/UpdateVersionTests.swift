import CodexCLI
import XCTest

final class UpdateVersionTests: XCTestCase {
    func testParsesVersionFromCaskContents() throws {
        let cask = """
            cask "codex" do
              version "0.55.0"
            end
        """

        XCTAssertEqual(try UpdateVersion.extractVersionFromCask(cask), "0.55.0")
    }

    func testMissingCaskVersionThrowsRustMatchingError() {
        XCTAssertThrowsError(try UpdateVersion.extractVersionFromCask("cask \"codex\" do\nend")) { error in
            XCTAssertEqual(String(describing: error), "Failed to find version in Homebrew cask file")
        }
    }

    func testExtractsVersionFromLatestTag() throws {
        XCTAssertEqual(try UpdateVersion.extractVersionFromLatestTag("rust-v1.5.0"), "1.5.0")
    }

    func testLatestTagWithoutPrefixIsInvalid() {
        XCTAssertThrowsError(try UpdateVersion.extractVersionFromLatestTag("v1.5.0")) { error in
            XCTAssertEqual(String(describing: error), "Failed to parse latest tag name 'v1.5.0'")
        }
    }

    func testPrereleaseVersionIsNotConsideredNewer() {
        XCTAssertNil(UpdateVersion.isNewer(latest: "0.11.0-beta.1", current: "0.11.0"))
        XCTAssertNil(UpdateVersion.isNewer(latest: "1.0.0-rc.1", current: "1.0.0"))
    }

    func testPlainSemverComparisonsWork() {
        XCTAssertEqual(UpdateVersion.isNewer(latest: "0.11.1", current: "0.11.0"), true)
        XCTAssertEqual(UpdateVersion.isNewer(latest: "0.11.0", current: "0.11.1"), false)
        XCTAssertEqual(UpdateVersion.isNewer(latest: "1.0.0", current: "0.9.9"), true)
        XCTAssertEqual(UpdateVersion.isNewer(latest: "0.9.9", current: "1.0.0"), false)
    }

    func testWhitespaceIsIgnored() {
        XCTAssertEqual(UpdateVersion.parseVersion(" 1.2.3 \n")?.major, 1)
        XCTAssertEqual(UpdateVersion.isNewer(latest: " 1.2.3 ", current: "1.2.2"), true)
    }

    func testVersionFilePathMatchesRustFilename() {
        let home = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)

        XCTAssertEqual(UpdateVersion.versionFilename, "version.json")
        XCTAssertEqual(UpdateVersion.versionFilePath(codexHome: home).path, "/tmp/codex-home/version.json")
    }

    func testShouldRefreshWhenMissingOrOlderThanTwentyHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = UpdateVersionInfo(latestVersion: "1.2.3", lastCheckedAt: now.addingTimeInterval(-19 * 60 * 60))
        let stale = UpdateVersionInfo(latestVersion: "1.2.3", lastCheckedAt: now.addingTimeInterval(-21 * 60 * 60))

        XCTAssertTrue(UpdateVersion.shouldRefreshVersionInfo(nil, now: now))
        XCTAssertFalse(UpdateVersion.shouldRefreshVersionInfo(fresh, now: now))
        XCTAssertTrue(UpdateVersion.shouldRefreshVersionInfo(stale, now: now))
    }

    func testUpgradeVersionUsesCachedInfoAndStartupGate() {
        let info = UpdateVersionInfo(latestVersion: "1.2.3", lastCheckedAt: Date())

        XCTAssertEqual(UpdateVersion.upgradeVersion(
            cachedInfo: info,
            currentVersion: "1.2.2",
            checkForUpdateOnStartup: true
        ), "1.2.3")
        XCTAssertNil(UpdateVersion.upgradeVersion(
            cachedInfo: info,
            currentVersion: "1.2.2",
            checkForUpdateOnStartup: false
        ))
        XCTAssertNil(UpdateVersion.upgradeVersion(
            cachedInfo: nil,
            currentVersion: "1.2.2",
            checkForUpdateOnStartup: true
        ))
        XCTAssertNil(UpdateVersion.upgradeVersion(
            cachedInfo: info,
            currentVersion: "1.2.4",
            checkForUpdateOnStartup: true
        ))
    }

    func testUpgradeVersionForPopupHonorsDismissedVersion() {
        let dismissed = UpdateVersionInfo(
            latestVersion: "1.2.3",
            lastCheckedAt: Date(),
            dismissedVersion: "1.2.3"
        )
        let notDismissed = UpdateVersionInfo(
            latestVersion: "1.2.3",
            lastCheckedAt: Date(),
            dismissedVersion: "1.2.2"
        )

        XCTAssertNil(UpdateVersion.upgradeVersionForPopup(
            cachedInfo: dismissed,
            currentVersion: "1.2.2",
            checkForUpdateOnStartup: true
        ))
        XCTAssertEqual(UpdateVersion.upgradeVersionForPopup(
            cachedInfo: notDismissed,
            currentVersion: "1.2.2",
            checkForUpdateOnStartup: true
        ), "1.2.3")
    }

    func testDismissVersionUpdatesExistingInfoOnly() {
        let info = UpdateVersionInfo(latestVersion: "1.2.3", lastCheckedAt: Date())

        XCTAssertNil(UpdateVersion.dismissVersion(info: nil, version: "1.2.3"))
        XCTAssertEqual(UpdateVersion.dismissVersion(info: info, version: "1.2.3")?.dismissedVersion, "1.2.3")
    }

    func testVersionInfoWireShapeUsesRFC3339AndSnakeCase() throws {
        let info = UpdateVersionInfo(
            latestVersion: "1.2.3",
            lastCheckedAt: Date(timeIntervalSince1970: 0),
            dismissedVersion: "1.2.2"
        )

        let data = try JSONEncoder().encode(info)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["latest_version"] as? String, "1.2.3")
        XCTAssertEqual(object["last_checked_at"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(object["dismissed_version"] as? String, "1.2.2")

        let decoded = try JSONDecoder().decode(UpdateVersionInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }
}
