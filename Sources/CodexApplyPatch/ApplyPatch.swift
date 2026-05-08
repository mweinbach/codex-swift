import Foundation

public enum ApplyPatchError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidPatch(String)
    case invalidHunk(message: String, lineNumber: Int)
    case io(String)
    case computeReplacements(String)

    public var description: String {
        switch self {
        case let .invalidPatch(message):
            return "Invalid patch: \(message)"
        case let .invalidHunk(message, lineNumber):
            return "Invalid patch hunk on line \(lineNumber): \(message)"
        case let .io(message), let .computeReplacements(message):
            return message
        }
    }
}

public struct UpdateFileChunk: Equatable, Sendable {
    public let changeContext: String?
    public let oldLines: [String]
    public let newLines: [String]
    public let isEndOfFile: Bool

    public init(
        changeContext: String?,
        oldLines: [String],
        newLines: [String],
        isEndOfFile: Bool
    ) {
        self.changeContext = changeContext
        self.oldLines = oldLines
        self.newLines = newLines
        self.isEndOfFile = isEndOfFile
    }
}

public enum Hunk: Equatable, Sendable {
    case addFile(path: String, contents: String)
    case deleteFile(path: String)
    case updateFile(path: String, movePath: String?, chunks: [UpdateFileChunk])
}

public struct ApplyPatchArgs: Equatable, Sendable {
    public let patch: String
    public let hunks: [Hunk]
    public let workdir: String?
}

public struct ApplyPatchResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
}

public struct AffectedPaths: Equatable, Sendable {
    public var added: [String] = []
    public var modified: [String] = []
    public var deleted: [String] = []
}

public enum ApplyPatch {
    private static let beginPatchMarker = "*** Begin Patch"
    private static let endPatchMarker = "*** End Patch"
    private static let addFileMarker = "*** Add File: "
    private static let deleteFileMarker = "*** Delete File: "
    private static let updateFileMarker = "*** Update File: "
    private static let moveToMarker = "*** Move to: "
    private static let eofMarker = "*** End of File"
    private static let changeContextMarker = "@@ "
    private static let emptyChangeContextMarker = "@@"

    public static func parsePatch(_ patch: String) throws -> ApplyPatchArgs {
        try parsePatchText(patch, lenient: true)
    }

    public static func apply(_ patch: String, cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> ApplyPatchResult {
        do {
            let args = try parsePatch(patch)
            let affected = try applyHunks(args.hunks, cwd: cwd)
            return ApplyPatchResult(stdout: printSummary(affected), stderr: "")
        } catch let error as ApplyPatchError {
            return ApplyPatchResult(stdout: "", stderr: error.description + "\n")
        } catch {
            return ApplyPatchResult(stdout: "", stderr: "\(error)\n")
        }
    }

    private static func parsePatchText(_ patch: String, lenient: Bool) throws -> ApplyPatchArgs {
        let trimmed = patch.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: "\n")

        do {
            try checkPatchBoundaries(lines)
        } catch {
            guard lenient, lines.count >= 4, let first = lines.first, let last = lines.last,
                  ["<<EOF", "<<'EOF'", "<<\"EOF\""].contains(first), last.hasSuffix("EOF")
            else {
                throw error
            }
            lines = Array(lines.dropFirst().dropLast())
            try checkPatchBoundaries(lines)
        }

        var hunks: [Hunk] = []
        var index = 1
        var lineNumber = 2
        let lastBodyIndex = max(lines.count - 1, 1)
        while index < lastBodyIndex {
            let (hunk, consumed) = try parseOneHunk(Array(lines[index..<lastBodyIndex]), lineNumber: lineNumber)
            hunks.append(hunk)
            index += consumed
            lineNumber += consumed
        }

        return ApplyPatchArgs(patch: lines.joined(separator: "\n"), hunks: hunks, workdir: nil)
    }

    private static func checkPatchBoundaries(_ lines: [String]) throws {
        guard lines.first == beginPatchMarker else {
            throw ApplyPatchError.invalidPatch("The first line of the patch must be '*** Begin Patch'")
        }
        guard lines.last == endPatchMarker else {
            throw ApplyPatchError.invalidPatch("The last line of the patch must be '*** End Patch'")
        }
    }

    private static func parseOneHunk(_ lines: [String], lineNumber: Int) throws -> (Hunk, Int) {
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ApplyPatchError.invalidHunk(message: "Update hunk does not contain any lines", lineNumber: lineNumber)
        }

        if let path = firstLine.removingPrefix(addFileMarker) {
            var contents = String()
            var parsedLines = 1
            for line in lines.dropFirst() {
                guard line.hasPrefix("+") else { break }
                contents += String(line.dropFirst()) + "\n"
                parsedLines += 1
            }
            return (.addFile(path: path, contents: contents), parsedLines)
        }

