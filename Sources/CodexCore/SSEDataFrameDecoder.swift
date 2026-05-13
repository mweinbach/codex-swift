import Foundation

public struct SSEDataFrameDecoder: Sendable {
    private var buffer = ""
    private var dataLines: [String] = []

    public init() {}

    public mutating func receive(_ chunk: String) -> [String] {
        buffer.append(chunk)
        var frames: [String] = []

        while let newlineIndex = buffer.firstIndex(where: \.isNewline) {
            let rawLine = String(buffer[..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            process(line: normalizedLine(rawLine), into: &frames)
        }

        return frames
    }

    public mutating func finish() -> [String] {
        buffer.removeAll(keepingCapacity: true)
        dataLines.removeAll(keepingCapacity: true)
        return []
    }

    public static func dataFrames(from text: String) -> [String] {
        var decoder = SSEDataFrameDecoder()
        return decoder.receive(text) + decoder.finish()
    }

    private mutating func process(line: String, into frames: inout [String]) {
        guard !line.isEmpty else {
            flush(into: &frames)
            return
        }

        guard line == "data" || line.hasPrefix("data:") else {
            return
        }

        var data = ""
        if line.hasPrefix("data:") {
            data = String(line.dropFirst("data:".count))
            if data.first == " " {
                data.removeFirst()
            }
        }
        dataLines.append(data)
    }

    private mutating func flush(into frames: inout [String]) {
        guard !dataLines.isEmpty else {
            return
        }
        frames.append(dataLines.joined(separator: "\n"))
        dataLines.removeAll(keepingCapacity: true)
    }

    private func normalizedLine(_ line: String) -> String {
        guard line.last == "\r" else {
            return line
        }
        return String(line.dropLast())
    }
}
