public enum DoctorCommandRuntime {
    public static var npmGlobalRootArguments: [String] {
        ["root", "-g"]
    }

    public static func npmGlobalRootCommand() -> String {
        npmGlobalRootCommand(isWindows: currentOSIsWindows)
    }

    public static func npmGlobalRootCommand(isWindows: Bool) -> String {
        isWindows ? "npm.cmd" : "npm"
    }

    private static var currentOSIsWindows: Bool {
        #if os(Windows)
            true
        #else
            false
        #endif
    }
}
