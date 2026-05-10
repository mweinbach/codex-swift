import Darwin
import Foundation

final class ExecServerPseudoTerminal {
    let master: FileHandle
    let stdinHandle: FileHandle
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle
    private let lock = NSLock()
    private var closed = false

    init() throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var windowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &windowSize) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        stdinHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        stdoutHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        stderrHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        close(slaveFD)
    }

    deinit {
        closeMaster()
    }

    func closeSlaveHandles() {
        try? stdinHandle.close()
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    func closeMaster() {
        let shouldClose = lock.withLock {
            guard !closed else {
                return false
            }
            closed = true
            return true
        }
        if shouldClose {
            try? master.close()
        }
    }
}