        if let path = firstLine.removingPrefix(deleteFileMarker) {
            return (.deleteFile(path: path), 1)
        }

        if let path = firstLine.removingPrefix(updateFileMarker) {
            var remaining = Array(lines.dropFirst())
            var parsedLines = 1
            var movePath: String?
            if let first = remaining.first, let parsedMovePath = first.removingPrefix(moveToMarker) {
                movePath = parsedMovePath
                remaining.removeFirst()
                parsedLines += 1
            }

            var chunks: [UpdateFileChunk] = []
            while !remaining.isEmpty {
                if remaining[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    remaining.removeFirst()
                    parsedLines += 1
                    continue
                }
                if remaining[0].hasPrefix("***") {
                    break
                }
                let (chunk, consumed) = try parseUpdateFileChunk(
                    remaining,
                    lineNumber: lineNumber + parsedLines,
                    allowMissingContext: chunks.isEmpty
                )
                chunks.append(chunk)
                remaining.removeFirst(consumed)
                parsedLines += consumed
            }

            guard !chunks.isEmpty else {
                throw ApplyPatchError.invalidHunk(
                    message: "Update file hunk for path '\(path)' is empty",
                    lineNumber: lineNumber
                )
            }

            return (.updateFile(path: path, movePath: movePath, chunks: chunks), parsedLines)
        }

