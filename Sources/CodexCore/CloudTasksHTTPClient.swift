import Foundation

public enum CloudTasksPathStyle: Equatable, Sendable {
    case codexAPI
    case chatGPTAPI

    public static func fromBaseURL(_ baseURL: String) -> CloudTasksPathStyle {
        baseURL.contains("/backend-api") ? .chatGPTAPI : .codexAPI
    }
}

public struct CloudGitApplyRequest: Equatable, Sendable {
    public let cwd: URL
    public let diff: String
    public let revert: Bool
    public let preflight: Bool

    public init(cwd: URL, diff: String, revert: Bool = false, preflight: Bool) {
        self.cwd = cwd
        self.diff = diff
        self.revert = revert
        self.preflight = preflight
    }
}

public struct CloudGitApplyResult: Equatable, Sendable {
    public let exitCode: Int32
    public let appliedPaths: [String]
    public let skippedPaths: [String]
    public let conflictedPaths: [String]
    public let stdout: String
    public let stderr: String
    public let commandForLog: String

    public init(
        exitCode: Int32,
        appliedPaths: [String] = [],
        skippedPaths: [String] = [],
        conflictedPaths: [String] = [],
        stdout: String = "",
        stderr: String = "",
        commandForLog: String = "git apply"
    ) {
        self.exitCode = exitCode
        self.appliedPaths = appliedPaths
        self.skippedPaths = skippedPaths
        self.conflictedPaths = conflictedPaths
        self.stdout = stdout
        self.stderr = stderr
        self.commandForLog = commandForLog
    }
}

public typealias CloudGitApply = @Sendable (CloudGitApplyRequest) async -> CloudTaskResult<CloudGitApplyResult>
public typealias CloudTaskErrorLog = @Sendable (String) -> Void

public struct CloudHTTPClient<Transport: APITransport, Auth: APIAuthProvider>: CloudBackend {
    public let baseURL: String
    public let pathStyle: CloudTasksPathStyle
    public let transport: Transport
    public let auth: Auth
    public let retry: ProviderRetryConfig
    public let headers: [String: String]

    private let now: @Sendable () -> Date
    private let environment: @Sendable () -> [String: String]
    private let currentDirectory: @Sendable () -> URL
    private let gitOriginURLs: @Sendable () -> [String]
    private let applyGitPatch: CloudGitApply
    private let errorLog: CloudTaskErrorLog

    public init(
        baseURL: String,
        transport: Transport,
        auth: Auth,
        retry: ProviderRetryConfig = ProviderRetryConfig(
            maxAttempts: 0,
            baseDelayMilliseconds: 0,
            retry429: false,
            retry5xx: false,
            retryTransport: false
        ),
        headers: [String: String] = ["user-agent": "codex-cli"],
        now: @escaping @Sendable () -> Date = Date.init,
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        gitOriginURLs: (@Sendable () -> [String])? = nil,
        applyGitPatch: CloudGitApply? = nil,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        let normalizedBaseURL = Self.normalizedBaseURL(baseURL)
        self.baseURL = normalizedBaseURL
        self.pathStyle = CloudTasksPathStyle.fromBaseURL(normalizedBaseURL)
        self.transport = transport
        self.auth = auth
        self.retry = retry
        self.headers = headers
        self.now = now
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.gitOriginURLs = gitOriginURLs ?? {
            GitInfoCollector.remoteURLs(cwd: currentDirectory())
        }
        self.applyGitPatch = applyGitPatch ?? Self.defaultApplyGitPatch
        self.errorLog = errorLog
    }

    public static func normalizedBaseURL(_ raw: String) -> String {
        var baseURL = raw
        while baseURL.last == "/" {
            baseURL.removeLast()
        }
        if (baseURL.hasPrefix("https://chatgpt.com") || baseURL.hasPrefix("https://chat.openai.com")),
           !baseURL.contains("/backend-api") {
            baseURL += "/backend-api"
        }
        return baseURL
    }

    public func listTasks(environment env: String?, limit: Int?, cursor: String?) async -> CloudTaskResult<CloudTaskPage> {
        var query: [(String, String)] = []
        if let limit {
            query.append(("limit", "\(limit)"))
        }
        query.append(("task_filter", "current"))
        if let cursor {
            query.append(("cursor", cursor))
        }
        if let env {
            query.append(("environment_id", env))
        }

        switch await executeText(method: .get, path: path(codex: "api/codex/tasks/list", chatGPT: "wham/tasks/list"), query: query) {
        case let .success(response):
            do {
                let list = try decode(CloudTaskListResponse.self, from: response)
                let tasks = list.items.map { Self.mapTaskListItemToSummary($0, now: now) }
                errorLog(
                    "http.list_tasks: env=\(env ?? "<all>") limit=\(limit.map(String.init) ?? "<default>") cursor_in=\(cursor ?? "<none>") cursor_out=\(list.cursor ?? "<none>") items=\(tasks.count)"
                )
                return .success(CloudTaskPage(tasks: tasks, cursor: list.cursor))
            } catch {
                return .failure(.http("list_tasks failed: \(decodeDescription(error, response: response))"))
            }
        case let .failure(error):
            return .failure(.http("list_tasks failed: \(Self.message(from: error))"))
        }
    }

    public func listEnvironments() async -> CloudTaskResult<[CloudEnvironmentRow]> {
        var rowsByID: [String: CloudEnvironmentRow] = [:]

        for origin in gitOriginURLs() {
            guard let (owner, repo) = Self.parseGitHubOwnerRepo(from: origin) else {
                continue
            }
            let repoHint = "\(owner)/\(repo)"
            let repoPath = path(
                codex: "api/codex/environments/by-repo/github/\(owner)/\(repo)",
                chatGPT: "wham/environments/by-repo/github/\(owner)/\(repo)"
            )
            switch await fetchEnvironments(path: repoPath, operation: "list_environments by-repo \(repoHint)") {
            case let .success(environments):
                errorLog("env_tui: by-repo \(repoHint) -> \(environments.count) envs")
                merge(environments: environments, repoHint: repoHint, into: &rowsByID)
            case let .failure(error):
                errorLog("env_tui: by-repo fetch failed for \(repoHint): \(Self.message(from: error))")
            }
        }

        let globalPath = path(codex: "api/codex/environments", chatGPT: "wham/environments")
        switch await fetchEnvironments(path: globalPath, operation: "list_environments") {
        case let .success(environments):
            errorLog("env_tui: global list -> \(environments.count) envs")
            merge(environments: environments, repoHint: nil, into: &rowsByID)
        case let .failure(error):
            if rowsByID.isEmpty {
                return .failure(error)
            }
            errorLog("env_tui: global list failed; using by-repo results only: \(Self.message(from: error))")
        }

        return .success(rowsByID.values.sorted(by: Self.compareEnvironmentRows))
    }

