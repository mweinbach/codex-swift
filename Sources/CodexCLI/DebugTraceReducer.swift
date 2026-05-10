import Foundation

struct DebugTraceReducer {
    private let bundleURL: URL
    private var rollout: [String: Any]
    private var rawPayloads: [String: [String: Any]] = [:]
    private var threadConversationSnapshots: [String: [String]] = [:]
    private var nextConversationItemOrdinal = 1
    private var nextTerminalOperationOrdinal = 1

    init(bundleURL: URL) throws {
        self.bundleURL = bundleURL
        let manifest = try Self.loadJSONObject(
            at: bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        )
        self.rollout = [
            "schema_version": 1,
            "trace_id": try Self.requiredString(manifest, key: "trace_id"),
            "rollout_id": try Self.requiredString(manifest, key: "rollout_id"),
            "started_at_unix_ms": try Self.requiredInt(manifest, key: "started_at_unix_ms"),
            "ended_at_unix_ms": NSNull(),
            "status": "running",
            "root_thread_id": try Self.requiredString(manifest, key: "root_thread_id"),
            "threads": [String: Any](),
            "codex_turns": [String: Any](),
            "conversation_items": [String: Any](),
            "inference_calls": [String: Any](),
            "code_cells": [String: Any](),
            "tool_calls": [String: Any](),
            "terminal_sessions": [String: Any](),
            "terminal_operations": [String: Any](),
            "compactions": [String: Any](),
            "compaction_requests": [String: Any](),
            "interaction_edges": [String: Any](),
            "raw_payloads": [String: Any]()
        ]
    }

