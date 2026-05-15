public extension AskForApproval {
    var appServerExperimentalReason: String? {
        switch self {
        case .granular:
            return "askForApproval.granular"
        case .unlessTrusted, .onFailure, .onRequest, .never:
            return nil
        }
    }
}

public extension AppServerProtocol.ProfileV2 {
    var appServerExperimentalReason: String? {
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if approvalsReviewer != nil {
            return "config/read.approvalsReviewer"
        }
        return nil
    }
}

public extension AppServerProtocol.Config {
    var appServerExperimentalReason: String? {
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if approvalsReviewer != nil {
            return "config/read.approvalsReviewer"
        }
        for key in profiles.keys.sorted() {
            if let reason = profiles[key]?.appServerExperimentalReason {
                return reason
            }
        }
        if apps != nil {
            return "config/read.apps"
        }
        return nil
    }
}

public extension AppServerProtocol.ConfigReadResponse {
    var appServerExperimentalReason: String? {
        config.appServerExperimentalReason
    }
}

public extension AppServerProtocol.ConfigRequirements {
    var appServerExperimentalReason: String? {
        if let policies = allowedApprovalPolicies {
            for policy in policies {
                if let reason = policy.appServerExperimentalReason {
                    return reason
                }
            }
        }
        if allowedApprovalsReviewers != nil {
            return "configRequirements/read.allowedApprovalsReviewers"
        }
        if hooks != nil {
            return "configRequirements/read.hooks"
        }
        if network != nil {
            return "configRequirements/read.network"
        }
        return nil
    }
}

public extension ThreadStartParams {
    var appServerExperimentalReason: String? {
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if permissions != nil {
            return "thread/start.permissions"
        }
        if environments != nil {
            return "thread/start.environments"
        }
        if dynamicTools != nil {
            return "thread/start.dynamicTools"
        }
        if mockExperimentalField != nil {
            return "thread/start.mockExperimentalField"
        }
        if experimentalRawEvents {
            return "thread/start.experimentalRawEvents"
        }
        if persistExtendedHistory {
            return "thread/start.persistFullHistory"
        }
        return nil
    }
}

public extension ThreadResumeParams {
    var appServerExperimentalReason: String? {
        if history != nil {
            return "thread/resume.history"
        }
        if path != nil {
            return "thread/resume.path"
        }
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if permissions != nil {
            return "thread/resume.permissions"
        }
        if excludeTurns {
            return "thread/resume.excludeTurns"
        }
        if persistExtendedHistory {
            return "thread/resume.persistFullHistory"
        }
        return nil
    }
}

public extension ThreadForkParams {
    var appServerExperimentalReason: String? {
        if path != nil {
            return "thread/fork.path"
        }
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if permissions != nil {
            return "thread/fork.permissions"
        }
        if excludeTurns {
            return "thread/fork.excludeTurns"
        }
        if persistExtendedHistory {
            return "thread/fork.persistFullHistory"
        }
        return nil
    }
}

public extension AppServerTurnStartParams {
    var appServerExperimentalReason: String? {
        if responsesapiClientMetadata != nil {
            return "turn/start.responsesapiClientMetadata"
        }
        if environments != nil {
            return "turn/start.environments"
        }
        if let reason = approvalPolicy?.appServerExperimentalReason {
            return reason
        }
        if permissions != nil {
            return "turn/start.permissions"
        }
        if collaborationMode != nil {
            return "turn/start.collaborationMode"
        }
        return nil
    }
}

public extension AppServerTurnSteerParams {
    var appServerExperimentalReason: String? {
        if responsesapiClientMetadata != nil {
            return "turn/steer.responsesapiClientMetadata"
        }
        return nil
    }
}
