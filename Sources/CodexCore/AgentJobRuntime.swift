import Foundation

public enum AgentJobRuntime {
    public static let defaultConcurrency = 16
    public static let maxConcurrency = 64
    public static let defaultItemTimeout: TimeInterval = 60 * 30

    public static func normalizeConcurrency(requested: Int?, maxThreads: Int?) -> Int {
        let requested = max(requested ?? defaultConcurrency, 1)
        let cappedRequested = min(requested, maxConcurrency)
        if let maxThreads {
            return min(cappedRequested, max(maxThreads, 1))
        }
        return cappedRequested
    }

    public static func normalizeMaxRuntimeSeconds(_ requested: UInt64?) throws -> UInt64? {
        guard let requested else {
            return nil
        }
        guard requested > 0 else {
            throw FunctionCallError.respondToModel("max_runtime_seconds must be >= 1")
        }
        return requested
    }

    public static func itemTimeout(for job: AgentJob) -> TimeInterval {
        job.maxRuntimeSeconds.map(TimeInterval.init) ?? defaultItemTimeout
    }

    public static func buildWorkerPrompt(job: AgentJob, item: AgentJobItem) -> String {
        let instruction = AgentJobCSV.renderInstructionTemplate(job.instruction, rowJSON: item.rowJSON)
        let outputSchema = job.outputSchemaJSON.map(AgentJobCSV.prettyJSONString) ?? "{}"
        let rowJSON = AgentJobCSV.prettyJSONString(item.rowJSON)
        return """
        You are processing one item for a generic agent job.
        Job ID: \(job.id)
        Item ID: \(item.itemID)

        Task instruction:
        \(instruction)

        Input row (JSON):
        \(rowJSON)

        Expected result schema (JSON Schema or {}):
        \(outputSchema)

        You MUST call the `report_agent_job_result` tool exactly once with:
        1. `job_id` = "\(job.id)"
        2. `item_id` = "\(item.itemID)"
        3. `result` = a JSON object that contains your analysis result for this row.

        If you need to stop the job early, include `stop` = true in the tool call.

        After the tool call succeeds, stop.
        """
    }

    public static func makeSpawnResult(
        job: AgentJob,
        progress: AgentJobProgress,
        failedItems: [AgentJobItem]
    ) -> SpawnAgentsOnCSVResult {
        var jobError = job.lastError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? job.lastError
            : nil
        let summaries = failedItems.compactMap { item -> AgentJobFailureSummary? in
            guard let lastError = item.lastError,
                  !lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return AgentJobFailureSummary(
                itemID: item.itemID,
                sourceID: item.sourceID,
                lastError: lastError
            )
        }
        let failedItemErrors: [AgentJobFailureSummary]?
        if progress.failed > 0, summaries.isEmpty {
            if jobError == nil {
                jobError = "agent job has failed items but no error details were recorded"
            }
            failedItemErrors = nil
        } else {
            failedItemErrors = summaries.isEmpty ? nil : summaries
        }
        return SpawnAgentsOnCSVResult(
            jobID: job.id,
            status: job.status.rawValue,
            outputCSVPath: job.outputCSVPath,
            totalItems: progress.totalItems,
            completedItems: progress.completed,
            failedItems: progress.failed,
            jobError: jobError,
            failedItemErrors: failedItemErrors
        )
    }

