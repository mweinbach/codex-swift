import Foundation

public enum CodexPrompts {
    public static let computerUsePrompt = loadMarkdownResource(
        name: "computer_use_prompt",
        subdirectory: "Prompts"
    )

    private static func loadMarkdownResource(name: String, subdirectory: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "md")
        guard let url else {
            preconditionFailure("Missing bundled prompt resource \(subdirectory)/\(name).md")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to load bundled prompt resource \(subdirectory)/\(name).md: \(error)")
        }
    }
}
