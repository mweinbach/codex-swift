import CodexCore
import Foundation

struct RemoteControlAppServerBridgeOutgoingMessage: Equatable, Sendable {
    var connectionID: RemoteControlVirtualConnectionID
    var message: ExecServerJSONRPCMessage
}

struct RemoteControlAppServerBridgeStep: Equatable, Sendable {
    var outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage]
    var droppedUnknownConnectionIDs: [RemoteControlVirtualConnectionID]

    init(
        outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage] = [],
        droppedUnknownConnectionIDs: [RemoteControlVirtualConnectionID] = []
    ) {
        self.outgoingMessages = outgoingMessages
        self.droppedUnknownConnectionIDs = droppedUnknownConnectionIDs
    }

    mutating func append(_ step: RemoteControlAppServerBridgeStep) {
        outgoingMessages.append(contentsOf: step.outgoingMessages)
        droppedUnknownConnectionIDs.append(contentsOf: step.droppedUnknownConnectionIDs)
    }
}

struct RemoteControlAppServerVirtualLoopStep: Equatable, Sendable {
    var transportStep: RemoteControlVirtualTransportStep
    var bridgeStep: RemoteControlAppServerBridgeStep
    var serverEvents: [RemoteControlQueuedServerEnvelope]

    init(
        transportStep: RemoteControlVirtualTransportStep = RemoteControlVirtualTransportStep(),
        bridgeStep: RemoteControlAppServerBridgeStep = RemoteControlAppServerBridgeStep(),
        serverEvents: [RemoteControlQueuedServerEnvelope] = []
    ) {
        self.transportStep = transportStep
        self.bridgeStep = bridgeStep
        self.serverEvents = serverEvents
    }
}

struct RemoteControlAppServerVirtualLoop {
    private var transport: RemoteControlVirtualTransportCore
    private var bridge: RemoteControlAppServerBridge

    init(
        transport: RemoteControlVirtualTransportCore = RemoteControlVirtualTransportCore(),
        bridge: RemoteControlAppServerBridge
    ) {
        self.transport = transport
        self.bridge = bridge
    }

    init(
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.init(
            bridge: RemoteControlAppServerBridge(
                configuration: configuration,
                threadStateManager: threadStateManager
            )
        )
    }

    mutating func handleClientEnvelope(
        _ envelope: RemoteControlClientEnvelope,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.handleClientEnvelope(envelope, now: now))
    }

    mutating func disconnect(
        connectionID: RemoteControlVirtualConnectionID
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.disconnect(connectionID: connectionID))
    }

    mutating func closeExpiredClients(
        now: TimeInterval
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.closeExpiredClients(now: now))
    }

    mutating func handleClientTrackerEffects(
        _ effects: [RemoteControlClientTrackerEffect]
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.applyClientTrackerEffects(effects))
    }

    mutating func drainPendingNotifications() async -> RemoteControlAppServerVirtualLoopStep {
        let bridgeStep = await bridge.drainPendingNotifications()
        return RemoteControlAppServerVirtualLoopStep(
            bridgeStep: bridgeStep,
            serverEvents: enqueue(bridgeStep.outgoingMessages)
        )
    }

    private mutating func apply(
        _ transportStep: RemoteControlVirtualTransportStep
    ) async -> RemoteControlAppServerVirtualLoopStep {
        let bridgeStep = await bridge.handle(transportStep.transportEvents)
        return RemoteControlAppServerVirtualLoopStep(
            transportStep: transportStep,
            bridgeStep: bridgeStep,
            serverEvents: transportStep.serverEvents + enqueue(bridgeStep.outgoingMessages)
        )
    }

    private mutating func enqueue(
        _ outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage]
    ) -> [RemoteControlQueuedServerEnvelope] {
        outgoingMessages.compactMap { outgoing in
            transport.enqueueOutgoingMessage(
                connectionID: outgoing.connectionID,
                message: outgoing.message
            )
        }
    }
}

struct RemoteControlAppServerWebSocketSessionStep: Equatable, Sendable {
    var connectionStep: RemoteControlWebsocketConnectionStep
    var appServerStep: RemoteControlAppServerVirtualLoopStep
    var writerSteps: [RemoteControlWebsocketConnectionStep]

