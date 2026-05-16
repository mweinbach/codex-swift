import Foundation

public struct RenderedMcpToolApprovalTemplate: Equatable, Sendable {
    public let question: String
    public let elicitationMessage: String
    public let toolParams: JSONValue?
    public let toolParamsDisplay: [RenderedMcpToolApprovalParam]

    public init(
        question: String,
        elicitationMessage: String,
        toolParams: JSONValue?,
        toolParamsDisplay: [RenderedMcpToolApprovalParam]
    ) {
        self.question = question
        self.elicitationMessage = elicitationMessage
        self.toolParams = toolParams
        self.toolParamsDisplay = toolParamsDisplay
    }
}

public struct RenderedMcpToolApprovalParam: Equatable, Codable, Sendable {
    public let name: String
    public let value: JSONValue
    public let displayName: String

    public init(name: String, value: JSONValue, displayName: String) {
        self.name = name
        self.value = value
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case displayName = "display_name"
    }
}

public struct ConsequentialToolMessageTemplate: Codable, Equatable, Sendable {
    public let connectorID: String
    public let serverName: String
    public let toolTitle: String
    public let template: String
    public let templateParams: [ConsequentialToolTemplateParam]

    public init(
        connectorID: String,
        serverName: String,
        toolTitle: String,
        template: String,
        templateParams: [ConsequentialToolTemplateParam]
    ) {
        self.connectorID = connectorID
        self.serverName = serverName
        self.toolTitle = toolTitle
        self.template = template
        self.templateParams = templateParams
    }

    enum CodingKeys: String, CodingKey {
        case connectorID = "connector_id"
        case serverName = "server_name"
        case toolTitle = "tool_title"
        case template
        case templateParams = "template_params"
    }
}

public struct ConsequentialToolTemplateParam: Codable, Equatable, Sendable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }
}

public enum McpToolApprovalTemplates {
    public static let schemaVersion: UInt8 = 4
    public static let connectorNamePlaceholder = "{connector_name}"
    public static let bundledTemplates = loadBundledTemplates()

    public static func render(
        serverName: String,
        connectorID: String?,
        connectorName: String?,
        toolTitle: String?,
        toolParams: JSONValue?
    ) -> RenderedMcpToolApprovalTemplate? {
        guard let bundledTemplates else {
            return nil
        }

        return render(
            from: bundledTemplates,
            serverName: serverName,
            connectorID: connectorID,
            connectorName: connectorName,
            toolTitle: toolTitle,
            toolParams: toolParams
        )
    }

    public static func buildDisplayParams(
        from toolParams: JSONValue?
    ) -> [RenderedMcpToolApprovalParam]? {
        guard case let .object(params)? = toolParams else {
            return nil
        }

        return params
            .map { name, value in
                RenderedMcpToolApprovalParam(name: name, value: value, displayName: name)
            }
            .sorted { left, right in left.name < right.name }
    }

    public static func render(
        from templates: [ConsequentialToolMessageTemplate],
        serverName: String,
        connectorID: String?,
        connectorName: String?,
        toolTitle: String?,
        toolParams: JSONValue?
    ) -> RenderedMcpToolApprovalTemplate? {
        guard let connectorID else {
            return nil
        }
        guard let toolTitle = toolTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolTitle.isEmpty
        else {
            return nil
        }
        guard let template = templates.first(where: {
            $0.serverName == serverName
                && $0.connectorID == connectorID
                && $0.toolTitle == toolTitle
        }) else {
            return nil
        }
        guard let elicitationMessage = renderQuestionTemplate(
            template.template,
            connectorName: connectorName
        ) else {
            return nil
        }

        let renderedParams: (toolParams: JSONValue?, displayParams: [RenderedMcpToolApprovalParam])
        switch toolParams {
        case let .object(params):
            guard let rendered = renderToolParams(
                params,
                templateParams: template.templateParams
            ) else {
                return nil
            }
            renderedParams = rendered
        case .none:
            renderedParams = (nil, [])
        default:
            return nil
        }

        return RenderedMcpToolApprovalTemplate(
            question: elicitationMessage,
            elicitationMessage: elicitationMessage,
            toolParams: renderedParams.toolParams,
            toolParamsDisplay: renderedParams.displayParams
        )
    }

    private static func renderQuestionTemplate(
        _ template: String,
        connectorName: String?
    ) -> String? {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTemplate.isEmpty else {
            return nil
        }

        guard trimmedTemplate.contains(connectorNamePlaceholder) else {
            return trimmedTemplate
        }
        guard let connectorName = connectorName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !connectorName.isEmpty
        else {
            return nil
        }

        return trimmedTemplate.replacingOccurrences(
            of: connectorNamePlaceholder,
            with: connectorName
        )
    }

    private static func renderToolParams(
        _ toolParams: [String: JSONValue],
        templateParams: [ConsequentialToolTemplateParam]
    ) -> (toolParams: JSONValue?, displayParams: [RenderedMcpToolApprovalParam])? {
        var displayParams: [RenderedMcpToolApprovalParam] = []
        var displayNames = Set<String>()
        var handledNames = Set<String>()

        for templateParam in templateParams {
            let label = templateParam.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                return nil
            }
            guard let value = toolParams[templateParam.name] else {
                continue
            }
            guard displayNames.insert(label).inserted else {
                return nil
            }
            displayParams.append(RenderedMcpToolApprovalParam(
                name: templateParam.name,
                value: value,
                displayName: label
            ))
            handledNames.insert(templateParam.name)
        }

        let remainingParams = toolParams
            .filter { !handledNames.contains($0.key) }
            .sorted { left, right in left.key < right.key }

        for (name, value) in remainingParams {
            guard displayNames.insert(name).inserted else {
                return nil
            }
            displayParams.append(RenderedMcpToolApprovalParam(
                name: name,
                value: value,
                displayName: name
            ))
        }

        return (.object(toolParams), displayParams)
    }

    private static func loadBundledTemplates() -> [ConsequentialToolMessageTemplate]? {
        guard let url = Bundle.module.url(
            forResource: "consequential_tool_message_templates",
            withExtension: "json"
        ) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let templatesFile = try JSONDecoder().decode(
                ConsequentialToolMessageTemplatesFile.self,
                from: data
            )
            guard templatesFile.schemaVersion == schemaVersion else {
                return nil
            }
            return templatesFile.templates
        } catch {
            return nil
        }
    }
}

private struct ConsequentialToolMessageTemplatesFile: Decodable {
    let schemaVersion: UInt8
    let templates: [ConsequentialToolMessageTemplate]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case templates
    }
}