    public func getTaskSummary(id: CloudTaskID) async -> CloudTaskResult<CloudTaskSummary> {
        switch await detailsWithBody(id: id.rawValue) {
        case let .success(details):
            return Self.summaryFromDetails(id: id, details: details, now: now)
        case let .failure(error):
            return .failure(.http("get_task_details failed: \(Self.message(from: error))"))
        }
    }

    public func getTaskDiff(id: CloudTaskID) async -> CloudTaskResult<String?> {
        switch await detailsWithBody(id: id.rawValue) {
        case let .success(details):
            return .success(details.parsed.unifiedDiff())
        case let .failure(error):
            return .failure(.http("get_task_details failed: \(Self.message(from: error))"))
        }
    }

    public func getTaskMessages(id: CloudTaskID) async -> CloudTaskResult<[String]> {
        switch await detailsWithBody(id: id.rawValue) {
        case let .success(details):
            var messages = details.parsed.assistantTextMessages()
            if messages.isEmpty {
                messages.append(contentsOf: Self.extractAssistantMessages(fromBody: details.body))
            }
            if !messages.isEmpty {
                return .success(messages)
            }
            if let error = details.parsed.assistantErrorMessage() {
                return .success(["Task failed: \(error)"])
            }

            return .failure(.http(
                "No assistant text messages in response. GET \(detailsPathForError(id: id.rawValue)); content-type=\(details.contentType); body=\(details.body)"
            ))
        case let .failure(error):
            return .failure(.http("get_task_details failed: \(Self.message(from: error))"))
        }
    }

    public func getTaskText(id: CloudTaskID) async -> CloudTaskResult<CloudTaskText> {
        switch await detailsWithBody(id: id.rawValue) {
        case let .success(details):
            var messages = details.parsed.assistantTextMessages()
            if messages.isEmpty {
                messages.append(contentsOf: Self.extractAssistantMessages(fromBody: details.body))
            }
            let assistantTurn = details.parsed.currentAssistantTurn
            return .success(CloudTaskText(
                prompt: details.parsed.userTextPrompt(),
                messages: messages,
                turnID: assistantTurn?.id,
                siblingTurnIDs: assistantTurn?.siblingTurnIDs ?? [],
                attemptPlacement: assistantTurn?.attemptPlacement,
                attemptStatus: Self.attemptStatus(from: assistantTurn?.turnStatus)
            ))
        case let .failure(error):
            return .failure(.http("get_task_details failed: \(Self.message(from: error))"))
        }
    }

    public func listSiblingAttempts(task: CloudTaskID, turnID: String) async -> CloudTaskResult<[CloudTurnAttempt]> {
        let path = path(
            codex: "api/codex/tasks/\(task.rawValue)/turns/\(turnID)/sibling_turns",
            chatGPT: "wham/tasks/\(task.rawValue)/turns/\(turnID)/sibling_turns"
        )
        switch await executeText(method: .get, path: path) {
        case let .success(response):
            do {
                let decoded = try decode(CloudSiblingTurnsResponse.self, from: response)
                return .success(decoded.siblingTurns.compactMap(Self.turnAttempt(from:)).sorted(by: Self.compareAttempts))
            } catch {
                return .failure(.http("list_sibling_turns failed: \(decodeDescription(error, response: response))"))
            }
        case let .failure(error):
            return .failure(.http("list_sibling_turns failed: \(Self.message(from: error))"))
        }
    }

