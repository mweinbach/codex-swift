import CodexApplyPatch
import Foundation

public enum PatchApplyTurnDiffTrackerUpdate: Equatable, Sendable {
    case track(AppliedPatchDelta)
    case invalidate
    case none

    public static func knownDelta(_ delta: AppliedPatchDelta) -> Self {
        if delta.isExact, delta.isEmpty {
            return .none
        }
        return .track(delta)
    }
}

public struct PatchApplyEventEmitter: Sendable {
    public let threadID: ConversationId
    public let turnID: String
    public let callID: String
    public let changes: [String: FileChange]
    public let autoApproved: Bool

    public init(
        threadID: ConversationId,
        turnID: String,
        callID: String,
        changes: [String: FileChange],
        autoApproved: Bool
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.callID = callID
        self.changes = changes
        self.autoApproved = autoApproved
    }

    public func beginEvent(startedAtMilliseconds: Int64 = 0) -> EventMessage {
        .itemStarted(ItemStartedEvent(
            threadID: threadID,
            turnID: turnID,
            item: .fileChange(FileChangeItem(
                id: callID,
                changes: changes,
                autoApproved: autoApproved
            )),
            startedAtMilliseconds: startedAtMilliseconds
        ))
    }

    public func completionEvents(
        stdout: String,
        stderr: String,
        status: PatchApplyStatus,
        tracker: inout TurnDiffTracker,
        turnDiffUpdate: PatchApplyTurnDiffTrackerUpdate,
        completedAtMilliseconds: Int64 = 0
    ) -> [EventMessage] {
        var events = [completionEvent(
            stdout: stdout,
            stderr: stderr,
            status: status,
            completedAtMilliseconds: completedAtMilliseconds
        )]
        if let turnDiff = tracker.applyPatchUpdate(turnDiffUpdate) {
            events.append(.turnDiff(turnDiff))
        }
        return events
    }

    public func completionEvent(
        stdout: String,
        stderr: String,
        status: PatchApplyStatus,
        completedAtMilliseconds: Int64 = 0
    ) -> EventMessage {
        .itemCompleted(ItemCompletedEvent(
            threadID: threadID,
            turnID: turnID,
            item: .fileChange(FileChangeItem(
                id: callID,
                changes: changes,
                status: status,
                stdout: stdout,
                stderr: stderr
            )),
            completedAtMilliseconds: completedAtMilliseconds
        ))
    }

    public static func fileChanges(from changes: [String: ApplyPatchFileChange]) -> [String: FileChange] {
        Dictionary(uniqueKeysWithValues: changes.map { path, change in
            (path, FileChange(change))
        })
    }
}

public extension TurnDiffTracker {
    mutating func applyPatchUpdate(_ update: PatchApplyTurnDiffTrackerUpdate) -> TurnDiffEvent? {
        let previousDiff = unifiedDiff()
        let trackerChanged: Bool

        switch update {
        case let .track(delta):
            trackDelta(delta)
            trackerChanged = true
        case .invalidate:
            invalidate()
            trackerChanged = true
        case .none:
            trackerChanged = false
        }

        let currentDiff = unifiedDiff()
        guard trackerChanged, previousDiff != nil || currentDiff != nil else {
            return nil
        }
        return TurnDiffEvent(unifiedDiff: currentDiff ?? "")
    }
}

private extension FileChange {
    init(_ change: ApplyPatchFileChange) {
        switch change {
        case let .add(content):
            self = .add(content: content)
        case let .delete(content):
            self = .delete(content: content)
        case let .update(unifiedDiff, movePath, _):
            self = .update(unifiedDiff: unifiedDiff, movePath: movePath)
        }
    }
}