    init(
        connectionStep: RemoteControlWebsocketConnectionStep = RemoteControlWebsocketConnectionStep(),
        appServerStep: RemoteControlAppServerVirtualLoopStep = RemoteControlAppServerVirtualLoopStep(),
        writerSteps: [RemoteControlWebsocketConnectionStep] = []
    ) {
        self.connectionStep = connectionStep
        self.appServerStep = appServerStep
        self.writerSteps = writerSteps
    }

    var terminalEnd: RemoteControlWebsocketConnectionEnd? {
        if let end = connectionStep.end {
            return end
        }
        return writerSteps.first { $0.end != nil }?.end
    }
}

struct RemoteControlAppServerWebSocketSession<Transport: RemoteControlWebSocketTransport> {
    private var runner: RemoteControlWebSocketSessionRunner<Transport>
    private var state = RemoteControlWebsocketState()
    private var clientTracker = RemoteControlClientTracker()
    private var appServerLoop: RemoteControlAppServerVirtualLoop

    init(
        transport: Transport,
        statusPublisher: RemoteControlStatusPublisherCore,
        appServerLoop: RemoteControlAppServerVirtualLoop
    ) {
        runner = RemoteControlWebSocketSessionRunner(
            transport: transport,
            statusPublisher: statusPublisher
        )
        self.appServerLoop = appServerLoop
    }

    init(
        transport: Transport,
        statusPublisher: RemoteControlStatusPublisherCore,
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.init(
            transport: transport,
            statusPublisher: statusPublisher,
            appServerLoop: RemoteControlAppServerVirtualLoop(
                configuration: configuration,
                threadStateManager: threadStateManager
            )
        )
    }

    mutating func receive(
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) async throws -> RemoteControlAppServerWebSocketSessionStep {
        try await process(.receive(now: now))
    }

    mutating func runUntilTerminal(
        now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        maxReceives: Int? = nil
    ) async throws -> [RemoteControlAppServerWebSocketSessionStep] {
        var steps: [RemoteControlAppServerWebSocketSessionStep] = []
        var receiveCount = 0
        while maxReceives.map({ receiveCount < $0 }) ?? true {
            let step = try await receive(now: now())
            steps.append(step)
            receiveCount += 1
            if step.terminalEnd != nil {
                break
            }
        }
        return steps
    }

    mutating func process(
        _ input: RemoteControlAppServerWebSocketSessionInput
    ) async throws -> RemoteControlAppServerWebSocketSessionStep {
        let connectionStep: RemoteControlWebsocketConnectionStep
        switch input {
        case let .receive(now):
            connectionStep = try await runner.receive(
                state: &state,
                clientTracker: &clientTracker,
                now: now
            )
        case let .connection(input):
            connectionStep = try await runner.process(
                input,
                state: &state,
                clientTracker: &clientTracker
            )
        }

        let appServerStep = await appServerLoop.handleClientTrackerEffects(connectionStep.trackerEffects)
        let writerSteps = try await writeServerEvents(appServerStep.serverEvents)
        return RemoteControlAppServerWebSocketSessionStep(
            connectionStep: connectionStep,
            appServerStep: appServerStep,
            writerSteps: writerSteps
        )
    }

    mutating func drainPendingNotifications() async throws -> RemoteControlAppServerWebSocketSessionStep {
        let appServerStep = await appServerLoop.drainPendingNotifications()
        let writerSteps = try await writeServerEvents(appServerStep.serverEvents)
        return RemoteControlAppServerWebSocketSessionStep(
            appServerStep: appServerStep,
            writerSteps: writerSteps
        )
    }

    private mutating func writeServerEvents(
        _ serverEvents: [RemoteControlQueuedServerEnvelope]
    ) async throws -> [RemoteControlWebsocketConnectionStep] {
        var writerSteps: [RemoteControlWebsocketConnectionStep] = []
        for serverEvent in serverEvents {
            let writerStep = try await runner.process(
                .queuedServerEvent(serverEvent),
                state: &state,
                clientTracker: &clientTracker
            )
            writerSteps.append(writerStep)
            if writerStep.end != nil {
                break
            }
        }
        return writerSteps
    }
}

