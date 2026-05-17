import Foundation

public enum PathUtils {
    public static func normalizeForPathComparison(
        _ path: String,
        isWSL: Bool = WSLPath.isWSL()
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return normalizeForWSLComparisonPath(canonical, isWSL: isWSL)
    }

    public static func pathsMatchAfterNormalization(
        _ left: String,
        _ right: String,
        isWSL: Bool = WSLPath.isWSL()
    ) -> Bool {
        if let normalizedLeft = try? normalizeForPathComparison(left, isWSL: isWSL),
           let normalizedRight = try? normalizeForPathComparison(right, isWSL: isWSL)
        {
            return normalizedLeft == normalizedRight
        }
        return left == right
    }

    public static func normalizeForNativeWorkdir(_ path: String) -> String {
        normalizeForNativeWorkdir(path, isWindows: currentPlatformIsWindows())
    }

    public static func normalizeForNativeWorkdir(_ path: String, isWindows: Bool) -> String {
        guard isWindows else {
            return path
        }

        let verbatimPrefix = #"\\?\"#
        if path.hasPrefix(verbatimPrefix) {
            return String(path.dropFirst(verbatimPrefix.count))
        }
        return path
    }

    public static func normalizeForWSLComparisonPath(_ path: String, isWSL: Bool = WSLPath.isWSL()) -> String {
        guard isWSL, isWSLCaseInsensitivePath(path) else {
            return path
        }
        return lowerASCII(path)
    }

    public static func isWSLCaseInsensitivePath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2,
              asciiEqualsIgnoreCase(components[0], "mnt")
        else {
            return false
        }

        let drive = components[1].utf8
        return drive.count == 1 && isASCIIAlphabetic(drive[drive.startIndex])
    }

    private static func asciiEqualsIgnoreCase(_ left: Substring, _ right: StaticString) -> Bool {
        let leftBytes = Array(left.utf8)
        let rightBytes = right.withUTF8Buffer { Array($0) }
        guard leftBytes.count == rightBytes.count else {
            return false
        }
        return zip(leftBytes, rightBytes).allSatisfy { lowerASCII($0) == lowerASCII($1) }
    }

    private static func lowerASCII(_ path: String) -> String {
        String(decoding: path.utf8.map(lowerASCII(_:)), as: UTF8.self)
    }

    private static func lowerASCII(_ byte: UInt8) -> UInt8 {
        if (Character("A").asciiValue!...Character("Z").asciiValue!).contains(byte) {
            return byte + 32
        }
        return byte
    }

    private static func isASCIIAlphabetic(_ byte: UInt8) -> Bool {
        (Character("A").asciiValue!...Character("Z").asciiValue!).contains(byte)
            || (Character("a").asciiValue!...Character("z").asciiValue!).contains(byte)
    }

    private static func currentPlatformIsWindows() -> Bool {
        #if os(Windows)
            true
        #else
            false
        #endif
    }
}
