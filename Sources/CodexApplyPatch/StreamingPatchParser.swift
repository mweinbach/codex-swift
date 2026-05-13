import Foundation

public struct StreamingPatchParser: Equatable, Sendable {
    private var lineBuffer = ""
    private var state = StreamingParserState()
    private var lineNumber = 0

    public init() {}

    public mutating func pushDelta(delta: String) throws -> [Hunk] {
        for scalar in delta.unicodeScalars {
            if scalar == "\n" {
                var line = lineBuffer
                lineBuffer.removeAll(keepingCapacity: true)
                if line.last == "\r" {
                    line.removeLast()
                }
                lineNumber += 1
                try processLine(line)
            } else {
                lineBuffer.unicodeScalars.append(scalar)
            }
        }
        return state.hunks
    }

    public mutating func finish() throws -> [Hunk] {
        if !lineBuffer.isEmpty {
            let line = lineBuffer
            lineBuffer.removeAll(keepingCapacity: true)
            lineNumber += 1
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == streamingEndPatchMarker {
                try ensureUpdateHunkIsNotEmpty(line.trimmingCharacters(in: .whitespacesAndNewlines))
                state.mode = .endedPatch
            } else {
                try processLine(line)
            }
        }

        guard state.mode == .endedPatch else {
            throw ApplyPatchError.invalidPatch("The last line of the patch must be '*** End Patch'")
        }
        return state.hunks
    }

    private func ensureUpdateHunkIsNotEmpty(_ line: String) throws {
        guard case let .updateFile(path, _, chunks) = state.hunks.last else {
            return
        }

        if chunks.isEmpty, case let .updateFile(hunkLineNumber) = state.mode {
            throw ApplyPatchError.invalidHunk(
                message: "Update file hunk for path '\(path)' is empty",
                lineNumber: hunkLineNumber
            )
        }

        if let chunk = chunks.last,
           chunk.oldLines.isEmpty,
           chunk.newLines.isEmpty {
            if line == streamingEndPatchMarker {
                throw ApplyPatchError.invalidHunk(
                    message: "Update hunk does not contain any lines",
                    lineNumber: lineNumber
                )
            }
            throw ApplyPatchError.invalidHunk(
                message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: lineNumber
            )
        }
    }

    private mutating func handleHunkHeadersAndEndPatch(_ line: String) throws -> Bool {
        if line == streamingEndPatchMarker {
            try ensureUpdateHunkIsNotEmpty(line)
            state.mode = .endedPatch
            return true
        }
        if let path = line.removingStreamingPrefix(streamingAddFileMarker) {
            try ensureUpdateHunkIsNotEmpty(line)
            state.hunks.append(.addFile(path: path, contents: ""))
            state.mode = .addFile
            return true
        }
        if let path = line.removingStreamingPrefix(streamingDeleteFileMarker) {
            try ensureUpdateHunkIsNotEmpty(line)
            state.hunks.append(.deleteFile(path: path))
            state.mode = .deleteFile
            return true
        }
        if let path = line.removingStreamingPrefix(streamingUpdateFileMarker) {
            try ensureUpdateHunkIsNotEmpty(line)
            state.hunks.append(.updateFile(path: path, movePath: nil, chunks: []))
            state.mode = .updateFile(hunkLineNumber: lineNumber)
            return true
        }
        return false
    }

    private mutating func processLine(_ line: String) throws {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.mode {
        case .notStarted:
            guard trimmed == streamingBeginPatchMarker else {
                throw ApplyPatchError.invalidPatch("The first line of the patch must be '*** Begin Patch'")
            }
            state.mode = .startedPatch

        case .startedPatch:
            guard try handleHunkHeadersAndEndPatch(trimmed) else {
                throw invalidHeaderError(trimmed)
            }

        case .addFile:
            if try handleHunkHeadersAndEndPatch(trimmed) {
                return
            }
            guard let lineToAdd = line.removingStreamingPrefix("+"),
                  case let .addFile(path, contents) = state.hunks.last
            else {
                throw invalidHeaderError(trimmed)
            }
            state.hunks[state.hunks.count - 1] = .addFile(path: path, contents: contents + lineToAdd + "\n")

        case .deleteFile:
            guard try handleHunkHeadersAndEndPatch(trimmed) else {
                throw invalidHeaderError(trimmed)
            }

        case let .updateFile(hunkLineNumber):
            try processUpdateLine(line, hunkLineNumber: hunkLineNumber)

        case .endedPatch:
            return
        }
    }

