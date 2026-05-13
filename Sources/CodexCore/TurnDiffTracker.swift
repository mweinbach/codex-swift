import CodexApplyPatch
import CryptoKit
import Foundation

private let zeroObjectID = "0000000000000000000000000000000000000000"
private let devNullPath = "/dev/null"
private let regularFileMode = "100644"

public struct TurnDiffTracker: Sendable {
    private var valid = true
    private var displayRoot: String?
    private var baselineByPath: [String: String] = [:]
    private var currentByPath: [String: String] = [:]
    private var originByCurrentPath: [String: String] = [:]

    public init() {}

    public init(displayRoot: String) {
        self.displayRoot = Self.normalizedPath(displayRoot)
    }

    public mutating func trackDelta(_ delta: AppliedPatchDelta) {
        guard delta.isExact else {
            invalidate()
            return
        }

        for change in delta.changes {
            applyChange(change)
        }
    }

    public mutating func invalidate() {
        valid = false
    }

    public func unifiedDiff() -> String? {
        guard valid else {
            return nil
        }

        let renamePairs = renamePairs()
        let pairedDestinations = Set(renamePairs.values)
        var handled = Set<String>()
        let paths = Array(Set(baselineByPath.keys).union(currentByPath.keys))
            .sorted { displayPath($0) < displayPath($1) }

        var aggregated = ""
        for path in paths {
            guard handled.insert(path).inserted else {
                continue
            }
            if pairedDestinations.contains(path) {
                continue
            }

            let diff: String?
            if let destination = renamePairs[path] {
                handled.insert(destination)
                diff = renderRenameDiff(sourcePath: path, destinationPath: destination)
            } else {
                diff = renderPathDiff(path)
            }

            if let diff {
                aggregated += diff
                if !aggregated.hasSuffix("\n") {
                    aggregated += "\n"
                }
            }
        }

        return aggregated.isEmpty ? nil : aggregated
    }

    private mutating func applyChange(_ change: AppliedPatchChange) {
        let sourcePath = Self.normalizedPath(change.path)
        switch change.change {
        case let .add(content, overwrittenContent):
            applyAdd(path: sourcePath, content: content, overwrittenContent: overwrittenContent)
        case let .delete(content):
            applyDelete(path: sourcePath, content: content)
        case let .update(movePath, originalContent, overwrittenMoveContent, newContent):
            applyUpdate(
                sourcePath: sourcePath,
                movePath: movePath.map(Self.normalizedPath),
                originalContent: originalContent,
                overwrittenMoveContent: overwrittenMoveContent,
                newContent: newContent
            )
        }
    }

    private mutating func applyAdd(path: String, content: String, overwrittenContent: String?) {
        originByCurrentPath.removeValue(forKey: path)
        if currentByPath[path] == nil, baselineByPath[path] == nil, let overwrittenContent {
            baselineByPath[path] = overwrittenContent
        }
        currentByPath[path] = content
    }

    private mutating func applyDelete(path: String, content: String) {
        if currentByPath.removeValue(forKey: path) == nil, baselineByPath[path] == nil {
            baselineByPath[path] = content
        }
        originByCurrentPath.removeValue(forKey: path)
    }

    private mutating func applyUpdate(
        sourcePath: String,
        movePath: String?,
        originalContent: String,
        overwrittenMoveContent: String?,
        newContent: String
    ) {
        if currentByPath[sourcePath] == nil, baselineByPath[sourcePath] == nil {
            baselineByPath[sourcePath] = originalContent
        }

        guard let destinationPath = movePath else {
            currentByPath[sourcePath] = newContent
            return
        }

        if currentByPath[destinationPath] == nil,
           baselineByPath[destinationPath] == nil,
           let overwrittenMoveContent {
            baselineByPath[destinationPath] = overwrittenMoveContent
        }
        let origin = originByCurrentPath.removeValue(forKey: sourcePath) ?? sourcePath
        currentByPath.removeValue(forKey: sourcePath)
        currentByPath[destinationPath] = newContent
        originByCurrentPath.removeValue(forKey: destinationPath)
        if destinationPath != origin {
            originByCurrentPath[destinationPath] = origin
        }
    }

    private func renamePairs() -> [String: String] {
        var pairs: [String: String] = [:]
        for (destinationPath, originPath) in originByCurrentPath {
            if destinationPath == originPath
                || currentByPath[originPath] != nil
                || currentByPath[destinationPath] == nil
                || baselineByPath[originPath] == nil
                || baselineByPath[destinationPath] != nil {
                continue
            }
            pairs[originPath] = destinationPath
        }
        return pairs
    }

    private func renderPathDiff(_ path: String) -> String? {
        renderDiff(
            leftPath: path,
            leftContent: baselineByPath[path],
            rightPath: path,
            rightContent: currentByPath[path]
        )
    }

    private func renderRenameDiff(sourcePath: String, destinationPath: String) -> String? {
        renderDiff(
            leftPath: sourcePath,
            leftContent: baselineByPath[sourcePath],
            rightPath: destinationPath,
            rightContent: currentByPath[destinationPath]
        )
    }