enum RemoteControlAppServerWebSocketSessionInput: Equatable, Sendable {
    case receive(now: TimeInterval)
    case connection(RemoteControlWebsocketConnectionInput)
}

struct RemoteControlAppServerExecutableConnection<Transport: RemoteControlWebSocketTransport>: Sendable {
    var transport: Transport
    var environmentID: String?

    init(
        transport: Transport,
        environmentID: String?
    ) {
        self.transport = transport
        self.environmentID = environmentID
    }
}

struct RemoteControlAppServerExecutableRuntimeStep: Equatable, Sendable {
    var runtimeStep: RemoteControlRuntimeStep
    var sessionSteps: [RemoteControlAppServerWebSocketSessionStep]
    var terminalEnd: RemoteControlWebsocketConnectionEnd?

    init(
        runtimeStep: RemoteControlRuntimeStep,
        sessionSteps: [RemoteControlAppServerWebSocketSessionStep] = [],
        terminalEnd: RemoteControlWebsocketConnectionEnd? = nil
    ) {
        self.runtimeStep = runtimeStep
        self.sessionSteps = sessionSteps
        self.terminalEnd = terminalEnd
    }
}

struct RemoteControlAppServerExecutableRuntime<Transport: RemoteControlWebSocketTransport>: Sendable {
    typealias Connect = @Sendable (
        RemoteControlTarget,
        String?
    ) async throws -> RemoteControlAppServerExecutableConnection<Transport>
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private var runtime: RemoteControlRuntimeCore
    private let configuration: CodexAppServerConfiguration
    private let connect: Connect

    init(
        runtime: RemoteControlRuntimeCore,
        configuration: CodexAppServerConfiguration,
        connect: @escaping Connect
    ) {
        self.runtime = runtime
        self.configuration = configuration
        self.connect = connect
    }

    mutating func start(
        appServerClientNameRequired: Bool = false,
        now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        maxReceives: Int? = nil
    ) async throws -> [RemoteControlAppServerExecutableRuntimeStep] {
        try await process(
            runtime.start(appServerClientNameRequired: appServerClientNameRequired),
            now: now,
            maxReceives: maxReceives
        )
    }

    mutating func run(
        appServerClientNameRequired: Bool = false,
        now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        maxReceives: Int? = nil,
        sleep: @escaping Sleep = Self.sleep
    ) async throws {
        var step = runtime.start(appServerClientNameRequired: appServerClientNameRequired)
        while true {
            let steps = try await process(step, now: now, maxReceives: maxReceives)
            guard let action = steps.last?.runtimeStep.action else {
                return
            }
            switch action {
            case .connected:
                return
            case .reconnect:
                step = runtime.reconnect()
            case .retryAfterAccountID:
                try await sleep(RemoteControlConnectLoopCore.accountIDRetryIntervalSeconds)
                step = runtime.reconnect()
            case let .retryAfterBackoff(delay):
                try await sleep(Self.backoffSeconds(for: delay))
                step = runtime.reconnect()
            case .waitForDisableAfterInvalidURL:
                return
            case .waitForAppServerClientName, .waitUntilEnabled, .shutdownTracker:
                return
            case .connect:
                step = RemoteControlRuntimeStep(action: action)
            }
        }
    }