    public static func exportJobCSVSnapshot(
        store: SQLiteAgentJobStore,
        job: AgentJob,
        fileManager: FileManager = .default
    ) async throws {
        let items = try await store.listAgentJobItems(jobID: job.id)
        let csvContent: String
        do {
            csvContent = try AgentJobCSV.renderJobCSV(inputHeaders: job.inputHeaders, items: items)
        } catch {
            throw FunctionCallError.respondToModel("failed to render job csv for auto-export: \(error)")
        }

        let outputURL = URL(fileURLWithPath: job.outputCSVPath)
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try csvContent.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    public static func makeSpawnAgentsOnCSVResult(
        store: SQLiteAgentJobStore,
        job: AgentJob,
        fileManager: FileManager = .default
    ) async throws -> SpawnAgentsOnCSVResult {
        if !fileManager.fileExists(atPath: job.outputCSVPath) {
            do {
                try await exportJobCSVSnapshot(store: store, job: job, fileManager: fileManager)
            } catch {
                throw FunctionCallError.respondToModel("failed to export output csv \(job.id): \(error)")
            }
        }

        let progress = try await store.getAgentJobProgress(job.id)
        let failedItems = progress.failed > 0
            ? try await store.listAgentJobItems(jobID: job.id, status: .failed, limit: 5)
            : []
        return makeSpawnResult(job: job, progress: progress, failedItems: failedItems)
    }

    public static func recoverRunningItems(
        store: SQLiteAgentJobStore,
        jobID: String,
        runtimeTimeout: TimeInterval,
        now: Date = Date(),
        statusForThread: @Sendable (ThreadId) async -> AgentStatus,
        shutdownThread: @Sendable (ThreadId) async -> Void
    ) async throws -> [ActiveAgentJobItem] {
        let runningItems = try await store.listAgentJobItems(jobID: jobID, status: .running)
        var activeItems: [ActiveAgentJobItem] = []
        for item in runningItems {
            if isItemStale(item, runtimeTimeout: runtimeTimeout, now: now) {
                _ = try await store.markAgentJobItemFailed(
                    jobID: jobID,
                    itemID: item.itemID,
                    errorMessage: staleWorkerErrorMessage(runtimeTimeout: runtimeTimeout)
                )
                if let assignedThreadID = item.assignedThreadID,
                   let threadID = try? ThreadId(string: assignedThreadID)
                {
                    await shutdownThread(threadID)
                }
                continue
            }

            guard let assignedThreadID = item.assignedThreadID else {
                _ = try await store.markAgentJobItemFailed(
                    jobID: jobID,
                    itemID: item.itemID,
                    errorMessage: "running item is missing assigned_thread_id"
                )
                continue
            }

            let threadID: ThreadId
            do {
                threadID = try ThreadId(string: assignedThreadID)
            } catch {
                _ = try await store.markAgentJobItemFailed(
                    jobID: jobID,
                    itemID: item.itemID,
                    errorMessage: "invalid assigned_thread_id: \(error)"
                )
                continue
            }

            if await statusForThread(threadID).isFinal {
                try await finalizeFinishedItem(
                    store: store,
                    jobID: jobID,
                    itemID: item.itemID,
                    threadID: threadID,
                    shutdownThread: shutdownThread
                )
            } else {
                activeItems.append(ActiveAgentJobItem(
                    threadID: threadID,
                    itemID: item.itemID,
                    startedAt: startedAt(from: item, now: now)
                ))
            }
        }
        return activeItems
    }

    public static func findFinishedThreads(
        activeItems: [ActiveAgentJobItem],
        statusForThread: @Sendable (ThreadId) async -> AgentStatus
    ) async -> [(threadID: ThreadId, itemID: String)] {
        var finished: [(threadID: ThreadId, itemID: String)] = []
        for item in activeItems {
            if await statusForThread(item.threadID).isFinal {
                finished.append((item.threadID, item.itemID))
            }
        }
        return finished
    }

    public static func reapStaleActiveItems(
        store: SQLiteAgentJobStore,
        jobID: String,
        activeItems: [ActiveAgentJobItem],
        runtimeTimeout: TimeInterval,
        now: Date = Date(),
        shutdownThread: @Sendable (ThreadId) async -> Void
    ) async throws -> (remainingItems: [ActiveAgentJobItem], didProgress: Bool) {
        var remainingItems: [ActiveAgentJobItem] = []
        var didProgress = false
        for item in activeItems {
            if now.timeIntervalSince(item.startedAt) >= runtimeTimeout {
                _ = try await store.markAgentJobItemFailed(
                    jobID: jobID,
                    itemID: item.itemID,
                    errorMessage: staleWorkerErrorMessage(runtimeTimeout: runtimeTimeout)
                )
                await shutdownThread(item.threadID)
                didProgress = true
            } else {
                remainingItems.append(item)
            }
        }
        return (remainingItems, didProgress)
    }

    public static func finalizeFinishedItem(
        store: SQLiteAgentJobStore,
        jobID: String,
        itemID: String,
        threadID: ThreadId,
        shutdownThread: @Sendable (ThreadId) async -> Void
    ) async throws {
        guard let item = try await store.getAgentJobItem(jobID: jobID, itemID: itemID) else {
            throw FunctionCallError.respondToModel("job item not found for finalization: \(jobID)/\(itemID)")
        }
        if item.status == .running {
            if item.resultJSON != nil {
                _ = try await store.markAgentJobItemCompleted(jobID: jobID, itemID: itemID)
            } else {
                _ = try await store.markAgentJobItemFailed(
                    jobID: jobID,
                    itemID: itemID,
                    errorMessage: "worker finished without calling report_agent_job_result"
                )
            }
        }
        await shutdownThread(threadID)
    }

    public static func decodeReportAgentJobResultArguments(
        _ argumentsJSON: String
    ) throws -> ReportAgentJobResultArguments {
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw FunctionCallError.respondToModel("failed to parse report_agent_job_result arguments")
        }
        do {
            return try JSONDecoder().decode(ReportAgentJobResultArguments.self, from: data)
        } catch {
            throw FunctionCallError.respondToModel(
                "failed to parse report_agent_job_result arguments: \(error)"
            )
        }
    }