    mutating func replay() throws -> [String: Any] {
        let traceURL = bundleURL.appendingPathComponent("trace.jsonl", isDirectory: false)
        let trace = try String(contentsOf: traceURL, encoding: .utf8)
        for (lineIndex, line) in trace.components(separatedBy: .newlines).enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let data = Data(line.utf8)
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DebugTraceReducerError.invalidTraceEvent(line: lineIndex + 1)
            }
            try apply(event: event, line: lineIndex + 1)
        }
        rollout["raw_payloads"] = rawPayloads
        return rollout
    }

    private mutating func apply(event: [String: Any], line: Int) throws {
        guard let payload = event["payload"] as? [String: Any],
              let type = payload["type"] as? String
        else {
            throw DebugTraceReducerError.missingPayloadType(line: line)
        }

        try insertRawPayloadRefs(from: payload)

        switch type {
        case "rollout_started":
            rollout["trace_id"] = try Self.requiredString(payload, key: "trace_id")
            rollout["root_thread_id"] = try Self.requiredString(payload, key: "root_thread_id")
        case "rollout_ended":
            rollout["status"] = try Self.requiredString(payload, key: "status")
            rollout["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        case "thread_started":
            try startThread(event: event, payload: payload)
        case "thread_ended":
            try endThread(event: event, payload: payload)
        case "codex_turn_started":
            try startCodexTurn(event: event, payload: payload)
        case "codex_turn_ended":
            try endCodexTurn(event: event, payload: payload)
        case "inference_started":
            try startInference(event: event, payload: payload)
        case "inference_completed", "inference_failed", "inference_cancelled":
            try endInference(event: event, payload: payload, type: type)
        case "tool_call_started":
            try startToolCall(event: event, payload: payload)
        case "tool_call_runtime_started":
            try startToolCallRuntime(event: event, payload: payload)
        case "tool_call_runtime_ended":
            try endToolCallRuntime(event: event, payload: payload)
        case "tool_call_ended":
            try endToolCall(event: event, payload: payload)
        case "compaction_request_started":
            try startCompactionRequest(event: event, payload: payload)
        case "compaction_request_completed":
            try completeCompactionRequest(event: event, payload: payload, status: "completed")
        case "compaction_request_failed":
            try completeCompactionRequest(event: event, payload: payload, status: "failed")
        case "protocol_event_observed", "other":
            break
        default:
            throw DebugTraceReducerError.unsupportedPayload(type)
        }
    }

    private mutating func startThread(event: [String: Any], payload: [String: Any]) throws {
        let threadID = try Self.requiredString(payload, key: "thread_id")
        var threads = try Self.dictionaryMap(rollout["threads"], key: "threads")
        if threads[threadID] != nil {
            throw DebugTraceReducerError.duplicateThread(threadID)
        }

        let metadata = try threadStartedMetadata(payload["metadata_payload"])
        let spawn = Self.threadSpawnMetadata(metadata)
        let agentPath = spawn?.agentPath
            ?? metadata?["agent_path"] as? String
            ?? (payload["agent_path"] as? String)
            ?? ""
        let origin: [String: Any]
        if let spawn {
            origin = [
                "type": "spawned",
                "parent_thread_id": spawn.parentThreadID,
                "spawn_edge_id": "edge:spawn:\(spawn.parentThreadID):\(threadID)",
                "task_name": spawn.taskName ?? Self.taskName(fromAgentPath: agentPath),
                "agent_role": spawn.agentRole ?? ""
            ]
        } else {
            origin = ["type": "root"]
        }

        threads[threadID] = [
            "thread_id": threadID,
            "agent_path": agentPath,
            "nickname": Self.nullableString(metadata?["nickname"]),
            "origin": origin,
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "default_model": Self.nullableString(metadata?["model"]),
            "conversation_item_ids": []
        ]
        rollout["threads"] = threads
    }

    private mutating func endThread(event: [String: Any], payload: [String: Any]) throws {
        let threadID = try Self.requiredString(payload, key: "thread_id")
        let status = try Self.requiredString(payload, key: "status")
        var threads = try Self.dictionaryMap(rollout["threads"], key: "threads")
        guard var thread = threads[threadID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownThread(threadID)
        }
        guard var execution = thread["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("thread execution for \(threadID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = Self.executionStatus(fromRolloutStatus: status)
        thread["execution"] = execution
        threads[threadID] = thread
        rollout["threads"] = threads
    }

    private mutating func startCodexTurn(event: [String: Any], payload: [String: Any]) throws {
        let turnID = try Self.requiredString(payload, key: "codex_turn_id")
        let threadID = try Self.requiredString(payload, key: "thread_id")
        let threads = try Self.dictionaryMap(rollout["threads"], key: "threads")
        guard threads[threadID] != nil else {
            throw DebugTraceReducerError.unknownThread(threadID)
        }
        var turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
        if turns[turnID] != nil {
            throw DebugTraceReducerError.duplicateCodexTurn(turnID)
        }
        turns[turnID] = [
            "codex_turn_id": turnID,
            "thread_id": threadID,
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "input_item_ids": []
        ]
        rollout["codex_turns"] = turns
    }

    private mutating func endCodexTurn(event: [String: Any], payload: [String: Any]) throws {
        let turnID = try Self.requiredString(payload, key: "codex_turn_id")
        let status = try Self.requiredString(payload, key: "status")
        var turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
        guard var turn = turns[turnID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownCodexTurn(turnID)
        }
        if let eventThreadID = event["thread_id"] as? String,
           let turnThreadID = turn["thread_id"] as? String,
           eventThreadID != turnThreadID {
            throw DebugTraceReducerError.mismatchedTurnThread(
                turnID: turnID,
                eventThreadID: eventThreadID,
                turnThreadID: turnThreadID
            )
        }
        guard var execution = turn["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("codex turn execution for \(turnID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = status
        turn["execution"] = execution
        turns[turnID] = turn
        rollout["codex_turns"] = turns
        try closeRunningInferenceCalls(
            turnID: turnID,
            turnStatus: status,
            event: event
        )
    }

    private mutating func startInference(event: [String: Any], payload: [String: Any]) throws {
        let inferenceID = try Self.requiredString(payload, key: "inference_call_id")
        let threadID = try Self.requiredString(payload, key: "thread_id")
        let turnID = try Self.requiredString(payload, key: "codex_turn_id")
        let requestPayload = try Self.requiredDictionary(payload, key: "request_payload")

        let turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
        guard let turn = turns[turnID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownCodexTurnForInference(
                inferenceID: inferenceID,
                turnID: turnID
            )
        }
        if let turnThreadID = turn["thread_id"] as? String,
           turnThreadID != threadID {
            throw DebugTraceReducerError.mismatchedInferenceTurnThread(
                inferenceID: inferenceID,
                eventThreadID: threadID,
                turnID: turnID,
                turnThreadID: turnThreadID
            )
        }

        var inferenceCalls = try Self.dictionaryMap(rollout["inference_calls"], key: "inference_calls")
        if inferenceCalls[inferenceID] != nil {
            throw DebugTraceReducerError.duplicateInference(inferenceID)
        }

        var inference: [String: Any] = [
            "inference_call_id": inferenceID,
            "thread_id": threadID,
            "codex_turn_id": turnID,
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "model": try Self.requiredString(payload, key: "model"),
            "provider_name": try Self.requiredString(payload, key: "provider_name"),
            "response_id": NSNull(),
            "upstream_request_id": NSNull(),
            "request_item_ids": [],
            "response_item_ids": [],
            "tool_call_ids_started_by_response": [],
            "usage": NSNull(),
            "raw_request_payload_id": try Self.requiredString(requestPayload, key: "raw_payload_id"),
            "raw_response_payload_id": NSNull()
        ]
        inference["request_item_ids"] = try reduceInferenceRequest(
            event: event,
            inferenceID: inferenceID,
            threadID: threadID,
            codexTurnID: turnID,
            requestPayload: requestPayload
        )
        inferenceCalls[inferenceID] = inference
        rollout["inference_calls"] = inferenceCalls
    }

    private mutating func endInference(event: [String: Any], payload: [String: Any], type: String) throws {
        let inferenceID = try Self.requiredString(payload, key: "inference_call_id")
        var inferenceCalls = try Self.dictionaryMap(rollout["inference_calls"], key: "inference_calls")
        guard var inference = inferenceCalls[inferenceID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownInference(inferenceID)
        }

        let status: String
        let responsePayloadKey: String
        switch type {
        case "inference_completed":
            status = "completed"
            responsePayloadKey = "response_payload"
            inference["response_id"] = Self.nullableString(payload["response_id"])
        case "inference_failed":
            status = "failed"
            responsePayloadKey = "partial_response_payload"
        case "inference_cancelled":
            status = "cancelled"
            responsePayloadKey = "partial_response_payload"
        default:
            throw DebugTraceReducerError.unsupportedPayload(type)
        }

        if let upstreamRequestID = payload["upstream_request_id"] as? String {
            inference["upstream_request_id"] = upstreamRequestID
        }
        if let responsePayload = payload[responsePayloadKey] as? [String: Any] {
            inference["raw_response_payload_id"] = try Self.requiredString(responsePayload, key: "raw_payload_id")
            if let usage = try tokenUsage(from: responsePayload) {
                inference["usage"] = usage
            }
            inference["response_item_ids"] = try reduceInferenceResponse(
                event: event,
                inferenceID: inferenceID,
                threadID: try Self.requiredString(inference, key: "thread_id"),
                codexTurnID: try Self.requiredString(inference, key: "codex_turn_id"),
                responsePayload: responsePayload
            )
        }

        guard var execution = inference["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("inference execution for \(inferenceID)")
        }
        if execution["status"] as? String == "running" {
            execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
            execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
            execution["status"] = status
            inference["execution"] = execution
        }
        inferenceCalls[inferenceID] = inference
        rollout["inference_calls"] = inferenceCalls
    }

    private mutating func closeRunningInferenceCalls(
        turnID: String,
        turnStatus: String,
        event: [String: Any]
    ) throws {
        let inferenceStatus: String
        switch turnStatus {
        case "running":
            return
        case "completed", "cancelled":
            inferenceStatus = "cancelled"
        case "failed":
            inferenceStatus = "failed"
        case "aborted":
            inferenceStatus = "aborted"
        default:
            inferenceStatus = turnStatus
        }

        var inferenceCalls = try Self.dictionaryMap(rollout["inference_calls"], key: "inference_calls")
        for (inferenceID, value) in inferenceCalls {
            guard var inference = value as? [String: Any],
                  inference["codex_turn_id"] as? String == turnID,
                  var execution = inference["execution"] as? [String: Any],
                  execution["status"] as? String == "running"
            else {
                continue
            }
            execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
            execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
            execution["status"] = inferenceStatus
            inference["execution"] = execution
            inferenceCalls[inferenceID] = inference
        }
        rollout["inference_calls"] = inferenceCalls
    }

    private mutating func startToolCall(event: [String: Any], payload: [String: Any]) throws {
        let toolCallID = try Self.requiredString(payload, key: "tool_call_id")
        let threadID = try toolThreadID(event: event)
        let codexTurnID = event["codex_turn_id"] as? String
        if let codexTurnID {
            try validateToolTurn(threadID: threadID, codexTurnID: codexTurnID)
        }

        var toolCalls = try Self.dictionaryMap(rollout["tool_calls"], key: "tool_calls")
        if toolCalls[toolCallID] != nil {
            throw DebugTraceReducerError.duplicateToolCall(toolCallID)
        }

        var toolCall: [String: Any] = [
            "tool_call_id": toolCallID,
            "model_visible_call_id": Self.nullableString(payload["model_visible_call_id"]),
            "code_mode_runtime_tool_id": Self.nullableString(payload["code_mode_runtime_tool_id"]),
            "thread_id": threadID,
            "started_by_codex_turn_id": codexTurnID.map { $0 as Any } ?? NSNull(),
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "requester": try Self.requiredDictionary(payload, key: "requester"),
            "kind": try Self.requiredDictionary(payload, key: "kind"),
            "model_visible_call_item_ids": [],
            "model_visible_output_item_ids": [],
            "terminal_operation_id": NSNull(),
            "summary": try Self.requiredDictionary(payload, key: "summary"),
            "raw_invocation_payload_id": try Self.optionalRawPayloadID(payload["invocation_payload"]),
            "raw_result_payload_id": NSNull(),
            "raw_runtime_payload_ids": []
        ]
        if let operationID = try startDispatchTerminalOperationIfNeeded(event: event, toolCall: toolCall, payload: payload) {
            toolCall["terminal_operation_id"] = operationID
            toolCall["summary"] = [
                "type": "terminal",
                "operation_id": operationID
            ]
        }
        toolCalls[toolCallID] = toolCall
        rollout["tool_calls"] = toolCalls
    }

    private mutating func startToolCallRuntime(event: [String: Any], payload: [String: Any]) throws {
        let toolCallID = try Self.requiredString(payload, key: "tool_call_id")
        var toolCalls = try Self.dictionaryMap(rollout["tool_calls"], key: "tool_calls")
        guard var toolCall = toolCalls[toolCallID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownToolCallRuntimeStart(toolCallID)
        }
        let runtimePayload = try Self.requiredDictionary(payload, key: "runtime_payload")
        try appendRawRuntimePayloadID(runtimePayload, to: &toolCall)
        if let operationKind = terminalOperationKind(for: toolCall) {
            if toolCall["terminal_operation_id"] as? String != nil {
                throw DebugTraceReducerError.duplicateTerminalOperation(toolCallID)
            }
            let operationID = try startTerminalOperation(
                event: event,
                toolCall: toolCall,
                operationKind: operationKind,
                runtimePayload: runtimePayload
            )
            toolCall["terminal_operation_id"] = operationID
            toolCall["summary"] = [
                "type": "terminal",
                "operation_id": operationID
            ]
        }
        toolCalls[toolCallID] = toolCall
        rollout["tool_calls"] = toolCalls
    }

    private mutating func endToolCallRuntime(event: [String: Any], payload: [String: Any]) throws {
        let toolCallID = try Self.requiredString(payload, key: "tool_call_id")
        var toolCalls = try Self.dictionaryMap(rollout["tool_calls"], key: "tool_calls")
        guard var toolCall = toolCalls[toolCallID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownToolCallRuntimeEnd(toolCallID)
        }
        let runtimePayload = try Self.requiredDictionary(payload, key: "runtime_payload")
        try appendRawRuntimePayloadID(runtimePayload, to: &toolCall)
        if let operationID = toolCall["terminal_operation_id"] as? String {
            let status = try Self.requiredString(payload, key: "status")
            try endTerminalOperation(
                event: event,
                operationID: operationID,
                threadID: try Self.requiredString(toolCall, key: "thread_id"),
                status: status,
                runtimePayload: runtimePayload
            )
        }
        toolCalls[toolCallID] = toolCall
        rollout["tool_calls"] = toolCalls
    }

    private mutating func endToolCall(event: [String: Any], payload: [String: Any]) throws {
        let toolCallID = try Self.requiredString(payload, key: "tool_call_id")
        var toolCalls = try Self.dictionaryMap(rollout["tool_calls"], key: "tool_calls")
        guard var toolCall = toolCalls[toolCallID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownToolCallEnd(toolCallID)
        }
        guard var execution = toolCall["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("tool call execution for \(toolCallID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = try Self.requiredString(payload, key: "status")
        toolCall["execution"] = execution
        toolCall["raw_result_payload_id"] = try Self.optionalRawPayloadID(payload["result_payload"])
        if let operationID = toolCall["terminal_operation_id"] as? String,
           (toolCall["raw_runtime_payload_ids"] as? [String] ?? []).isEmpty {
            try endDispatchTerminalOperation(
                event: event,
                operationID: operationID,
                threadID: try Self.requiredString(toolCall, key: "thread_id"),
                status: try Self.requiredString(payload, key: "status"),
                resultPayload: payload["result_payload"] as? [String: Any]
            )
        }
        toolCalls[toolCallID] = toolCall
        rollout["tool_calls"] = toolCalls
    }

    private mutating func startCompactionRequest(event: [String: Any], payload: [String: Any]) throws {
        let requestID = try Self.requiredString(payload, key: "compaction_request_id")
        let compactionID = try Self.requiredString(payload, key: "compaction_id")
        let threadID = try Self.requiredString(payload, key: "thread_id")
        let codexTurnID = try Self.requiredString(payload, key: "codex_turn_id")
        let requestPayload = try Self.requiredDictionary(payload, key: "request_payload")

        let threads = try Self.dictionaryMap(rollout["threads"], key: "threads")
        guard threads[threadID] != nil else {
            throw DebugTraceReducerError.unknownThread(threadID)
        }
        let turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
        guard let turn = turns[codexTurnID] as? [String: Any],
              let turnThreadID = turn["thread_id"] as? String
        else {
            throw DebugTraceReducerError.unknownCodexTurnForCompactionRequest(
                requestID: requestID,
                turnID: codexTurnID
            )
        }
        if turnThreadID != threadID {
            throw DebugTraceReducerError.mismatchedCompactionRequestTurnThread(
                requestID: requestID,
                eventThreadID: threadID,
                turnID: codexTurnID,
                turnThreadID: turnThreadID
            )
        }

        var requests = try Self.dictionaryMap(rollout["compaction_requests"], key: "compaction_requests")
        if requests[requestID] != nil {
            throw DebugTraceReducerError.duplicateCompactionRequest(requestID)
        }
        requests[requestID] = [
            "compaction_request_id": requestID,
            "compaction_id": compactionID,
            "thread_id": threadID,
            "codex_turn_id": codexTurnID,
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "model": try Self.requiredString(payload, key: "model"),
            "provider_name": try Self.requiredString(payload, key: "provider_name"),
            "raw_request_payload_id": try Self.requiredString(requestPayload, key: "raw_payload_id"),
            "raw_response_payload_id": NSNull()
        ]
        rollout["compaction_requests"] = requests
    }

    private mutating func reduceInferenceRequest(
        event: [String: Any],
        inferenceID: String,
        threadID: String,
        codexTurnID: String,
        requestPayload: [String: Any]
    ) throws -> [String] {
        let rawPayloadID = try Self.requiredString(requestPayload, key: "raw_payload_id")
        let payload = try loadRawPayloadJSON(requestPayload)
        guard let input = payload["input"] as? [Any] else {
            throw DebugTraceReducerError.invalidTraceObject("inference request payload \(rawPayloadID) input")
        }
        let normalized = try input.map { try normalizeConversationItem($0, rawPayloadID: rawPayloadID) }
        let requestItemIDs: [String]
        if let previousResponseID = payload["previous_response_id"] as? String {
            let inferenceCalls = try Self.dictionaryMap(rollout["inference_calls"], key: "inference_calls")
            guard var previousItemIDs = inferenceCalls.values.compactMap({ value -> [String]? in
                guard let inference = value as? [String: Any],
                      inference["thread_id"] as? String == threadID,
                      inference["response_id"] as? String == previousResponseID
                else {
                    return nil
                }
                return (inference["request_item_ids"] as? [String] ?? [])
                    + (inference["response_item_ids"] as? [String] ?? [])
            }).first else {
                throw DebugTraceReducerError.unknownPreviousResponse(
                    inferenceID: inferenceID,
                    previousResponseID: previousResponseID
                )
            }
            previousItemIDs += try reconcileConversationItems(
                normalized,
                event: event,
                threadID: threadID,
                codexTurnID: codexTurnID,
                startIndex: previousItemIDs.count,
                mode: .appendOnly,
                producedBy: []
            )
            requestItemIDs = previousItemIDs
        } else {
            requestItemIDs = try reconcileConversationItems(
                normalized,
                event: event,
                threadID: threadID,
                codexTurnID: codexTurnID,
                startIndex: 0,
                mode: .fullSnapshot,
                producedBy: []
            )
        }
        try appendThreadConversationItems(threadID: threadID, itemIDs: requestItemIDs)
        threadConversationSnapshots[threadID] = requestItemIDs
        return requestItemIDs
    }

    private mutating func reduceInferenceResponse(
        event: [String: Any],
        inferenceID: String,
        threadID: String,
        codexTurnID: String,
        responsePayload: [String: Any]
    ) throws -> [String] {
        let rawPayloadID = try Self.requiredString(responsePayload, key: "raw_payload_id")
        let payload = try loadRawPayloadJSON(responsePayload)
        guard let outputItems = payload["output_items"] as? [Any] else {
            throw DebugTraceReducerError.invalidTraceObject("inference response payload \(rawPayloadID) output_items")
        }
        let normalized = try outputItems.map { try normalizeConversationItem($0, rawPayloadID: rawPayloadID) }
        let responseItemIDs = try reconcileConversationItems(
            normalized,
            event: event,
            threadID: threadID,
            codexTurnID: codexTurnID,
            startIndex: threadConversationSnapshots[threadID]?.count ?? 0,
            mode: .appendOnly,
            producedBy: [["type": "inference", "inference_call_id": inferenceID]]
        )
        try appendThreadConversationItems(threadID: threadID, itemIDs: responseItemIDs)
        threadConversationSnapshots[threadID, default: []] += responseItemIDs
        return responseItemIDs
    }

    private mutating func reconcileConversationItems(
        _ items: [NormalizedConversationItem],
        event: [String: Any],
        threadID: String,
        codexTurnID: String,
        startIndex: Int,
        mode: ConversationReconcileMode,
        producedBy: [[String: Any]]
    ) throws -> [String] {
        let previousSnapshot = threadConversationSnapshots[threadID] ?? []
        var itemIDs: [String] = []
        for (offset, item) in items.enumerated() {
            let index = startIndex + offset
            let itemID: String
            if let previousItemID = previousSnapshot[safe: index] {
                if conversationItem(previousItemID, matches: item) {
                    itemID = previousItemID
                } else if mode == .fullSnapshot,
                          let matched = findMatchingSnapshotItem(
                            previousSnapshot: previousSnapshot,
                            usedItemIDs: itemIDs,
                            normalized: item
                          ) {
                    itemID = matched
                } else if mode == .appendOnly {
                    throw DebugTraceReducerError.conversationMismatch(
                        turnID: codexTurnID,
                        threadID: threadID,
                        index: index,
                        existingItemID: previousItemID
                    )
                } else {
                    itemID = try createConversationItem(
                        item,
                        event: event,
                        threadID: threadID,
                        codexTurnID: codexTurnID,
                        producedBy: producedBy
                    )
                }
            } else if mode == .fullSnapshot,
                      let matched = findMatchingSnapshotItem(
                        previousSnapshot: previousSnapshot,
                        usedItemIDs: itemIDs,
                        normalized: item
                      ) {
                itemID = matched
            } else {
                itemID = try createConversationItem(
                    item,
                    event: event,
                    threadID: threadID,
                    codexTurnID: codexTurnID,
                    producedBy: producedBy
                )
            }
            try updateConversationItem(itemID, producedBy: producedBy)
            try attachModelVisibleToolItem(itemID: itemID, normalized: item)
            itemIDs.append(itemID)
        }
        return itemIDs
    }

    private mutating func createConversationItem(
        _ item: NormalizedConversationItem,
        event: [String: Any],
        threadID: String,
        codexTurnID: String,
        producedBy: [[String: Any]]
    ) throws -> String {
        let itemID = nextConversationItemID()
        var conversationItems = try Self.dictionaryMap(rollout["conversation_items"], key: "conversation_items")
        conversationItems[itemID] = [
            "item_id": itemID,
            "thread_id": threadID,
            "codex_turn_id": codexTurnID,
            "first_seen_at_unix_ms": try Self.requiredInt(event, key: "wall_time_unix_ms"),
            "role": item.role,
            "channel": item.channel.map { $0 as Any } ?? NSNull(),
            "kind": item.kind,
            "body": ["parts": item.parts],
            "call_id": item.callID.map { $0 as Any } ?? NSNull(),
            "produced_by": producedBy
        ]
        rollout["conversation_items"] = conversationItems
        return itemID
    }

    private mutating func updateConversationItem(_ itemID: String, producedBy: [[String: Any]]) throws {
        guard !producedBy.isEmpty else {
            return
        }
        var conversationItems = try Self.dictionaryMap(rollout["conversation_items"], key: "conversation_items")
        guard var item = conversationItems[itemID] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("conversation item \(itemID)")
        }
        var producers = item["produced_by"] as? [[String: Any]] ?? []
        for producer in producedBy where !producers.contains(where: { NSDictionary(dictionary: $0).isEqual(to: producer) }) {
            producers.append(producer)
        }
        item["produced_by"] = producers
        conversationItems[itemID] = item
        rollout["conversation_items"] = conversationItems
    }

    private mutating func appendThreadConversationItems(threadID: String, itemIDs: [String]) throws {
        var threads = try Self.dictionaryMap(rollout["threads"], key: "threads")
        guard var thread = threads[threadID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownThread(threadID)
        }
        var threadItemIDs = thread["conversation_item_ids"] as? [String] ?? []
        for itemID in itemIDs where !threadItemIDs.contains(itemID) {
            threadItemIDs.append(itemID)
        }
        thread["conversation_item_ids"] = threadItemIDs
        threads[threadID] = thread
        rollout["threads"] = threads
    }

    private mutating func attachModelVisibleToolItem(itemID: String, normalized: NormalizedConversationItem) throws {
        guard let callID = normalized.callID else {
            return
        }
        var toolCalls = try Self.dictionaryMap(rollout["tool_calls"], key: "tool_calls")
        let matchingIDs = toolCalls.compactMap { toolCallID, value -> String? in
            guard let toolCall = value as? [String: Any],
                  toolCall["model_visible_call_id"] as? String == callID
            else {
                return nil
            }
            return toolCallID
        }
        guard matchingIDs.count == 1, let toolCallID = matchingIDs.first,
              var toolCall = toolCalls[toolCallID] as? [String: Any]
        else {
            return
        }
        let key: String?
        switch normalized.kind {
        case "function_call", "custom_tool_call":
            key = "model_visible_call_item_ids"
        case "function_call_output", "custom_tool_call_output":
            key = "model_visible_output_item_ids"
        default:
            key = nil
        }
        guard let key else {
            return
        }
        var ids = toolCall[key] as? [String] ?? []
        if !ids.contains(itemID) {
            ids.append(itemID)
        }
        toolCall[key] = ids
        toolCalls[toolCallID] = toolCall
        rollout["tool_calls"] = toolCalls
    }

    private func findMatchingSnapshotItem(
        previousSnapshot: [String],
        usedItemIDs: [String],
        normalized: NormalizedConversationItem
    ) -> String? {
        previousSnapshot.first { itemID in
            !usedItemIDs.contains(itemID) && conversationItem(itemID, matches: normalized)
        }
    }

    private func conversationItem(_ itemID: String, matches normalized: NormalizedConversationItem) -> Bool {
        guard let conversationItems = rollout["conversation_items"] as? [String: Any],
              let item = conversationItems[itemID] as? [String: Any],
              item["role"] as? String == normalized.role,
              (item["channel"] as? String) == normalized.channel,
              item["kind"] as? String == normalized.kind,
              (item["call_id"] as? String) == normalized.callID,
              let body = item["body"] as? [String: Any],
              let existingParts = body["parts"] as? [[String: Any]]
        else {
            return false
        }
        return Self.conversationParts(existingParts, match: normalized.parts)
    }

    private mutating func nextConversationItemID() -> String {
        let itemID = "conversation_item:\(nextConversationItemOrdinal)"
        nextConversationItemOrdinal += 1
        return itemID
    }

    private mutating func completeCompactionRequest(
        event: [String: Any],
        payload: [String: Any],
        status: String
    ) throws {
        let requestID = try Self.requiredString(payload, key: "compaction_request_id")
        let compactionID = try Self.requiredString(payload, key: "compaction_id")
        var requests = try Self.dictionaryMap(rollout["compaction_requests"], key: "compaction_requests")
        guard var request = requests[requestID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownCompactionRequestCompletion(requestID)
        }
        guard let startedCompactionID = request["compaction_id"] as? String,
              startedCompactionID == compactionID
        else {
            throw DebugTraceReducerError.mismatchedCompactionRequestCompletion(
                requestID: requestID,
                eventCompactionID: compactionID,
                startedCompactionID: request["compaction_id"] as? String ?? ""
            )
        }
        guard var execution = request["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("compaction request execution for \(requestID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = status
        request["execution"] = execution
        if status == "completed" {
            let responsePayload = try Self.requiredDictionary(payload, key: "response_payload")
            request["raw_response_payload_id"] = try Self.requiredString(responsePayload, key: "raw_payload_id")
        }
        requests[requestID] = request
        rollout["compaction_requests"] = requests
    }

    private mutating func appendRawRuntimePayloadID(_ runtimePayload: [String: Any], to toolCall: inout [String: Any]) throws {
        let rawPayloadID = try Self.requiredString(runtimePayload, key: "raw_payload_id")
        var rawRuntimePayloadIDs = toolCall["raw_runtime_payload_ids"] as? [String] ?? []
        if !rawRuntimePayloadIDs.contains(rawPayloadID) {
            rawRuntimePayloadIDs.append(rawPayloadID)
        }
        toolCall["raw_runtime_payload_ids"] = rawRuntimePayloadIDs
    }

    private mutating func startDispatchTerminalOperationIfNeeded(
        event: [String: Any],
        toolCall: [String: Any],
        payload: [String: Any]
    ) throws -> String? {
        guard terminalOperationKind(for: toolCall) == "write_stdin",
              let invocationPayload = payload["invocation_payload"] as? [String: Any]
        else {
            return nil
        }
        let rawPayloadID = try Self.requiredString(invocationPayload, key: "raw_payload_id")
        let invocationJSON = try loadRawPayloadJSON(invocationPayload)
        let request = try dispatchWriteStdinRequest(fromInvocationPayload: invocationJSON)
        let operationID = nextTerminalOperationID()
        let toolCallID = try Self.requiredString(toolCall, key: "tool_call_id")
        let threadID = try Self.requiredString(toolCall, key: "thread_id")
        let terminalID = request.terminalID

        var terminalOperations = try Self.dictionaryMap(rollout["terminal_operations"], key: "terminal_operations")
        terminalOperations[operationID] = [
            "operation_id": operationID,
            "terminal_id": terminalID,
            "tool_call_id": toolCallID,
            "kind": "write_stdin",
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "request": request.request,
            "result": NSNull(),
            "model_observations": [],
            "raw_payload_ids": [rawPayloadID]
        ]
        rollout["terminal_operations"] = terminalOperations
        try ensureTerminalSession(
            threadID: threadID,
            terminalID: terminalID,
            operationID: operationID,
            startedAt: try Self.requiredInt(event, key: "wall_time_unix_ms"),
            startedSeq: try Self.requiredInt(event, key: "seq")
        )
        return operationID
    }

    private mutating func endDispatchTerminalOperation(
        event: [String: Any],
        operationID: String,
        threadID: String,
        status: String,
        resultPayload: [String: Any]?
    ) throws {
        let parsedResult: (rawPayloadID: String, result: [String: Any])?
        if let resultPayload {
            let rawPayloadID = try Self.requiredString(resultPayload, key: "raw_payload_id")
            parsedResult = (rawPayloadID, try dispatchTerminalResult(fromResultPayload: try loadRawPayloadJSON(resultPayload)))
        } else {
            parsedResult = nil
        }

        var terminalOperations = try Self.dictionaryMap(rollout["terminal_operations"], key: "terminal_operations")
        guard var operation = terminalOperations[operationID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownTerminalOperation(operationID)
        }
        guard var execution = operation["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("terminal operation execution for \(operationID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = status
        operation["execution"] = execution
        if let parsedResult {
            operation["result"] = parsedResult.result
            var rawPayloadIDs = operation["raw_payload_ids"] as? [String] ?? []
            if !rawPayloadIDs.contains(parsedResult.rawPayloadID) {
                rawPayloadIDs.append(parsedResult.rawPayloadID)
            }
            operation["raw_payload_ids"] = rawPayloadIDs
        }
        terminalOperations[operationID] = operation
        rollout["terminal_operations"] = terminalOperations

        if let terminalID = operation["terminal_id"] as? String,
           let startedAt = execution["started_at_unix_ms"] as? Int,
           let startedSeq = execution["started_seq"] as? Int {
            try ensureTerminalSession(
                threadID: threadID,
                terminalID: terminalID,
                operationID: operationID,
                startedAt: startedAt,
                startedSeq: startedSeq
            )
        }
    }

    private mutating func startTerminalOperation(
        event: [String: Any],
        toolCall: [String: Any],
        operationKind: String,
        runtimePayload: [String: Any]
    ) throws -> String {
        let rawPayloadID = try Self.requiredString(runtimePayload, key: "raw_payload_id")
        let runtimeJSON = try loadRawPayloadJSON(runtimePayload)
        let request = try terminalRequest(fromBeginPayload: runtimeJSON, operationKind: operationKind)
        let terminalID = runtimeJSON["process_id"] as? String
        let operationID = nextTerminalOperationID()
        let toolCallID = try Self.requiredString(toolCall, key: "tool_call_id")
        let threadID = try Self.requiredString(toolCall, key: "thread_id")

        var terminalOperations = try Self.dictionaryMap(rollout["terminal_operations"], key: "terminal_operations")
        terminalOperations[operationID] = [
            "operation_id": operationID,
            "terminal_id": terminalID.map { $0 as Any } ?? NSNull(),
            "tool_call_id": toolCallID,
            "kind": operationKind,
            "execution": try executionWindow(
                event: event,
                status: "running",
                endedAt: NSNull(),
                endedSeq: NSNull()
            ),
            "request": request,
            "result": NSNull(),
            "model_observations": [],
            "raw_payload_ids": [rawPayloadID]
        ]
        rollout["terminal_operations"] = terminalOperations

        if let terminalID {
            try ensureTerminalSession(
                threadID: threadID,
                terminalID: terminalID,
                operationID: operationID,
                startedAt: try Self.requiredInt(event, key: "wall_time_unix_ms"),
                startedSeq: try Self.requiredInt(event, key: "seq")
            )
        }
        return operationID
    }

    private mutating func endTerminalOperation(
        event: [String: Any],
        operationID: String,
        threadID: String,
        status: String,
        runtimePayload: [String: Any]
    ) throws {
        let rawPayloadID = try Self.requiredString(runtimePayload, key: "raw_payload_id")
        let runtimeJSON = try loadRawPayloadJSON(runtimePayload)
        var terminalOperations = try Self.dictionaryMap(rollout["terminal_operations"], key: "terminal_operations")
        guard var operation = terminalOperations[operationID] as? [String: Any] else {
            throw DebugTraceReducerError.unknownTerminalOperation(operationID)
        }
        let response = try terminalResult(fromEndPayload: runtimeJSON)
        if let responseTerminalID = response.terminalID {
            if let existingTerminalID = operation["terminal_id"] as? String,
               existingTerminalID != responseTerminalID {
                throw DebugTraceReducerError.mismatchedTerminalProcess(
                    operationID: operationID,
                    existingTerminalID: existingTerminalID,
                    responseTerminalID: responseTerminalID
                )
            }
            operation["terminal_id"] = responseTerminalID
        }
        guard var execution = operation["execution"] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("terminal operation execution for \(operationID)")
        }
        execution["ended_at_unix_ms"] = try Self.requiredInt(event, key: "wall_time_unix_ms")
        execution["ended_seq"] = try Self.requiredInt(event, key: "seq")
        execution["status"] = status
        operation["execution"] = execution
        operation["result"] = response.result
        var rawPayloadIDs = operation["raw_payload_ids"] as? [String] ?? []
        if !rawPayloadIDs.contains(rawPayloadID) {
            rawPayloadIDs.append(rawPayloadID)
        }
        operation["raw_payload_ids"] = rawPayloadIDs
        terminalOperations[operationID] = operation
        rollout["terminal_operations"] = terminalOperations

        if let terminalID = operation["terminal_id"] as? String,
           let startedAt = execution["started_at_unix_ms"] as? Int,
           let startedSeq = execution["started_seq"] as? Int {
            try ensureTerminalSession(
                threadID: threadID,
                terminalID: terminalID,
                operationID: operationID,
                startedAt: startedAt,
                startedSeq: startedSeq
            )
        }
    }

    private mutating func ensureTerminalSession(
        threadID: String,
        terminalID: String,
        operationID: String,
        startedAt: Int,
        startedSeq: Int
    ) throws {
        var sessions = try Self.dictionaryMap(rollout["terminal_sessions"], key: "terminal_sessions")
        if sessions[terminalID] == nil {
            sessions[terminalID] = [
                "terminal_id": terminalID,
                "thread_id": threadID,
                "created_by_operation_id": operationID,
                "operation_ids": [],
                "execution": [
                    "started_at_unix_ms": startedAt,
                    "started_seq": startedSeq,
                    "ended_at_unix_ms": NSNull(),
                    "ended_seq": NSNull(),
                    "status": "running"
                ]
            ]
        }
        guard var session = sessions[terminalID] as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject("terminal session \(terminalID)")
        }
        guard session["thread_id"] as? String == threadID else {
            throw DebugTraceReducerError.mismatchedTerminalSessionThread(
                terminalID: terminalID,
                existingThreadID: session["thread_id"] as? String ?? "",
                eventThreadID: threadID
            )
        }
        var operationIDs = session["operation_ids"] as? [String] ?? []
        if !operationIDs.contains(operationID) {
            operationIDs.append(operationID)
        }
        session["operation_ids"] = operationIDs
        sessions[terminalID] = session
        rollout["terminal_sessions"] = sessions
    }

    private mutating func nextTerminalOperationID() -> String {
        let operationID = "terminal_operation:\(nextTerminalOperationOrdinal)"
        nextTerminalOperationOrdinal += 1
        return operationID
    }

    private func terminalOperationKind(for toolCall: [String: Any]) -> String? {
        guard let kind = toolCall["kind"] as? [String: Any],
              let type = kind["type"] as? String
        else {
            return nil
        }
        switch type {
        case "exec_command", "write_stdin":
            return type
        default:
            return nil
        }
    }

    private func terminalRequest(fromBeginPayload payload: [String: Any], operationKind: String) throws -> [String: Any] {
        switch operationKind {
        case "exec_command":
            return [
                "type": "exec_command",
                "command": try Self.requiredStringArray(payload, key: "command"),
                "display_command": try Self.requiredStringArray(payload, key: "command").joined(separator: " "),
                "cwd": try Self.requiredString(payload, key: "cwd"),
                "yield_time_ms": NSNull(),
                "max_output_tokens": NSNull()
            ]
        case "write_stdin":
            _ = try Self.requiredStringArray(payload, key: "command")
            _ = try Self.requiredString(payload, key: "cwd")
            return [
                "type": "write_stdin",
                "stdin": payload["interaction_input"] as? String ?? "",
                "yield_time_ms": NSNull(),
                "max_output_tokens": NSNull()
            ]
        default:
            throw DebugTraceReducerError.invalidTraceObject("terminal operation kind \(operationKind)")
        }
    }

    private func dispatchWriteStdinRequest(fromInvocationPayload payload: [String: Any]) throws -> DispatchTerminalRequest {
        guard (payload["tool_name"] as? String) == "write_stdin" else {
            throw DebugTraceReducerError.invalidTraceObject("dispatch terminal request")
        }
        let toolPayload = try Self.requiredDictionary(payload, key: "payload")
        guard (toolPayload["type"] as? String) == "function" else {
            throw DebugTraceReducerError.invalidTraceObject("write_stdin dispatch payload")
        }
        let arguments = try Self.requiredString(toolPayload, key: "arguments")
        guard let argumentsData = arguments.data(using: .utf8),
              let args = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
              let terminalID = Self.terminalID(from: args["session_id"])
        else {
            throw DebugTraceReducerError.missingField("session_id")
        }
        return DispatchTerminalRequest(
            terminalID: terminalID,
            request: [
                "type": "write_stdin",
                "stdin": args["chars"] as? String ?? "",
                "yield_time_ms": args["yield_time_ms"] ?? NSNull(),
                "max_output_tokens": args["max_output_tokens"] ?? NSNull()
            ]
        )
    }

    private func terminalResult(fromEndPayload payload: [String: Any]) throws -> TerminalEndResult {
        let result: [String: Any] = [
            "exit_code": try Self.requiredInt(payload, key: "exit_code"),
            "stdout": try Self.requiredString(payload, key: "stdout"),
            "stderr": try Self.requiredString(payload, key: "stderr"),
            "formatted_output": try Self.requiredString(payload, key: "formatted_output"),
            "original_token_count": NSNull(),
            "chunk_id": NSNull()
        ]
        return TerminalEndResult(terminalID: payload["process_id"] as? String, result: result)
    }

    private func dispatchTerminalResult(fromResultPayload payload: [String: Any]) throws -> [String: Any] {
        let type = try Self.requiredString(payload, key: "type")
        switch type {
        case "direct_response":
            let responseItem = try Self.requiredDictionary(payload, key: "response_item")
            let output = Self.jsonTextContent(responseItem["output"]) ?? Self.jsonString(responseItem)
            return [
                "exit_code": NSNull(),
                "stdout": output,
                "stderr": "",
                "formatted_output": output,
                "original_token_count": NSNull(),
                "chunk_id": NSNull()
            ]
        case "code_mode_response":
            let value = try Self.requiredDictionary(payload, key: "value")
            let output = value["output"] as? String ?? (Self.jsonTextContent(value["output"]) ?? Self.jsonString(value))
            return [
                "exit_code": value["exit_code"] ?? NSNull(),
                "stdout": output,
                "stderr": "",
                "formatted_output": output,
                "original_token_count": value["original_token_count"] ?? NSNull(),
                "chunk_id": value["chunk_id"] ?? NSNull()
            ]
        case "error":
            let error = try Self.requiredString(payload, key: "error")
            return [
                "exit_code": NSNull(),
                "stdout": "",
                "stderr": error,
                "formatted_output": error,
                "original_token_count": NSNull(),
                "chunk_id": NSNull()
            ]
        default:
            throw DebugTraceReducerError.invalidTraceObject("dispatch terminal response \(type)")
        }
    }

    private func normalizeConversationItem(_ value: Any, rawPayloadID: String) throws -> NormalizedConversationItem {
        guard let item = value as? [String: Any],
              let type = item["type"] as? String
        else {
            throw DebugTraceReducerError.invalidTraceObject("model item in payload \(rawPayloadID)")
        }
        switch type {
        case "message":
            guard let role = item["role"] as? String else {
                throw DebugTraceReducerError.invalidTraceObject("message item in payload \(rawPayloadID) role")
            }
            return NormalizedConversationItem(
                role: role,
                channel: Self.channel(fromPhase: item["phase"] as? String),
                kind: "message",
                parts: Self.contentParts(item["content"], rawPayloadID: rawPayloadID),
                callID: nil
            )
        case "function_call":
            return NormalizedConversationItem(
                role: "assistant",
                channel: "commentary",
                kind: "function_call",
                parts: [Self.rawTextOrJSONPart(item["arguments"], rawPayloadID: rawPayloadID)],
                callID: item["call_id"] as? String
            )
        case "function_call_output":
            return NormalizedConversationItem(
                role: "tool",
                channel: "commentary",
                kind: "function_call_output",
                parts: Self.toolOutputParts(item["output"], rawPayloadID: rawPayloadID),
                callID: item["call_id"] as? String
            )
        case "custom_tool_call":
            return NormalizedConversationItem(
                role: "assistant",
                channel: "commentary",
                kind: "custom_tool_call",
                parts: [Self.customToolCallPart(item, rawPayloadID: rawPayloadID)],
                callID: item["call_id"] as? String
            )
        case "custom_tool_call_output":
            return NormalizedConversationItem(
                role: "tool",
                channel: "commentary",
                kind: "custom_tool_call_output",
                parts: Self.toolOutputParts(item["output"], rawPayloadID: rawPayloadID),
                callID: item["call_id"] as? String
            )
        case "tool_search_call", "web_search_call", "image_generation_call", "local_shell_call":
            return NormalizedConversationItem(
                role: "assistant",
                channel: "commentary",
                kind: "function_call",
                parts: [Self.jsonPart(item, rawPayloadID: rawPayloadID)],
                callID: item["call_id"] as? String
            )
        case "tool_search_output", "mcp_tool_call_output":
            return NormalizedConversationItem(
                role: "tool",
                channel: "commentary",
                kind: "function_call_output",
                parts: [Self.jsonPart(item, rawPayloadID: rawPayloadID)],
                callID: item["call_id"] as? String
            )
        default:
            throw DebugTraceReducerError.unsupportedModelItem(type: type, rawPayloadID: rawPayloadID)
        }
    }

    private func loadRawPayloadJSON(_ payloadRef: [String: Any]) throws -> [String: Any] {
        let path = try Self.requiredString(payloadRef, key: "path")
        return try Self.loadJSONObject(at: bundleURL.appendingPathComponent(path, isDirectory: false))
    }

    private func toolThreadID(event: [String: Any]) throws -> String {
        if let threadID = event["thread_id"] as? String {
            return threadID
        }
        if let codexTurnID = event["codex_turn_id"] as? String {
            let turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
            guard let turn = turns[codexTurnID] as? [String: Any],
                  let threadID = turn["thread_id"] as? String
            else {
                throw DebugTraceReducerError.unknownCodexTurnForToolCall(codexTurnID)
            }
            return threadID
        }
        throw DebugTraceReducerError.missingToolThreadContext
    }

    private func validateToolTurn(threadID: String, codexTurnID: String) throws {
        let turns = try Self.dictionaryMap(rollout["codex_turns"], key: "codex_turns")
        guard let turn = turns[codexTurnID] as? [String: Any],
              let turnThreadID = turn["thread_id"] as? String
        else {
            throw DebugTraceReducerError.unknownCodexTurnForToolCall(codexTurnID)
        }
        if threadID != turnThreadID {
            throw DebugTraceReducerError.mismatchedToolTurnThread(
                eventThreadID: threadID,
                turnID: codexTurnID,
                turnThreadID: turnThreadID
            )
        }
    }

    private func tokenUsage(from responsePayload: [String: Any]) throws -> Any? {
        guard let path = responsePayload["path"] as? String else {
            return nil
        }
        let payload = try Self.loadJSONObject(at: bundleURL.appendingPathComponent(path, isDirectory: false))
        guard let usage = payload["token_usage"] as? [String: Any] else {
            return nil
        }
        return [
            "input_tokens": try Self.requiredInt(usage, key: "input_tokens"),
            "cached_input_tokens": try Self.requiredInt(usage, key: "cached_input_tokens"),
            "output_tokens": try Self.requiredInt(usage, key: "output_tokens"),
            "reasoning_output_tokens": try Self.requiredInt(usage, key: "reasoning_output_tokens")
        ]
    }

    private func executionWindow(
        event: [String: Any],
        status: String,
        endedAt: Any,
        endedSeq: Any
    ) throws -> [String: Any] {
        [
            "started_at_unix_ms": try Self.requiredInt(event, key: "wall_time_unix_ms"),
            "started_seq": try Self.requiredInt(event, key: "seq"),
            "ended_at_unix_ms": endedAt,
            "ended_seq": endedSeq,
            "status": status
        ]
    }

    private mutating func insertRawPayloadRefs(from value: Any) throws {
        if let dictionary = value as? [String: Any] {
            if let rawPayloadID = dictionary["raw_payload_id"] as? String {
                rawPayloads[rawPayloadID] = dictionary
            }
            for nestedValue in dictionary.values {
                try insertRawPayloadRefs(from: nestedValue)
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                try insertRawPayloadRefs(from: nestedValue)
            }
        }
    }

    private func threadStartedMetadata(_ metadataPayload: Any?) throws -> [String: Any]? {
        guard let payload = metadataPayload as? [String: Any],
              let path = payload["path"] as? String
        else {
            return nil
        }
        return try Self.loadJSONObject(at: bundleURL.appendingPathComponent(path, isDirectory: false))
    }

    private static func threadSpawnMetadata(_ metadata: [String: Any]?) -> ThreadSpawnMetadata? {
        guard let metadata,
              let sessionSource = metadata["session_source"] as? [String: Any],
              let subagent = sessionSource["subagent"] as? [String: Any],
              let threadSpawn = subagent["thread_spawn"] as? [String: Any],
              let parentThreadID = threadSpawn["parent_thread_id"] as? String
        else {
            return nil
        }
        let agentPath = threadSpawn["agent_path"] as? String ?? metadata["agent_path"] as? String
        return ThreadSpawnMetadata(
            parentThreadID: parentThreadID,
            agentPath: agentPath,
            taskName: threadSpawn["task_name"] as? String
                ?? metadata["task_name"] as? String
                ?? agentPath.map(Self.taskName(fromAgentPath:)),
            agentRole: threadSpawn["agent_role"] as? String ?? metadata["agent_role"] as? String
        )
    }

    private static func nullableString(_ value: Any?) -> Any {
        (value as? String) ?? NSNull()
    }

    private static func taskName(fromAgentPath agentPath: String) -> String {
        agentPath.split(separator: "/").last.map(String.init) ?? agentPath
    }

    private static func executionStatus(fromRolloutStatus status: String) -> String {
        switch status {
        case "completed":
            return "completed"
        case "failed":
            return "failed"
        case "aborted":
            return "aborted"
        default:
            return "running"
        }
    }

    private static func dictionaryMap(_ value: Any?, key: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw DebugTraceReducerError.invalidTraceObject(key)
        }
        return dictionary
    }

    private static func requiredDictionary(_ dictionary: [String: Any], key: String) throws -> [String: Any] {
        guard let value = dictionary[key] as? [String: Any] else {
            throw DebugTraceReducerError.missingField(key)
        }
        return value
    }

    private static func optionalRawPayloadID(_ value: Any?) throws -> Any {
        guard let dictionary = value as? [String: Any] else {
            return NSNull()
        }
        return try requiredString(dictionary, key: "raw_payload_id")
    }

    private static func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DebugTraceReducerError.invalidJSONObject(url.path)
        }
        return object
    }

    private static func requiredString(_ dictionary: [String: Any], key: String) throws -> String {
        guard let value = dictionary[key] as? String else {
            throw DebugTraceReducerError.missingField(key)
        }
        return value
    }

    private static func requiredInt(_ dictionary: [String: Any], key: String) throws -> Int {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        throw DebugTraceReducerError.missingField(key)
    }

    private static func requiredStringArray(_ dictionary: [String: Any], key: String) throws -> [String] {
        guard let value = dictionary[key] as? [String] else {
            throw DebugTraceReducerError.missingField(key)
        }
        return value
    }

    private static func terminalID(from value: Any?) -> String? {
        switch value {
        case let string as String where !string.isEmpty:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func jsonTextContent(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let array as [[String: Any]]:
            let text = array.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        case nil, is NSNull:
            return nil
        case let value?:
            return jsonString(value)
        }
    }

    private static func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "\(value)"
        }
        return string
    }

    private static func channel(fromPhase phase: String?) -> String? {
        switch phase {
        case "commentary":
            return "commentary"
        case "final_answer":
            return "final"
        case "summary":
            return "summary"
        default:
            return nil
        }
    }

    private static func contentParts(_ content: Any?, rawPayloadID: String) -> [[String: Any]] {
        guard let content = content as? [[String: Any]] else {
            return [payloadRefPart(label: "content", rawPayloadID: rawPayloadID)]
        }
        var parts: [[String: Any]] = []
        for part in content {
            switch part["type"] as? String {
            case "input_text", "output_text", "text":
                if let text = part["text"] as? String {
                    parts.append(["type": "text", "text": text])
                }
            case "input_image":
                parts.append(payloadRefPart(label: "input_image", rawPayloadID: rawPayloadID))
            case let type?:
                parts.append(payloadRefPart(label: type, rawPayloadID: rawPayloadID))
            case nil:
                parts.append(payloadRefPart(label: "content", rawPayloadID: rawPayloadID))
            }
        }
        if parts.isEmpty {
            parts.append(payloadRefPart(label: "empty_content", rawPayloadID: rawPayloadID))
        }
        return parts
    }

    private static func rawTextOrJSONPart(_ value: Any?, rawPayloadID: String) -> [String: Any] {
        if let text = value as? String {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               JSONSerialization.isValidJSONObject(json) {
                return jsonPart(json, rawPayloadID: rawPayloadID)
            }
            return ["type": "text", "text": text]
        }
        if let value, JSONSerialization.isValidJSONObject(value) {
            return jsonPart(value, rawPayloadID: rawPayloadID)
        }
        return payloadRefPart(label: "payload", rawPayloadID: rawPayloadID)
    }

    private static func customToolCallPart(_ item: [String: Any], rawPayloadID: String) -> [String: Any] {
        guard let input = item["input"] as? String else {
            return jsonPart(item, rawPayloadID: rawPayloadID)
        }
        if item["name"] as? String == "exec" {
            return ["type": "code", "language": "javascript", "source": input]
        }
        return ["type": "text", "text": input]
    }

    private static func toolOutputParts(_ output: Any?, rawPayloadID: String) -> [[String: Any]] {
        if let text = output as? String {
            return [["type": "text", "text": text]]
        }
        if let array = output as? [[String: Any]] {
            return contentParts(array, rawPayloadID: rawPayloadID)
        }
        if let output, JSONSerialization.isValidJSONObject(output) {
            return [jsonPart(output, rawPayloadID: rawPayloadID)]
        }
        return [payloadRefPart(label: "tool_output", rawPayloadID: rawPayloadID)]
    }

    private static func jsonPart(_ value: Any, rawPayloadID: String) -> [String: Any] {
        [
            "type": "json",
            "summary": jsonSummary(value),
            "raw_payload_id": rawPayloadID
        ]
    }

    private static func payloadRefPart(label: String, rawPayloadID: String) -> [String: Any] {
        [
            "type": "payload_ref",
            "label": label,
            "raw_payload_id": rawPayloadID
        ]
    }

    private static func jsonSummary(_ value: Any) -> String {
        var summary = jsonString(value)
        if summary.count > 240 {
            summary = String(summary.prefix(240)) + "..."
        }
        return summary
    }

    private static func conversationParts(_ left: [[String: Any]], match right: [[String: Any]]) -> Bool {
        guard left.count == right.count else {
            return false
        }
        return zip(left, right).allSatisfy { lhs, rhs in
            if lhs["type"] as? String == "json",
               rhs["type"] as? String == "json" {
                return lhs["summary"] as? String == rhs["summary"] as? String
            }
            return NSDictionary(dictionary: lhs).isEqual(to: rhs)
        }
    }
}

private enum ConversationReconcileMode {
    case fullSnapshot
    case appendOnly
}

private struct ThreadSpawnMetadata {
    var parentThreadID: String
    var agentPath: String?
    var taskName: String?
    var agentRole: String?
}

private struct TerminalEndResult {
    var terminalID: String?
    var result: [String: Any]
}

private struct DispatchTerminalRequest {
    var terminalID: String
    var request: [String: Any]
}

private struct NormalizedConversationItem {
    var role: String
    var channel: String?
    var kind: String
    var parts: [[String: Any]]
    var callID: String?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private enum DebugTraceReducerError: Error, CustomStringConvertible {
    case invalidJSONObject(String)
    case invalidTraceEvent(line: Int)
    case missingPayloadType(line: Int)
    case missingField(String)
    case invalidTraceObject(String)
    case unsupportedPayload(String)
    case duplicateThread(String)
    case unknownThread(String)
    case duplicateCodexTurn(String)
    case unknownCodexTurn(String)
    case mismatchedTurnThread(turnID: String, eventThreadID: String, turnThreadID: String)
    case duplicateInference(String)
    case unknownInference(String)
    case unknownCodexTurnForInference(inferenceID: String, turnID: String)
    case mismatchedInferenceTurnThread(
        inferenceID: String,
        eventThreadID: String,
        turnID: String,
        turnThreadID: String
    )
    case duplicateToolCall(String)
    case unknownToolCallEnd(String)
    case unknownToolCallRuntimeStart(String)
    case unknownToolCallRuntimeEnd(String)
    case missingToolThreadContext
    case unknownCodexTurnForToolCall(String)
    case mismatchedToolTurnThread(eventThreadID: String, turnID: String, turnThreadID: String)
    case duplicateCompactionRequest(String)
    case unknownCompactionRequestCompletion(String)
    case unknownCodexTurnForCompactionRequest(requestID: String, turnID: String)
    case mismatchedCompactionRequestTurnThread(
        requestID: String,
        eventThreadID: String,
        turnID: String,
        turnThreadID: String
    )
    case mismatchedCompactionRequestCompletion(
        requestID: String,
        eventCompactionID: String,
        startedCompactionID: String
    )
    case duplicateTerminalOperation(String)
    case unknownTerminalOperation(String)
    case mismatchedTerminalProcess(
        operationID: String,
        existingTerminalID: String,
        responseTerminalID: String
    )
    case mismatchedTerminalSessionThread(
        terminalID: String,
        existingThreadID: String,
        eventThreadID: String
    )
    case unknownPreviousResponse(inferenceID: String, previousResponseID: String)
    case conversationMismatch(turnID: String, threadID: String, index: Int, existingItemID: String)
    case unsupportedModelItem(type: String, rawPayloadID: String)

    var description: String {
        switch self {
        case let .invalidJSONObject(path):
            return "invalid JSON object at \(path)"
        case let .invalidTraceEvent(line):
            return "invalid trace event line \(line)"
        case let .missingPayloadType(line):
            return "missing trace event payload type on line \(line)"
        case let .missingField(field):
            return "missing required trace field \(field)"
        case let .invalidTraceObject(name):
            return "invalid trace object \(name)"
        case let .unsupportedPayload(type):
            return "unsupported trace event payload type \(type)"
        case let .duplicateThread(threadID):
            return "duplicate thread start for \(threadID)"
        case let .unknownThread(threadID):
            return "trace event referenced unknown thread \(threadID)"
        case let .duplicateCodexTurn(turnID):
            return "duplicate codex turn start for \(turnID)"
        case let .unknownCodexTurn(turnID):
            return "codex turn end referenced unknown turn \(turnID)"
        case let .mismatchedTurnThread(turnID, eventThreadID, turnThreadID):
            return "codex turn end for \(turnID) used thread \(eventThreadID), but the turn belongs to \(turnThreadID)"
        case let .duplicateInference(inferenceID):
            return "duplicate inference start for \(inferenceID)"
        case let .unknownInference(inferenceID):
            return "inference completion referenced unknown call \(inferenceID)"
        case let .unknownCodexTurnForInference(inferenceID, turnID):
            return "inference start \(inferenceID) referenced unknown codex turn \(turnID)"
        case let .mismatchedInferenceTurnThread(inferenceID, eventThreadID, turnID, turnThreadID):
            return "inference start \(inferenceID) used thread \(eventThreadID), but codex turn \(turnID) belongs to \(turnThreadID)"
        case let .duplicateToolCall(toolCallID):
            return "duplicate tool call start for \(toolCallID)"
        case let .unknownToolCallEnd(toolCallID):
            return "tool call end referenced unknown call \(toolCallID)"
        case let .unknownToolCallRuntimeStart(toolCallID):
            return "tool runtime start referenced unknown call \(toolCallID)"
        case let .unknownToolCallRuntimeEnd(toolCallID):
            return "tool runtime end referenced unknown call \(toolCallID)"
        case .missingToolThreadContext:
            return "tool call start is missing thread or codex turn context"
        case let .unknownCodexTurnForToolCall(turnID):
            return "tool call start referenced unknown codex turn \(turnID)"
        case let .mismatchedToolTurnThread(eventThreadID, turnID, turnThreadID):
            return "tool call start used thread \(eventThreadID), but codex turn \(turnID) belongs to \(turnThreadID)"
        case let .duplicateCompactionRequest(requestID):
            return "duplicate compaction request start for \(requestID)"
        case let .unknownCompactionRequestCompletion(requestID):
            return "compaction request completion referenced unknown request \(requestID)"
        case let .unknownCodexTurnForCompactionRequest(requestID, turnID):
            return "compaction request \(requestID) referenced unknown codex turn \(turnID)"
        case let .mismatchedCompactionRequestTurnThread(requestID, eventThreadID, turnID, turnThreadID):
            return "compaction request \(requestID) used thread \(eventThreadID), but codex turn \(turnID) belongs to \(turnThreadID)"
        case let .mismatchedCompactionRequestCompletion(requestID, eventCompactionID, startedCompactionID):
            return "compaction request \(requestID) completion used compaction \(eventCompactionID), but start used \(startedCompactionID)"
        case let .duplicateTerminalOperation(toolCallID):
            return "tool runtime start would create a second terminal operation for \(toolCallID)"
        case let .unknownTerminalOperation(operationID):
            return "terminal end referenced unknown operation \(operationID)"
        case let .mismatchedTerminalProcess(operationID, existingTerminalID, responseTerminalID):
            return "terminal operation \(operationID) changed process id from \(existingTerminalID) to \(responseTerminalID)"
        case let .mismatchedTerminalSessionThread(terminalID, existingThreadID, eventThreadID):
            return "terminal session \(terminalID) belongs to thread \(existingThreadID), not \(eventThreadID)"
        case let .unknownPreviousResponse(inferenceID, previousResponseID):
            return "incremental inference request \(inferenceID) referenced unknown previous_response_id \(previousResponseID)"
        case let .conversationMismatch(turnID, threadID, index, existingItemID):
            return "model conversation mismatch while reducing turn \(turnID) for thread \(threadID) at item index \(index): existing item \(existingItemID) does not match the current model payload item"
        case let .unsupportedModelItem(type, rawPayloadID):
            return "unsupported model item type \(type) in payload \(rawPayloadID)"
        }
    }
}
