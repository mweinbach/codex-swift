import Foundation
import PackagePlugin

@main
struct CodexBuildMetadataPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appending(
            path: "Generated",
            directoryHint: .isDirectory
        )
        let outputFile = outputDirectory.appending(path: "CodexBuildMetadata.swift")
        let generator = context.package.directoryURL.appending(
            path: "scripts/generate-build-metadata.sh"
        )
        let buildEnvironment = [
            "CODEX_SWIFT_VERSION",
            "CODEX_VERSION",
            "CODEX_BUILD_COMMIT",
            "GITHUB_SHA",
            "GITHUB_REF_NAME"
        ].reduce(into: [String: String]()) { values, key in
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                values[key] = value
            }
        }

        return [
            .prebuildCommand(
                displayName: "Generate Codex build metadata",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    generator.path,
                    "--package-directory",
                    context.package.directoryURL.path,
                    "--output",
                    outputFile.path
                ],
                environment: buildEnvironment,
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
