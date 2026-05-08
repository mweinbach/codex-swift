import CodexCore
import XCTest

final class RolloutErrorTests: XCTestCase {
    func testPermissionDeniedMapsToOwnershipHint() {
        let error = RolloutErrors.mapRolloutIOError(
            RolloutIOFailure(kind: .permissionDenied, underlyingDescription: "permission denied"),
            codexHome: codexHome
        )

        XCTAssertEqual(
            error?.description,
            "Codex cannot access session files at /tmp/codex-home/sessions (permission denied). If sessions were created using sudo, fix ownership: sudo chown -R $(whoami) /tmp/codex-home (underlying error: permission denied)"
        )
    }

    func testKnownIOErrorKindsMapToRustHints() {
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .notFound, underlyingDescription: "not found"),
                codexHome: codexHome
            )?.description,
            "Session storage missing at /tmp/codex-home/sessions. Create the directory or choose a different Codex home. (underlying error: not found)"
        )
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .alreadyExists, underlyingDescription: "already exists"),
                codexHome: codexHome
            )?.description,
            "Session storage path /tmp/codex-home/sessions is blocked by an existing file. Remove or rename it so Codex can create sessions. (underlying error: already exists)"
        )
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .invalidData, underlyingDescription: "invalid data"),
                codexHome: codexHome
            )?.description,
            "Session data under /tmp/codex-home/sessions looks corrupt or unreadable. Clearing the sessions directory may help (this will remove saved conversations). (underlying error: invalid data)"
        )
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .invalidInput, underlyingDescription: "invalid input"),
                codexHome: codexHome
            )?.description,
            "Session data under /tmp/codex-home/sessions looks corrupt or unreadable. Clearing the sessions directory may help (this will remove saved conversations). (underlying error: invalid input)"
        )
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .isDirectory, underlyingDescription: "is a directory"),
                codexHome: codexHome
            )?.description,
            "Session storage path /tmp/codex-home/sessions has an unexpected type. Ensure it is a directory Codex can use for session files. (underlying error: is a directory)"
        )
        XCTAssertEqual(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .notDirectory, underlyingDescription: "not a directory"),
                codexHome: codexHome
            )?.description,
            "Session storage path /tmp/codex-home/sessions has an unexpected type. Ensure it is a directory Codex can use for session files. (underlying error: not a directory)"
        )
        XCTAssertNil(
            RolloutErrors.mapRolloutIOError(
                RolloutIOFailure(kind: .other, underlyingDescription: "other"),
                codexHome: codexHome
            )
        )
    }

    func testSessionInitErrorUsesFirstMappedIOCauseOrFallback() {
        let mapped = RolloutErrors.mapSessionInitError(
            RolloutSessionInitFailure(
                description: "outer failure",
                causes: [
                    RolloutIOFailure(kind: .other, underlyingDescription: "other"),
                    RolloutIOFailure(kind: .notFound, underlyingDescription: "missing")
                ]
            ),
            codexHome: codexHome
        )
        XCTAssertEqual(
            mapped.description,
            "Session storage missing at /tmp/codex-home/sessions. Create the directory or choose a different Codex home. (underlying error: missing)"
        )

        let fallback = RolloutErrors.mapSessionInitError(
            RolloutSessionInitFailure(description: "outer failure: inner failure"),
            codexHome: codexHome
        )
        XCTAssertEqual(
            fallback.description,
            "Failed to initialize session: outer failure: inner failure"
        )
    }

    private var codexHome: URL {
        URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
    }
}