    private mutating func process(
        _ runtimeStep: RemoteControlRuntimeStep,
        now: @Sendable () -> TimeInterval,
        maxReceives: Int?
    ) async throws -> [RemoteControlAppServerExecutableRuntimeStep] {
        var steps = [RemoteControlAppServerExecutableRuntimeStep(runtimeStep: runtimeStep)]
        await publishStatusUpdates(runtimeStep.statusUpdates)
        guard case let .connect(target, appServerClientName) = runtimeStep.action else {
            return steps
        }

        let connection: RemoteControlAppServerExecutableConnection<Transport>
        do {
            connection = try await connect(target, appServerClientName)
        } catch {
            let failureStep = runtime.connectionFailed(Self.connectionFailure(for: error))
            await publishStatusUpdates(failureStep.statusUpdates)
            steps.append(RemoteControlAppServerExecutableRuntimeStep(runtimeStep: failureStep))
            return steps
        }
        let connectedStep = runtime.connectionEstablished(environmentID: connection.environmentID)
        await publishStatusUpdates(connectedStep.statusUpdates)
        steps.append(RemoteControlAppServerExecutableRuntimeStep(runtimeStep: connectedStep))

        var session = RemoteControlAppServerWebSocketSession(
            transport: connection.transport,
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: runtime.statusSnapshot),
            configuration: configuration.withRemoteControlStatus(runtime.statusSnapshot)
        )
        let sessionSteps = try await session.runUntilTerminal(now: now, maxReceives: maxReceives)
        guard let terminalEnd = sessionSteps.last?.terminalEnd else {
            return steps + [
                RemoteControlAppServerExecutableRuntimeStep(
                    runtimeStep: RemoteControlRuntimeStep(action: .connected),
                    sessionSteps: sessionSteps
                ),
            ]
        }

        let terminalStep = runtime.connectionEnded(Self.sessionEnd(for: terminalEnd))
        await publishStatusUpdates(terminalStep.statusUpdates)
        steps.append(RemoteControlAppServerExecutableRuntimeStep(
            runtimeStep: terminalStep,
            sessionSteps: sessionSteps,
            terminalEnd: terminalEnd
        ))
        return steps
    }

    private func publishStatusUpdates(_ updates: [CodexCore.RemoteControlStatusSnapshot]) async {
        guard let broadcaster = configuration.remoteControlStatusBroadcaster else {
            return
        }
        for update in updates {
            await broadcaster.publish(CodexAppServerConfiguration.RemoteControlStatusSnapshot(update))
        }
    }

    private static func connectionFailure(for error: Error) -> RemoteControlConnectLoopFailure {
        if case RemoteControlAuthLoadError.waitingForChatGPTAccountID = error {
            return .waitingForAccountID
        }
        return .failed(String(describing: error))
    }

    private static func backoffSeconds(for delay: RemoteControlReconnectDelay) -> TimeInterval {
        TimeInterval(delay.baseMilliseconds) / 1_000
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func sessionEnd(
        for websocketEnd: RemoteControlWebsocketConnectionEnd
    ) -> RemoteControlSessionConnectionEnd {
        switch websocketEnd {
        case .disabled:
            return .disabled
        case .shutdown:
            return .shutdown
        case .reconnect:
            return .workerEnded
        }
    }
}

private actor RemoteControlURLSessionWebSocketBox {
    private var transport: RemoteControlURLSessionWebSocket?

    func store(_ transport: RemoteControlURLSessionWebSocket) {
        self.transport = transport
    }

    func take() -> RemoteControlURLSessionWebSocket? {
        let current = transport
        transport = nil
        return current
    }
}

public extension CodexAppServer {
    static func runRemoteControlExecutable(
        configuration: CodexAppServerConfiguration,
        startState: RemoteControlStartState,
        codexHome: URL,
        authCredentialsStoreMode: AuthCredentialsStoreMode,
        stateStore: SQLiteAgentGraphStore
    ) async throws {
        var runtime = RemoteControlAppServerExecutableRuntime(
            runtime: try RemoteControlRuntimeCore(
                remoteControlURL: startState.remoteControlURL,
                installationID: startState.statusSnapshot.installationID,
                requestedEnabled: startState.requestedEnabled,
                stateDatabaseAvailable: startState.stateDatabaseAvailable
            ),
            configuration: configuration,
            connect: { target, appServerClientName in
                try await Self.remoteControlExecutableConnection(
                    target: target,
                    appServerClientName: appServerClientName,
                    startState: startState,
                    codexHome: codexHome,
                    authCredentialsStoreMode: authCredentialsStoreMode,
                    stateStore: stateStore,
                    appServerVersion: configuration.version
                )
            }
        )
        try await runtime.run()
    }