    private func renderDiff(
        leftPath: String,
        leftContent: String?,
        rightPath: String,
        rightContent: String?
    ) -> String? {
        guard leftContent != rightContent else {
            return nil
        }

        let leftDisplay = displayPath(leftPath)
        let rightDisplay = displayPath(rightPath)
        let leftObjectID = leftContent.map { gitBlobObjectID($0) } ?? zeroObjectID
        let rightObjectID = rightContent.map { gitBlobObjectID($0) } ?? zeroObjectID

        var diff = "diff --git a/\(leftDisplay) b/\(rightDisplay)\n"
        switch (leftContent, rightContent) {
        case (nil, .some):
            diff += "new file mode \(regularFileMode)\n"
        case (.some, nil):
            diff += "deleted file mode \(regularFileMode)\n"
        case (.some, .some):
            break
        case (nil, nil):
            return nil
        }

        diff += "index \(leftObjectID)..\(rightObjectID)\n"
        let oldHeader = leftContent == nil ? devNullPath : "a/\(leftDisplay)"
        let newHeader = rightContent == nil ? devNullPath : "b/\(rightDisplay)"
        diff += renderUnifiedDiff(
            oldContent: leftContent ?? "",
            newContent: rightContent ?? "",
            oldHeader: oldHeader,
            newHeader: newHeader,
            context: 3
        )
        return diff
    }

    private func displayPath(_ path: String) -> String {
        let normalized = Self.normalizedPath(path)
        if let displayRoot,
           normalized == displayRoot || normalized.hasPrefix(displayRoot + "/") {
            let relative = String(normalized.dropFirst(displayRoot.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? "." : relative
        }
        return normalized.replacingOccurrences(of: "\\", with: "/")
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "/")
    }
}

private enum DiffOperation: Equatable {
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

private func renderUnifiedDiff(
    oldContent: String,
    newContent: String,
    oldHeader: String,
    newHeader: String,
    context: Int
) -> String {
    let oldLines = diffLines(oldContent)
    let newLines = diffLines(newContent)
    let operations = diffOperations(oldLines: oldLines, newLines: newLines)
    let hunks = diffHunks(operations: operations, context: context)

    var output = "--- \(oldHeader)\n+++ \(newHeader)\n"
    for hunk in hunks {
        let hunkOperations = Array(operations[hunk.start..<hunk.end])
        let oldConsumed = consumedLines(in: operations, upTo: hunk.start, consumingOld: true)
        let newConsumed = consumedLines(in: operations, upTo: hunk.start, consumingOld: false)
        let oldCount = hunkOperations.filter(\.consumesOld).count
        let newCount = hunkOperations.filter(\.consumesNew).count
        output += "@@ \(rangeHeader(prefix: "-", consumed: oldConsumed, count: oldCount)) \(rangeHeader(prefix: "+", consumed: newConsumed, count: newCount)) @@\n"
        for operation in hunkOperations {
            switch operation {
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

private func diffLines(_ content: String) -> [String] {
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" {
        lines.removeLast()
    }
    return lines
}

private func diffOperations(oldLines: [String], newLines: [String]) -> [DiffOperation] {
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

    var output: [DiffOperation] = []
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

private func diffHunks(operations: [DiffOperation], context: Int) -> [(start: Int, end: Int)] {
    let changed = operations.indices.filter { operations[$0].isChange }
    guard let firstChanged = changed.first else {
        return []
    }

    var hunks: [(start: Int, end: Int)] = []
    var groupStart = firstChanged
    var groupEnd = firstChanged
    for index in changed.dropFirst() {
        if index - groupEnd <= context * 2 + 1 {
            groupEnd = index
        } else {
            appendDiffHunk(start: groupStart, end: groupEnd, context: context, count: operations.count, hunks: &hunks)
            groupStart = index
            groupEnd = index
        }
    }
    appendDiffHunk(start: groupStart, end: groupEnd, context: context, count: operations.count, hunks: &hunks)
    return hunks
}

private func appendDiffHunk(
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

private func consumedLines(in operations: [DiffOperation], upTo end: Int, consumingOld: Bool) -> Int {
    operations[..<end].reduce(0) { partial, operation in
        partial + ((consumingOld ? operation.consumesOld : operation.consumesNew) ? 1 : 0)
    }
}

private func rangeHeader(prefix: String, consumed: Int, count: Int) -> String {
    let start = count == 0 ? consumed : consumed + 1
    if count == 1 {
        return "\(prefix)\(start)"
    }
    return "\(prefix)\(start),\(count)"
}

private func gitBlobObjectID(_ content: String) -> String {
    var data = Data("blob \(Data(content.utf8).count)\0".utf8)
    data.append(Data(content.utf8))
    return hexString(Insecure.SHA1.hash(data: data))
}

private func hexString<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var output = [UInt8]()
    output.reserveCapacity(40)
    for byte in bytes {
        output.append(digits[Int(byte >> 4)])
        output.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: output, as: UTF8.self)
}
