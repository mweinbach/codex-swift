import Foundation

public enum ToolSearchError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidArguments(String)
    case emptyQuery
    case invalidLimit

    public var description: String {
        switch self {
        case let .invalidArguments(message):
            return "failed to parse tool_search arguments: \(message)"
        case .emptyQuery:
            return "query must not be empty"
        case .invalidLimit:
            return "limit must be greater than zero"
        }
    }
}

public struct ToolSearchSourceInfo: Equatable, Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

public struct ToolSearchEntry: Equatable, Sendable {
    public let searchText: String
    public let output: ToolSpec
    public let limitBucket: String?

    public init(searchText: String, output: ToolSpec, limitBucket: String? = nil) {
        self.searchText = searchText
        self.output = output
        self.limitBucket = limitBucket
    }
}

public struct ToolSearchIndex: Equatable, Sendable {
    public static let defaultLimit = 8
    private static let computerUseServerName = "computer-use"
    private static let computerUseDefaultLimit = 20

    public let entries: [ToolSearchEntry]
    public let sourceInfos: [ToolSearchSourceInfo]

    public init(entries: [ToolSearchEntry], sourceInfos: [ToolSearchSourceInfo] = []) {
        self.entries = entries
        self.sourceInfos = sourceInfos
    }

    public static func mcpIndex(from tools: [String: McpTool]) -> ToolSearchIndex {
        ToolSearchIndex(
            entries: mcpEntries(from: tools),
            sourceInfos: mcpSourceInfos(from: tools)
        )
    }

    public static func mcpEntries(from tools: [String: McpTool]) -> [ToolSearchEntry] {
        tools.keys.sorted().compactMap { qualifiedName in
            guard let tool = tools[qualifiedName],
                  let split = McpToolName.splitQualifiedToolName(qualifiedName)
            else {
                return nil
            }
            let namespace = "\(McpToolName.prefix)\(McpToolName.delimiter)\(split.serverName)\(McpToolName.delimiter)"
            let output = ToolSpec.namespace(ResponsesAPINamespace(
                name: namespace,
                description: ToolSpecFactory.defaultNamespaceDescription(namespace),
                tools: [
                    .function(ToolSpecFactory.createMCPResponsesAPITool(
                        name: split.toolName,
                        tool: tool,
                        deferLoading: true
                    ))
                ]
            ))
            return ToolSearchEntry(
                searchText: buildMCPSearchText(
                    qualifiedName: qualifiedName,
                    serverName: split.serverName,
                    callableName: split.toolName,
                    tool: tool
                ),
                output: output,
                limitBucket: split.serverName
            )
        }
    }

    public static func mcpSourceInfos(from tools: [String: McpTool]) -> [ToolSearchSourceInfo] {
        let names = Set(tools.keys.compactMap { qualifiedName in
            McpToolName.splitQualifiedToolName(qualifiedName)?.serverName
        })
        return names.sorted().map { ToolSearchSourceInfo(name: $0) }
    }

    public func toolSpec(defaultLimit: Int = ToolSearchIndex.defaultLimit) -> ToolSpec {
        .toolSearch(
            execution: "client",
            description: toolDescription(defaultLimit: defaultLimit),
            parameters: .object(
                properties: [
                    "limit": .number(description: "Maximum number of tools to return (defaults to \(defaultLimit))."),
                    "query": .string(description: "Search query for deferred tools.")
                ],
                required: ["query"],
                additionalProperties: .boolean(false)
            )
        )
    }

    public func search(arguments: JSONValue) throws -> [JSONValue] {
        let arguments = try SearchToolCallParams.decodeToolSearchArguments(from: arguments)
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolSearchError.emptyQuery
        }
        let requestedLimit = arguments.limit
        let limit = requestedLimit ?? Self.defaultLimit
        guard limit > 0 else {
            throw ToolSearchError.invalidLimit
        }
        guard !entries.isEmpty else {
            return []
        }

