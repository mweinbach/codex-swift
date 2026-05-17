import Darwin
import Foundation

/// Tracks a spawned process tree and provides whole-tree termination.
///
/// Use this after launching long-lived local tools whose shell children must
/// not outlive the owning app-server or exec-server session. The supervisor
/// combines fork tracking with a current child-process scan so callers can
/// clean up descendants even when the root process exits first.
public final class ProcessTreeSupervisor: @unchecked Sendable {
    public static let defaultTerminationGracePeriod: TimeInterval = 2

    private let rootPID: pid_t
    private let lock = NSLock()
    private var tracker: SeatbeltPidTracker?
    private var terminationRequested = false

    public init?(rootPID: pid_t) {
        guard rootPID > 0 else {
            return nil
        }
        self.rootPID = rootPID
        self.tracker = SeatbeltPidTracker(rootPID: rootPID)
    }

    public func requestTermination(gracePeriod: TimeInterval = ProcessTreeSupervisor.defaultTerminationGracePeriod) {
        Task.detached { [self] in
            terminateProcessTree(gracePeriod: gracePeriod)
        }
    }

    public func terminateProcessTree(gracePeriod: TimeInterval = ProcessTreeSupervisor.defaultTerminationGracePeriod) {
        let shouldTerminate = lock.withLock {
            guard !terminationRequested else {
                return false
            }
            terminationRequested = true
            return true
        }
        guard shouldTerminate else {
            return
        }

        let pids = signalTrackedProcessTree(signal: SIGTERM, includeRoot: true)
        guard !pids.isEmpty else {
            return
        }
        if waitForExit(of: pids, timeout: gracePeriod) {
            return
        }
        signalPIDs(pids, signal: SIGKILL)
        _ = waitForExit(of: pids, timeout: gracePeriod)
    }

    public func terminateDescendants(signal: Int32 = SIGKILL) {
        _ = signalTrackedProcessTree(signal: signal, includeRoot: false)
    }

    private func signalTrackedProcessTree(signal: Int32, includeRoot: Bool) -> Set<pid_t> {
        let pids = trackedProcessTree(includeRoot: includeRoot)
        signalPIDs(pids, signal: signal)
        return pids
    }

    private func trackedProcessTree(includeRoot: Bool) -> Set<pid_t> {
        var pids = lock.withLock {
            let tracked = tracker?.stop() ?? []
            tracker = nil
            return tracked
        }
        collectDescendants(of: rootPID, into: &pids)
        if includeRoot {
            pids.insert(rootPID)
        } else {
            pids.remove(rootPID)
        }
        return pids.filter { $0 > 0 && processTreePIDIsAlive($0) }
    }

    private func collectDescendants(of parent: pid_t, into pids: inout Set<pid_t>) {
        for child in listChildPIDs(parent: parent) {
            if pids.insert(child).inserted {
                collectDescendants(of: child, into: &pids)
            }
        }
    }

    private func signalPIDs(_ pids: Set<pid_t>, signal: Int32) {
        for pid in pids.sorted(by: >) where processTreePIDIsAlive(pid) {
            _ = Darwin.kill(pid, signal)
        }
    }

    private func waitForExit(of pids: Set<pid_t>, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ !processTreePIDIsAlive($0) }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return pids.allSatisfy { !processTreePIDIsAlive($0) }
    }
}

private func processTreePIDIsAlive(_ pid: pid_t) -> Bool {
    guard pid > 0 else {
        return false
    }
    let result = Darwin.kill(pid, 0)
    if result == 0 {
        return true
    }
    return errno == EPERM
}
