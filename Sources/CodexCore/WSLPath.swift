import Foundation

public enum WSLPath {
    public static func isWSL() -> Bool {
        isWSL(
            environment: ProcessInfo.processInfo.environment,
            procVersion: currentProcVersion(),
            isLinux: currentOSIsLinux
        )
    }

    public static func isWSL(
        environment: [String: String],
        procVersion: String?,
        isLinux: Bool
    ) -> Bool {
        guard isLinux else {
            return false
        }
        if environment["WSL_DISTRO_NAME"] != nil {
            return true
        }
        return procVersion?.lowercased().contains("microsoft") ?? false
    }

    /// Port of codex-rs/cli/src/wsl_paths.rs `win_path_to_wsl`.
    public static func winPathToWSL(_ path: String) -> String? {
        let bytes = Array(path.utf8)
        guard bytes.count >= 3,
              bytes[1] == Character(":").asciiValue,
              bytes[2] == Character("\\").asciiValue || bytes[2] == Character("/").asciiValue,
              isASCIIAlphabetic(bytes[0])
        else {
            return nil
        }

        let drive = Character(UnicodeScalar(bytes[0])).lowercased()
        let tailBytes = bytes.dropFirst(3)
        let tail = String(decoding: tailBytes, as: UTF8.self)
            .replacingOccurrences(of: "\\", with: "/")

        if tail.isEmpty {
            return "/mnt/\(drive)"
        }
        return "/mnt/\(drive)/\(tail)"
    }

    /// Port of codex-rs/cli/src/wsl_paths.rs `normalize_for_wsl`.
    public static func normalizeForWSL(_ path: String, isWSL: Bool = Self.isWSL()) -> String {
        guard isWSL else {
            return path
        }
        return winPathToWSL(path) ?? path
    }

    private static var currentOSIsLinux: Bool {
        #if os(Linux)
            true
        #else
            false
        #endif
    }

    private static func currentProcVersion() -> String? {
        #if os(Linux)
            try? String(contentsOfFile: "/proc/version", encoding: .utf8)
        #else
            nil
        #endif
    }

    private static func isASCIIAlphabetic(_ byte: UInt8) -> Bool {
        (Character("A").asciiValue!...Character("Z").asciiValue!).contains(byte)
            || (Character("a").asciiValue!...Character("z").asciiValue!).contains(byte)
    }
}
