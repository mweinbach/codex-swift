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
