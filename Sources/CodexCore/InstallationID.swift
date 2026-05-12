import Darwin
import Foundation

public enum InstallationIDResolver {
    public static let fileName = "installation_id"

    public static func resolve(codexHome: URL) throws -> String {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let path = codexHome.appendingPathComponent(fileName, isDirectory: false).path
        let descriptor = Darwin.open(path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

        _ = Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        let contents = try handle.readToEnd() ?? Data()
        let trimmed = String(decoding: contents, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = UUID(uuidString: trimmed) {
            return existing.uuidString.lowercased()
        }

        let installationID = UUID().uuidString.lowercased()
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(installationID.utf8))
        try handle.synchronize()
        return installationID
    }
}
