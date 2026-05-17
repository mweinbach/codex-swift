import Foundation

public struct AgentJobToolContext: Sendable {
    public var store: SQLiteAgentJobStore
    public var reportingThreadID: String
    public var maxThreads: Int?
    public var sessionSource: SessionSource
    public var maxDepth: Int32?
    public var spawnConfigSource: AgentJobSpawnConfigSource?
    public var environments: [TurnEnvironmentSelection]?
    public var remoteEnvironmentIDs: Set<String>
    public var configuredMaxRuntimeSeconds: UInt64?
    public var statusForThread: (@Sendable (ThreadId) async -> AgentStatus)?
    public var spawnWorker: (@Sendable (AgentJobWorkerSpawnRequest) async -> AgentJobWorkerSpawnResult)?
    public var shutdownThread: (@Sendable (ThreadId) async -> Void)?
    public var waitWhenIdle: (@Sendable () async -> Void)?

    public init(
        store: SQLiteAgentJobStore,
        reportingThreadID: String,
        maxThreads: Int? = nil,
        sessionSource: SessionSource = .default,
        maxDepth: Int32? = nil,
        spawnConfigSource: AgentJobSpawnConfigSource? = nil,
        environments: [TurnEnvironmentSelection]? = nil,
        remoteEnvironmentIDs: Set<String> = [],
        configuredMaxRuntimeSeconds: UInt64? = nil,
        statusForThread: (@Sendable (ThreadId) async -> AgentStatus)? = nil,
        spawnWorker: (@Sendable (AgentJobWorkerSpawnRequest) async -> AgentJobWorkerSpawnResult)? = nil,
        shutdownThread: (@Sendable (ThreadId) async -> Void)? = nil,
        waitWhenIdle: (@Sendable () async -> Void)? = nil
    ) {
        self.store = store
        self.reportingThreadID = reportingThreadID
        self.maxThreads = maxThreads
        self.sessionSource = sessionSource
        self.maxDepth = maxDepth
        self.spawnConfigSource = spawnConfigSource
        self.environments = environments
        self.remoteEnvironmentIDs = remoteEnvironmentIDs
        self.configuredMaxRuntimeSeconds = configuredMaxRuntimeSeconds
        self.statusForThread = statusForThread
        self.spawnWorker = spawnWorker
        self.shutdownThread = shutdownThread
        self.waitWhenIdle = waitWhenIdle
    }
}

public enum AgentJobToolExecutor {
    public static func execute(
        name: String,
        arguments: String,
        callID: String,
        cwd: URL,
        context: AgentJobToolContext?
    ) async -> ResponseItem? {
        switch name {
        case "spawn_agents_on_csv":
            guard let context,
                  let statusForThread = context.statusForThread,
                  let spawnWorker = context.spawnWorker,
                  let shutdownThread = context.shutdownThread
            else {
                return functionOutput(callID: callID, content: "unsupported call: \(name)", success: false)
            }
            do {
                let executionCwd = try spawnAgentsOnCSVExecutionCwd(
                    selections: context.environments,
                    remoteEnvironmentIDs: context.remoteEnvironmentIDs,
                    defaultCwd: cwd
                )
                let inputCSVPath = resolvePath(
                    try AgentJobRuntime.decodeSpawnAgentsOnCSVArguments(arguments).csvPath,
                    cwd: executionCwd
                )
                let csvContent: String
                do {
                    csvContent = try String(contentsOfFile: inputCSVPath, encoding: .utf8)
                } catch {
                    throw FunctionCallError.respondToModel(
                        "failed to read csv input \(inputCSVPath): \(error)"
                    )
                }
                let prepared = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                    argumentsJSON: arguments,
                    csvContent: csvContent,
                    cwd: executionCwd.path,
                    store: context.store,
                    maxThreads: context.maxThreads,
                    sessionSource: context.sessionSource,
                    maxDepth: context.maxDepth,
                    spawnConfigSource: context.spawnConfigSource,
                    configuredMaxRuntimeSeconds: context.configuredMaxRuntimeSeconds
                )
                let finalJob: AgentJob
                do {
                    finalJob = try await AgentJobRuntime.runAgentJobLoop(
                        store: context.store,
                        jobID: prepared.job.id,
                        maxConcurrency: prepared.concurrency,
                        spawnConfig: prepared.spawnConfig,
                        environments: context.environments,
                        statusForThread: statusForThread,
                        spawnWorker: spawnWorker,
                        shutdownThread: shutdownThread,
                        waitWhenIdle: context.waitWhenIdle ?? {}
                    )
                } catch {
                    let errorMessage = "job runner failed: \(error)"
                    try? await context.store.markAgentJobFailed(
                        prepared.job.id,
                        errorMessage: errorMessage
                    )
                    throw FunctionCallError.respondToModel(
                        "agent job \(prepared.job.id) failed: \(error)"
                    )
                }
                let result = try await AgentJobRuntime.makeSpawnAgentsOnCSVResult(
                    store: context.store,
                    job: finalJob
                )
                let data = try JSONEncoder().encode(result)
                return functionOutput(
                    callID: callID,
                    content: String(decoding: data, as: UTF8.self),
                    success: true
                )
            } catch let error as FunctionCallError {
                return functionOutput(callID: callID, content: error.description, success: false)
            } catch {
                return functionOutput(
                    callID: callID,
                    content: "failed to handle \(name): \(String(describing: error))",
                    success: false
                )
            }

        case "report_agent_job_result":
            guard let context,
                  AgentJobRuntime.isAgentJobWorkerSessionSource(context.sessionSource)
            else {
                return functionOutput(callID: callID, content: "unsupported call: \(name)", success: false)
            }
            do {
                let result = try await AgentJobRuntime.recordReportAgentJobResult(
                    argumentsJSON: arguments,
                    reportingThreadID: context.reportingThreadID,
                    store: context.store
                )
                let data = try JSONEncoder().encode(result)
                return functionOutput(
                    callID: callID,
                    content: String(decoding: data, as: UTF8.self),
                    success: true
                )
            } catch let error as FunctionCallError {
                return functionOutput(callID: callID, content: error.description, success: false)
            } catch {
                return functionOutput(
                    callID: callID,
                    content: "failed to handle \(name): \(String(describing: error))",
                    success: false
                )
            }

        default:
            return nil
        }
    }

    private static func resolvePath(_ path: String, cwd: URL) -> String {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : cwd.appendingPathComponent(path)
        return url.standardizedFileURL.path
    }

    private static func spawnAgentsOnCSVExecutionCwd(
        selections: [TurnEnvironmentSelection]?,
        remoteEnvironmentIDs: Set<String>,
        defaultCwd: URL
    ) throws -> URL {
        guard let selections else {
            return defaultCwd.standardizedFileURL
        }
        guard selections.count == 1, let selection = selections.first else {
            throw FunctionCallError.respondToModel("spawn_agents_on_csv requires exactly one local environment")
        }
        if remoteEnvironmentIDs.contains(selection.environmentID) {
            throw FunctionCallError.respondToModel("spawn_agents_on_csv is not supported for remote environments")
        }
        return URL(fileURLWithPath: selection.cwd, isDirectory: true).standardizedFileURL
    }

    private static func functionOutput(callID: String, content: String, success: Bool) -> ResponseItem {
        .functionCallOutput(
            callID: callID,
            output: FunctionCallOutputPayload(content: content, success: success)
        )
    }
}
