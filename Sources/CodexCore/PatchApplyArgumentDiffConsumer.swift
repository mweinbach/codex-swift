import CodexApplyPatch
import Foundation

public enum ApplyPatchArgumentDiffConsumerError: Error, Equatable, CustomStringConvertible, Sendable {
    case respondToModel(String)

    public var description: String {
        switch self {
        case let .respondToModel(message):
            return message
        }
    }
}

public struct ApplyPatchArgumentDiffConsumer: Sendable {
    public static let bufferInterval: TimeInterval = 0.5

    private var parser: StreamingPatchParser
    private var lastSentAt: Date?
    private var pending: PatchApplyUpdatedEvent?

    public init() {
        self.parser = StreamingPatchParser()
    }

    public mutating func pushDelta(
        callID: String,
        delta: String,
        now: Date = Date()
    ) -> PatchApplyUpdatedEvent? {
        guard let hunks = try? parser.pushDelta(delta: delta),
              !hunks.isEmpty
        else {
            return nil
        }

        let event = PatchApplyUpdatedEvent(callID: callID, changes: Self.fileChanges(from: hunks))
        if let lastSentAt,
           now.timeIntervalSince(lastSentAt) < Self.bufferInterval {
            pending = event
            return nil
        }

        pending = nil
        lastSentAt = now
        return event
    }

    public mutating func finishUpdateOnComplete(now: Date = Date()) throws -> PatchApplyUpdatedEvent? {
        do {
            _ = try parser.finish()
        } catch {
            throw ApplyPatchArgumentDiffConsumerError.respondToModel("failed to parse apply_patch: \(error)")
        }

        let event = pending
        if event != nil {
            lastSentAt = now
        }
        pending = nil
        return event
    }

    public static func fileChanges(from hunks: [Hunk]) -> [String: FileChange] {
        Dictionary(uniqueKeysWithValues: hunks.map { hunk in
            (hunk.sourcePath, FileChange(progressHunk: hunk))
        })
    }
}

private extension Hunk {
    var sourcePath: String {
        switch self {
        case let .addFile(path, _),
             let .deleteFile(path),
             let .updateFile(path, _, _):
            return path
        }
    }
}

private extension FileChange {
    init(progressHunk hunk: Hunk) {
        switch hunk {
        case let .addFile(_, contents):
            self = .add(content: contents)
        case .deleteFile:
            self = .delete(content: "")
        case let .updateFile(_, movePath, chunks):
            self = .update(
                unifiedDiff: Self.formatUpdateChunksForProgress(chunks),
                movePath: movePath
            )
        }
    }

    static func formatUpdateChunksForProgress(_ chunks: [UpdateFileChunk]) -> String {
        var unifiedDiff = ""
        for chunk in chunks {
            if let context = chunk.changeContext {
                unifiedDiff += "@@ \(context)\n"
            } else {
                unifiedDiff += "@@\n"
            }
            for line in chunk.oldLines {
                unifiedDiff += "-\(line)\n"
            }
            for line in chunk.newLines {
                unifiedDiff += "+\(line)\n"
            }
            if chunk.isEndOfFile {
                unifiedDiff += "*** End of File\n"
            }
        }
        return unifiedDiff
    }
}