    public func applyTaskPreflight(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome> {
        await runApply(id: id, diffOverride: diffOverride, preflight: true)
    }

    public func applyTask(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome> {
        await runApply(id: id, diffOverride: diffOverride, preflight: false)
    }

    public func createTask(
        environmentID: String,
        prompt: String,
        gitRef: String,
        qaMode: Bool,
        bestOfN: Int
    ) async -> CloudTaskResult<CloudCreatedTask> {
        var inputItems: [JSONValue] = [
            .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object([
                        "content_type": .string("text"),
                        "text": .string(prompt)
                    ])
                ])
            ])
        ]

        if let diff = environment()["CODEX_STARTING_DIFF"], !diff.isEmpty {
            inputItems.append(.object([
                "type": .string("pre_apply_patch"),
                "output_diff": .object(["diff": .string(diff)])
            ]))
        }

        var body: [String: JSONValue] = [
            "new_task": .object([
                "environment_id": .string(environmentID),
                "branch": .string(gitRef),
                "run_environment_in_qa_mode": .bool(qaMode)
            ]),
            "input_items": .array(inputItems)
        ]
        if bestOfN > 1 {
            body["metadata"] = .object(["best_of_n": .integer(Int64(bestOfN))])
        }

        let path = path(codex: "api/codex/tasks", chatGPT: "wham/tasks")
        switch await executeText(method: .post, path: path, body: .object(body)) {
        case let .success(response):
            do {
                let value = try decode(JSONValue.self, from: response)
                if let id = value.objectValue?["task"]?.objectValue?["id"]?.stringValue
                    ?? value.objectValue?["id"]?.stringValue {
                    errorLog("new_task: created id=\(id) env=\(environmentID) prompt_chars=\(prompt.count)")
                    return .success(CloudCreatedTask(id: CloudTaskID(id)))
                }
                return .failure(.http(
                    "create_task failed: POST \(response.url) succeeded but no task id found; content-type=\(response.contentType); body=\(response.body)"
                ))
            } catch {
                return .failure(.http("create_task failed: \(decodeDescription(error, response: response))"))
            }
        case let .failure(error):
            errorLog("new_task: create failed env=\(environmentID) prompt_chars=\(prompt.count): \(Self.message(from: error))")
            return .failure(.http("create_task failed: \(Self.message(from: error))"))
        }
    }

    private func fetchEnvironments(path: String, operation: String) async -> CloudTaskResult<[CloudCodeEnvironment]> {
        switch await executeText(method: .get, path: path) {
        case let .success(response):
            do {
                return .success(try decode([CloudCodeEnvironment].self, from: response))
            } catch {
                return .failure(.http("\(operation) failed: \(decodeDescription(error, response: response))"))
            }
        case let .failure(error):
            return .failure(.http("\(operation) failed: \(Self.message(from: error))"))
        }
    }

    private func merge(
        environments: [CloudCodeEnvironment],
        repoHint: String?,
        into rowsByID: inout [String: CloudEnvironmentRow]
    ) {
        for environment in environments {
            guard !environment.id.isEmpty else {
                continue
            }
            let existing = rowsByID[environment.id]
            rowsByID[environment.id] = CloudEnvironmentRow(
                id: environment.id,
                label: existing?.label ?? environment.label,
                isPinned: (existing?.isPinned ?? false) || (environment.isPinned ?? false),
                repoHints: existing?.repoHints ?? repoHint
            )
        }
    }

    private func runApply(id: CloudTaskID, diffOverride: String?, preflight: Bool) async -> CloudTaskResult<CloudApplyOutcome> {
        let diff: String
        if let diffOverride {
            diff = diffOverride
        } else {
            switch await detailsWithBody(id: id.rawValue) {
            case let .success(details):
                guard let fetchedDiff = details.parsed.unifiedDiff() else {
                    return .failure(.message("No diff available for task \(id.rawValue)"))
                }
                diff = fetchedDiff
            case let .failure(error):
                return .failure(.http("get_task_details failed: \(Self.message(from: error))"))
            }
        }

        if !Self.isUnifiedDiff(diff) {
            let mode = preflight ? "preflight" : "apply"
            errorLog("apply_error: id=\(id.rawValue) mode=\(mode) format=non-unified; \(Self.summarizePatchForLogging(diff, cwd: currentDirectory()))")
            return .success(CloudApplyOutcome(
                applied: false,
                status: .error,
                message: "Expected unified git diff; backend returned an incompatible format."
            ))
        }

        let request = CloudGitApplyRequest(
            cwd: currentDirectory(),
            diff: diff,
            revert: false,
            preflight: preflight
        )

        let result: CloudGitApplyResult
        switch await applyGitPatch(request) {
        case let .success(value):
            result = value
        case let .failure(error):
            return .failure(.io("git apply failed to run: \(Self.message(from: error))"))
        }

        let status: CloudApplyStatus
        if result.exitCode == 0 {
            status = .success
        } else if !result.appliedPaths.isEmpty || !result.conflictedPaths.isEmpty {
            status = .partial
        } else {
            status = .error
        }
        let applied = status == .success && !preflight
        let message = Self.applyMessage(
            id: id.rawValue,
            result: result,
            status: status,
            preflight: preflight
        )

        if status == .partial || status == .error || (preflight && status != .success) {
            let mode = preflight ? "preflight" : "apply"
            errorLog("""
            apply_result: mode=\(mode) id=\(id.rawValue) status=\(Self.logStatus(status)) applied=\(result.appliedPaths.count) skipped=\(result.skippedPaths.count) conflicts=\(result.conflictedPaths.count) cmd=\(result.commandForLog)
            stdout_tail=
            \(Self.tail(result.stdout, max: 2_000))
            stderr_tail=
            \(Self.tail(result.stderr, max: 2_000))
            \(Self.summarizePatchForLogging(diff, cwd: currentDirectory()))
            ----- PATCH BEGIN -----
            \(diff)
            ----- PATCH END -----
            """)
        }

        return .success(CloudApplyOutcome(
            applied: applied,
            status: status,
            message: message,
            skippedPaths: result.skippedPaths,
            conflictPaths: result.conflictedPaths
        ))
    }

    private func detailsWithBody(id: String) async -> CloudTaskResult<CloudTaskDetailsPayload> {
        switch await executeText(method: .get, path: path(codex: "api/codex/tasks/\(id)", chatGPT: "wham/tasks/\(id)")) {
        case let .success(response):
            do {
                return .success(CloudTaskDetailsPayload(
                    parsed: try decode(CloudTaskDetailsResponse.self, from: response),
                    body: response.body,
                    contentType: response.contentType
                ))
            } catch {
                return .failure(.http(decodeDescription(error, response: response)))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private func executeText(
        method: HTTPMethod,
        path: String,
        query: [(String, String)] = [],
        body: JSONValue? = nil
    ) async -> CloudTaskResult<CloudHTTPTextResponse> {
        let result = await TransportRetry.runWithRetry(
            policy: retry.toPolicy(),
            makeRequest: {
                makeRequest(method: method, path: path, query: query, body: body)
            },
            operation: { request, _ in
                await transport.execute(request)
            }
        )

        switch result {
        case let .success(response):
            return .success(CloudHTTPTextResponse(
                url: makeURL(path: path, query: query),
                body: String(decoding: response.body, as: UTF8.self),
                contentType: Self.contentType(from: response.headers)
            ))
        case let .failure(error):
            return .failure(.http(String(describing: error)))
        }
    }

    private func makeRequest(method: HTTPMethod, path: String, query: [(String, String)], body: JSONValue?) -> APIRequest {
        var requestHeaders = headers
        if body != nil,
           !requestHeaders.keys.contains(where: { $0.caseInsensitiveCompare("content-type") == .orderedSame }) {
            requestHeaders["content-type"] = "application/json"
        }
        let request = APIRequest(
            method: method,
            url: makeURL(path: path, query: query),
            headers: requestHeaders,
            body: body
        )
        return request.addingAuthHeaders(from: auth)
    }

    private func makeURL(path: String, query: [(String, String)] = []) -> String {
        var url = "\(baseURL)/\(path)"
        guard !query.isEmpty, var components = URLComponents(string: url) else {
            return url
        }
        components.queryItems = (components.queryItems ?? []) + query.map {
            URLQueryItem(name: $0.0, value: $0.1)
        }
        url = components.string ?? url
        return url
    }

    private func path(codex: String, chatGPT: String) -> String {
        switch pathStyle {
        case .codexAPI:
            return codex
        case .chatGPTAPI:
            return chatGPT
        }
    }

    private func detailsPathForError(id: String) -> String {
        switch pathStyle {
        case .chatGPTAPI:
            return "\(baseURL)/wham/tasks/\(id)"
        case .codexAPI where baseURL.contains("/api/codex"):
            return "\(baseURL)/tasks/\(id)"
        case .codexAPI:
            return "\(baseURL)/api/codex/tasks/\(id)"
        }
    }

    private static func contentType(from headers: [String: String]) -> String {
        headers.first { key, _ in key.caseInsensitiveCompare("content-type") == .orderedSame }?.value ?? ""
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: CloudHTTPTextResponse) throws -> T {
        _ = type
        return try JSONDecoder().decode(T.self, from: Data(response.body.utf8))
    }

    private func decodeDescription(_ error: Error, response: CloudHTTPTextResponse) -> String {
        "Decode error for \(response.url): \(error); content-type=\(response.contentType); body=\(response.body)"
    }

    private static func message(from error: CloudTaskError) -> String {
        switch error {
        case let .unimplemented(message),
             let .http(message),
             let .io(message),
             let .message(message):
            return message
        }
    }
}

private struct CloudHTTPTextResponse: Equatable, Sendable {
    let url: String
    let body: String
    let contentType: String
}

private struct CloudTaskDetailsPayload: Equatable, Sendable {
    let parsed: CloudTaskDetailsResponse
    let body: String
    let contentType: String
}

private struct CloudTaskListResponse: Decodable, Equatable, Sendable {
    let items: [CloudTaskListItem]
    let cursor: String?
}

private struct CloudTaskListItem: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let archived: Bool
    let hasUnreadTurn: Bool
    let updatedAt: Double?
    let taskStatusDisplay: [String: JSONValue]?
    let pullRequests: [JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case archived
        case hasUnreadTurn = "has_unread_turn"
        case updatedAt = "updated_at"
        case taskStatusDisplay = "task_status_display"
        case pullRequests = "pull_requests"
    }
}

private struct CloudCodeEnvironment: Decodable, Equatable, Sendable {
    let id: String
    let label: String?
    let isPinned: Bool?
    let taskCount: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case isPinned = "is_pinned"
        case taskCount = "task_count"
    }
}