    public static func recordReportAgentJobResult(
        argumentsJSON: String,
        reportingThreadID: String,
        store: SQLiteAgentJobStore
    ) async throws -> ReportAgentJobResultToolResult {
        let arguments = try decodeReportAgentJobResultArguments(argumentsJSON)
        return try await recordReportAgentJobResult(
            arguments: arguments,
            reportingThreadID: reportingThreadID,
            store: store
        )
    }

    public static func recordReportAgentJobResult(
        arguments: ReportAgentJobResultArguments,
        reportingThreadID: String,
        store: SQLiteAgentJobStore
    ) async throws -> ReportAgentJobResultToolResult {
        guard case .object = arguments.result else {
            throw FunctionCallError.respondToModel("result must be a JSON object")
        }

        let accepted: Bool
        do {
            accepted = try await store.reportAgentJobItemResult(
                jobID: arguments.jobID,
                itemID: arguments.itemID,
                reportingThreadID: reportingThreadID,
                resultJSON: arguments.result
            )
        } catch {
            throw FunctionCallError.respondToModel(
                "failed to record agent job result for \(arguments.jobID) / \(arguments.itemID): \(error)"
            )
        }

        if accepted, arguments.stop == true {
            _ = try await store.markAgentJobCancelled(
                arguments.jobID,
                errorMessage: "cancelled by worker request"
            )
        }
        return ReportAgentJobResultToolResult(accepted: accepted)
    }