    private static func remoteControlExecutableConnection(
        target: RemoteControlTarget,
        appServerClientName: String?,
        startState: RemoteControlStartState,
        codexHome: URL,
        authCredentialsStoreMode: AuthCredentialsStoreMode,
        stateStore: SQLiteAgentGraphStore,
        appServerVersion: String
    ) async throws -> RemoteControlAppServerExecutableConnection<RemoteControlURLSessionWebSocket> {
        let authLoader = RemoteControlAuthLoader(
            loadAuth: {
                try CodexAuthStorage.loadEffectiveAuthDotJSON(
                    codexHome: codexHome,
                    mode: authCredentialsStoreMode
                )
            },
            reloadAuth: {
                _ = try await CodexAuthStorage.loadFreshTokenData(
                    codexHome: codexHome,
                    mode: authCredentialsStoreMode
                )
            }
        )
        let auth = try await authLoader.load()
        let enrollmentClient = RemoteControlEnrollmentClient(
            auth: auth,
            installationID: startState.statusSnapshot.installationID,
            appServerVersion: appServerVersion
        )
        let socketBox = RemoteControlURLSessionWebSocketBox()
        let connector = RemoteControlWebSocketConnector(
            auth: auth,
            installationID: startState.statusSnapshot.installationID,
            appServerClientName: appServerClientName,
            enroll: enrollmentClient.enroll,
            connect: { request, _ in
                await socketBox.store(RemoteControlURLSessionWebSocket(request: request))
            }
        )
        let result = try await connector.connect(
            target: target,
            store: stateStore,
            currentEnrollment: nil,
            subscribeCursor: nil,
            statusPublisher: startState.statusPublisher
        )
        let transport = await socketBox.take() ?? RemoteControlURLSessionWebSocket(request: result.request)
        return RemoteControlAppServerExecutableConnection(
            transport: transport,
            environmentID: result.updatedEnrollment?.environmentID ?? result.enrollment.environmentID
        )
    }
}

private extension CodexAppServerConfiguration {
    func withRemoteControlStatus(
        _ snapshot: CodexCore.RemoteControlStatusSnapshot
    ) -> CodexAppServerConfiguration {
        CodexAppServerConfiguration(
            codexHome: codexHome,
            cwd: cwd,
            defaultModelProvider: defaultModelProvider,
            originator: originator,
            version: version,
            requiresOpenAIAuth: requiresOpenAIAuth,
            authCredentialsStoreMode: authCredentialsStoreMode,
            sessionSource: sessionSource,
            environment: environment,
            activeProfile: activeProfile,
            feedback: feedback,
            feedbackUploadTransport: feedbackUploadTransport,
            acceptedLineAnalyticsUploader: acceptedLineAnalyticsUploader,
            accountRateLimitsFetcher: accountRateLimitsFetcher,
            addCreditsNudgeEmailSender: addCreditsNudgeEmailSender,
            authRefreshTransport: authRefreshTransport,
            authLoginTransport: authLoginTransport,
            authDeviceCodeTransport: authDeviceCodeTransport,
            mcpHTTPTransport: mcpHTTPTransport,
            pluginHTTPTransport: pluginHTTPTransport,
            accessibleConnectorProvider: accessibleConnectorProvider,
            mcpOAuthLoginStarter: mcpOAuthLoginStarter,
            cliConfigOverrides: cliConfigOverrides,
            threadConfigSources: threadConfigSources,
            configLayerOverrides: configLayerOverrides,
            stateStore: stateStore,
            configWarnings: configWarnings,
            remoteControlStatusSnapshot: CodexAppServerConfiguration.RemoteControlStatusSnapshot(snapshot),
            remoteControlStatusBroadcaster: remoteControlStatusBroadcaster,
            pluginStartupTasksEnabled: pluginStartupTasksEnabled,
            curatedPluginStartupSyncEnabled: curatedPluginStartupSyncEnabled
        )
    }
}