private struct CloudSiblingTurnsResponse: Decodable, Equatable, Sendable {
    let siblingTurns: [[String: JSONValue]]

    private enum CodingKeys: String, CodingKey {
        case siblingTurns = "sibling_turns"
    }
}

private struct CloudTaskDetailsResponse: Decodable, Equatable, Sendable {
    let currentUserTurn: CloudTaskTurn?
    let currentAssistantTurn: CloudTaskTurn?
    let currentDiffTaskTurn: CloudTaskTurn?

    private enum CodingKeys: String, CodingKey {
        case currentUserTurn = "current_user_turn"
        case currentAssistantTurn = "current_assistant_turn"
        case currentDiffTaskTurn = "current_diff_task_turn"
    }
}

private struct CloudTaskTurn: Decodable, Equatable, Sendable {
    let id: String?
    let attemptPlacement: Int64?
    let turnStatus: String?
    let siblingTurnIDs: [String]
    let inputItems: [CloudTaskTurnItem]
    let outputItems: [CloudTaskTurnItem]
    let worklog: CloudTaskWorklog?
    let error: CloudTaskTurnError?

    private enum CodingKeys: String, CodingKey {
        case id
        case attemptPlacement = "attempt_placement"
        case turnStatus = "turn_status"
        case siblingTurnIDs = "sibling_turn_ids"
        case inputItems = "input_items"
        case outputItems = "output_items"
        case worklog
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.attemptPlacement = try container.decodeIfPresent(Int64.self, forKey: .attemptPlacement)
        self.turnStatus = try container.decodeIfPresent(String.self, forKey: .turnStatus)
        self.siblingTurnIDs = try container.decodeIfPresent([String].self, forKey: .siblingTurnIDs) ?? []
        self.inputItems = try container.decodeIfPresent([CloudTaskTurnItem].self, forKey: .inputItems) ?? []
        self.outputItems = try container.decodeIfPresent([CloudTaskTurnItem].self, forKey: .outputItems) ?? []
        self.worklog = try container.decodeIfPresent(CloudTaskWorklog.self, forKey: .worklog)
        self.error = try container.decodeIfPresent(CloudTaskTurnError.self, forKey: .error)
    }

    func unifiedDiff() -> String? {
        outputItems.lazy.compactMap(\.diffText).first
    }

    func messageTexts() -> [String] {
        var output = outputItems
            .filter { $0.kind == "message" }
            .flatMap(\.textValues)

        if let worklog {
            for message in worklog.messages where message.isAssistant {
                output.append(contentsOf: message.textValues)
            }
        }
        return output
    }

    func userPrompt() -> String? {
        let parts = inputItems
            .filter { $0.kind == "message" }
            .filter { item in
                item.role.map { $0.caseInsensitiveCompare("user") == .orderedSame } ?? true
            }
            .flatMap(\.textValues)
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func errorSummary() -> String? {
        error?.summary
    }
}

private struct CloudTaskTurnItem: Decodable, Equatable, Sendable {
    let kind: String
    let role: String?
    let content: [CloudContentFragment]
    let diff: String?
    let outputDiff: CloudDiffPayload?

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case role
        case content
        case diff
        case outputDiff = "output_diff"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
        self.content = try container.decodeIfPresent([CloudContentFragment].self, forKey: .content) ?? []
        self.diff = try container.decodeIfPresent(String.self, forKey: .diff)
        self.outputDiff = try container.decodeIfPresent(CloudDiffPayload.self, forKey: .outputDiff)
    }

