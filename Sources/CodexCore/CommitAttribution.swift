public enum CommitAttribution {
    public static let defaultAttributionValue = "Codex <noreply@openai.com>"

    public static func resolvedAttributionValue(configAttribution: String?) -> String? {
        guard let configAttribution else {
            return defaultAttributionValue
        }

        let trimmed = configAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func commitMessageTrailer(configAttribution: String?) -> String? {
        guard let value = resolvedAttributionValue(configAttribution: configAttribution) else {
            return nil
        }
        return "Co-authored-by: \(value)"
    }

    public static func commitMessageTrailerInstruction(configAttribution: String?) -> String? {
        guard let trailer = commitMessageTrailer(configAttribution: configAttribution) else {
            return nil
        }
        return """
        When you write or edit a git commit message, ensure the message ends with this trailer exactly once:
        \(trailer)

        Rules:
        - Keep existing trailers and append this trailer at the end if missing.
        - Do not duplicate this trailer if it already exists.
        - Keep one blank line between the commit body and trailer block.
        """
    }
}
