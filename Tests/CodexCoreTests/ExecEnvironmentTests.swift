import CodexCore
import XCTest

final class ExecEnvironmentTests: XCTestCase {
    func testDefaultPolicyInheritsAllAndKeepsSensitiveVars() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("HOME", "/home/user"),
            ("API_KEY", "secret"),
            ("SECRET_TOKEN", "t")
        ])

        let result = ExecEnvironment.populateEnv(vars, policy: ShellEnvironmentPolicy())

        XCTAssertEqual(result, vars)
    }

    func testDefaultExcludesCanRemoveSensitiveVars() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("HOME", "/home/user"),
            ("API_KEY", "secret"),
            ("SECRET_TOKEN", "t"),
            ("github_token", "lower")
        ])

        let result = ExecEnvironment.populateEnv(
            vars,
            policy: ShellEnvironmentPolicy(ignoreDefaultExcludes: false)
        )

        XCTAssertEqual(result, [
            "PATH": "/usr/bin",
            "HOME": "/home/user"
        ])
    }

    func testIncludeOnlyRunsAfterSetOverrides() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("FOO", "bar")
        ])
        let policy = ShellEnvironmentPolicy(
            set: [
                "NEW_VAR": "42",
                "DROP_ME": "no"
            ],
            includeOnly: [.newCaseInsensitive("*PATH"), .newCaseInsensitive("NEW_*")]
        )

        let result = ExecEnvironment.populateEnv(vars, policy: policy)

        XCTAssertEqual(result, [
            "PATH": "/usr/bin",
            "NEW_VAR": "42"
        ])
    }

    func testSetOverridesInheritedValues() {
        let vars = makeVars([
            ("PATH", "/usr/bin")
        ])
        let policy = ShellEnvironmentPolicy(set: [
            "PATH": "/custom/bin",
            "NEW_VAR": "42"
        ])

        let result = ExecEnvironment.populateEnv(vars, policy: policy)

        XCTAssertEqual(result, [
            "PATH": "/custom/bin",
            "NEW_VAR": "42"
        ])
    }

    func testInheritNoneStartsEmptyThenAppliesSet() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("HOME", "/home")
        ])
        let policy = ShellEnvironmentPolicy(
            inherit: .none,
            set: ["ONLY_VAR": "yes"]
        )

        let result = ExecEnvironment.populateEnv(vars, policy: policy)

        XCTAssertEqual(result, ["ONLY_VAR": "yes"])
    }

    func testCoreInheritKeepsRustCoreVarsOnly() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("HOME", "/home"),
            ("LOGNAME", "me"),
            ("SHELL", "/bin/zsh"),
            ("USER", "me"),
            ("USERNAME", "me2"),
            ("TMPDIR", "/tmp/dir"),
            ("TEMP", "/tmp/temp"),
            ("TMP", "/tmp/tmp"),
            ("PWD", "/workspace")
        ])

        let result = ExecEnvironment.populateEnv(
            vars,
            policy: ShellEnvironmentPolicy(inherit: .core)
        )

        XCTAssertEqual(result, [
            "PATH": "/usr/bin",
            "HOME": "/home",
            "LOGNAME": "me",
            "SHELL": "/bin/zsh",
            "USER": "me",
            "USERNAME": "me2",
            "TMPDIR": "/tmp/dir",
            "TEMP": "/tmp/temp",
            "TMP": "/tmp/tmp"
        ])
    }

    func testCustomExcludeUsesCaseInsensitiveWildcards() {
        let vars = makeVars([
            ("PATH", "/usr/bin"),
            ("FOO_PATH", "/foo"),
            ("APP_MODE", "test"),
            ("APPLE_MODE", "prod")
        ])
        let policy = ShellEnvironmentPolicy(exclude: [
            .newCaseInsensitive("*path"),
            .newCaseInsensitive("APP??_MODE")
        ])

        let result = ExecEnvironment.populateEnv(vars, policy: policy)

        XCTAssertEqual(result, ["APP_MODE": "test"])
    }

    func testTomlPolicyAppliesRustDefaultsAndPatternConversion() {
        let toml = ShellEnvironmentPolicyToml(
            inherit: ShellEnvironmentPolicyInherit.none,
            ignoreDefaultExcludes: nil,
            exclude: ["*secret*"],
            set: ["SECRET_NAME": "drop", "SAFE": "keep"],
            includeOnly: ["safe"],
            experimentalUseProfile: true
        )

        let policy = ShellEnvironmentPolicy(toml: toml)
        let result = ExecEnvironment.populateEnv(["SECRET_INPUT": "drop"], policy: policy)

        XCTAssertTrue(policy.ignoreDefaultExcludes)
        XCTAssertTrue(policy.useProfile)
        XCTAssertEqual(result, ["SAFE": "keep"])
    }

    private func makeVars(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: pairs)
    }
}