    var textValues: [String] {
        content.compactMap(\.text)
    }

    var diffText: String? {
        if kind == "output_diff", let diff, !diff.isEmpty {
            return diff
        }
        if kind == "pr", let diff = outputDiff?.diff, !diff.isEmpty {
            return diff
        }
        return nil
    }
}

private enum CloudContentFragment: Decodable, Equatable, Sendable {
    case structured(CloudStructuredContent)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let structured = try? container.decode(CloudStructuredContent.self) {
            self = .structured(structured)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    var text: String? {
        switch self {
        case let .structured(content):
            guard content.contentType?.caseInsensitiveCompare("text") == .orderedSame,
                  let text = content.text,
                  !text.isEmpty
            else {
                return nil
            }
            return text
        case let .text(raw):
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw
        }
    }
}

private struct CloudStructuredContent: Decodable, Equatable, Sendable {
    let contentType: String?
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case text
    }
}

private struct CloudDiffPayload: Decodable, Equatable, Sendable {
    let diff: String?
}

private struct CloudTaskWorklog: Decodable, Equatable, Sendable {
    let messages: [CloudTaskWorklogMessage]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try container.decodeIfPresent([CloudTaskWorklogMessage].self, forKey: .messages) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case messages
    }
}

private struct CloudTaskWorklogMessage: Decodable, Equatable, Sendable {
    let author: CloudTaskAuthor?
    let content: CloudTaskWorklogContent?

    var isAssistant: Bool {
        author?.role?.caseInsensitiveCompare("assistant") == .orderedSame
    }

    var textValues: [String] {
        content?.parts.compactMap(\.text) ?? []
    }
}

private struct CloudTaskAuthor: Decodable, Equatable, Sendable {
    let role: String?
}

private struct CloudTaskWorklogContent: Decodable, Equatable, Sendable {
    let parts: [CloudContentFragment]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.parts = try container.decodeIfPresent([CloudContentFragment].self, forKey: .parts) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case parts
    }
}

private struct CloudTaskTurnError: Decodable, Equatable, Sendable {
    let code: String?
    let message: String?

    var summary: String? {
        let code = code ?? ""
        let message = message ?? ""
        switch (code.isEmpty, message.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return code
        case (true, false):
            return message
        case (false, false):
            return "\(code): \(message)"
        }
    }
}

private extension CloudTaskDetailsResponse {
    func unifiedDiff() -> String? {
        [currentDiffTaskTurn, currentAssistantTurn].compactMap { $0 }.lazy.compactMap { $0.unifiedDiff() }.first
    }

    func assistantTextMessages() -> [String] {
        [currentDiffTaskTurn, currentAssistantTurn].compactMap { $0 }.flatMap { $0.messageTexts() }
    }

    func userTextPrompt() -> String? {
        currentUserTurn?.userPrompt()
    }

    func assistantErrorMessage() -> String? {
        currentAssistantTurn?.errorSummary()
    }
}

