import Foundation

public enum EnvDisplay {
    public static func formatEnvDisplay(
        env: [String: String]?,
        envVars: [String]
    ) -> String {
        var parts: [String] = []

        if let env {
            parts.append(contentsOf: env.keys.sorted().map { "\($0)=*****" })
        }

        parts.append(contentsOf: envVars.map { "\($0)=*****" })

        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }
}