        throw ApplyPatchError.invalidHunk(
            message: "'\(firstLine)' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
            lineNumber: lineNumber
        )
    }

    private static func parseUpdateFileChunk(
        _ lines: [String],
        lineNumber: Int,
        allowMissingContext: Bool
    ) throws -> (UpdateFileChunk, Int) {
        guard !lines.isEmpty else {
            throw ApplyPatchError.invalidHunk(message: "Update hunk does not contain any lines", lineNumber: lineNumber)
        }

        let changeContext: String?
        let startIndex: Int
        if lines[0] == emptyChangeContextMarker {
            changeContext = nil
            startIndex = 1
        } else if let context = lines[0].removingPrefix(changeContextMarker) {
            changeContext = context
            startIndex = 1
        } else if allowMissingContext {
            changeContext = nil
            startIndex = 0
        } else {
            throw ApplyPatchError.invalidHunk(
                message: "Expected update hunk to start with a @@ context marker, got: '\(lines[0])'",
                lineNumber: lineNumber
            )
        }

        guard startIndex < lines.count else {
            throw ApplyPatchError.invalidHunk(message: "Update hunk does not contain any lines", lineNumber: lineNumber + 1)
        }

        var oldLines: [String] = []
        var newLines: [String] = []
        var isEndOfFile = false
        var parsedLines = 0

        for line in lines.dropFirst(startIndex) {
            if line == eofMarker {
                guard parsedLines > 0 else {
                    throw ApplyPatchError.invalidHunk(message: "Update hunk does not contain any lines", lineNumber: lineNumber + 1)
                }
                isEndOfFile = true
                parsedLines += 1
                break
            }

            guard let marker = line.first else {
                oldLines.append("")
                newLines.append("")
                parsedLines += 1
                continue
            }

            switch marker {
            case " ":
                let content = String(line.dropFirst())
                oldLines.append(content)
                newLines.append(content)
            case "+":
                newLines.append(String(line.dropFirst()))
            case "-":
                oldLines.append(String(line.dropFirst()))
            default:
                if parsedLines == 0 {
                    throw ApplyPatchError.invalidHunk(
                        message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                        lineNumber: lineNumber + 1
                    )
                }
                return (
                    UpdateFileChunk(
                        changeContext: changeContext,
                        oldLines: oldLines,
                        newLines: newLines,
                        isEndOfFile: isEndOfFile
                    ),
                    parsedLines + startIndex
                )
            }
            parsedLines += 1
        }

        return (
            UpdateFileChunk(
                changeContext: changeContext,
                oldLines: oldLines,
                newLines: newLines,
                isEndOfFile: isEndOfFile
            ),
            parsedLines + startIndex
        )
    }

    private static func applyHunks(_ hunks: [Hunk], cwd: URL) throws -> AffectedPaths {
        guard !hunks.isEmpty else {
            throw ApplyPatchError.io("No files were modified.")
        }

        var affected = AffectedPaths()
        for hunk in hunks {
            switch hunk {
            case let .addFile(path, contents):
                let url = resolve(path, cwd: cwd)
                try createParentDirectory(for: url, contextPath: path)
                try contents.write(to: url, atomically: true, encoding: .utf8)
                affected.added.append(path)

            case let .deleteFile(path):
                let url = resolve(path, cwd: cwd)
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw ApplyPatchError.io("Failed to delete file \(path)")
                }
                affected.deleted.append(path)

            case let .updateFile(path, movePath, chunks):
                let sourceURL = resolve(path, cwd: cwd)
                let newContents = try deriveNewContents(path: path, sourceURL: sourceURL, chunks: chunks)
                if let movePath {
                    let destinationURL = resolve(movePath, cwd: cwd)
                    try createParentDirectory(for: destinationURL, contextPath: movePath)
                    try newContents.write(to: destinationURL, atomically: true, encoding: .utf8)
                    do {
                        try FileManager.default.removeItem(at: sourceURL)
                    } catch {
                        throw ApplyPatchError.io("Failed to remove original \(path)")
                    }
                    affected.modified.append(movePath)
                } else {
                    try newContents.write(to: sourceURL, atomically: true, encoding: .utf8)
                    affected.modified.append(path)
                }
            }
        }
        return affected
    }

    private static func deriveNewContents(path: String, sourceURL: URL, chunks: [UpdateFileChunk]) throws -> String {
        let originalContents: String
        do {
            originalContents = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw ApplyPatchError.io("Failed to read file to update \(path): \(error.localizedDescription)")
        }

        var originalLines = originalContents.components(separatedBy: "\n")
        if originalLines.last == "" {
            originalLines.removeLast()
        }

        let replacements = try computeReplacements(originalLines: originalLines, path: path, chunks: chunks)
        var newLines = applyReplacements(lines: originalLines, replacements: replacements)
        if newLines.last != "" {
            newLines.append("")
        }
        return newLines.joined(separator: "\n")
    }

    private static func computeReplacements(
        originalLines: [String],
        path: String,
        chunks: [UpdateFileChunk]
    ) throws -> [(start: Int, oldLength: Int, newLines: [String])] {
        var replacements: [(start: Int, oldLength: Int, newLines: [String])] = []
        var lineIndex = 0

        for chunk in chunks {
            if let context = chunk.changeContext {
                guard let index = seekSequence(originalLines, [context], start: lineIndex, endOfFile: false) else {
                    throw ApplyPatchError.computeReplacements("Failed to find context '\(context)' in \(path)")
                }
                lineIndex = index + 1
            }

            if chunk.oldLines.isEmpty {
                replacements.append((originalLines.count, 0, chunk.newLines))
                continue
            }

            var pattern = chunk.oldLines
            var newLines = chunk.newLines
            var found = seekSequence(originalLines, pattern, start: lineIndex, endOfFile: chunk.isEndOfFile)

            if found == nil, pattern.last == "" {
                pattern.removeLast()
                if newLines.last == "" {
                    newLines.removeLast()
                }
                found = seekSequence(originalLines, pattern, start: lineIndex, endOfFile: chunk.isEndOfFile)
            }

            guard let start = found else {
                throw ApplyPatchError.computeReplacements("Failed to find expected lines in \(path):\n\(chunk.oldLines.joined(separator: "\n"))")
            }

            replacements.append((start, pattern.count, newLines))
            lineIndex = start + pattern.count
        }

        return replacements.sorted { $0.start < $1.start }
    }

    private static func applyReplacements(
        lines: [String],
        replacements: [(start: Int, oldLength: Int, newLines: [String])]
    ) -> [String] {
        var result = lines
        for replacement in replacements.reversed() {
            if replacement.oldLength > 0 {
                result.removeSubrange(replacement.start..<min(replacement.start + replacement.oldLength, result.count))
            }
            result.insert(contentsOf: replacement.newLines, at: replacement.start)
        }
        return result
    }

    private static func seekSequence(_ lines: [String], _ pattern: [String], start: Int, endOfFile: Bool) -> Int? {
        if pattern.isEmpty {
            return start
        }
        guard pattern.count <= lines.count else { return nil }
        var index = start
        while index + pattern.count <= lines.count {
            if Array(lines[index..<index + pattern.count]) == pattern {
                if endOfFile, index + pattern.count != lines.count {
                    index += 1
                    continue
                }
                return index
            }
            index += 1
        }
        return nil
    }

    private static func resolve(_ path: String, cwd: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return cwd.appendingPathComponent(path)
    }

    private static func createParentDirectory(for url: URL, contextPath: String) throws {
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path, !parent.path.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw ApplyPatchError.io("Failed to create parent directories for \(contextPath)")
        }
    }

    private static func printSummary(_ affected: AffectedPaths) -> String {
        var output = "Success. Updated the following files:\n"
        for path in affected.added {
            output += "A \(path)\n"
        }
        for path in affected.modified {
            output += "M \(path)\n"
        }
        for path in affected.deleted {
            output += "D \(path)\n"
        }
        return output
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