private extension CloudHTTPClient {
    static func summaryFromDetails(
        id: CloudTaskID,
        details: CloudTaskDetailsPayload,
        now: @Sendable () -> Date
    ) -> CloudTaskResult<CloudTaskSummary> {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(details.body.utf8))
        } catch {
            return .failure(.http(
                "Decode error for \(id.rawValue): \(error); content-type=\(details.contentType); body=\(details.body)"
            ))
        }

        guard let taskObject = value.objectValue?["task"]?.objectValue else {
            return .failure(.http("Task metadata missing from details for \(id.rawValue)"))
        }

        let statusDisplay = value.objectValue?["task_status_display"]?.objectValue
            ?? taskObject["task_status_display"]?.objectValue
        let status = mapStatus(statusDisplay)
        var summary = diffSummaryFromStatusDisplay(statusDisplay)
        if summary.filesChanged == 0,
           summary.linesAdded == 0,
           summary.linesRemoved == 0,
           let diff = details.parsed.unifiedDiff() {
            summary = diffSummaryFromDiff(diff)
        }

        let updatedAtRaw = taskObject["updated_at"]?.numberValue
            ?? taskObject["created_at"]?.numberValue
            ?? latestTurnTimestamp(statusDisplay)
        let title = taskObject["title"]?.stringValue ?? "<untitled>"
        return .success(CloudTaskSummary(
            id: id,
            title: title,
            status: status,
            updatedAt: updatedAtRaw.map(dateFromUnixTimestamp) ?? now(),
            environmentID: taskObject["environment_id"]?.stringValue,
            environmentLabel: envLabelFromStatusDisplay(statusDisplay),
            summary: summary,
            isReview: taskObject["is_review"]?.boolValue ?? false,
            attemptTotal: attemptTotalFromStatusDisplay(statusDisplay)
        ))
    }

    static func mapTaskListItemToSummary(
        _ item: CloudTaskListItem,
        now: @Sendable () -> Date
    ) -> CloudTaskSummary {
        let statusDisplay = item.taskStatusDisplay
        return CloudTaskSummary(
            id: CloudTaskID(item.id),
            title: item.title,
            status: mapStatus(statusDisplay),
            updatedAt: item.updatedAt.map(dateFromUnixTimestamp) ?? now(),
            environmentID: nil,
            environmentLabel: envLabelFromStatusDisplay(statusDisplay),
            summary: diffSummaryFromStatusDisplay(statusDisplay),
            isReview: item.pullRequests?.isEmpty == false,
            attemptTotal: attemptTotalFromStatusDisplay(statusDisplay)
        )
    }

    static func mapStatus(_ value: [String: JSONValue]?) -> CloudTaskStatus {
        if let latest = value?["latest_turn_status_display"]?.objectValue,
           let status = latest["turn_status"]?.stringValue {
            switch status {
            case "failed", "cancelled":
                return .error
            case "completed":
                return .ready
            case "in_progress", "pending":
                return .pending
            default:
                return .pending
            }
        }

        if let state = value?["state"]?.stringValue {
            switch state {
            case "pending":
                return .pending
            case "ready":
                return .ready
            case "applied":
                return .applied
            case "error":
                return .error
            default:
                return .pending
            }
        }

        return .pending
    }

    static func diffSummaryFromStatusDisplay(_ value: [String: JSONValue]?) -> CloudDiffSummary {
        guard let stats = value?["latest_turn_status_display"]?.objectValue?["diff_stats"]?.objectValue else {
            return CloudDiffSummary()
        }
        return CloudDiffSummary(
            filesChanged: max(0, stats["files_modified"]?.intValue ?? 0),
            linesAdded: max(0, stats["lines_added"]?.intValue ?? 0),
            linesRemoved: max(0, stats["lines_removed"]?.intValue ?? 0)
        )
    }

    static func diffSummaryFromDiff(_ diff: String) -> CloudDiffSummary {
        var filesChanged = 0
        var linesAdded = 0
        var linesRemoved = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                filesChanged += 1
                continue
            }
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                continue
            }
            if line.hasPrefix("+") {
                linesAdded += 1
            } else if line.hasPrefix("-") {
                linesRemoved += 1
            }
        }
        if filesChanged == 0, !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filesChanged = 1
        }
        return CloudDiffSummary(filesChanged: filesChanged, linesAdded: linesAdded, linesRemoved: linesRemoved)
    }

    static func latestTurnTimestamp(_ value: [String: JSONValue]?) -> Double? {
        let latest = value?["latest_turn_status_display"]?.objectValue
        return latest?["updated_at"]?.numberValue ?? latest?["created_at"]?.numberValue
    }

    static func envLabelFromStatusDisplay(_ value: [String: JSONValue]?) -> String? {
        value?["environment_label"]?.stringValue
    }

    static func attemptTotalFromStatusDisplay(_ value: [String: JSONValue]?) -> Int? {
        guard let siblings = value?["latest_turn_status_display"]?.objectValue?["sibling_turn_ids"]?.arrayValue else {
            return nil
        }
        return siblings.count + 1
    }

    static func compareEnvironmentRows(_ lhs: CloudEnvironmentRow, _ rhs: CloudEnvironmentRow) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        let leftLabel = lhs.label?.lowercased() ?? ""
        let rightLabel = rhs.label?.lowercased() ?? ""
        if leftLabel != rightLabel {
            return leftLabel < rightLabel
        }
        return lhs.id < rhs.id
    }

    static func parseGitHubOwnerRepo(from rawURL: String) -> (owner: String, repo: String)? {
        var value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("ssh://") {
            value.removeFirst("ssh://".count)
        }

        if let range = value.range(of: "@github.com:") {
            let rest = String(value[range.upperBound...])
            return ownerRepo(fromPath: rest)
        }
        if let range = value.range(of: "@github.com/") {
            let rest = String(value[range.upperBound...])
            return ownerRepo(fromPath: rest)
        }

        for prefix in [
            "https://github.com/",
            "http://github.com/",
            "git://github.com/",
            "github.com/"
        ] {
            if value.hasPrefix(prefix) {
                let rest = String(value.dropFirst(prefix.count))
                return ownerRepo(fromPath: rest)
            }
        }
        return nil
    }

    static func ownerRepo(fromPath rawPath: String) -> (owner: String, repo: String)? {
        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") {
            path.removeLast(".git".count)
        }
        let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }
        let owner = String(parts[0])
        let repo = String(parts[1])
        guard !owner.isEmpty, !repo.isEmpty else {
            return nil
        }
        return (owner, repo)
    }

    static func extractAssistantMessages(fromBody body: String) -> [String] {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
              let messages = value.objectValue?["current_assistant_turn"]?.objectValue?["worklog"]?.objectValue?["messages"]?.arrayValue
        else {
            return []
        }

        var output: [String] = []
        for message in messages {
            let object = message.objectValue
            let role = object?["author"]?.objectValue?["role"]?.stringValue
            guard role == "assistant",
                  let parts = object?["content"]?.objectValue?["parts"]?.arrayValue
            else {
                continue
            }
            for part in parts {
                if let text = part.stringValue, !text.isEmpty {
                    output.append(text)
                    continue
                }
                if part.objectValue?["content_type"]?.stringValue == "text",
                   let text = part.objectValue?["text"]?.stringValue {
                    output.append(text)
                }
            }
        }
        return output
    }

    static func turnAttempt(from turn: [String: JSONValue]) -> CloudTurnAttempt? {
        guard let turnID = turn["id"]?.stringValue else {
            return nil
        }
        return CloudTurnAttempt(
            turnID: turnID,
            attemptPlacement: turn["attempt_placement"]?.int64Value,
            createdAt: turn["created_at"]?.numberValue.map(dateFromUnixTimestamp),
            status: attemptStatus(from: turn["turn_status"]?.stringValue),
            diff: extractDiff(fromTurn: turn),
            messages: extractAssistantMessages(fromTurn: turn)
        )
    }

    static func compareAttempts(_ lhs: CloudTurnAttempt, _ rhs: CloudTurnAttempt) -> Bool {
        switch (lhs.attemptPlacement, rhs.attemptPlacement) {
        case let (left?, right?):
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.turnID < rhs.turnID
            }
        }
    }

    static func extractDiff(fromTurn turn: [String: JSONValue]) -> String? {
        guard let items = turn["output_items"]?.arrayValue else {
            return nil
        }
        for item in items {
            switch item.objectValue?["type"]?.stringValue {
            case "output_diff":
                if let diff = item.objectValue?["diff"]?.stringValue, !diff.isEmpty {
                    return diff
                }
            case "pr":
                if let diff = item.objectValue?["output_diff"]?.objectValue?["diff"]?.stringValue, !diff.isEmpty {
                    return diff
                }
            default:
                continue
            }
        }
        return nil
    }

    static func extractAssistantMessages(fromTurn turn: [String: JSONValue]) -> [String] {
        guard let items = turn["output_items"]?.arrayValue else {
            return []
        }
        var output: [String] = []
        for item in items where item.objectValue?["type"]?.stringValue == "message" {
            guard let content = item.objectValue?["content"]?.arrayValue else {
                continue
            }
            for part in content {
                if part.objectValue?["content_type"]?.stringValue == "text",
                   let text = part.objectValue?["text"]?.stringValue,
                   !text.isEmpty {
                    output.append(text)
                }
            }
        }
        return output
    }

    static func attemptStatus(from raw: String?) -> CloudAttemptStatus {
        switch raw ?? "" {
        case "failed":
            return .failed
        case "completed":
            return .completed
        case "in_progress":
            return .inProgress
        case "pending":
            return .pending
        default:
            return .pending
        }
    }

    static func dateFromUnixTimestamp(_ timestamp: Double) -> Date {
        Date(timeIntervalSince1970: max(0, timestamp))
    }

    static func isUnifiedDiff(_ diff: String) -> Bool {
        let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("diff --git ") {
            return true
        }
        let hasDashHeaders = diff.contains("\n--- ") && diff.contains("\n+++ ")
        let hasHunk = diff.contains("\n@@ ") || diff.hasPrefix("@@ ")
        return hasDashHeaders && hasHunk
    }

    static func applyMessage(
        id: String,
        result: CloudGitApplyResult,
        status: CloudApplyStatus,
        preflight: Bool
    ) -> String {
        if preflight {
            switch status {
            case .success:
                return "Preflight passed for task \(id) (applies cleanly)"
            case .partial:
                return "Preflight: patch does not fully apply for task \(id) (applied=\(result.appliedPaths.count), skipped=\(result.skippedPaths.count), conflicts=\(result.conflictedPaths.count))"
            case .error:
                return "Preflight failed for task \(id) (applied=\(result.appliedPaths.count), skipped=\(result.skippedPaths.count), conflicts=\(result.conflictedPaths.count))"
            }
        }

        switch status {
        case .success:
            return "Applied task \(id) locally (\(result.appliedPaths.count) files)"
        case .partial:
            return "Apply partially succeeded for task \(id) (applied=\(result.appliedPaths.count), skipped=\(result.skippedPaths.count), conflicts=\(result.conflictedPaths.count))"
        case .error:
            return "Apply failed for task \(id) (applied=\(result.appliedPaths.count), skipped=\(result.skippedPaths.count), conflicts=\(result.conflictedPaths.count))"
        }
    }

    static func tail(_ text: String, max: Int) -> String {
        text.count <= max ? text : String(text.suffix(max))
    }

    static func logStatus(_ status: CloudApplyStatus) -> String {
        switch status {
        case .success:
            return "Success"
        case .partial:
            return "Partial"
        case .error:
            return "Error"
        }
    }

    static func summarizePatchForLogging(_ patch: String, cwd: URL) -> String {
        let trimmed = patch.drop(while: { $0.isWhitespace })
        let kind: String
        if trimmed.hasPrefix("*** Begin Patch") {
            kind = "codex-patch"
        } else if trimmed.hasPrefix("diff --git ") || trimmed.contains("\n*** End Patch\n") {
            kind = "git-diff"
        } else if trimmed.hasPrefix("@@ ") || trimmed.contains("\n@@ ") {
            kind = "unified-diff"
        } else {
            kind = "unknown"
        }
        let lines = rustLines(patch)
        let head = lines.prefix(20).joined(separator: "\n")
        let headTruncated = head.count > 800 ? "\(head.prefix(800))..." : head
        return "patch_summary: kind=\(kind) lines=\(lines.count) chars=\(patch.utf8.count) cwd=\(cwd.path) ; head=\n\(headTruncated)"
    }

    static func rustLines(_ text: String) -> [Substring] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.hasSuffix("\n") {
            _ = lines.popLast()
        }
        return lines
    }

    static func defaultApplyGitPatch(_ request: CloudGitApplyRequest) async -> CloudTaskResult<CloudGitApplyResult> {
        do {
            let result = try await Task.detached {
                try runGitApply(request)
            }.value
            return .success(result)
        } catch {
            return .failure(.io("\(error)"))
        }
    }

    private static func runGitApply(_ request: CloudGitApplyRequest) throws -> CloudGitApplyResult {
        let gitRoot = try resolveGitRoot(cwd: request.cwd)
        let patchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cloud-apply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: patchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: patchDirectory) }

        let patchPath = patchDirectory.appendingPathComponent("patch.diff")
        try request.diff.write(to: patchPath, atomically: true, encoding: .utf8)

        let gitConfig = gitApplyConfigArguments(environment: ProcessInfo.processInfo.environment)
        if request.revert, !request.preflight {
            _ = try runGit(cwd: gitRoot, config: gitConfig, arguments: ["add", "--"] + extractPathsFromPatch(request.diff))
        }

        let applyArguments: [String]
        if request.preflight {
            applyArguments = ["apply", "--check"] + (request.revert ? ["-R"] : []) + [patchPath.path]
        } else {
            applyArguments = ["apply", "--3way"] + (request.revert ? ["-R"] : []) + [patchPath.path]
        }

        let commandForLog = renderGitCommandForLog(cwd: gitRoot, config: gitConfig, arguments: applyArguments)
        let output = try runGit(cwd: gitRoot, config: gitConfig, arguments: applyArguments)
        let parsed = parseGitApplyOutput(stdout: output.stdout, stderr: output.stderr)
        return CloudGitApplyResult(
            exitCode: output.exitCode,
            appliedPaths: parsed.applied,
            skippedPaths: parsed.skipped,
            conflictedPaths: parsed.conflicted,
            stdout: output.stdout,
            stderr: output.stderr,
            commandForLog: commandForLog
        )
    }

    private static func resolveGitRoot(cwd: URL) throws -> URL {
        let output = try runGit(cwd: cwd, config: [], arguments: ["rev-parse", "--show-toplevel"])
        guard output.exitCode == 0 else {
            throw CloudGitApplyError.message("not a git repository (exit \(output.exitCode)): \(output.stderr)")
        }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw CloudGitApplyError.message("not a git repository: git returned an empty root")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private struct GitProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private enum CloudGitApplyError: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case let .message(message):
                return message
            }
        }
    }

    private static func runGit(cwd: URL, config: [String], arguments: [String]) throws -> GitProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + config + arguments
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        return GitProcessOutput(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private static func gitApplyConfigArguments(environment: [String: String]) -> [String] {
        guard let raw = environment["CODEX_APPLY_GIT_CFG"] else {
            return []
        }
        var arguments: [String] = []
        for pair in raw.split(separator: ",") {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("=") else {
                continue
            }
            arguments.append("-c")
            arguments.append(trimmed)
        }
        return arguments
    }

    private static func renderGitCommandForLog(cwd: URL, config: [String], arguments: [String]) -> String {
        let parts = ["git"] + config + arguments
        return "(cd \(quoteShell(cwd.path)) && \(parts.map(quoteShell).joined(separator: " ")))"
    }

    private static func quoteShell(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || "-_.:/@%+".contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func extractPathsFromPatch(_ diff: String) -> [String] {
        var paths = Set<String>()
        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("diff --git ") else {
                continue
            }
            let rest = String(line.dropFirst("diff --git ".count))
            let tokens = readDiffGitTokens(rest)
            guard tokens.count >= 2 else {
                continue
            }
            for (token, prefix) in [(tokens[0], "a/"), (tokens[1], "b/")] {
                guard token.hasPrefix(prefix) else {
                    continue
                }
                let path = String(token.dropFirst(prefix.count))
                if path != "/dev/null", !path.isEmpty {
                    paths.insert(path)
                }
            }
        }
        return paths.sorted()
    }

    private static func readDiffGitTokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                flush()
                continue
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    private static func parseGitApplyOutput(stdout: String, stderr: String) -> (
        applied: [String],
        skipped: [String],
        conflicted: [String]
    ) {
        var applied = Set<String>()
        var skipped = Set<String>()
        var conflicted = Set<String>()
        var lastSeenPath: String?

        func add(_ raw: String, to set: inout Set<String>) {
            let path = unquoteGitPath(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !path.isEmpty else {
                return
            }
            set.insert(path)
            lastSeenPath = path
        }

        for rawLine in [stdout, stderr].filter({ !$0.isEmpty }).joined(separator: "\n").split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Checking patch "), line.hasSuffix("...") {
                lastSeenPath = String(line.dropFirst("Checking patch ".count).dropLast(3))
                continue
            }
            if let path = pathBetween(line, prefix: "Applied patch to ", suffix: " cleanly."), !path.isEmpty {
                let parsed = unquoteGitPath(path)
                applied.insert(parsed)
                skipped.remove(parsed)
                conflicted.remove(parsed)
                lastSeenPath = parsed
                continue
            }
            if let path = pathBetween(line, prefix: "Applied patch ", suffix: " cleanly."), !path.isEmpty {
                let parsed = unquoteGitPath(path)
                applied.insert(parsed)
                skipped.remove(parsed)
                conflicted.remove(parsed)
                lastSeenPath = parsed
                continue
            }
            if let path = pathBetween(line, prefix: "Applied patch to ", suffix: " with conflicts."), !path.isEmpty {
                let parsed = unquoteGitPath(path)
                conflicted.insert(parsed)
                applied.remove(parsed)
                skipped.remove(parsed)
                lastSeenPath = parsed
                continue
            }
            if line.hasPrefix("U ") {
                add(String(line.dropFirst(2)), to: &conflicted)
                continue
            }
            if line == "Failed to perform three-way merge..." || line.lowercased().contains("repository lacks the necessary blob") {
                if let lastSeenPath {
                    skipped.insert(lastSeenPath)
                    applied.remove(lastSeenPath)
                    conflicted.remove(lastSeenPath)
                }
                continue
            }
            if line.hasPrefix("error: patch failed: ") {
                let rest = String(line.dropFirst("error: patch failed: ".count))
                let path = rest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? rest
                add(path, to: &skipped)
                continue
            }
            if line.hasPrefix("error: "), let colon = line.dropFirst("error: ".count).firstIndex(of: ":") {
                let rest = line.dropFirst("error: ".count)
                let path = String(rest[..<colon])
                if line.hasSuffix("patch does not apply")
                    || line.contains("does not match index")
                    || line.contains("does not exist in index")
                    || line.contains("already exists in the working directory")
                    || line.contains("cannot read the current contents of") {
                    add(path, to: &skipped)
                    continue
                }
            }
            if let path = pathBetween(line, prefix: "Skipped patch ", suffix: ".") {
                add(path, to: &skipped)
                continue
            }
            if let rest = pathBetween(line, prefix: "warning: Cannot merge binary files: ", suffix: nil),
               let path = rest.split(separator: " ", maxSplits: 1).first.map(String.init) {
                add(path, to: &conflicted)
            }
        }

        skipped.subtract(applied)
        skipped.subtract(conflicted)
        applied.subtract(conflicted)
        return (applied.sorted(), skipped.sorted(), conflicted.sorted())
    }

    private static func pathBetween(_ value: String, prefix: String, suffix: String?) -> String? {
        guard value.hasPrefix(prefix) else {
            return nil
        }
        var rest = String(value.dropFirst(prefix.count))
        if let suffix {
            guard rest.hasSuffix(suffix) else {
                return nil
            }
            rest.removeLast(suffix.count)
        }
        return rest
    }

    private static func unquoteGitPath(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              first == value.last,
              first == "\"" || first == "'"
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    var numberValue: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case let .integer(value):
            return Int(value)
        case let .double(value):
            return Int(value)
        default:
            return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case let .integer(value):
            return value
        case let .double(value):
            return Int64(value)
        default:
            return nil
        }
    }
}

public enum CloudTaskErrorLogger {
    public static func append(_ message: String) {
        let timestamp = CloudTaskErrorLogger.timestamp()
        guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "error.log"))
        else {
            if !FileManager.default.fileExists(atPath: "error.log") {
                try? "[\(timestamp)] \(message)\n".write(toFile: "error.log", atomically: true, encoding: .utf8)
            }
            return
        }
        defer {
            try? handle.close()
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
