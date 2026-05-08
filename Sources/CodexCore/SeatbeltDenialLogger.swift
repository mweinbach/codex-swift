import Darwin
import Dispatch
import Foundation

struct SeatbeltSandboxDenial: Equatable, Hashable, Sendable {
    let name: String
    let capability: String
}

enum SeatbeltDenialLogParser {
    static func parseDenials(from logs: String, trackedPIDs: Set<pid_t>) -> [SeatbeltSandboxDenial] {
        guard !trackedPIDs.isEmpty else {
            return []
        }

        var seen: Set<SeatbeltSandboxDenial> = []
        var denials: [SeatbeltSandboxDenial] = []

        for line in logs.split(separator: "\n", omittingEmptySubsequences: false) {
            guard
                let message = eventMessage(from: String(line)),
                let parsed = parseMessage(message),
                trackedPIDs.contains(parsed.pid)
            else {
                continue
            }

            let denial = SeatbeltSandboxDenial(name: parsed.name, capability: parsed.capability)
            if seen.insert(denial).inserted {
                denials.append(denial)
            }
        }

        return denials
    }

    private static func eventMessage(from line: String) -> String? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["eventMessage"] as? String
        else {
            return nil
        }
        return message
    }

    private static func parseMessage(_ message: String) -> (pid: pid_t, name: String, capability: String)? {
        let nsRange = NSRange(message.startIndex..<message.endIndex, in: message)
        guard
            let match = Self.denialMessageRegex.firstMatch(in: message, range: nsRange),
            match.numberOfRanges == 4,
            let nameRange = Range(match.range(at: 1), in: message),
            let pidRange = Range(match.range(at: 2), in: message),
            let capabilityRange = Range(match.range(at: 3), in: message),
            let pid = pid_t(String(message[pidRange]))
        else {
            return nil
        }

        return (
            pid: pid,
            name: String(message[nameRange]),
            capability: String(message[capabilityRange])
        )
    }

    private static let denialMessageRegex = try! NSRegularExpression(
        pattern: #"^Sandbox:\s*(.+?)\((\d+)\)\s+deny\(.*?\)\s*(.+)$"#
    )
}

final class SeatbeltDenialLogger: @unchecked Sendable {
    private static let logExecutablePath = "/usr/bin/log"
    private static let predicate = #"(((processID == 0) AND (senderImagePath CONTAINS "/Sandbox")) OR (subsystem == "com.apple.sandbox.reporting"))"#

    private let logStream: Process
    private let reader: SeatbeltLogReader
    private var pidTracker: SeatbeltPidTracker?

    private init(logStream: Process, reader: SeatbeltLogReader) {
        self.logStream = logStream
        self.reader = reader
    }

    static func start(logExecutablePath: String = SeatbeltDenialLogger.logExecutablePath) -> SeatbeltDenialLogger? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: logExecutablePath)
        process.arguments = [
            "stream",
            "--style",
            "ndjson",
            "--predicate",
            Self.predicate
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        return SeatbeltDenialLogger(
            logStream: process,
            reader: SeatbeltLogReader(fileHandle: stdout.fileHandleForReading)
        )
    }

    func onChildSpawn(_ rootPID: pid_t) {
        pidTracker = SeatbeltPidTracker(rootPID: rootPID)
    }

    func finish() -> [SeatbeltSandboxDenial] {
        let trackedPIDs = pidTracker?.stop() ?? []
        guard !trackedPIDs.isEmpty else {
            stopLogStream()
            return []
        }

        stopLogStream()
        let logs = String(decoding: reader.wait(), as: UTF8.self)
        return SeatbeltDenialLogParser.parseDenials(from: logs, trackedPIDs: trackedPIDs)
    }

    static func formatSummary(denials: [SeatbeltSandboxDenial]) -> Data {
        var lines = ["", "=== Sandbox denials ==="]
        if denials.isEmpty {
            lines.append("None found.")
        } else {
            lines.append(contentsOf: denials.map { "(\($0.name)) \($0.capability)" })
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func stopLogStream() {
        if logStream.isRunning {
            Darwin.kill(logStream.processIdentifier, SIGKILL)
            logStream.waitUntilExit()
        }
    }
}

private final class SeatbeltLogReader: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let storage = SeatbeltLogStorage()

    init(fileHandle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [done, storage] in
            storage.set(fileHandle.readDataToEndOfFile())
            done.signal()
        }
    }

    func wait() -> Data {
        done.wait()
        return storage.data()
    }
}

private final class SeatbeltLogStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class SeatbeltPidTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openai.codex-swift.seatbelt-pid-tracker")
    private var seen: Set<pid_t> = []
    private var active: Set<pid_t> = []
    private var sources: [pid_t: DispatchSourceProcess] = [:]
    private var stopped = false

    init?(rootPID: pid_t) {
        guard rootPID > 0 else {
            return nil
        }
        queue.sync {
            addPIDWatch(rootPID)
        }
    }

    func stop() -> Set<pid_t> {
        queue.sync {
            stopped = true
            for source in sources.values {
                source.cancel()
            }
            sources.removeAll()
            active.removeAll()
            return seen
        }
    }

    private func addPIDWatch(_ pid: pid_t) {
        guard pid > 0, !stopped else {
            return
        }

        let newlySeen = seen.insert(pid).inserted
        var shouldRecurse = newlySeen

        if active.insert(pid).inserted {
            guard pidIsAlive(pid) else {
                active.remove(pid)
                return
            }

            let source = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: [.fork, .exec, .exit],
                queue: queue
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source, !self.stopped else {
                    return
                }
                let event = source.data
                if event.contains(.fork) {
                    self.watchChildren(parent: pid)
                }
                if event.contains(.exit) {
                    self.active.remove(pid)
                    self.sources[pid]?.cancel()
                    self.sources[pid] = nil
                }
            }
            sources[pid] = source
            source.resume()
            shouldRecurse = true
        }

        if shouldRecurse {
            watchChildren(parent: pid)
        }
    }

    private func watchChildren(parent: pid_t) {
        for childPID in listChildPIDs(parent: parent) {
            addPIDWatch(childPID)
        }
    }
}

func listChildPIDs(parent: pid_t) -> [pid_t] {
    var capacity = 16
    while true {
        var buffer = [pid_t](repeating: 0, count: capacity)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_listchildpids(
                parent,
                pointer.baseAddress,
                Int32(pointer.count * MemoryLayout<pid_t>.stride)
            )
        }

        guard count > 0 else {
            return []
        }

        let returned = Int(count)
        if returned < capacity {
            return Array(buffer.prefix(returned))
        }
        capacity = max(capacity * 2, returned + 16)
    }
}

private func pidIsAlive(_ pid: pid_t) -> Bool {
    guard pid > 0 else {
        return false
    }

    let result = Darwin.kill(pid, 0)
    if result == 0 {
        return true
    }
    return errno == EPERM
}