struct RemoteControlAppServerBridge {
    private let configuration: CodexAppServerConfiguration
    private let threadStateManager: AppServerThreadStateManager
    private let notificationBuffer = RemoteControlAppServerBridgeNotificationBuffer()
    private var processors: [RemoteControlVirtualConnectionID: CodexAppServerMessageProcessor] = [:]
    private var runtimeManagers: [RemoteControlVirtualConnectionID: AppServerLiveRuntimeManager] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.configuration = configuration
        self.threadStateManager = threadStateManager
    }

    mutating func handle(_ events: [RemoteControlVirtualTransportEvent]) async -> RemoteControlAppServerBridgeStep {
        var combined = RemoteControlAppServerBridgeStep()
        for event in events {
            combined.append(await handle(event))
        }
        return combined
    }

    mutating func handle(_ event: RemoteControlVirtualTransportEvent) async -> RemoteControlAppServerBridgeStep {
        switch event {
        case let .connectionOpened(connectionID, _, _):
            processors.removeValue(forKey: connectionID)?.closeConnection()
            runtimeManagers.removeValue(forKey: connectionID)?.shutdown()
            let runtimeManager = AppServerLiveRuntimeManager(configuration: configuration)
            let processor = CodexAppServerMessageProcessor(
                configuration: configuration,
                connectionID: Self.appServerConnectionID(for: connectionID),
                notificationSink: { [notificationBuffer] data in
                    await notificationBuffer.append(data, connectionID: connectionID)
                },
                coreOpSubmitter: { requestID, threadID, op in
                    try runtimeManager.submitCoreOp(requestID: requestID, threadID: threadID, op: op)
                },
                liveRuntimeSubmitter: runtimeManager.submitLiveRuntime,
                threadStateManager: threadStateManager
            )
            runtimeManager.setEventSink { [weak processor] threadID, turnID, event in
                await processor?.handleRuntimeEvent(threadID: threadID, turnID: turnID, event: event)
            }
            processors[connectionID] = processor
            runtimeManagers[connectionID] = runtimeManager
            return RemoteControlAppServerBridgeStep()

        case let .incomingMessage(connectionID, message):
            guard let processor = processors[connectionID] else {
                return RemoteControlAppServerBridgeStep(droppedUnknownConnectionIDs: [connectionID])
            }
            guard let line = try? encoder.encode(message) else {
                return RemoteControlAppServerBridgeStep()
            }
            return RemoteControlAppServerBridgeStep(
                outgoingMessages: Self.decodeOutgoingMessages(
                    processor.processLine(line),
                    connectionID: connectionID,
                    decoder: decoder
                )
            )

        case let .connectionClosed(connectionID):
            processors.removeValue(forKey: connectionID)?.closeConnection()
            runtimeManagers.removeValue(forKey: connectionID)?.shutdown()
            return RemoteControlAppServerBridgeStep()
        }
    }

    func drainPendingNotifications() async -> RemoteControlAppServerBridgeStep {
        let payloads = await notificationBuffer.drain()
        return RemoteControlAppServerBridgeStep(
            outgoingMessages: payloads.flatMap { connectionID, data in
                Self.decodeOutgoingMessages(data, connectionID: connectionID, decoder: decoder)
            }
        )
    }

    private static func appServerConnectionID(
        for connectionID: RemoteControlVirtualConnectionID
    ) -> AppServerConnectionID {
        let boundedValue = min(connectionID.rawValue, UInt64(Int64.max))
        return AppServerConnectionID(boundedValue)
    }

    private static func decodeOutgoingMessages(
        _ data: Data?,
        connectionID: RemoteControlVirtualConnectionID,
        decoder: JSONDecoder
    ) -> [RemoteControlAppServerBridgeOutgoingMessage] {
        guard let data, !data.isEmpty else {
            return []
        }
        let payload = String(decoding: data, as: UTF8.self)
        return payload.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let message = try? decoder.decode(
                ExecServerJSONRPCMessage.self,
                from: Data(line.utf8)
            ) else {
                return nil
            }
            return RemoteControlAppServerBridgeOutgoingMessage(connectionID: connectionID, message: message)
        }
    }
}

private actor RemoteControlAppServerBridgeNotificationBuffer {
    private var payloads: [(RemoteControlVirtualConnectionID, Data)] = []

    func append(_ data: Data, connectionID: RemoteControlVirtualConnectionID) {
        payloads.append((connectionID, data))
    }

    func drain() -> [(RemoteControlVirtualConnectionID, Data)] {
        let drained = payloads
        payloads.removeAll()
        return drained
    }
}
