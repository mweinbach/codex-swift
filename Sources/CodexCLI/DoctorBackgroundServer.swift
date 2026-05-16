import CodexCore
import Darwin
import Foundation

public enum DoctorBackgroundFileProbe: Equatable, Sendable {
    case file
    case notFile
    case missing
    case failed(String)
}

public enum DoctorBackgroundSocketProbe: Equatable, Sendable {
    case resolved(path: String, status: DoctorBackgroundSocketStatus)
    case failed(String)
}

public enum DoctorBackgroundSocketStatus: Equatable, Sendable {
    case notRunning
    case running
    case staleOrUnreachable
}

public struct DoctorBackgroundServerCheckInputs: Equatable, Sendable {
    public let codexHomePath: String
    public let settingsFile: DoctorBackgroundFileProbe
    public let pidFile: DoctorBackgroundFileProbe
    public let updatePidFile: DoctorBackgroundFileProbe
    public let controlSocket: DoctorBackgroundSocketProbe

    public init(
        codexHomePath: String,
        settingsFile: DoctorBackgroundFileProbe,
        pidFile: DoctorBackgroundFileProbe,
        updatePidFile: DoctorBackgroundFileProbe,
        controlSocket: DoctorBackgroundSocketProbe
    ) {
        self.codexHomePath = codexHomePath
        self.settingsFile = settingsFile
        self.pidFile = pidFile
        self.updatePidFile = updatePidFile
        self.controlSocket = controlSocket
    }
}

extension DoctorCommandRuntime {
    public static func backgroundServerCheck(codexHome: URL) -> DoctorCheck {
        let stateDir = backgroundServerStateDirectory(codexHomePath: codexHome.path)
        let settingsPath = stateDir.appendingPathComponent(backgroundServerSettingsFilename).path
        let pidPath = stateDir.appendingPathComponent(backgroundServerPidFilename).path
        let updatePidPath = stateDir.appendingPathComponent(backgroundServerUpdatePidFilename).path
        return backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs(
            codexHomePath: codexHome.path,
            settingsFile: backgroundFileProbe(path: settingsPath),
            pidFile: backgroundFileProbe(path: pidPath),
            updatePidFile: backgroundFileProbe(path: updatePidPath),
            controlSocket: backgroundControlSocketProbe(codexHome: codexHome)
        ))
    }

    public static func backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs) -> DoctorCheck {
        let stateDir = backgroundServerStateDirectory(codexHomePath: inputs.codexHomePath)
        let settingsPath = stateDir.appendingPathComponent(backgroundServerSettingsFilename).path
        let pidPath = stateDir.appendingPathComponent(backgroundServerPidFilename).path
        let updatePidPath = stateDir.appendingPathComponent(backgroundServerUpdatePidFilename).path
        var details = [
            "daemon state dir: \(stateDir.path)",
            backgroundFileDetail(label: "settings", path: settingsPath, probe: inputs.settingsFile),
            backgroundFileDetail(label: "pid file", path: pidPath, probe: inputs.pidFile),
            backgroundFileDetail(label: "update-loop pid file", path: updatePidPath, probe: inputs.updatePidFile)
        ]

        switch inputs.controlSocket {
        case let .failed(error):
            return DoctorCheck(
                id: "app_server.status",
                category: "app-server",
                status: .warning,
                summary: "background server socket path could not be resolved",
                details: details + [error]
            )
        case let .resolved(path, socketStatus):
            details.append("control socket: \(path)")
            details.append("status: \(socketStatus.detailLabel)")
            details.append("mode: \(backgroundServerMode(settingsFile: inputs.settingsFile))")
            return DoctorCheck(
                id: "app_server.status",
                category: "app-server",
                status: socketStatus.checkStatus,
                summary: socketStatus.summary,
                details: details,
                remediation: socketStatus.checkStatus == .warning
                    ? "Run codex app-server daemon version for more details."
                    : nil
            )
        }
    }

    private static let backgroundServerStateDirectoryName = "app-server-daemon"
    private static let backgroundServerSettingsFilename = "settings.json"
    private static let backgroundServerPidFilename = "app-server.pid"
    private static let backgroundServerUpdatePidFilename = "app-server-updater.pid"

    private static func backgroundServerStateDirectory(codexHomePath: String) -> URL {
        URL(fileURLWithPath: codexHomePath)
            .appendingPathComponent(backgroundServerStateDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private static func backgroundFileDetail(
        label: String,
        path: String,
        probe: DoctorBackgroundFileProbe
    ) -> String {
        switch probe {
        case .file:
            "\(label): \(path) (file)"
        case .notFile:
            "\(label): \(path) (not a file)"
        case .missing:
            "\(label): \(path) (missing)"
        case let .failed(error):
            "\(label): \(path) (\(error))"
        }
    }

    private static func backgroundServerMode(settingsFile: DoctorBackgroundFileProbe) -> String {
        switch settingsFile {
        case .file:
            "persistent"
        case .notFile, .missing, .failed:
            "ephemeral"
        }
    }

    private static func backgroundFileProbe(path: String) -> DoctorBackgroundFileProbe {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            if attributes[.type] as? FileAttributeType == .typeRegular {
                return .file
            }
            return .notFile
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError
            {
                return .missing
            }
            return .failed(error.localizedDescription)
        }
    }

    private static func backgroundControlSocketProbe(codexHome: URL) -> DoctorBackgroundSocketProbe {
        do {
            guard case let .unixSocket(socketPath) = try AppServerListenURLParser.parse("unix://", codexHome: codexHome) else {
                return .failed("default app-server control socket did not resolve to a unix socket")
            }
            return .resolved(path: socketPath, status: backgroundSocketStatus(path: socketPath))
        } catch {
            return .failed(String(describing: error))
        }
    }

    private static func backgroundSocketStatus(path: String) -> DoctorBackgroundSocketStatus {
        guard FileManager.default.fileExists(atPath: path) else {
            return .notRunning
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return .staleOrUnreachable
        }
        defer { close(fd) }
        do {
            var address = try doctorUnixSocketAddress(path: path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            return result == 0 ? .running : .staleOrUnreachable
        } catch {
            return .staleOrUnreachable
        }
    }
}

private extension DoctorBackgroundSocketStatus {
    var checkStatus: DoctorCheckStatus {
        switch self {
        case .notRunning, .running:
            .ok
        case .staleOrUnreachable:
            .warning
        }
    }

    var summary: String {
        switch self {
        case .notRunning:
            "background server is not running"
        case .running:
            "background server is running"
        case .staleOrUnreachable:
            "background server socket is stale or unreachable"
        }
    }

    var detailLabel: String {
        switch self {
        case .notRunning:
            "not running"
        case .running:
            "running"
        case .staleOrUnreachable:
            "stale or unreachable"
        }
    }
}

private func doctorUnixSocketAddress(path: String) throws -> sockaddr_un {
    let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    let encodedPath = Array(path.utf8CString)
    guard encodedPath.count <= maxPathLength else {
        throw DoctorBackgroundSocketPathError.pathTooLong
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { buffer in
            for index in encodedPath.indices {
                buffer[index] = CChar(encodedPath[index])
            }
        }
    }
    return address
}

private enum DoctorBackgroundSocketPathError: Error {
    case pathTooLong
}
