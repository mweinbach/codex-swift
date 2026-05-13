import Foundation

public let rawMemoriesFilename = "raw_memories.md"
public let rolloutSummariesSubdirectory = "rollout_summaries"
public let memoryExtensionsSubdirectory = "extensions"

public func rawMemoriesFile(root: URL) -> URL {
    root.appendingPathComponent(rawMemoriesFilename, isDirectory: false)
}

public func rolloutSummariesDirectory(root: URL) -> URL {
    root.appendingPathComponent(rolloutSummariesSubdirectory, isDirectory: true)
}

public func memoryExtensionsRoot(root: URL) -> URL {
    root.appendingPathComponent(memoryExtensionsSubdirectory, isDirectory: true)
}

public func ensureMemoryLayout(root: URL) throws {
    try FileManager.default.createDirectory(
        at: rolloutSummariesDirectory(root: root),
        withIntermediateDirectories: true
    )
}

/// Rebuild `raw_memories.md` from DB-backed stage-1 outputs.
public func rebuildRawMemoriesFileFromMemories(
    root: URL,
    memories: [Stage1Output],
    maxRawMemoriesForConsolidation: Int
) throws {
    try ensureMemoryLayout(root: root)
    let retained = retainedMemories(memories, limit: maxRawMemoriesForConsolidation)
    var body = "# Raw Memories\n\n"

    if retained.isEmpty {
        body += "No raw memories yet.\n"
        try body.write(to: rawMemoriesFile(root: root), atomically: true, encoding: .utf8)
        return
    }

    body += "Merged stage-1 raw memories (stable ascending thread-id order):\n\n"
    for memory in retained {
        body += "## Thread `\(memory.threadID)`\n"
        body += "updated_at: \(rustRFC3339String(memory.sourceUpdatedAt))\n"
        body += "cwd: \(memory.cwd)\n"
        body += "rollout_path: \(memory.rolloutPath)\n"
        body += "rollout_summary_file: \(rolloutSummaryFileStem(memory)).md\n\n"
        body += memory.rawMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        body += "\n\n"
    }

    try body.write(to: rawMemoriesFile(root: root), atomically: true, encoding: .utf8)
}

/// Sync canonical rollout summary files from DB-backed stage-1 output rows.
public func syncRolloutSummariesFromMemories(
    root: URL,
    memories: [Stage1Output],
    maxRawMemoriesForConsolidation: Int
) throws {
    try ensureMemoryLayout(root: root)

    let retained = retainedMemories(memories, limit: maxRawMemoriesForConsolidation)
    let keep = Set(retained.map(rolloutSummaryFileStem))
    try pruneRolloutSummaries(root: root, keeping: keep)

    for memory in retained {
        try writeRolloutSummary(root: root, memory: memory)
    }
}

public func rolloutSummaryFileStem(_ memory: Stage1Output) -> String {
    rolloutSummaryFileStem(
        threadID: memory.threadID,
        sourceUpdatedAt: memory.sourceUpdatedAt,
        rolloutSlug: memory.rolloutSlug
    )
}

func rolloutSummaryFileStem(
    threadID: ThreadId,
    sourceUpdatedAt: Date,
    rolloutSlug: String?
) -> String {
    let bytes = threadID.uuid.codexBytes
    let timestamp = uuidV7Date(bytes: bytes) ?? sourceUpdatedAt
    let shortHashSeed = UInt32(bytes[12]) << 24
        | UInt32(bytes[13]) << 16
        | UInt32(bytes[14]) << 8
        | UInt32(bytes[15])
    let filePrefix = "\(timestampFragment(timestamp))-\(shortHash(seed: shortHashSeed))"

    guard let rolloutSlug else {
        return filePrefix
    }

    var slug = ""
    for scalar in rolloutSlug.unicodeScalars {
        if slug.utf8.count >= 60 {
            break
        }
        if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
            slug.append(Character(scalar).lowercased())
        } else {
            slug.append("_")
        }
    }
    while slug.last == "_" {
        slug.removeLast()
    }

    if slug.isEmpty {
        return filePrefix
    }
    return "\(filePrefix)-\(slug)"
}

private func retainedMemories(_ memories: [Stage1Output], limit: Int) -> ArraySlice<Stage1Output> {
    memories.prefix(max(0, min(memories.count, limit)))
}

private func pruneRolloutSummaries(root: URL, keeping keep: Set<String>) throws {
    let directory = rolloutSummariesDirectory(root: root)
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )) ?? []

    for path in contents {
        guard path.pathExtension == "md" else {
            continue
        }
        let stem = path.deletingPathExtension().lastPathComponent
        if !keep.contains(stem) {
            try? FileManager.default.removeItem(at: path)
        }
    }
}

private func writeRolloutSummary(root: URL, memory: Stage1Output) throws {
    let path = rolloutSummariesDirectory(root: root)
        .appendingPathComponent("\(rolloutSummaryFileStem(memory)).md", isDirectory: false)
    var body = ""
    body += "thread_id: \(memory.threadID)\n"
    body += "updated_at: \(rustRFC3339String(memory.sourceUpdatedAt))\n"
    body += "rollout_path: \(memory.rolloutPath)\n"
    body += "cwd: \(memory.cwd)\n"
    if let gitBranch = memory.gitBranch {
        body += "git_branch: \(gitBranch)\n"
    }
    body += "\n"
    body += memory.rolloutSummary
    body += "\n"

    try body.write(to: path, atomically: true, encoding: .utf8)
}

private func rustRFC3339String(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
    return formatter.string(from: date)
}

private func timestampFragment(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return formatter.string(from: date)
}

private func uuidV7Date(bytes: [UInt8]) -> Date? {
    guard bytes.count == 16, bytes[6] >> 4 == 0x7 else {
        return nil
    }
    let milliseconds = UInt64(bytes[0]) << 40
        | UInt64(bytes[1]) << 32
        | UInt64(bytes[2]) << 24
        | UInt64(bytes[3]) << 16
        | UInt64(bytes[4]) << 8
        | UInt64(bytes[5])
    return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
}

private func shortHash(seed: UInt32) -> String {
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var value = seed % 14_776_336
    var characters = Array(repeating: Character("0"), count: 4)
    for index in stride(from: characters.count - 1, through: 0, by: -1) {
        characters[index] = alphabet[Int(value % UInt32(alphabet.count))]
        value /= UInt32(alphabet.count)
    }
    return String(characters)
}

private extension UUID {
    var codexBytes: [UInt8] {
        [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5,
            uuid.6, uuid.7,
            uuid.8, uuid.9,
            uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ]
    }
}