        let useDefaultLimit = requestedLimit == nil
        let resultEntries = searchResultEntries(query: query, limit: limit, useDefaultLimit: useDefaultLimit)
        return Self.coalesce(resultEntries.map(\.output)).map(Self.jsonValue)
    }

    private func toolDescription(defaultLimit: Int) -> String {
        let sourceDescriptions: String
        if sourceInfos.isEmpty {
            sourceDescriptions = "None currently enabled."
        } else {
            var names = Set<String>()
            var descriptions: [String: String] = [:]
            for source in sourceInfos {
                let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                names.insert(name)
                if descriptions[name] == nil,
                   let description = source.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty
                {
                    descriptions[name] = description
                }
            }
            sourceDescriptions = names.sorted().map { name in
                if let description = descriptions[name] {
                    return "- \(name): \(description)"
                }
                return "- \(name)"
            }.joined(separator: "\n")
        }

        return """
        # Tool discovery

        Searches over deferred tool metadata with BM25 and exposes matching tools for the next model call.

        You have access to tools from the following sources:
        \(sourceDescriptions)
        Some of the tools may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools. For MCP tool discovery, always use `tool_search` instead of `list_mcp_resources` or `list_mcp_resource_templates`.
        """
    }

    private func searchResultEntries(
        query: String,
        limit: Int,
        useDefaultLimit: Bool
    ) -> [ToolSearchEntry] {
        var results = rankedEntries(query: query, limit: limit)
        guard useDefaultLimit else {
            return results
        }

        if results.contains(where: { $0.limitBucket == Self.computerUseServerName }) {
            results = rankedEntries(query: query, limit: Self.computerUseDefaultLimit)
        }
        return limitResultsByBucket(results)
    }

    private func rankedEntries(query: String, limit: Int) -> [ToolSearchEntry] {
        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty else {
            return []
        }

        let documents = entries.map { Document(entry: $0, tokens: Self.tokenize($0.searchText)) }
        let nonEmptyDocuments = documents.filter { !$0.tokens.isEmpty }
        guard !nonEmptyDocuments.isEmpty else {
            return []
        }

        let documentCount = Double(nonEmptyDocuments.count)
        let averageDocumentLength = nonEmptyDocuments
            .map { Double($0.tokens.count) }
            .reduce(0, +) / documentCount
        let documentFrequency = Dictionary(
            grouping: nonEmptyDocuments.flatMap { Set($0.tokens) },
            by: { $0 }
        ).mapValues(\.count)

        return nonEmptyDocuments.enumerated().compactMap { index, document in
            let score = Self.bm25Score(
                queryTerms: queryTerms,
                document: document,
                documentFrequency: documentFrequency,
                documentCount: documentCount,
                averageDocumentLength: averageDocumentLength
            )
            return score > 0 ? (index: index, score: score, entry: document.entry) : nil
        }
        .sorted {
            if $0.score == $1.score {
                return $0.index < $1.index
            }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map(\.entry)
    }

    private func limitResultsByBucket(_ results: [ToolSearchEntry]) -> [ToolSearchEntry] {
        var counts: [String: Int] = [:]
        return results.filter { result in
            guard let bucket = result.limitBucket else {
                return true
            }
            let limit = bucket == Self.computerUseServerName ? Self.computerUseDefaultLimit : Self.defaultLimit
            let count = counts[bucket, default: 0]
            guard count < limit else {
                return false
            }
            counts[bucket] = count + 1
            return true
        }
    }

    private static func coalesce(_ specs: [ToolSpec]) -> [ToolSpec] {
        var coalesced: [ToolSpec] = []
        for spec in specs {
            switch spec {
            case let .namespace(namespace):
                if let index = coalesced.firstIndex(where: { existing in
                    if case let .namespace(existingNamespace) = existing {
                        return existingNamespace.name == namespace.name
                    }
                    return false
                }),
                    case let .namespace(existingNamespace) = coalesced[index]
                {
                    coalesced[index] = .namespace(ResponsesAPINamespace(
                        name: existingNamespace.name,
                        description: existingNamespace.description,
                        tools: existingNamespace.tools + namespace.tools
                    ))
                } else {
                    coalesced.append(spec)
                }
            default:
                coalesced.append(spec)
            }
        }
        return coalesced
    }

    private static func bm25Score(
        queryTerms: [String],
        document: Document,
        documentFrequency: [String: Int],
        documentCount: Double,
        averageDocumentLength: Double
    ) -> Double {
        let k1 = 1.2
        let b = 0.75
        let termFrequency = Dictionary(grouping: document.tokens, by: { $0 }).mapValues(\.count)
        let documentLength = Double(document.tokens.count)

        return queryTerms.reduce(0) { total, term in
            guard let frequency = termFrequency[term],
                  let documentsWithTerm = documentFrequency[term]
            else {
                return total
            }
            let tf = Double(frequency)
            let df = Double(documentsWithTerm)
            let idf = log(1 + (documentCount - df + 0.5) / (df + 0.5))
            let denominator = tf + k1 * (1 - b + b * documentLength / max(averageDocumentLength, 1))
            return total + idf * (tf * (k1 + 1)) / denominator
        }
    }

    private static func tokenize(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current.lowercased())
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }

    private static func jsonValue(from tool: ToolSpec) -> JSONValue {
        do {
            let data = try JSONEncoder().encode(tool)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return .string("failed to serialize tool_search output: \(error)")
        }
    }

    private static func buildMCPSearchText(
        qualifiedName: String,
        serverName: String,
        callableName: String,
        tool: McpTool
    ) -> String {
        var parts = [
            qualifiedName,
            callableName,
            tool.name,
            serverName
        ]

        if let title = tool.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            parts.append(title)
        }
        if let description = tool.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            parts.append(description)
        }
        if case let .object(properties) = tool.inputSchema.properties {
            parts.append(contentsOf: properties.keys.sorted())
        }

        return parts.joined(separator: " ")
    }

    private struct Document {
        let entry: ToolSearchEntry
        let tokens: [String]
    }
}

private extension SearchToolCallParams {
    static func decodeToolSearchArguments(from value: JSONValue) throws -> SearchToolCallParams {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(SearchToolCallParams.self, from: data)
        } catch {
            throw ToolSearchError.invalidArguments(String(describing: error))
        }
    }
}
