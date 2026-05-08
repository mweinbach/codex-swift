import Darwin
import Foundation

@_silgen_name("ptrace")
private func codexPtrace(
    _ request: Int32,
    _ pid: pid_t,
    _ address: UnsafeMutableRawPointer?,
    _ data: Int32
) -> Int32

@_silgen_name("_NSGetEnviron")
private func codexNSGetEnviron() -> UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>?

public enum ProcessHardening {
    public static let ptraceDenyAttachFailedExitCode: Int32 = 6
    public static let setRLimitCoreFailedExitCode: Int32 = 7

    private static let ptDenyAttach: Int32 = 31

    public struct MacOSActions {
        public let denyDebuggerAttach: () -> Int32
        public let setCoreFileSizeLimitToZero: () -> Int32
        public let environmentKeysWithPrefix: ([UInt8]) -> [[UInt8]]
        public let removeEnvironmentVariable: ([UInt8]) -> Void
        public let lastErrorDescription: () -> String

        public init(
            denyDebuggerAttach: @escaping () -> Int32,
            setCoreFileSizeLimitToZero: @escaping () -> Int32,
            environmentKeysWithPrefix: @escaping ([UInt8]) -> [[UInt8]],
            removeEnvironmentVariable: @escaping ([UInt8]) -> Void,
            lastErrorDescription: @escaping () -> String
        ) {
            self.denyDebuggerAttach = denyDebuggerAttach
            self.setCoreFileSizeLimitToZero = setCoreFileSizeLimitToZero
            self.environmentKeysWithPrefix = environmentKeysWithPrefix
            self.removeEnvironmentVariable = removeEnvironmentVariable
            self.lastErrorDescription = lastErrorDescription
        }
    }

    public enum Failure: Equatable, CustomStringConvertible, Sendable {
        case ptraceDenyAttach(message: String)
        case setRLimitCore(message: String)

        public var exitCode: Int32 {
            switch self {
            case .ptraceDenyAttach:
                ProcessHardening.ptraceDenyAttachFailedExitCode
            case .setRLimitCore:
                ProcessHardening.setRLimitCoreFailedExitCode
            }
        }

        public var description: String {
            switch self {
            case let .ptraceDenyAttach(message):
                "ptrace(PT_DENY_ATTACH) failed: \(message)"
            case let .setRLimitCore(message):
                "setrlimit(RLIMIT_CORE) failed: \(message)"
            }
        }
    }

    public static func preMainHardening() {
        if let failure = runMacOSHardening(actions: .live) {
            fputs("ERROR: \(failure.description)\n", Darwin.stderr)
            Darwin.exit(failure.exitCode)
        }
    }

    public static func runMacOSHardening(actions: MacOSActions) -> Failure? {
        if actions.denyDebuggerAttach() == -1 {
            return .ptraceDenyAttach(message: actions.lastErrorDescription())
        }

        if actions.setCoreFileSizeLimitToZero() != 0 {
            return .setRLimitCore(message: actions.lastErrorDescription())
        }

        for key in actions.environmentKeysWithPrefix(Array("DYLD_".utf8)) {
            actions.removeEnvironmentVariable(key)
        }

        return nil
    }

    public static func environmentKeysWithPrefix(
        _ variables: [(key: [UInt8], value: [UInt8])],
        prefix: [UInt8]
    ) -> [[UInt8]] {
        variables.compactMap { variable in
            variable.key.starts(with: prefix) ? variable.key : nil
        }
    }

    private static func denyDebuggerAttach() -> Int32 {
        codexPtrace(ptDenyAttach, 0, nil, 0)
    }

    private static func setCoreFileSizeLimitToZero() -> Int32 {
        var limit = rlimit(rlim_cur: 0, rlim_max: 0)
        return setrlimit(RLIMIT_CORE, &limit)
    }

    private static func currentEnvironmentKeysWithPrefix(_ prefix: [UInt8]) -> [[UInt8]] {
        environmentKeysWithPrefix(currentEnvironment(), prefix: prefix)
    }

    private static func currentEnvironment() -> [(key: [UInt8], value: [UInt8])] {
        guard let environmentPointer = codexNSGetEnviron(),
              let environment = environmentPointer.pointee
        else {
            return []
        }

        var variables: [(key: [UInt8], value: [UInt8])] = []
        var index = 0
        while let entry = environment[index] {
            let bytes = bytes(fromCString: entry)
            if let separator = bytes.firstIndex(of: UInt8(ascii: "=")) {
                variables.append((
                    key: Array(bytes[..<separator]),
                    value: Array(bytes[bytes.index(after: separator)...])
                ))
            }
            index += 1
        }
        return variables
    }

    private static func bytes(fromCString pointer: UnsafePointer<CChar>) -> [UInt8] {
        var result: [UInt8] = []
        var cursor = pointer
        while cursor.pointee != 0 {
            result.append(UInt8(bitPattern: cursor.pointee))
            cursor = cursor.advanced(by: 1)
        }
        return result
    }

    private static func removeEnvironmentVariable(_ key: [UInt8]) {
        guard !key.isEmpty else {
            return
        }
        let nulTerminated = key.map(CChar.init(bitPattern:)) + [0]
        nulTerminated.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                _ = unsetenv(baseAddress)
            }
        }
    }

    private static func lastOSErrorDescription() -> String {
        String(cString: strerror(errno))
    }
}

extension ProcessHardening.MacOSActions {
    public static var live: ProcessHardening.MacOSActions {
        ProcessHardening.MacOSActions(
            denyDebuggerAttach: ProcessHardening.denyDebuggerAttach,
            setCoreFileSizeLimitToZero: ProcessHardening.setCoreFileSizeLimitToZero,
            environmentKeysWithPrefix: ProcessHardening.currentEnvironmentKeysWithPrefix,
            removeEnvironmentVariable: ProcessHardening.removeEnvironmentVariable,
            lastErrorDescription: ProcessHardening.lastOSErrorDescription
        )
    }
}