    public static func decodeSpawnAgentsOnCSVArguments(
        _ argumentsJSON: String
    ) throws -> SpawnAgentsOnCSVArguments {
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw FunctionCallError.respondToModel("failed to parse spawn_agents_on_csv arguments")
        }
        do {
            return try JSONDecoder().decode(SpawnAgentsOnCSVArguments.self, from: data)
        } catch {
            throw FunctionCallError.respondToModel("failed to parse spawn_agents_on_csv arguments: \(error)")
        }
    }

    public static func createSpawnAgentsOnCSVJob(
        argumentsJSON: String,
        csvContent: String,
        cwd: String,
        store: SQLiteAgentJobStore,
        jobID: String = UUID().uuidString,
        maxThreads: Int? = nil,
        configuredMaxRuntimeSeconds: UInt64? = nil
    ) async throws -> PreparedSpawnAgentsOnCSVJob {
        let arguments = try decodeSpawnAgentsOnCSVArguments(argumentsJSON)
        return try await createSpawnAgentsOnCSVJob(
            arguments: arguments,
            csvContent: csvContent,
            cwd: cwd,
            store: store,
            jobID: jobID,
            maxThreads: maxThreads,
            configuredMaxRuntimeSeconds: configuredMaxRuntimeSeconds
        )
    }

    public static func createSpawnAgentsOnCSVJob(
        arguments: SpawnAgentsOnCSVArguments,
        csvContent: String,
        cwd: String,
        store: SQLiteAgentJobStore,
        jobID: String = UUID().uuidString,
        maxThreads: Int? = nil,
        configuredMaxRuntimeSeconds: UInt64? = nil
    ) async throws -> PreparedSpawnAgentsOnCSVJob {
        guard !arguments.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FunctionCallError.respondToModel("instruction must be non-empty")
        }

        let inputCSVPath = resolveSpawnAgentsOnCSVPath(arguments.csvPath, cwd: cwd)
        let document: AgentJobCSVDocument
        do {
            document = try AgentJobCSV.parse(csvContent)
        } catch {
            throw FunctionCallError.respondToModel("failed to parse csv input: \(error)")
        }
        guard !document.headers.isEmpty else {
            throw FunctionCallError.respondToModel("csv input must include a header row")
        }
        try AgentJobCSV.ensureUniqueHeaders(document.headers)
        let items = try AgentJobCSV.makeItems(
            headers: document.headers,
            rows: document.rows,
            idColumn: arguments.idColumn
        )

        let outputCSVPath = arguments.outputCSVPath.map {
            resolveSpawnAgentsOnCSVPath($0, cwd: cwd)
        } ?? AgentJobCSV.defaultOutputCSVPath(inputCSVPath: inputCSVPath, jobID: jobID)
        let maxRuntimeSeconds = try normalizeMaxRuntimeSeconds(
            arguments.maxRuntimeSeconds ?? configuredMaxRuntimeSeconds
        )
        let jobSuffix = String(jobID.prefix(8))
        let job: AgentJob
        do {
            job = try await store.createAgentJob(
                params: AgentJobCreateParams(
                    id: jobID,
                    name: "agent-job-\(jobSuffix)",
                    instruction: arguments.instruction,
                    outputSchemaJSON: arguments.outputSchemaJSON,
                    inputHeaders: document.headers,
                    inputCSVPath: inputCSVPath,
                    outputCSVPath: outputCSVPath,
                    autoExport: true,
                    maxRuntimeSeconds: maxRuntimeSeconds
                ),
                items: items
            )
        } catch {
            throw FunctionCallError.respondToModel("failed to create agent job: \(error)")
        }

        do {
            try await store.markAgentJobRunning(jobID)
        } catch {
            throw FunctionCallError.respondToModel(
                "failed to transition agent job \(jobID) to running: \(error)"
            )
        }

        let requestedConcurrency = arguments.maxConcurrency ?? arguments.maxWorkers
        let runningJob = try await store.getAgentJob(jobID) ?? job
        return PreparedSpawnAgentsOnCSVJob(
            job: runningJob,
            itemCount: items.count,
            concurrency: normalizeConcurrency(requested: requestedConcurrency, maxThreads: maxThreads)
        )
    }

    private static func resolveSpawnAgentsOnCSVPath(_ path: String, cwd: String) -> String {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: cwd, isDirectory: true).appendingPathComponent(path)
        }
        return url.standardizedFileURL.path
    }

    private static func startedAt(from item: AgentJobItem, now: Date) -> Date {
        let age = now.timeIntervalSince(item.updatedAt)
        guard age >= 0 else {
            return now
        }
        return now.addingTimeInterval(-age)
    }

    private static func isItemStale(_ item: AgentJobItem, runtimeTimeout: TimeInterval, now: Date) -> Bool {
        let age = now.timeIntervalSince(item.updatedAt)
        return age >= runtimeTimeout
    }

    private static func staleWorkerErrorMessage(runtimeTimeout: TimeInterval) -> String {
        "worker exceeded max runtime of \(rustDurationDebug(runtimeTimeout))"
    }

    private static func rustDurationDebug(_ interval: TimeInterval) -> String {
        if interval.rounded(.towardZero) == interval {
            return "\(Int(interval))s"
        }
        let milliseconds = interval * 1_000
        if milliseconds.rounded(.towardZero) == milliseconds {
            return "\(Int(milliseconds))ms"
        }
        return "\(interval)s"
    }
}

public struct ActiveAgentJobItem: Equatable, Sendable {
    public var threadID: ThreadId
    public var itemID: String
    public var startedAt: Date

