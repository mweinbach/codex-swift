import Foundation

public enum CodexEnvironmentFlags {
    public static let sseFixtureEnvironmentVariable = "CODEX_RS_SSE_FIXTURE"

    public static func sseFixturePath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        environment[sseFixtureEnvironmentVariable]
    }
}
