import Foundation

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

    public mutating func finish() -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }

    private static func validUTF8PrefixLength(in data: Data) -> Int {
        guard !data.isEmpty else {
            return 0
        }

        for droppedSuffixLength in 0...min(3, data.count) {
            let candidateLength = data.count - droppedSuffixLength
            if String(data: data.prefix(candidateLength), encoding: .utf8) != nil {
                return candidateLength
            }
        }

        return 0
    }
}