    private mutating func processUpdateLine(_ line: String, hunkLineNumber: Int) throws {
        let updateLine = line.streamingTrimmedEnd()
        if try handleHunkHeadersAndEndPatch(updateLine) {
            return
        }

        guard case let .updateFile(path, movePath, chunks) = state.hunks.last else {
            throw unexpectedUpdateLineError(line)
        }

        var nextMovePath = movePath
        var nextChunks = chunks

        if nextChunks.isEmpty,
           nextMovePath == nil,
           let parsedMovePath = updateLine.removingStreamingPrefix(streamingMoveToMarker) {
            nextMovePath = parsedMovePath
            replaceLastHunk(.updateFile(path: path, movePath: nextMovePath, chunks: nextChunks))
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if (updateLine == streamingEmptyChangeContextMarker || updateLine.hasPrefix(streamingChangeContextMarker)),
           nextChunks.last.map({ $0.oldLines.isEmpty && $0.newLines.isEmpty }) == true {
            throw ApplyPatchError.invalidHunk(
                message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: lineNumber
            )
        }

        if updateLine == streamingEmptyChangeContextMarker {
            nextChunks.append(UpdateFileChunk(
                changeContext: nil,
                oldLines: [],
                newLines: [],
                isEndOfFile: false
            ))
            replaceLastHunk(.updateFile(path: path, movePath: nextMovePath, chunks: nextChunks))
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let context = updateLine.removingStreamingPrefix(streamingChangeContextMarker) {
            nextChunks.append(UpdateFileChunk(
                changeContext: context,
                oldLines: [],
                newLines: [],
                isEndOfFile: false
            ))
            replaceLastHunk(.updateFile(path: path, movePath: nextMovePath, chunks: nextChunks))
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if updateLine == streamingEOFMarker {
            if nextChunks.last.map({ $0.oldLines.isEmpty && $0.newLines.isEmpty }) == true {
                throw ApplyPatchError.invalidHunk(
                    message: "Update hunk does not contain any lines",
                    lineNumber: lineNumber
                )
            }
            if let last = nextChunks.last {
                nextChunks[nextChunks.count - 1] = UpdateFileChunk(
                    changeContext: last.changeContext,
                    oldLines: last.oldLines,
                    newLines: last.newLines,
                    isEndOfFile: true
                )
            }
            replaceLastHunk(.updateFile(path: path, movePath: nextMovePath, chunks: nextChunks))
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if line.isEmpty {
            appendUpdateContextLine(
                "",
                path: path,
                movePath: nextMovePath,
                chunks: &nextChunks,
                hunkLineNumber: hunkLineNumber
            )
            return
        }

        if let lineToAdd = line.removingStreamingPrefix(" ") {
            appendUpdateContextLine(
                lineToAdd,
                path: path,
                movePath: nextMovePath,
                chunks: &nextChunks,
                hunkLineNumber: hunkLineNumber
            )
            return
        }

        if let lineToAdd = line.removingStreamingPrefix("+") {
            appendUpdateLine(
                newLine: lineToAdd,
                path: path,
                movePath: nextMovePath,
                chunks: &nextChunks,
                hunkLineNumber: hunkLineNumber
            )
            return
        }

        if let lineToRemove = line.removingStreamingPrefix("-") {
            appendUpdateLine(
                oldLine: lineToRemove,
                path: path,
                movePath: nextMovePath,
                chunks: &nextChunks,
                hunkLineNumber: hunkLineNumber
            )
            return
        }

        if nextChunks.last.map({ !$0.oldLines.isEmpty || !$0.newLines.isEmpty }) == true {
            throw ApplyPatchError.invalidHunk(
                message: "Expected update hunk to start with a @@ context marker, got: '\(line)'",
                lineNumber: lineNumber
            )
        }

        throw unexpectedUpdateLineError(line)
    }

    private mutating func appendUpdateContextLine(
        _ line: String,
        path: String,
        movePath: String?,
        chunks: inout [UpdateFileChunk],
        hunkLineNumber: Int
    ) {
        ensureUpdateChunkExists(chunks: &chunks)
        let last = chunks[chunks.count - 1]
        chunks[chunks.count - 1] = UpdateFileChunk(
            changeContext: last.changeContext,
            oldLines: last.oldLines + [line],
            newLines: last.newLines + [line],
            isEndOfFile: last.isEndOfFile
        )
        replaceLastHunk(.updateFile(path: path, movePath: movePath, chunks: chunks))
        state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
    }

    private mutating func appendUpdateLine(
        oldLine: String? = nil,
        newLine: String? = nil,
        path: String,
        movePath: String?,
        chunks: inout [UpdateFileChunk],
        hunkLineNumber: Int
    ) {
        ensureUpdateChunkExists(chunks: &chunks)
        let last = chunks[chunks.count - 1]
        chunks[chunks.count - 1] = UpdateFileChunk(
            changeContext: last.changeContext,
            oldLines: oldLine.map { last.oldLines + [$0] } ?? last.oldLines,
            newLines: newLine.map { last.newLines + [$0] } ?? last.newLines,
            isEndOfFile: last.isEndOfFile
        )
        replaceLastHunk(.updateFile(path: path, movePath: movePath, chunks: chunks))
        state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
    }

    private func ensureUpdateChunkExists(chunks: inout [UpdateFileChunk]) {
        if chunks.isEmpty {
            chunks.append(UpdateFileChunk(
                changeContext: nil,
                oldLines: [],
                newLines: [],
                isEndOfFile: false
            ))
        }
    }

    private mutating func replaceLastHunk(_ hunk: Hunk) {
        state.hunks[state.hunks.count - 1] = hunk
    }

    private func invalidHeaderError(_ line: String) -> ApplyPatchError {
        .invalidHunk(
            message: "'\(line)' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
            lineNumber: lineNumber
        )
    }

    private func unexpectedUpdateLineError(_ line: String) -> ApplyPatchError {
        .invalidHunk(
            message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
            lineNumber: lineNumber
        )
    }
}

private struct StreamingParserState: Equatable, Sendable {
    var mode: StreamingParserMode = .notStarted
    var hunks: [Hunk] = []
}

private enum StreamingParserMode: Equatable, Sendable {
    case notStarted
    case startedPatch
    case addFile
    case deleteFile
    case updateFile(hunkLineNumber: Int)
    case endedPatch
}

private let streamingBeginPatchMarker = "*** Begin Patch"
private let streamingEndPatchMarker = "*** End Patch"
private let streamingAddFileMarker = "*** Add File: "
private let streamingDeleteFileMarker = "*** Delete File: "
private let streamingUpdateFileMarker = "*** Update File: "
private let streamingMoveToMarker = "*** Move to: "
private let streamingEOFMarker = "*** End of File"
private let streamingChangeContextMarker = "@@ "
private let streamingEmptyChangeContextMarker = "@@"

private extension String {
    func removingStreamingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }

    func streamingTrimmedEnd() -> String {
        var result = self
        while let last = result.last, last.isWhitespace {
            result.removeLast()
        }
        return result
    }
}
