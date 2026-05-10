import Foundation

public enum AbsolutePathError: Error, Equatable, CustomStringConvertible, Sendable {
    case basePathIsNotAbsolute(String)
    case decodedRelativePathWithoutBase(String)

    public var description: String {
        switch self {
        case let .basePathIsNotAbsolute(path):
            return "Base path is not absolute: \(path)"
        case let .decodedRelativePathWithoutBase(path):
            return "AbsolutePath decoded relative path without a base path: \(path)"
        }
    }
}

public struct AbsolutePath: Equatable, Hashable, Codable, CustomStringConvertible, Sendable {
    public static let decodingBaseUserInfoKey = CodingUserInfoKey(rawValue: "codex.absolutePath.base")!

    public let path: String

    public var description: String { path }

    public init(absolutePath path: String) throws {
        let path = Self.expandingHomeDirectory(in: path)
        guard path.hasPrefix("/") else {
            throw AbsolutePathError.basePathIsNotAbsolute(path)
        }
        self.path = Self.normalizeAbsolute(path)
    }

    public static func resolve(_ path: String, against basePath: String) throws -> AbsolutePath {
        if path.hasPrefix("/") {
            return try AbsolutePath(absolutePath: path)
        }
        guard basePath.hasPrefix("/") else {
            throw AbsolutePathError.basePathIsNotAbsolute(basePath)
        }
        let joined = basePath == "/" ? "/" + path : basePath + "/" + path
        return try AbsolutePath(absolutePath: joined)
    }

    public static func currentDirectory() throws -> AbsolutePath {
        try AbsolutePath(absolutePath: FileManager.default.currentDirectoryPath)
    }

    public func join(_ path: String) throws -> AbsolutePath {
        try Self.resolve(path, against: self.path)
    }

    public var parent: AbsolutePath? {
        guard path != "/" else { return nil }
        let nsParent = (path as NSString).deletingLastPathComponent
        return try? AbsolutePath(absolutePath: nsParent.isEmpty ? "/" : nsParent)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(String.self)
        if decoded.hasPrefix("/") {
            self = try AbsolutePath(absolutePath: decoded)
            return
        }
        guard let basePath = decoder.userInfo[Self.decodingBaseUserInfoKey] as? String else {
            throw AbsolutePathError.decodedRelativePathWithoutBase(decoded)
        }
        self = try Self.resolve(decoded, against: basePath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }

    private static func normalizeAbsolute(_ absolutePath: String) -> String {
        var stack: [String] = []
        for component in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." {
                continue
            }
            if component == ".." {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                continue
            }
            stack.append(String(component))
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }

    private static func expandingHomeDirectory(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }
        let rest = path.dropFirst(2)
        return home + "/" + rest
    }
}
