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
