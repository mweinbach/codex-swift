import Foundation

public enum UTF8StreamDecoderError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidUTF8(message: String)

    public var description: String {
        switch self {
        case let .invalidUTF8(message):
            "UTF8 error: \(message)"
        }
    }
}

public struct UTF8StreamDecoder: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func receive(_ data: Data) -> String {
        pending.append(data)
        let validByteCount = Self.validUTF8PrefixLength(in: pending)
        guard validByteCount > 0 else {
            return ""
        }

        let decoded = String(decoding: pending.prefix(validByteCount), as: UTF8.self)
        pending.removeFirst(validByteCount)
        return decoded
    }

    public mutating func finish() throws -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        guard !pending.isEmpty else {
            return ""
        }
        if let error = Self.firstUTF8Error(in: pending) {
            throw UTF8StreamDecoderError.invalidUTF8(message: Self.rustErrorMessage(for: error))
        }
        return String(decoding: pending, as: UTF8.self)
    }

    private static func validUTF8PrefixLength(in data: Data) -> Int {
        firstUTF8Error(in: data)?.validUpTo ?? data.count
    }

    private struct UTF8ErrorLocation: Equatable {
        var validUpTo: Int
        var errorLength: Int?
    }

    private static func firstUTF8Error(in data: Data) -> UTF8ErrorLocation? {
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                index += 1
                continue
            }

            let length: Int
            let secondByteRange: ClosedRange<UInt8>
            switch byte {
            case 0xC2...0xDF:
                length = 2
                secondByteRange = 0x80...0xBF
            case 0xE0:
                length = 3
                secondByteRange = 0xA0...0xBF
            case 0xE1...0xEC:
                length = 3
                secondByteRange = 0x80...0xBF
            case 0xED:
                length = 3
                secondByteRange = 0x80...0x9F
            case 0xEE...0xEF:
                length = 3
                secondByteRange = 0x80...0xBF
            case 0xF0:
                length = 4
                secondByteRange = 0x90...0xBF
            case 0xF1...0xF3:
                length = 4
                secondByteRange = 0x80...0xBF
            case 0xF4:
                length = 4
                secondByteRange = 0x80...0x8F
            default:
                return UTF8ErrorLocation(validUpTo: index, errorLength: 1)
            }

            guard index + 1 < bytes.count else {
                return UTF8ErrorLocation(validUpTo: index, errorLength: nil)
            }
            guard secondByteRange.contains(bytes[index + 1]) else {
                return UTF8ErrorLocation(validUpTo: index, errorLength: 1)
            }

            if length > 2 {
                for offset in 2..<length {
                    guard index + offset < bytes.count else {
                        return UTF8ErrorLocation(validUpTo: index, errorLength: nil)
                    }
                    guard (0x80...0xBF).contains(bytes[index + offset]) else {
                        return UTF8ErrorLocation(validUpTo: index, errorLength: 1)
                    }
                }
            }

            index += length
        }

        return nil
    }

    private static func rustErrorMessage(for error: UTF8ErrorLocation) -> String {
        if let errorLength = error.errorLength {
            return "invalid utf-8 sequence of \(errorLength) bytes from index \(error.validUpTo)"
        }
        return "incomplete utf-8 byte sequence from index \(error.validUpTo)"
    }
}
