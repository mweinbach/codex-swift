import Foundation

public enum CloudRequirements {
    public static let loadFailedMessage = "Failed to load cloud requirements (workspace-managed policies)."
    public static let parseFailedMessagePrefix = "Cloud requirements (workspace-managed policies) are invalid and could not be parsed. Please contact your workspace admin."

    public static func parse(_ contents: String) throws -> ConfigRequirementsToml? {
        guard contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let requirements = try ConfigRequirementsToml.parse(contents)
        return requirements.isEmpty ? nil : requirements
    }

    public static func parseFailedMessage(details: Error) -> String {
        "\(parseFailedMessagePrefix)\n\nDetails:\n\(details)"
    }
}
