import Foundation

public enum ApplyPatchError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidPatch(String)
    case invalidHunk(message: String, lineNumber: Int)
    case io(String)
    case computeReplacements(String)
    case implicitInvocation

    public var description: String {
        switch self {
        case let .invalidPatch(message):
            return "Invalid patch: \(message)"
        case let .invalidHunk(message, lineNumber):
            return "Invalid patch hunk on line \(lineNumber): \(message)"
        case let .io(message), let .computeReplacements(message):
            return message
        case .implicitInvocation:
            return #"patch detected without explicit call to apply_patch. Rerun as ["apply_patch", "<patch>"]"#
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

public struct ApplyPatchFileUpdate: Equatable, Sendable {
    public let unifiedDiff: String
    public let content: String

    public init(unifiedDiff: String, content: String) {
        self.unifiedDiff = unifiedDiff
        self.content = content
    }
}

public enum ApplyPatchFileChange: Equatable, Sendable {
    case add(content: String)
    case delete(content: String)
    case update(unifiedDiff: String, movePath: String?, newContent: String)
}

public struct ApplyPatchAction: Equatable, Sendable {
    public let changes: [String: ApplyPatchFileChange]
    public let patch: String
    public let cwd: String

    public init(changes: [String: ApplyPatchFileChange], patch: String, cwd: String) {
        self.changes = changes
        self.patch = patch
        self.cwd = cwd
    }

    public var isEmpty: Bool {
        changes.isEmpty
    }
}

public struct ApplyPatchResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
}

public enum ExtractHeredocError: Error, Equatable, Sendable {
    case commandDidNotStartWithApplyPatch
    case failedToParsePatchIntoAST
    case failedToFindHeredocBody
}

public enum MaybeApplyPatch: Equatable, Sendable {
    case body(ApplyPatchArgs)
    case shellParseError(ExtractHeredocError)
    case patchParseError(ApplyPatchError)
    case notApplyPatch
}

public enum MaybeApplyPatchVerified: Equatable, Sendable {
    case body(ApplyPatchAction)
    case shellParseError(ExtractHeredocError)
    case correctnessError(ApplyPatchError)
    case notApplyPatch
}

public struct AffectedPaths: Equatable, Sendable {
    public var added: [String] = []
    public var modified: [String] = []
    public var deleted: [String] = []
}

public enum ApplyPatchToolInstructions {
    public static let text: String = {
        guard let url = Bundle.module.url(forResource: "apply_patch_tool_instructions", withExtension: "md") else {
            preconditionFailure("Missing bundled apply_patch_tool_instructions.md")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to load apply_patch_tool_instructions.md: \(error)")
        }
    }()
}

public enum ApplyPatchInvocation {
    private enum ShellKind: Sendable {
        case unix
        case powerShell
        case cmd
    }

    private static let applyPatchCommands: Set<String> = ["apply_patch", "applypatch"]

    public static func maybeParseApplyPatch(_ argv: [String]) -> MaybeApplyPatch {
        if argv.count == 2, applyPatchCommands.contains(argv[0]) {
            do {
                return .body(try ApplyPatch.parsePatch(argv[1]))
            } catch let error as ApplyPatchError {
                return .patchParseError(error)
            } catch {
                return .patchParseError(.io("\(error)"))
            }
        }

        guard let (_, script) = parseShellScript(argv) else {
            return .notApplyPatch
        }

        switch extractApplyPatchFromShell(script) {
        case let .success((body, workdir)):
            do {
                let args = try ApplyPatch.parsePatch(body)
                return .body(ApplyPatchArgs(patch: args.patch, hunks: args.hunks, workdir: workdir))
            } catch let error as ApplyPatchError {
                return .patchParseError(error)
            } catch {
                return .patchParseError(.io("\(error)"))
            }
        case .failure(.commandDidNotStartWithApplyPatch):
            return .notApplyPatch
        case let .failure(error):
            return .shellParseError(error)
        }
    }

    public static func maybeParseApplyPatchVerified(_ argv: [String], cwd: URL) -> MaybeApplyPatchVerified {
        if argv.count == 1, (try? ApplyPatch.parsePatch(argv[0])) != nil {
            return .correctnessError(.implicitInvocation)
        }
        if let (_, script) = parseShellScript(argv), (try? ApplyPatch.parsePatch(script)) != nil {
            return .correctnessError(.implicitInvocation)
        }

        switch maybeParseApplyPatch(argv) {
        case let .body(args):
            return verify(args, cwd: cwd)
        case let .shellParseError(error):
            return .shellParseError(error)
        case let .patchParseError(error):
            return .correctnessError(error)
        case .notApplyPatch:
            return .notApplyPatch
        }
    }

    private static func verify(_ args: ApplyPatchArgs, cwd: URL) -> MaybeApplyPatchVerified {
        let effectiveCwd = effectiveCWD(base: cwd, workdir: args.workdir)
        var changes: [String: ApplyPatchFileChange] = [:]

        for hunk in args.hunks {
            switch hunk {
            case let .addFile(path, contents):
                let url = ApplyPatch.resolve(path, cwd: effectiveCwd)
                changes[url.path] = .add(content: contents)

            case let .deleteFile(path):
                let url = ApplyPatch.resolve(path, cwd: effectiveCwd)
                do {
                    changes[url.path] = .delete(content: try String(contentsOf: url, encoding: .utf8))
                } catch {
                    return .correctnessError(.io("Failed to read \(url.path): \(error.localizedDescription)"))
                }

            case let .updateFile(path, movePath, chunks):
                let sourceURL = ApplyPatch.resolve(path, cwd: effectiveCwd)
                do {
                    let update = try ApplyPatch.unifiedDiffFromChunks(path: path, sourceURL: sourceURL, chunks: chunks)
                    changes[sourceURL.path] = .update(
                        unifiedDiff: update.unifiedDiff,
                        movePath: movePath.map { ApplyPatch.resolve($0, cwd: effectiveCwd).path },
                        newContent: update.content
                    )
                } catch let error as ApplyPatchError {
                    return .correctnessError(error)
                } catch {
                    return .correctnessError(.io("\(error)"))
                }
            }
        }

        return .body(ApplyPatchAction(changes: changes, patch: args.patch, cwd: effectiveCwd.path))
    }

    private static func effectiveCWD(base: URL, workdir: String?) -> URL {
        guard let workdir else {
            return base
        }
        if workdir.hasPrefix("/") {
            return URL(fileURLWithPath: workdir)
        }
        return base.appendingPathComponent(workdir)
    }

    private static func parseShellScript(_ argv: [String]) -> (ShellKind, String)? {
        if argv.count == 3 {
            return classifyShell(argv[0], flag: argv[1]).map { ($0, argv[2]) }
        }
        if argv.count == 4, canSkipFlag(argv[0], flag: argv[1]) {
            return classifyShell(argv[0], flag: argv[2]).map { ($0, argv[3]) }
        }
        return nil
    }

    private static func classifyShell(_ shell: String, flag: String) -> ShellKind? {
        guard let name = shellStem(shell) else {
            return nil
        }

        if ["bash", "zsh", "sh"].contains(name), flag == "-lc" || flag == "-c" {
            return .unix
        }
        if ["pwsh", "powershell"].contains(name), flag.caseInsensitiveCompare("-command") == .orderedSame {
            return .powerShell
        }
        if name == "cmd", flag.caseInsensitiveCompare("/c") == .orderedSame {
            return .cmd
        }
        return nil
    }

    private static func canSkipFlag(_ shell: String, flag: String) -> Bool {
        guard let name = shellStem(shell), name == "pwsh" || name == "powershell" else {
            return false
        }
        return flag.caseInsensitiveCompare("-noprofile") == .orderedSame
    }

    private static func shellStem(_ shell: String) -> String? {
        let executable = shell
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? shell
        let stem: String
        if let dot = executable.lastIndex(of: ".") {
            stem = String(executable[..<dot])
        } else {
            stem = executable
        }
        return stem.isEmpty ? nil : stem.lowercased()
    }

    private static func extractApplyPatchFromShell(
        _ script: String
    ) -> Result<(String, String?), ExtractHeredocError> {
        extractApplyPatchFromBash(script)
    }

    private static func extractApplyPatchFromBash(
        _ script: String
    ) -> Result<(String, String?), ExtractHeredocError> {
        guard let newline = script.firstIndex(of: "\n") else {
            return .failure(.commandDidNotStartWithApplyPatch)
        }

        let header = String(script[..<newline])
        guard let tokens = shellWords(header) else {
            return .failure(.failedToParsePatchIntoAST)
        }

        let workdir: String?
        let redirect: String
        if tokens.count == 2, applyPatchCommands.contains(tokens[0]) {
            workdir = nil
            redirect = tokens[1]
        } else if tokens.count == 5,
                  tokens[0] == "cd",
                  tokens[2] == "&&",
                  applyPatchCommands.contains(tokens[3])
        {
            workdir = tokens[1]
            redirect = tokens[4]
        } else {
            return .failure(.commandDidNotStartWithApplyPatch)
        }

        guard let delimiter = heredocDelimiter(from: redirect) else {
            return .failure(.commandDidNotStartWithApplyPatch)
        }

        let bodyWithTerminator = String(script[script.index(after: newline)...])
        guard let body = heredocBody(in: bodyWithTerminator, delimiter: delimiter) else {
            if hasNonTerminalDelimiterLine(in: bodyWithTerminator, delimiter: delimiter) {
                return .failure(.commandDidNotStartWithApplyPatch)
            }
            return .failure(.failedToFindHeredocBody)
        }

        return .success((body, workdir))
    }

    private static func heredocDelimiter(from redirect: String) -> String? {
        guard redirect.hasPrefix("<<") else {
            return nil
        }

        var delimiter = String(redirect.dropFirst(2))
        if delimiter.hasPrefix("-") {
            delimiter.removeFirst()
        }
        guard !delimiter.isEmpty else {
            return nil
        }

        if delimiter.count >= 2 {
            let first = delimiter.first
            let last = delimiter.last
            if (first == "'" && last == "'") || (first == "\"" && last == "\"") {
                delimiter = String(delimiter.dropFirst().dropLast())
            }
        }
        return delimiter.isEmpty ? nil : delimiter
    }

    private static func heredocBody(in bodyWithTerminator: String, delimiter: String) -> String? {
        var lines = bodyWithTerminator.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }

        guard let closingLine = lines.last,
              closingLine.trimmingCharacters(in: .whitespacesAndNewlines) == delimiter
        else {
            return nil
        }

        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    private static func hasNonTerminalDelimiterLine(in bodyWithTerminator: String, delimiter: String) -> Bool {
        bodyWithTerminator
            .components(separatedBy: "\n")
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix(delimiter) && trimmed != delimiter
            }
    }

    private static func shellWords(_ source: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var iterator = source.makeIterator()

        while let character = iterator.next() {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character == "\\" {
                if let next = iterator.next() {
                    current.append(next)
                    continue
                }
                current.append(character)
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        guard quote == nil else {
            return nil
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
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

    fileprivate static func unifiedDiffFromChunks(
        path: String,
        sourceURL: URL,
        chunks: [UpdateFileChunk]
    ) throws -> ApplyPatchFileUpdate {
        let originalContents: String
        do {
            originalContents = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw ApplyPatchError.io("Failed to read file to update \(path): \(error.localizedDescription)")
        }

        let newContents = try deriveNewContents(
            path: path,
            originalContents: originalContents,
            chunks: chunks
        )
        return ApplyPatchFileUpdate(
            unifiedDiff: unifiedDiff(originalContents: originalContents, newContents: newContents),
            content: newContents
        )
    }

    private static func deriveNewContents(path: String, sourceURL: URL, chunks: [UpdateFileChunk]) throws -> String {
        let originalContents: String
        do {
            originalContents = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw ApplyPatchError.io("Failed to read file to update \(path): \(error.localizedDescription)")
        }

        return try deriveNewContents(path: path, originalContents: originalContents, chunks: chunks)
    }

    private static func deriveNewContents(path: String, originalContents: String, chunks: [UpdateFileChunk]) throws -> String {
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

    private enum DiffOp: Equatable {
        case equal(String)
        case delete(String)
        case insert(String)

        var consumesOld: Bool {
            switch self {
            case .equal, .delete:
                return true
            case .insert:
                return false
            }
        }

        var consumesNew: Bool {
            switch self {
            case .equal, .insert:
                return true
            case .delete:
                return false
            }
        }

        var isChange: Bool {
            switch self {
            case .equal:
                return false
            case .delete, .insert:
                return true
            }
        }
    }

    private static func unifiedDiff(originalContents: String, newContents: String, context: Int = 1) -> String {
        let oldLines = diffLines(originalContents)
        let newLines = diffLines(newContents)
        let ops = diffOps(oldLines: oldLines, newLines: newLines)
        let hunks = diffHunks(ops: ops, context: context)

        var output = ""
        for hunk in hunks {
            let hunkOps = Array(ops[hunk.start..<hunk.end])
            let oldStart = lineStart(in: ops, upTo: hunk.start, consumingOld: true)
            let newStart = lineStart(in: ops, upTo: hunk.start, consumingOld: false)
            let oldCount = hunkOps.filter(\.consumesOld).count
            let newCount = hunkOps.filter(\.consumesNew).count
            output += "@@ \(rangeHeader(prefix: "-", start: oldStart, count: oldCount)) \(rangeHeader(prefix: "+", start: newStart, count: newCount)) @@\n"
            for op in hunkOps {
                switch op {
                case let .equal(line):
                    output += " \(line)\n"
                case let .delete(line):
                    output += "-\(line)\n"
                case let .insert(line):
                    output += "+\(line)\n"
                }
            }
        }
        return output
    }

    private static func diffLines(_ contents: String) -> [String] {
        var lines = contents.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func diffOps(oldLines: [String], newLines: [String]) -> [DiffOp] {
        var lcs = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )

        if !oldLines.isEmpty, !newLines.isEmpty {
            for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
                for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                    if oldLines[oldIndex] == newLines[newIndex] {
                        lcs[oldIndex][newIndex] = lcs[oldIndex + 1][newIndex + 1] + 1
                    } else {
                        lcs[oldIndex][newIndex] = max(lcs[oldIndex + 1][newIndex], lcs[oldIndex][newIndex + 1])
                    }
                }
            }
        }

        var output: [DiffOp] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count, newIndex < newLines.count {
            if oldLines[oldIndex] == newLines[newIndex] {
                output.append(.equal(oldLines[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if lcs[oldIndex + 1][newIndex] >= lcs[oldIndex][newIndex + 1] {
                output.append(.delete(oldLines[oldIndex]))
                oldIndex += 1
            } else {
                output.append(.insert(newLines[newIndex]))
                newIndex += 1
            }
        }
        while oldIndex < oldLines.count {
            output.append(.delete(oldLines[oldIndex]))
            oldIndex += 1
        }
        while newIndex < newLines.count {
            output.append(.insert(newLines[newIndex]))
            newIndex += 1
        }
        return output
    }

    private static func diffHunks(ops: [DiffOp], context: Int) -> [(start: Int, end: Int)] {
        let changed = ops.indices.filter { ops[$0].isChange }
        guard !changed.isEmpty else {
            return []
        }

        var hunks: [(start: Int, end: Int)] = []
        var groupStart = changed[0]
        var groupEnd = changed[0]

        for index in changed.dropFirst() {
            if index - groupEnd <= context * 2 + 1 {
                groupEnd = index
            } else {
                appendDiffHunk(start: groupStart, end: groupEnd, context: context, count: ops.count, hunks: &hunks)
                groupStart = index
                groupEnd = index
            }
        }
        appendDiffHunk(start: groupStart, end: groupEnd, context: context, count: ops.count, hunks: &hunks)
        return hunks
    }

    private static func appendDiffHunk(
        start: Int,
        end: Int,
        context: Int,
        count: Int,
        hunks: inout [(start: Int, end: Int)]
    ) {
        let expanded = (start: max(0, start - context), end: min(count, end + context + 1))
        if let last = hunks.last, expanded.start <= last.end {
            hunks[hunks.count - 1] = (start: last.start, end: max(last.end, expanded.end))
        } else {
            hunks.append(expanded)
        }
    }

    private static func lineStart(in ops: [DiffOp], upTo end: Int, consumingOld: Bool) -> Int {
        let consumed = ops[..<end].reduce(0) { partial, op in
            partial + ((consumingOld ? op.consumesOld : op.consumesNew) ? 1 : 0)
        }
        return max(consumed, 1)
    }

    private static func rangeHeader(prefix: String, start: Int, count: Int) -> String {
        if count == 1 {
            return "\(prefix)\(start)"
        }
        return "\(prefix)\(start),\(count)"
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

    fileprivate static func resolve(_ path: String, cwd: URL) -> URL {
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

public func maybeParseApplyPatch(_ argv: [String]) -> MaybeApplyPatch {
    ApplyPatchInvocation.maybeParseApplyPatch(argv)
}

public func maybeParseApplyPatchVerified(_ argv: [String], cwd: URL) -> MaybeApplyPatchVerified {
    ApplyPatchInvocation.maybeParseApplyPatchVerified(argv, cwd: cwd)
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