    public init(threadID: ThreadId, itemID: String, startedAt: Date) {
        self.threadID = threadID
        self.itemID = itemID
        self.startedAt = startedAt
    }
}

public struct SpawnAgentsOnCSVArguments: Equatable, Codable, Sendable {
    public var csvPath: String
    public var instruction: String
    public var maxConcurrency: Int?
    public var maxWorkers: Int?
    public var idColumn: String?
    public var outputCSVPath: String?
    public var outputSchemaJSON: JSONValue?
    public var maxRuntimeSeconds: UInt64?

    private enum CodingKeys: String, CodingKey {
        case csvPath = "csv_path"
        case instruction
        case maxConcurrency = "max_concurrency"
        case maxWorkers = "max_workers"
        case idColumn = "id_column"
        case outputCSVPath = "output_csv_path"
        case outputSchemaJSON = "output_schema"
        case maxRuntimeSeconds = "max_runtime_seconds"
    }

    public init(
        csvPath: String,
        instruction: String,
        maxConcurrency: Int? = nil,
        maxWorkers: Int? = nil,
        idColumn: String? = nil,
        outputCSVPath: String? = nil,
        outputSchemaJSON: JSONValue? = nil,
        maxRuntimeSeconds: UInt64? = nil
    ) {
        self.csvPath = csvPath
        self.instruction = instruction
        self.maxConcurrency = maxConcurrency
        self.maxWorkers = maxWorkers
        self.idColumn = idColumn
        self.outputCSVPath = outputCSVPath
        self.outputSchemaJSON = outputSchemaJSON
        self.maxRuntimeSeconds = maxRuntimeSeconds
    }
}

public struct PreparedSpawnAgentsOnCSVJob: Equatable, Sendable {
    public var job: AgentJob
    public var itemCount: Int
    public var concurrency: Int

    public init(job: AgentJob, itemCount: Int, concurrency: Int) {
        self.job = job
        self.itemCount = itemCount
        self.concurrency = concurrency
    }
}

public struct ReportAgentJobResultArguments: Equatable, Codable, Sendable {
    public var jobID: String
    public var itemID: String
    public var result: JSONValue
    public var stop: Bool?

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case itemID = "item_id"
        case result
        case stop
    }

    public init(jobID: String, itemID: String, result: JSONValue, stop: Bool? = nil) {
        self.jobID = jobID
        self.itemID = itemID
        self.result = result
        self.stop = stop
    }
}

public struct SpawnAgentsOnCSVResult: Equatable, Codable, Sendable {
    public var jobID: String
    public var status: String
    public var outputCSVPath: String
    public var totalItems: Int64
    public var completedItems: Int64
    public var failedItems: Int64
    public var jobError: String?
    public var failedItemErrors: [AgentJobFailureSummary]?

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case outputCSVPath = "output_csv_path"
        case totalItems = "total_items"
        case completedItems = "completed_items"
        case failedItems = "failed_items"
        case jobError = "job_error"
        case failedItemErrors = "failed_item_errors"
    }

    public init(
        jobID: String,
        status: String,
        outputCSVPath: String,
        totalItems: Int64,
        completedItems: Int64,
        failedItems: Int64,
        jobError: String?,
        failedItemErrors: [AgentJobFailureSummary]?
    ) {
        self.jobID = jobID
        self.status = status
        self.outputCSVPath = outputCSVPath
        self.totalItems = totalItems
        self.completedItems = completedItems
        self.failedItems = failedItems
        self.jobError = jobError
        self.failedItemErrors = failedItemErrors
    }
}

public struct AgentJobFailureSummary: Equatable, Codable, Sendable {
    public var itemID: String
    public var sourceID: String?
    public var lastError: String

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case sourceID = "source_id"
        case lastError = "last_error"
    }

    public init(itemID: String, sourceID: String?, lastError: String) {
        self.itemID = itemID
        self.sourceID = sourceID
        self.lastError = lastError
    }
}

public struct ReportAgentJobResultToolResult: Equatable, Codable, Sendable {
    public var accepted: Bool

    public init(accepted: Bool) {
        self.accepted = accepted
    }
}
