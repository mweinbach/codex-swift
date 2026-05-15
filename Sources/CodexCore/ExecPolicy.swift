import Foundation

public enum ExecPolicyDecision: String, Codable, Comparable, Sendable {
    case allow
    case prompt
    case forbidden

    public static func < (lhs: ExecPolicyDecision, rhs: ExecPolicyDecision) -> Bool {
        lhs.severity < rhs.severity
    }

    public static func parse(_ raw: String) throws -> ExecPolicyDecision {
        guard let decision = ExecPolicyDecision(rawValue: raw) else {
            throw ExecPolicyError.invalidDecision(raw)
        }
        return decision
    }

    private var severity: Int {
        switch self {
        case .allow:
            return 0
        case .prompt:
            return 1
        case .forbidden:
            return 2
        }
    }
}

public enum ExecPolicyError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidDecision(String)
    case invalidPattern(String)
    case invalidExample(String)
    case invalidRule(String)
    case exampleDidNotMatch(rules: [String], examples: [String])
    case exampleDidMatch(rule: String, example: String)
    case invalidSyntax(String)

    public var description: String {
        switch self {
        case let .invalidDecision(decision):
            return "invalid decision: \(decision)"
        case let .invalidPattern(message):
            return "invalid pattern: \(message)"
        case let .invalidExample(message):
            return "invalid example: \(message)"
        case let .invalidRule(message):
            return "invalid rule: \(message)"
        case let .exampleDidNotMatch(rules, examples):
            return "examples did not match rules \(rules): \(examples)"
        case let .exampleDidMatch(rule, example):
            return "example matched rule \(rule): \(example)"
        case let .invalidSyntax(message):
            return "invalid policy syntax: \(message)"
        }
    }
}

public enum ExecPolicyAmendError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyPrefix
    case invalidNetworkRule(String)
    case missingParent(path: String)
    case createPolicyDirectory(dir: String, message: String)
    case serializePrefix(message: String)
    case serializeNetworkRule(message: String)
    case readPolicyFile(path: String, message: String)
    case writePolicyFile(path: String, message: String)

    public var description: String {
        switch self {
        case .emptyPrefix:
            return "prefix rule requires at least one token"
        case let .invalidNetworkRule(message):
            return "invalid network rule: \(message)"
        case let .missingParent(path):
            return "policy path has no parent: \(path)"
        case let .createPolicyDirectory(dir, message):
            return "failed to create policy directory \(dir): \(message)"
        case let .serializePrefix(message):
            return "failed to format prefix tokens: \(message)"
        case let .serializeNetworkRule(message):
            return "failed to serialize network rule field: \(message)"
        case let .readPolicyFile(path, message):
            return "failed to read policy file \(path): \(message)"
        case let .writePolicyFile(path, message):
            return "failed to write to policy file \(path): \(message)"
        }
    }
}

public enum ExecPolicyLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case readDirectory(dir: String, message: String)
    case readFile(path: String, message: String)
    case parsePolicy(path: String, message: String)

    public var description: String {
        switch self {
        case let .readDirectory(dir, message):
            return "failed to read execpolicy files from \(dir): \(message)"
        case let .readFile(path, message):
            return "failed to read execpolicy file \(path): \(message)"
        case let .parsePolicy(path, message):
            return "failed to parse execpolicy file \(path): \(message)"
        }
    }
}

public func formatExecPolicyErrorWithSource(_ error: ExecPolicyLoadError) -> String {
    guard case let .parsePolicy(path, renderedSource) = error else {
        return error.description
    }

    let message = execPolicyMessageForDisplay(renderedSource)
    guard let (locationPath, line) = parseStarlarkLine(from: renderedSource) else {
        return "\(path): \(message)"
    }
    return "\(locationPath):\(line): \(message) (problem is on or around line \(line))"
}

private func execPolicyMessageForDisplay(_ renderedSource: String) -> String {
    for line in renderedSource.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("error: ") {
            return String(line)
        }
    }

    if let firstLine = renderedSource.split(separator: "\n", omittingEmptySubsequences: false).first,
       let range = firstLine.range(of: ": starlark error: ", options: .backwards) {
        return String(firstLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return renderedSource
        .split(separator: "\n", omittingEmptySubsequences: false)
        .first
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        ?? ""
}

private func parseStarlarkLine(from message: String) -> (path: String, line: Int)? {
    guard let firstLine = message.split(separator: "\n", omittingEmptySubsequences: false).first else {
        return nil
    }
    let trimmed = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = trimmed.range(of: ": starlark error:", options: .backwards) else {
        return nil
    }

    let pathAndPosition = String(trimmed[..<range.lowerBound])
    let parts = pathAndPosition.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 3,
          let line = Int(parts[parts.count - 2]),
          Int(parts[parts.count - 1]) != nil,
          line != 0
    else {
        return nil
    }

    let path = parts.dropLast(2).joined(separator: ":")
    return (path, line)
}

public enum PatternToken: Equatable, Sendable {
    case single(String)
    case alts([String])

    public func matches(_ token: String) -> Bool {
        switch self {
        case let .single(expected):
            return expected == token
        case let .alts(alternatives):
            return alternatives.contains(token)
        }
    }

    public var alternatives: [String] {
        switch self {
        case let .single(expected):
            return [expected]
        case let .alts(alternatives):
            return alternatives
        }
    }
}

public struct PrefixPattern: Equatable, Sendable {
    public let first: String
    public let rest: [PatternToken]

    public init(first: String, rest: [PatternToken]) {
        self.first = first
        self.rest = rest
    }

    public func matchesPrefix(_ command: [String]) -> [String]? {
        let patternLength = rest.count + 1
        guard command.count >= patternLength, command.first == first else {
            return nil
        }

        for (patternToken, commandToken) in zip(rest, command.dropFirst().prefix(rest.count)) {
            guard patternToken.matches(commandToken) else {
                return nil
            }
        }

        return Array(command.prefix(patternLength))
    }
}

public struct PrefixRule: Equatable, Sendable, CustomStringConvertible {
    public let pattern: PrefixPattern
    public let decision: ExecPolicyDecision
    public let justification: String?

    public init(pattern: PrefixPattern, decision: ExecPolicyDecision, justification: String? = nil) {
        self.pattern = pattern
        self.decision = decision
        self.justification = justification
    }

    public var program: String {
        pattern.first
    }

    public func matches(_ command: [String]) -> RuleMatch? {
        pattern.matchesPrefix(command).map {
            .prefixRuleMatch(
                matchedPrefix: $0,
                decision: decision,
                resolvedProgram: nil,
                justification: justification
            )
        }
    }

    public var description: String {
        if let justification {
            return "PrefixRule(pattern: \(pattern), decision: \(decision.rawValue), justification: \(justification))"
        }
        return "PrefixRule(pattern: \(pattern), decision: \(decision.rawValue))"
    }
}

public enum NetworkRuleProtocol: String, Equatable, Sendable {
    case http
    case https
    case socks5Tcp = "socks5_tcp"
    case socks5Udp = "socks5_udp"

    public static func parse(_ raw: String) throws -> NetworkRuleProtocol {
        switch raw {
        case "http":
            return .http
        case "https", "https_connect", "http-connect":
            return .https
        case "socks5_tcp":
            return .socks5Tcp
        case "socks5_udp":
            return .socks5Udp
        default:
            throw ExecPolicyError.invalidRule(
                "network_rule protocol must be one of http, https, socks5_tcp, socks5_udp (got \(raw))"
            )
        }
    }

    fileprivate var policyString: String {
        switch self {
        case .http:
            return "http"
        case .https:
            return "https"
        case .socks5Tcp:
            return "socks5_tcp"
        case .socks5Udp:
            return "socks5_udp"
        }
    }
}

public struct NetworkRule: Equatable, Sendable {
    public let host: String
    public let `protocol`: NetworkRuleProtocol
    public let decision: ExecPolicyDecision
    public let justification: String?

    public init(
        host: String,
        protocol: NetworkRuleProtocol,
        decision: ExecPolicyDecision,
        justification: String? = nil
    ) {
        self.host = host
        self.protocol = `protocol`
        self.decision = decision
        self.justification = justification
    }
}

public enum RuleMatch: Equatable, Sendable, Encodable {
    case prefixRuleMatch(
        matchedPrefix: [String],
        decision: ExecPolicyDecision,
        resolvedProgram: String? = nil,
        justification: String? = nil
    )
    case heuristicsRuleMatch(command: [String], decision: ExecPolicyDecision)

    public var decision: ExecPolicyDecision {
        switch self {
        case let .prefixRuleMatch(_, decision, _, _), let .heuristicsRuleMatch(_, decision):
            return decision
        }
    }

    public var isPolicyMatch: Bool {
        switch self {
        case .prefixRuleMatch:
            return true
        case .heuristicsRuleMatch:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case prefixRuleMatch
        case heuristicsRuleMatch
    }

    private enum PrefixRuleMatchCodingKeys: String, CodingKey {
        case matchedPrefix
        case decision
        case resolvedProgram
        case justification
    }

    private enum HeuristicsRuleMatchCodingKeys: String, CodingKey {
        case command
        case decision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .prefixRuleMatch(matchedPrefix, decision, resolvedProgram, justification):
            var nested = container.nestedContainer(
                keyedBy: PrefixRuleMatchCodingKeys.self,
                forKey: .prefixRuleMatch
            )
            try nested.encode(matchedPrefix, forKey: .matchedPrefix)
            try nested.encode(decision, forKey: .decision)
            try nested.encodeIfPresent(resolvedProgram, forKey: .resolvedProgram)
            try nested.encodeIfPresent(justification, forKey: .justification)
        case let .heuristicsRuleMatch(command, decision):
            var nested = container.nestedContainer(
                keyedBy: HeuristicsRuleMatchCodingKeys.self,
                forKey: .heuristicsRuleMatch
            )
            try nested.encode(command, forKey: .command)
            try nested.encode(decision, forKey: .decision)
        }
    }
}

public struct PolicyEvaluation: Equatable, Sendable {
    public let decision: ExecPolicyDecision
    public let matchedRules: [RuleMatch]

    public init(decision: ExecPolicyDecision, matchedRules: [RuleMatch]) {
        self.decision = decision
        self.matchedRules = matchedRules
    }

    public var isMatch: Bool {
        matchedRules.contains(where: \.isPolicyMatch)
    }

    public static func fromMatches(_ matchedRules: [RuleMatch]) -> PolicyEvaluation {
        PolicyEvaluation(
            decision: matchedRules.map(\.decision).max() ?? .allow,
            matchedRules: matchedRules
        )
    }
}

public struct ExecPolicyMatchOptions: Equatable, Sendable {
    public var resolveHostExecutables: Bool

    public init(resolveHostExecutables: Bool = false) {
        self.resolveHostExecutables = resolveHostExecutables
    }
}

public struct ExecPolicy: Equatable, Sendable {
    private var rulesByProgram: [String: [PrefixRule]]
    private var networkRulesStorage: [NetworkRule]
    private var hostExecutablesByName: [String: [String]]

    public init(
        rulesByProgram: [String: [PrefixRule]] = [:],
        networkRules: [NetworkRule] = [],
        hostExecutables: [String: [String]] = [:]
    ) {
        self.rulesByProgram = rulesByProgram
        self.networkRulesStorage = networkRules
        self.hostExecutablesByName = hostExecutables
    }

    public static func empty() -> ExecPolicy {
        ExecPolicy()
    }

    public func rules(for program: String) -> [PrefixRule] {
        rulesByProgram[program] ?? []
    }

    public func networkRules() -> [NetworkRule] {
        networkRulesStorage
    }

    public func hostExecutables() -> [String: [String]] {
        hostExecutablesByName
    }

    public func allowedPrefixes() -> [[String]] {
        var prefixes: [[String]] = []
        for rules in rulesByProgram.values {
            for rule in rules where rule.decision == .allow {
                prefixes.append([rule.pattern.first] + rule.pattern.rest.map(\.policyText))
            }
        }
        prefixes.sort { $0.lexicographicallyPrecedes($1) }
        prefixes = prefixes.reduce(into: []) { result, prefix in
            if result.last != prefix {
                result.append(prefix)
            }
        }
        return prefixes
    }

    public func formattedAllowedPrefixes() -> String? {
        Self.formatAllowedPrefixes(allowedPrefixes()).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func formatAllowedPrefixes(_ prefixes: [[String]]) -> String? {
        let maxRenderedPrefixes = 100
        let maxAllowPrefixTextBytes = 5_000
        let truncatedMarker = "...\n[Some commands were truncated]"
        var truncated = prefixes.count > maxRenderedPrefixes
        let sortedPrefixes = prefixes.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            let lhsLength = lhs.reduce(0) { $0 + $1.count }
            let rhsLength = rhs.reduce(0) { $0 + $1.count }
            if lhsLength != rhsLength {
                return lhsLength < rhsLength
            }
            return lhs.lexicographicallyPrecedes(rhs)
        }
        let fullText = sortedPrefixes
            .prefix(maxRenderedPrefixes)
            .map { "- \(renderCommandPrefix($0))" }
            .joined(separator: "\n")

        var output = fullText
        if let byteIndex = output.utf8Index(atOffset: maxAllowPrefixTextBytes) {
            truncated = true
            output = String(output[..<byteIndex])
        }
        return truncated ? "\(output)\(truncatedMarker)" : output
    }

    public func mergingOverlay(_ overlay: ExecPolicy) -> ExecPolicy {
        var combinedRules = rulesByProgram
        for (program, rules) in overlay.rulesByProgram {
            combinedRules[program, default: []].append(contentsOf: rules)
        }

        var combinedHostExecutables = hostExecutablesByName
        for (name, paths) in overlay.hostExecutablesByName {
            combinedHostExecutables[name] = paths
        }

        return ExecPolicy(
            rulesByProgram: combinedRules,
            networkRules: networkRulesStorage + overlay.networkRulesStorage,
            hostExecutables: combinedHostExecutables
        )
    }

    public func compiledNetworkDomains() -> (allowed: [String], denied: [String]) {
        var allowed: [String] = []
        var denied: [String] = []

        for rule in networkRulesStorage {
            switch rule.decision {
            case .allow:
                denied.removeAll { $0 == rule.host }
                Self.upsertDomain(&allowed, rule.host)
            case .forbidden:
                allowed.removeAll { $0 == rule.host }
                Self.upsertDomain(&denied, rule.host)
            case .prompt:
                continue
            }
        }

        return (allowed, denied)
    }

    public mutating func addPrefixRule(_ prefix: [String], decision: ExecPolicyDecision) throws {
        guard let firstToken = prefix.first else {
            throw ExecPolicyError.invalidPattern("prefix cannot be empty")
        }

        let rule = PrefixRule(
            pattern: PrefixPattern(
                first: firstToken,
                rest: prefix.dropFirst().map { .single($0) }
            ),
            decision: decision,
            justification: nil
        )
        rulesByProgram[firstToken, default: []].append(rule)
    }

    public mutating func addNetworkRule(
        host rawHost: String,
        protocol: NetworkRuleProtocol,
        decision: ExecPolicyDecision,
        justification: String? = nil
    ) throws {
        if let justification, justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExecPolicyError.invalidRule("justification cannot be empty")
        }
        networkRulesStorage.append(NetworkRule(
            host: try Self.normalizeNetworkRuleHost(rawHost),
            protocol: `protocol`,
            decision: decision,
            justification: justification
        ))
    }

    private static func upsertDomain(_ domains: inout [String], _ host: String) {
        domains.removeAll { $0 == host }
        domains.append(host)
    }

    fileprivate static func normalizeNetworkRuleHost(_ raw: String) throws -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ExecPolicyError.invalidRule("network_rule host cannot be empty")
        }
        if host.contains("://") || host.contains("/") || host.contains("?") || host.contains("#") {
            throw ExecPolicyError.invalidRule(
                "network_rule host must be a hostname or IP literal (without scheme or path)"
            )
        }

        if host.hasPrefix("[") {
            guard let closeBracket = host.firstIndex(of: "]") else {
                throw ExecPolicyError.invalidRule("network_rule host has an invalid bracketed IPv6 literal")
            }
            let insideStart = host.index(after: host.startIndex)
            let restStart = host.index(after: closeBracket)
            let rest = String(host[restStart...])
            if !rest.isEmpty {
                guard rest.hasPrefix(":") else {
                    throw ExecPolicyError.invalidRule("network_rule host contains an unsupported suffix: \(raw)")
                }
                let port = rest.dropFirst()
                guard !port.isEmpty, port.allSatisfy(\.isASCIIWholeNumber) else {
                    throw ExecPolicyError.invalidRule("network_rule host contains an unsupported suffix: \(raw)")
                }
            }
            host = String(host[insideStart..<closeBracket])
        } else if host.filter({ $0 == ":" }).count == 1,
                  let separator = host.lastIndex(of: ":") {
            let candidate = String(host[..<separator])
            let port = host[host.index(after: separator)...]
            if !candidate.isEmpty, !port.isEmpty, port.allSatisfy(\.isASCIIWholeNumber) {
                host = candidate
            }
        }

        while host.hasSuffix(".") {
            host.removeLast()
        }
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw ExecPolicyError.invalidRule("network_rule host cannot be empty")
        }
        if normalized.contains("*") {
            throw ExecPolicyError.invalidRule(
                "network_rule host must be a specific host; wildcards are not allowed"
            )
        }
        if normalized.contains(where: \.isWhitespace) {
            throw ExecPolicyError.invalidRule("network_rule host cannot contain whitespace")
        }

        return normalized
    }

    public mutating func setHostExecutablePaths(name rawName: String, paths rawPaths: [String]) throws {
        let name = try Self.validateHostExecutableName(rawName)
        var paths: [String] = []
        for rawPath in rawPaths {
            let path = try Self.parseLiteralAbsolutePath(rawPath)
            guard let pathName = Self.executablePathLookupKey(path),
                  pathName == Self.executableLookupKey(name)
            else {
                throw ExecPolicyError.invalidRule("host_executable path `\(rawPath)` must have basename `\(name)`")
            }
            if !paths.contains(path) {
                paths.append(path)
            }
        }
        hostExecutablesByName[Self.executableLookupKey(name)] = paths
    }

    private static func validateHostExecutableName(_ name: String) throws -> String {
        guard !name.isEmpty else {
            throw ExecPolicyError.invalidRule("host_executable name cannot be empty")
        }
        guard !name.contains("/") && name != "." && name != ".." else {
            throw ExecPolicyError.invalidRule("host_executable name must be a bare executable name (got \(name))")
        }
        return name
    }

    private static func parseLiteralAbsolutePath(_ raw: String) throws -> String {
        guard raw.hasPrefix("/") else {
            throw ExecPolicyError.invalidRule("host_executable paths must be absolute (got \(raw))")
        }
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    private static func executableLookupKey(_ raw: String) -> String {
        #if os(Windows)
        let lowercased = raw.lowercased()
        for suffix in [".exe", ".cmd", ".bat", ".com"] where lowercased.hasSuffix(suffix) {
            return String(lowercased.dropLast(suffix.count))
        }
        return lowercased
        #else
        return raw
        #endif
    }

    private static func executablePathLookupKey(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard !name.isEmpty else {
            return nil
        }
        return executableLookupKey(name)
    }

    public func check(
        _ command: [String],
        heuristicsFallback: @escaping (ArraySlice<String>) -> ExecPolicyDecision
    ) -> PolicyEvaluation {
        PolicyEvaluation.fromMatches(matchesForCommand(command, heuristicsFallback: heuristicsFallback))
    }

    public func checkMultiple(
        _ commands: [[String]],
        heuristicsFallback: @escaping (ArraySlice<String>) -> ExecPolicyDecision
    ) -> PolicyEvaluation {
        let matches = commands.flatMap {
            matchesForCommand($0, heuristicsFallback: heuristicsFallback)
        }
        return PolicyEvaluation.fromMatches(matches)
    }

    public func matchesForCommand(
        _ command: [String],
        heuristicsFallback: ((ArraySlice<String>) -> ExecPolicyDecision)?
    ) -> [RuleMatch] {
        matchesForCommand(command, heuristicsFallback: heuristicsFallback, options: ExecPolicyMatchOptions())
    }

    public func matchesForCommand(
        _ command: [String],
        heuristicsFallback: ((ArraySlice<String>) -> ExecPolicyDecision)?,
        options: ExecPolicyMatchOptions
    ) -> [RuleMatch] {
        var matchedRules = matchExactRules(command)
        if matchedRules.isEmpty, options.resolveHostExecutables {
            matchedRules = matchHostExecutableRules(command)
        }

        if matchedRules.isEmpty, let heuristicsFallback {
            matchedRules.append(.heuristicsRuleMatch(
                command: command,
                decision: heuristicsFallback(command[...])
            ))
        }

        return matchedRules
    }

    public func check(
        _ command: [String],
        heuristicsFallback: @escaping (ArraySlice<String>) -> ExecPolicyDecision,
        options: ExecPolicyMatchOptions
    ) -> PolicyEvaluation {
        PolicyEvaluation.fromMatches(matchesForCommand(
            command,
            heuristicsFallback: heuristicsFallback,
            options: options
        ))
    }

    private func matchExactRules(_ command: [String]) -> [RuleMatch] {
        command.first
            .flatMap { rulesByProgram[$0] }?
            .compactMap { $0.matches(command) }
            ?? []
    }

    private func matchHostExecutableRules(_ command: [String]) -> [RuleMatch] {
        guard let first = command.first,
              first.hasPrefix("/"),
              let basename = Self.executablePathLookupKey(first),
              let rules = rulesByProgram[basename]
        else {
            return []
        }

        if let paths = hostExecutablesByName[basename],
           !paths.contains(URL(fileURLWithPath: first).standardizedFileURL.path) {
            return []
        }

        let basenameCommand = [basename] + command.dropFirst()
        return rules.compactMap { rule in
            guard case let .prefixRuleMatch(matchedPrefix, decision, _, justification) = rule.matches(basenameCommand) else {
                return nil
            }
            return .prefixRuleMatch(
                matchedPrefix: matchedPrefix,
                decision: decision,
                resolvedProgram: first,
                justification: justification
            )
        }
    }
}

private extension PatternToken {
    var policyText: String {
        switch self {
        case let .single(value):
            return value
        case let .alts(alternatives):
            return "[\(alternatives.joined(separator: "|"))]"
        }
    }
}

private func renderCommandPrefix(_ prefix: [String]) -> String {
    let tokens = prefix.map { token in
        (try? JSONEncoder().encode(token))
            .map { String(decoding: $0, as: UTF8.self) } ?? String(describing: token)
    }
    return "[\(tokens.joined(separator: ", "))]"
}

private extension String {
    func utf8Index(atOffset offset: Int) -> String.Index? {
        var byteCount = 0
        for index in indices {
            if byteCount == offset {
                return index
            }
            byteCount += self[index].utf8.count
            if byteCount > offset {
                return nil
            }
        }
        return byteCount == offset ? endIndex : nil
    }
}

public final class PolicyParser {
    private struct StarlarkFunctionParameter {
        enum Kind {
            case positionalOrKeyword
            case keywordOnly
            case varargs
            case kwargs
        }

        let name: String
        let defaultValueExpression: String?
        let kind: Kind
    }

    private struct StarlarkFunction {
        let parameters: [StarlarkFunctionParameter]
        let body: [String]
    }

    private struct StarlarkMethodCallee {
        let receiverText: String
        let methodName: String
    }

    private struct StarlarkFormatArguments {
        let positional: [ConfigValue]
        let named: [String: ConfigValue]
    }

    private enum StarlarkFormatConversion {
        case string
        case representation
    }

    private enum StarlarkPercentArgumentSource {
        case positional([ConfigValue])
        case mapping([String: ConfigValue])
    }

    private enum StarlarkStatementFlow: Equatable {
        case none
        case continueLoop
        case breakLoop
    }

    private enum StarlarkFunctionFlow {
        case none
        case continueLoop
        case breakLoop
        case returnValue(ConfigValue)
    }

    private var policy = ExecPolicy.empty()
    private var pendingExampleValidations: [(rules: [PrefixRule], matches: [[String]], notMatches: [[String]])] = []

    public init() {}

    public func parse(_ policyIdentifier: String, _ policyFileContents: String) throws {
        let pendingValidationStartIndex = pendingExampleValidations.count
        let source = Self.stripLineComments(from: policyFileContents)
        var constants: [String: ConfigValue] = [:]
        var functions: [String: StarlarkFunction] = [:]
        let flow = try parseStatements(
            Self.topLevelStatements(from: source),
            identifier: policyIdentifier,
            constants: &constants,
            functions: &functions
        )
        guard flow == .none else {
            throw ConfigOverrideError.invalidLiteral(policyIdentifier)
        }
        try validatePendingExamples(from: pendingValidationStartIndex)
    }

    private func parseStatements(
        _ statements: [String],
        identifier: String,
        constants: inout [String: ConfigValue],
        functions: inout [String: StarlarkFunction]
    ) throws -> StarlarkStatementFlow {
        var index = 0
        while index < statements.count {
            let statement = statements[index]
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                index += 1
                continue
            }

            if let functionHeader = try Self.parseTopLevelFunctionHeader(statement) {
                let collected = try Self.collectIndentedBlock(
                    after: index,
                    in: statements,
                    parentIndent: Self.indentationCount(statement),
                    identifier: identifier,
                    blockName: "function"
                )
                functions[functionHeader.name] = try Self.parseStarlarkFunction(
                    parameters: functionHeader.parameters,
                    body: collected.body
                )
                index = collected.nextIndex
                continue
            }

            if let forLoop = try Self.parseTopLevelForHeader(statement) {
                let headerIndent = Self.indentationCount(statement)
                let collected = try Self.collectIndentedBlock(
                    after: index,
                    in: statements,
                    parentIndent: headerIndent,
                    identifier: identifier,
                    blockName: "for loop"
                )
                let body = collected.body

                let iterable = try Self.parsePolicyLiteral(
                    forLoop.iterableText,
                    constants: constants,
                    functions: functions
                )
                let items = try Self.starlarkIterableItems(iterable, expression: forLoop.iterableText)

                var loopConstants = constants
                var shouldBreakLoop = false
                for item in items {
                    try Self.bindStarlarkLoopTargets(
                        forLoop.targets,
                        to: item,
                        constants: &loopConstants,
                        expression: statement.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    let flow = try parseStatements(
                        body,
                        identifier: identifier,
                        constants: &loopConstants,
                        functions: &functions
                    )
                    switch flow {
                    case .none:
                        break
                    case .continueLoop:
                        continue
                    case .breakLoop:
                        shouldBreakLoop = true
                    }
                    if shouldBreakLoop {
                        break
                    }
                }
                constants = loopConstants
                index = collected.nextIndex
                continue
            }

            if let condition = try Self.parseTopLevelIfHeader(statement) {
                let headerIndent = Self.indentationCount(statement)
                let thenBlock = try Self.collectIndentedBlock(
                    after: index,
                    in: statements,
                    parentIndent: headerIndent,
                    identifier: identifier,
                    blockName: "if block"
                )
                var nextIndex = thenBlock.nextIndex
                var branches = [(condition: condition, body: thenBlock.body)]
                var elseBody: [String] = []
                while nextIndex < statements.count,
                      Self.indentationCount(statements[nextIndex]) == headerIndent,
                      let elifCondition = try Self.parseTopLevelElifHeader(statements[nextIndex]) {
                    let elifBlock = try Self.collectIndentedBlock(
                        after: nextIndex,
                        in: statements,
                        parentIndent: headerIndent,
                        identifier: identifier,
                        blockName: "elif block"
                    )
                    branches.append((condition: elifCondition, body: elifBlock.body))
                    nextIndex = elifBlock.nextIndex
                }
                if nextIndex < statements.count,
                   Self.indentationCount(statements[nextIndex]) == headerIndent,
                   Self.isTopLevelElseHeader(statements[nextIndex]) {
                    let elseBlock = try Self.collectIndentedBlock(
                        after: nextIndex,
                        in: statements,
                        parentIndent: headerIndent,
                        identifier: identifier,
                        blockName: "else block"
                    )
                    elseBody = elseBlock.body
                    nextIndex = elseBlock.nextIndex
                }

                var matchedBranch = false
                for branch in branches where try Self.evaluateStarlarkCondition(
                    branch.condition,
                    constants: constants,
                    functions: functions
                ) {
                    let flow = try parseStatements(
                        branch.body,
                        identifier: identifier,
                        constants: &constants,
                        functions: &functions
                    )
                    if flow != .none {
                        return flow
                    }
                    matchedBranch = true
                    break
                }
                if !matchedBranch, !elseBody.isEmpty {
                    let flow = try parseStatements(
                        elseBody,
                        identifier: identifier,
                        constants: &constants,
                        functions: &functions
                    )
                    if flow != .none {
                        return flow
                    }
                }
                index = nextIndex
                continue
            }

            if trimmed == "continue" {
                return .continueLoop
            }
            if trimmed == "break" {
                return .breakLoop
            }

            if let lambdaAssignment = try Self.parseStarlarkLambdaAssignment(statement) {
                functions[lambdaAssignment.name] = lambdaAssignment.function
                index += 1
                continue
            }

            try parseStatement(statement, identifier: identifier, constants: &constants, functions: functions)
            index += 1
        }
        return .none
    }

    public func build() -> ExecPolicy {
        policy
    }

    private func parseStatement(
        _ statement: String,
        identifier: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws {
        if try Self.parseTopLevelDestructuringAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkListPopAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkDictPopAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkCollectionNoneMutationAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkDictMutationStatement(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkListMutationStatement(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkDeleteStatement(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkIndexedAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if try Self.parseStarlarkAugmentedAssignment(
            statement,
            constants: &constants,
            functions: functions
        ) {
            return
        }

        if let assignment = try Self.parseTopLevelLiteralAssignment(
            statement,
            constants: constants,
            functions: functions
        ) {
            constants[assignment.key] = assignment.value
            return
        }

        if try Self.parseStarlarkFailStatement(statement, constants: constants, functions: functions) {
            return
        }

        if let callee = try Self.parseTopLevelFunctionCallName(statement),
           !["prefix_rule", "network_rule", "host_executable"].contains(callee) {
            throw ExecPolicyError.invalidSyntax("unsupported Starlark top-level call: \(callee)")
        }

        let prefixRuleBodies = try Self.extractCallBodies(
            named: "prefix_rule",
            from: statement,
            identifier: identifier
        )
        for body in prefixRuleBodies {
            try addPrefixRule(from: body, constants: constants, functions: functions)
        }
        let networkRuleBodies = try Self.extractCallBodies(
            named: "network_rule",
            from: statement,
            identifier: identifier
        )
        for body in networkRuleBodies {
            try addNetworkRule(from: body, constants: constants, functions: functions)
        }
        let hostExecutableBodies = try Self.extractCallBodies(
            named: "host_executable",
            from: statement,
            identifier: identifier
        )
        for body in hostExecutableBodies {
            try addHostExecutable(from: body, constants: constants, functions: functions)
        }
    }

    private static func parseTopLevelFunctionCallName(_ statement: String) throws -> String? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              first == "_" || first.isLetter
        else {
            return nil
        }

        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            guard character == "_" || character.isLetter || character.isNumber else {
                break
            }
            index = trimmed.index(after: index)
        }

        let name = String(trimmed[..<index])
        var cursor = index
        while cursor < trimmed.endIndex, trimmed[cursor].isWhitespace {
            cursor = trimmed.index(after: cursor)
        }
        guard cursor < trimmed.endIndex, trimmed[cursor] == "(" else {
            return nil
        }

        let closeIndex = try matchingCloseParenIndex(in: trimmed, openIndex: cursor)
        var trailing = trimmed.index(after: closeIndex)
        while trailing < trimmed.endIndex, trimmed[trailing].isWhitespace {
            trailing = trimmed.index(after: trailing)
        }
        guard trailing == trimmed.endIndex else {
            return nil
        }
        return name
    }

    private static func matchingCloseParenIndex(in text: String, openIndex: String.Index) throws -> String.Index {
        var index = openIndex
        var quote: Character?
        var previousWasBackslash = false
        var depth = 0

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }

        throw ExecPolicyError.invalidSyntax("unterminated Starlark top-level call")
    }

    private func addPrefixRule(
        from body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws {
        let arguments = try Self.parseArguments(
            body,
            constants: constants,
            functions: functions,
            positionalNames: ["pattern", "decision", "match", "not_match", "justification"]
        )
        guard let patternValue = arguments["pattern"] else {
            throw ExecPolicyError.invalidPattern("missing pattern")
        }

        let decision: ExecPolicyDecision
        if let decisionValue = arguments["decision"] {
            guard case let .string(rawDecision) = decisionValue else {
                throw ExecPolicyError.invalidDecision(String(describing: decisionValue))
            }
            decision = try ExecPolicyDecision.parse(rawDecision)
        } else {
            decision = .allow
        }

        let justification = try Self.parseOptionalJustification(arguments["justification"])
        let patternTokens = try Self.parsePattern(patternValue)
        let matchExamples = try arguments["match"].map(Self.parseExamples) ?? []
        let notMatchExamples = try arguments["not_match"].map(Self.parseExamples) ?? []

        guard let firstToken = patternTokens.first else {
            throw ExecPolicyError.invalidPattern("pattern cannot be empty")
        }

        let rest = Array(patternTokens.dropFirst())
        let rules = firstToken.alternatives.map { head in
            PrefixRule(
                pattern: PrefixPattern(first: head, rest: rest),
                decision: decision,
                justification: justification
            )
        }

        for rule in rules {
            var existing = policy.rules(for: rule.program)
            existing.append(rule)
            policy = policy.replacingRules(for: rule.program, with: existing)
        }
        pendingExampleValidations.append((rules, matchExamples, notMatchExamples))
    }

    private func addNetworkRule(
        from body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws {
        let arguments = try Self.parseArguments(
            body,
            constants: constants,
            functions: functions,
            positionalNames: ["host", "protocol", "decision", "justification"]
        )
        let host = try Self.requireStringArgument(arguments, key: "host", function: "network_rule")
        let rawProtocol = try Self.requireStringArgument(arguments, key: "protocol", function: "network_rule")
        let rawDecision = try Self.requireStringArgument(arguments, key: "decision", function: "network_rule")
        try policy.addNetworkRule(
            host: host,
            protocol: NetworkRuleProtocol.parse(rawProtocol),
            decision: rawDecision == "deny" ? .forbidden : ExecPolicyDecision.parse(rawDecision),
            justification: try Self.parseOptionalJustification(arguments["justification"])
        )
    }

    private func addHostExecutable(
        from body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws {
        let arguments = try Self.parseArguments(
            body,
            constants: constants,
            functions: functions,
            positionalNames: ["name", "paths"]
        )
        let name = try Self.requireStringArgument(arguments, key: "name", function: "host_executable")
        guard let pathsValue = arguments["paths"] else {
            throw ExecPolicyError.invalidRule("host_executable missing paths")
        }
        guard case let .array(items) = pathsValue else {
            throw ExecPolicyError.invalidRule("host_executable paths must be a list")
        }
        let paths = try items.map { item -> String in
            guard case let .string(path) = item else {
                throw ExecPolicyError.invalidRule("host_executable paths must be strings")
            }
            return path
        }
        try policy.setHostExecutablePaths(name: name, paths: paths)
    }

    private func validatePendingExamples(from startIndex: Int) throws {
        for validation in pendingExampleValidations[startIndex...] {
            let validationPolicy = ExecPolicy(
                rulesByProgram: Dictionary(grouping: validation.rules, by: \.program),
                hostExecutables: policy.hostExecutables()
            )
            try Self.validateNotMatchExamples(
                policy: validationPolicy,
                rules: validation.rules,
                notMatches: validation.notMatches
            )
            try Self.validateMatchExamples(
                policy: validationPolicy,
                rules: validation.rules,
                matches: validation.matches
            )
        }
    }

    private static func extractCallBodies(
        named functionName: String,
        from source: String,
        identifier: String
    ) throws -> [String] {
        var bodies: [String] = []
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if character == "\"" || character == "'" {
                index = Self.index(afterQuotedStringAt: index, in: source)
                continue
            }

            guard source[index...].hasPrefix(functionName),
                  isIdentifierBoundaryBefore(index, in: source)
            else {
                index = source.index(after: index)
                continue
            }

            let functionEnd = source.index(index, offsetBy: functionName.count)
            guard isIdentifierBoundaryAfter(functionEnd, in: source) else {
                index = functionEnd
                continue
            }

            index = functionEnd
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex, source[index] == "(" else {
                throw ExecPolicyError.invalidSyntax("\(identifier): expected '(' after \(functionName)")
            }

            let bodyStart = source.index(after: index)
            var quote: Character?
            var previousWasBackslash = false
            var depth = 1
            index = bodyStart
            while index < source.endIndex {
                let character = source[index]
                if let activeQuote = quote {
                    if character == activeQuote && !previousWasBackslash {
                        quote = nil
                    }
                    previousWasBackslash = character == "\\" && !previousWasBackslash
                    if character != "\\" {
                        previousWasBackslash = false
                    }
                    index = source.index(after: index)
                    continue
                }

                if character == "\"" || character == "'" {
                    quote = character
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        bodies.append(String(source[bodyStart..<index]))
                        index = source.index(after: index)
                        break
                    }
                }
                index = source.index(after: index)
            }

            if depth != 0 {
                throw ExecPolicyError.invalidSyntax("\(identifier): unterminated \(functionName)")
            }
        }

        return bodies
    }

    private static func stripLineComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        var quote: Character?
        var previousWasBackslash = false

        while index < source.endIndex {
            let character = source[index]
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = source.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                result.append(character)
                index = source.index(after: index)
                continue
            }

            if character == "#" {
                while index < source.endIndex, !source[index].isNewline {
                    index = source.index(after: index)
                }
                if index < source.endIndex {
                    result.append(source[index])
                    index = source.index(after: index)
                }
                continue
            }

            result.append(character)
            index = source.index(after: index)
        }

        return result
    }

    private static func index(afterQuotedStringAt start: String.Index, in source: String) -> String.Index {
        let quote = source[start]
        var index = source.index(after: start)
        var previousWasBackslash = false
        while index < source.endIndex {
            let character = source[index]
            if character == quote && !previousWasBackslash {
                return source.index(after: index)
            }
            previousWasBackslash = character == "\\" && !previousWasBackslash
            if character != "\\" {
                previousWasBackslash = false
            }
            index = source.index(after: index)
        }
        return index
    }

    private static func isIdentifierBoundaryBefore(_ index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else {
            return true
        }
        return !isStarlarkIdentifierCharacter(source[source.index(before: index)])
    }

    private static func isIdentifierBoundaryAfter(_ index: String.Index, in source: String) -> Bool {
        guard index < source.endIndex else {
            return true
        }
        return !isStarlarkIdentifierCharacter(source[index])
    }

    private static func isStarlarkIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func parseTopLevelDestructuringAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let equalsIndex = topLevelEqualsIndex(in: trimmed)
        else {
            return false
        }

        let targetText = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard targetText.contains(",") ||
            (targetText.hasPrefix("[") && targetText.hasSuffix("]")) ||
            (targetText.hasPrefix("(") && targetText.hasSuffix(")"))
        else {
            return false
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valueText.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let targets = try parseStarlarkLoopTargets(targetText, expression: trimmed)
        let value = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
        try bindStarlarkLoopTargets(targets, to: value, constants: &constants, expression: trimmed)
        return true
    }

    private static func parseStarlarkMethodCallee(
        _ callee: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> StarlarkMethodCallee? {
        if let methodDotIndex = topLevelMethodDotIndex(in: callee) {
            let receiverText = String(callee[..<methodDotIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let methodStart = callee.index(after: methodDotIndex)
            let methodName = String(callee[methodStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return StarlarkMethodCallee(receiverText: receiverText, methodName: methodName)
        }

        guard callee.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: callee)
        else {
            return nil
        }

        let calleeName = String(callee[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard calleeName == "getattr" else {
            return nil
        }

        let bodyStart = callee.index(after: openIndex)
        let body = String(callee[bodyStart..<callee.index(before: callee.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard rawArguments.count == 2 || rawArguments.count == 3 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let receiverText = rawArguments[0]
        let receiver = try parsePolicyLiteral(receiverText, constants: constants, functions: functions)
        let attribute = try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
        guard case let .string(methodName) = attribute,
              starlarkAttributeNames(for: receiver).contains(methodName)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        return StarlarkMethodCallee(receiverText: receiverText, methodName: methodName)
    }

    private static func parseStarlarkDictMutationStatement(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topLevelEqualsIndex(in: trimmed) == nil else {
            return false
        }
        guard trimmed.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: trimmed)
        else {
            return false
        }

        let callee = String(trimmed[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodCallee = try parseStarlarkMethodCallee(
            callee,
            constants: constants,
            functions: functions,
            expression: trimmed
        ) else {
            return false
        }

        let receiverText = methodCallee.receiverText
        let methodName = methodCallee.methodName
        guard ["update", "clear", "pop", "popitem", "setdefault"].contains(methodName) else {
            return false
        }
        guard isStarlarkIdentifier(receiverText),
              let receiver = constants[receiverText]
        else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }
        guard case var .table(items) = receiver else {
            if methodName == "clear" || methodName == "pop" || methodName == "popitem" || methodName == "setdefault" {
                return false
            }
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let bodyStart = trimmed.index(after: openIndex)
        let body = String(trimmed[bodyStart..<trimmed.index(before: trimmed.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch methodName {
        case "update":
            try applyStarlarkDictUpdateArguments(
                rawArguments,
                to: &items,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
        case "clear":
            guard rawArguments.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(trimmed)
            }
            items.removeAll()
        case "pop":
            _ = try popStarlarkDictValue(
                from: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
        case "popitem":
            _ = try popFirstStarlarkDictItem(from: &items, rawArguments: rawArguments, expression: trimmed)
        case "setdefault":
            _ = try setDefaultStarlarkDictValue(
                in: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
        default:
            return false
        }
        constants[receiverText] = .table(items)
        return true
    }

    private static func applyStarlarkDictUpdateArguments(
        _ rawArguments: [String],
        to items: inout [String: ConfigValue],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        var sawKeywordArgument = false
        var consumedPositionalArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                let rawKey = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard isStarlarkIdentifier(rawKey), !rawValue.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawKeywordArgument = true
                items[rawKey] = try parsePolicyLiteral(rawValue, constants: constants, functions: functions)
                continue
            }

            guard !sawKeywordArgument, !consumedPositionalArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            consumedPositionalArgument = true
            guard rawArgument != "None" else {
                continue
            }
            let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            switch argument {
            case let .table(updateItems):
                for (key, value) in updateItems {
                    items[key] = value
                }
            case let .array(pairs):
                for pair in pairs {
                    guard case let .array(pairItems) = pair,
                          pairItems.count == 2,
                          case let .string(key) = pairItems[0]
                    else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    items[key] = pairItems[1]
                }
            default:
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }
    }

    private static func parseStarlarkDictPopAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = topLevelEqualsIndex(in: trimmed) else {
            return false
        }

        let target = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(target) else {
            return false
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard valueText.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: valueText)
        else {
            return false
        }

        let callee = String(valueText[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodCallee = try parseStarlarkMethodCallee(
            callee,
            constants: constants,
            functions: functions,
            expression: trimmed
        ) else {
            return false
        }

        let receiverText = methodCallee.receiverText
        let methodName = methodCallee.methodName
        guard methodName == "pop" || methodName == "popitem" || methodName == "setdefault" else {
            return false
        }
        guard isStarlarkIdentifier(receiverText),
              case var .table(items) = constants[receiverText]
        else {
            return false
        }

        let bodyStart = valueText.index(after: openIndex)
        let body = String(valueText[bodyStart..<valueText.index(before: valueText.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let item: ConfigValue
        switch methodName {
        case "pop":
            item = try popStarlarkDictValue(
                from: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
        case "popitem":
            item = try popFirstStarlarkDictItem(from: &items, rawArguments: rawArguments, expression: trimmed)
        case "setdefault":
            item = try setDefaultStarlarkDictValue(
                in: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
        default:
            return false
        }
        constants[receiverText] = .table(items)
        constants[target] = item
        return true
    }

    private static func parseStarlarkCollectionNoneMutationAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = topLevelEqualsIndex(in: trimmed) else {
            return false
        }

        let target = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(target) else {
            return false
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard valueText.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: valueText)
        else {
            return false
        }

        let callee = String(valueText[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodCallee = try parseStarlarkMethodCallee(
            callee,
            constants: constants,
            functions: functions,
            expression: trimmed
        ) else {
            return false
        }

        let receiverText = methodCallee.receiverText
        let methodName = methodCallee.methodName

        let bodyStart = valueText.index(after: openIndex)
        let body = String(valueText[bodyStart..<valueText.index(before: valueText.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if starlarkListMutationMethods.contains(methodName), methodName != "pop" {
            let mutatesNamedReceiver = isStarlarkIdentifier(receiverText)
            let sourceItems: [ConfigValue]?
            if mutatesNamedReceiver, case let .array(namedItems) = constants[receiverText] {
                sourceItems = namedItems
            } else if !mutatesNamedReceiver,
                      case let .array(parsedItems) = try? parsePolicyLiteral(
                        receiverText,
                        constants: constants,
                        functions: functions
                      ) {
                sourceItems = parsedItems
            } else {
                sourceItems = nil
            }
            if var items = sourceItems {
                try applyStarlarkListMutation(
                    methodName: methodName,
                    to: &items,
                    rawArguments: rawArguments,
                    constants: constants,
                    functions: functions,
                    expression: trimmed
                )
                if mutatesNamedReceiver {
                    constants[receiverText] = .array(items)
                }
                constants[target] = ConfigValue.none
                return true
            }
        }

        if starlarkDictNoneMutationMethods.contains(methodName) {
            let mutatesNamedReceiver = isStarlarkIdentifier(receiverText)
            var items: [String: ConfigValue]
            if mutatesNamedReceiver, case let .table(sourceItems) = constants[receiverText] {
                items = sourceItems
            } else {
                guard case let .table(sourceItems) = try? parsePolicyLiteral(
                    receiverText,
                    constants: constants,
                    functions: functions
                ) else {
                    return false
                }
                items = sourceItems
            }
            try applyStarlarkDictNoneMutation(
                methodName: methodName,
                to: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: trimmed
            )
            if mutatesNamedReceiver {
                constants[receiverText] = .table(items)
            }
            constants[target] = ConfigValue.none
            return true
        }

        return false
    }

    private static func popStarlarkDictValue(
        from items: inout [String: ConfigValue],
        rawArguments: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        guard rawArguments.count == 1 || rawArguments.count == 2,
              let rawKey = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let key = try parsePolicyLiteral(rawKey, constants: constants, functions: functions)
        guard case let .string(key) = key else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        if let removed = items.removeValue(forKey: key) {
            return removed
        }
        guard rawArguments.count == 2 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
    }

    private static func popFirstStarlarkDictItem(
        from items: inout [String: ConfigValue],
        rawArguments: [String],
        expression: String
    ) throws -> ConfigValue {
        guard rawArguments.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        guard let (key, value) = items.first else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        items.removeValue(forKey: key)
        return .array([.string(key), value])
    }

    private static func setDefaultStarlarkDictValue(
        in items: inout [String: ConfigValue],
        rawArguments: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        guard rawArguments.count == 1 || rawArguments.count == 2,
              let rawKey = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let key = try parsePolicyLiteral(rawKey, constants: constants, functions: functions)
        guard case let .string(key) = key else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        if let existing = items[key] {
            return existing
        }
        let defaultValue = rawArguments.count == 2
            ? try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
            : .none
        items[key] = defaultValue
        return defaultValue
    }

    private static let starlarkDictNoneMutationMethods = ["update", "clear"]

    private static func applyStarlarkDictNoneMutation(
        methodName: String,
        to items: inout [String: ConfigValue],
        rawArguments: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        switch methodName {
        case "update":
            try applyStarlarkDictUpdateArguments(
                rawArguments,
                to: &items,
                constants: constants,
                functions: functions,
                expression: expression
            )
        case "clear":
            guard rawArguments.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items.removeAll()
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkListMutationStatement(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topLevelEqualsIndex(in: trimmed) == nil else {
            return false
        }
        guard trimmed.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: trimmed)
        else {
            return false
        }

        let callee = String(trimmed[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodCallee = try parseStarlarkMethodCallee(
            callee,
            constants: constants,
            functions: functions,
            expression: trimmed
        ) else {
            return false
        }

        let receiverText = methodCallee.receiverText
        let methodName = methodCallee.methodName
        guard isStarlarkIdentifier(receiverText),
              case var .array(items) = constants[receiverText]
        else {
            return false
        }
        guard starlarkListMutationMethods.contains(methodName) else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let bodyStart = trimmed.index(after: openIndex)
        let body = String(trimmed[bodyStart..<trimmed.index(before: trimmed.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        try applyStarlarkListMutation(
            methodName: methodName,
            to: &items,
            rawArguments: rawArguments,
            constants: constants,
            functions: functions,
            expression: trimmed
        )
        constants[receiverText] = .array(items)
        return true
    }

    private static let starlarkListMutationMethods = [
        "append",
        "extend",
        "insert",
        "clear",
        "pop",
        "remove",
        "sort",
        "reverse",
    ]

    private static func applyStarlarkListMutation(
        methodName: String,
        to items: inout [ConfigValue],
        rawArguments: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        switch methodName {
        case "append":
            guard rawArguments.count == 1,
                  let rawArgument = rawArguments.first
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            items.append(argument)
        case "extend":
            guard rawArguments.count == 1,
                  let rawArgument = rawArguments.first
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            let extensionItems: [ConfigValue]
            switch argument {
            case let .array(items):
                extensionItems = items
            case let .table(items):
                extensionItems = items.keys.map(ConfigValue.string)
            default:
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items.append(contentsOf: extensionItems)
        case "insert":
            guard rawArguments.count == 2 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let insertionIndex = try parseStarlarkInteger(
                rawArguments[0],
                constants: constants,
                functions: functions,
                expression: expression
            )
            let argument = try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
            let clampedIndex: Int
            if insertionIndex < 0 {
                clampedIndex = max(items.count + insertionIndex, 0)
            } else {
                clampedIndex = min(insertionIndex, items.count)
            }
            items.insert(argument, at: clampedIndex)
        case "clear":
            guard rawArguments.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items.removeAll()
        case "pop":
            _ = try popStarlarkListItem(
                from: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: expression
            )
        case "remove":
            guard rawArguments.count == 1,
                  let rawArgument = rawArguments.first
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            guard let removalIndex = items.firstIndex(of: argument) else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items.remove(at: removalIndex)
        case "sort":
            let arguments = try parseStarlarkSortArguments(
                rawArguments,
                expression: expression,
                constants: constants,
                functions: functions
            )
            guard arguments.positionalArguments.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items = try sortedStarlarkItems(
                items,
                keyFunction: arguments.keyFunction,
                reverse: arguments.reverse,
                constants: constants,
                functions: functions,
                expression: expression
            )
        case "reverse":
            guard rawArguments.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            items.reverse()
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkDeleteStatement(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("del ") else {
            return false
        }

        let targetText = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = try parseStarlarkIndexedAssignmentTarget(targetText, expression: trimmed),
              var existingValue = constants[target.root]
        else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        try deleteStarlarkIndexedValue(
            &existingValue,
            indexes: target.indexes,
            constants: constants,
            functions: functions,
            expression: trimmed
        )
        constants[target.root] = existingValue
        return true
    }

    private static func parseStarlarkListPopAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = topLevelEqualsIndex(in: trimmed) else {
            return false
        }

        let target = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(target) else {
            return false
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard valueText.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: valueText)
        else {
            return false
        }

        let callee = String(valueText[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodCallee = try parseStarlarkMethodCallee(
            callee,
            constants: constants,
            functions: functions,
            expression: trimmed
        ) else {
            return false
        }

        let receiverText = methodCallee.receiverText
        let methodName = methodCallee.methodName
        guard methodName == "pop" else {
            return false
        }
        guard isStarlarkIdentifier(receiverText),
              case var .array(items) = constants[receiverText]
        else {
            return false
        }

        let bodyStart = valueText.index(after: openIndex)
        let body = String(valueText[bodyStart..<valueText.index(before: valueText.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let item = try popStarlarkListItem(
            from: &items,
            rawArguments: rawArguments,
            constants: constants,
            functions: functions,
            expression: trimmed
        )
        constants[receiverText] = .array(items)
        constants[target] = item
        return true
    }

    private static func popStarlarkListItem(
        from items: inout [ConfigValue],
        rawArguments: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        guard rawArguments.count <= 1 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let itemIndex: Int
        if let rawArgument = rawArguments.first {
            itemIndex = try parseStarlarkInteger(
                rawArgument,
                constants: constants,
                functions: functions,
                expression: expression
            )
        } else {
            itemIndex = items.count - 1
        }
        guard itemIndex >= 0, items.indices.contains(itemIndex) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return items.remove(at: itemIndex)
    }

    private static func parseStarlarkIndexedAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = topLevelEqualsIndex(in: trimmed) else {
            return false
        }

        let targetText = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = try parseStarlarkIndexedAssignmentTarget(targetText, expression: trimmed) else {
            return false
        }

        guard var existingValue = constants[target.root]
        else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valueText.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }
        let assignedValue = try parsePolicyLiteral(valueText, constants: constants, functions: functions)

        try assignStarlarkIndexedValue(
            &existingValue,
            indexes: target.indexes,
            assignedValue: assignedValue,
            constants: constants,
            functions: functions,
            expression: trimmed
        )
        constants[target.root] = existingValue
        return true
    }

    private static func parseStarlarkIndexedAssignmentTarget(
        _ text: String,
        expression: String
    ) throws -> (root: String, indexes: [String])? {
        guard let firstOpenIndex = text.firstIndex(of: "[") else {
            return nil
        }
        let root = String(text[..<firstOpenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(root) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        var indexes: [String] = []
        var cursor = firstOpenIndex
        while cursor < text.endIndex {
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else {
                break
            }
            guard text[cursor] == "[",
                  let closeIndex = matchingIndexClose(from: cursor, in: text)
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let indexStart = text.index(after: cursor)
            let indexText = String(text[indexStart..<closeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !indexText.isEmpty,
                  !indexText.contains(":")
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            indexes.append(indexText)
            cursor = text.index(after: closeIndex)
        }

        guard !indexes.isEmpty else {
            return nil
        }
        return (root, indexes)
    }

    private static func matchingIndexClose(from openIndex: String.Index, in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = openIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
                if squareDepth == 0 && braceDepth == 0 && parenDepth == 0 {
                    return index
                }
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            default:
                break
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func assignStarlarkIndexedValue(
        _ value: inout ConfigValue,
        indexes: [String],
        assignedValue: ConfigValue,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        guard let indexText = indexes.first else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let remainingIndexes = Array(indexes.dropFirst())

        switch value {
        case var .array(items):
            let itemIndex = try parseStarlarkInteger(
                indexText,
                constants: constants,
                functions: functions,
                expression: expression
            )
            let resolvedIndex = itemIndex >= 0 ? itemIndex : items.count + itemIndex
            guard items.indices.contains(resolvedIndex) else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if remainingIndexes.isEmpty {
                items[resolvedIndex] = assignedValue
            } else {
                var nested = items[resolvedIndex]
                try assignStarlarkIndexedValue(
                    &nested,
                    indexes: remainingIndexes,
                    assignedValue: assignedValue,
                    constants: constants,
                    functions: functions,
                    expression: expression
                )
                items[resolvedIndex] = nested
            }
            value = .array(items)
        case var .table(items):
            let key = try parsePolicyLiteral(indexText, constants: constants, functions: functions)
            guard case let .string(key) = key else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if remainingIndexes.isEmpty {
                items[key] = assignedValue
            } else {
                guard var nested = items[key] else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                try assignStarlarkIndexedValue(
                    &nested,
                    indexes: remainingIndexes,
                    assignedValue: assignedValue,
                    constants: constants,
                    functions: functions,
                    expression: expression
                )
                items[key] = nested
            }
            value = .table(items)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func deleteStarlarkIndexedValue(
        _ value: inout ConfigValue,
        indexes: [String],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        guard let indexText = indexes.first else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let remainingIndexes = Array(indexes.dropFirst())

        switch value {
        case var .array(items):
            let itemIndex = try parseStarlarkInteger(
                indexText,
                constants: constants,
                functions: functions,
                expression: expression
            )
            let resolvedIndex = itemIndex >= 0 ? itemIndex : items.count + itemIndex
            guard items.indices.contains(resolvedIndex) else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if remainingIndexes.isEmpty {
                items.remove(at: resolvedIndex)
            } else {
                var nested = items[resolvedIndex]
                try deleteStarlarkIndexedValue(
                    &nested,
                    indexes: remainingIndexes,
                    constants: constants,
                    functions: functions,
                    expression: expression
                )
                items[resolvedIndex] = nested
            }
            value = .array(items)
        case var .table(items):
            let key = try parsePolicyLiteral(indexText, constants: constants, functions: functions)
            guard case let .string(key) = key else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if remainingIndexes.isEmpty {
                guard items.removeValue(forKey: key) != nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
            } else {
                guard var nested = items[key] else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                try deleteStarlarkIndexedValue(
                    &nested,
                    indexes: remainingIndexes,
                    constants: constants,
                    functions: functions,
                    expression: expression
                )
                items[key] = nested
            }
            value = .table(items)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkAugmentedAssignment(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let assignmentOperator = topLevelAugmentedAssignmentOperator(in: trimmed) else {
            return false
        }

        let target = String(trimmed[..<assignmentOperator.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(target),
              let existingValue = constants[target]
        else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let valueStart = assignmentOperator.range.upperBound
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valueText.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let rhs = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
        constants[target] = try evaluateStarlarkAugmentedAssignment(
            existingValue,
            rhs,
            operatorText: assignmentOperator.operatorText,
            expression: trimmed
        )
        return true
    }

    private static func evaluateStarlarkAugmentedAssignment(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        operatorText: String,
        expression: String
    ) throws -> ConfigValue {
        switch operatorText {
        case "+=":
            return try evaluateStarlarkAddition(lhs, rhs, expression: expression)
        case "-=":
            return try evaluateStarlarkSubtraction(lhs, rhs, expression: expression)
        case "*=":
            return try evaluateStarlarkMultiplication(lhs, rhs, expression: expression)
        case "/=":
            return try evaluateStarlarkDivision(lhs, rhs, expression: expression)
        case "//=":
            return try evaluateStarlarkFloorDivision(lhs, rhs, expression: expression)
        case "%=":
            return try evaluateStarlarkModulo(lhs, rhs, expression: expression)
        case "|=":
            return try evaluateStarlarkUnion(lhs, rhs, expression: expression)
        case "&=":
            return try evaluateStarlarkIntegerBitwise(lhs, rhs, operatorText: "&", expression: expression)
        case "^=":
            return try evaluateStarlarkIntegerBitwise(lhs, rhs, operatorText: "^", expression: expression)
        case "<<=":
            return try evaluateStarlarkIntegerShift(lhs, rhs, operatorText: "<<", expression: expression)
        case ">>=":
            return try evaluateStarlarkIntegerShift(lhs, rhs, operatorText: ">>", expression: expression)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseTopLevelLiteralAssignment(
        _ statement: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> (key: String, value: ConfigValue)? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let equalsIndex = trimmed.firstIndex(of: "=")
        else {
            return nil
        }

        let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(key) else {
            return nil
        }
        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return (key, try parsePolicyLiteral(valueText, constants: constants, functions: functions))
        } catch {
            return nil
        }
    }

    private static func parseStarlarkLambdaAssignment(
        _ statement: String
    ) throws -> (name: String, function: StarlarkFunction)? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let equalsIndex = topLevelEqualsIndex(in: trimmed)
        else {
            return nil
        }

        let name = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(name) else {
            return nil
        }

        let valueStart = trimmed.index(after: equalsIndex)
        let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let function = try parseStarlarkLambdaFunction(valueText, expression: trimmed) else {
            return nil
        }
        return (name, function)
    }

    private static func parseStarlarkLambdaFunction(
        _ text: String,
        expression: String
    ) throws -> StarlarkFunction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lambdaRange = topLevelKeywordRange("lambda", in: trimmed),
              lambdaRange.lowerBound == trimmed.startIndex
        else {
            return nil
        }
        guard let colonIndex = topLevelColonIndex(in: trimmed) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let parametersText = String(trimmed[lambdaRange.upperBound..<colonIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(trimmed[trimmed.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        return StarlarkFunction(
            parameters: try parseStarlarkFunctionParameters(parametersText, expression: expression),
            body: ["return \(body)"]
        )
    }

    private static func parseTopLevelFunctionHeader(_ statement: String) throws -> (
        name: String,
        parameters: [StarlarkFunctionParameter]
    )? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":"),
              let defRange = topLevelKeywordRange("def", in: trimmed),
              defRange.lowerBound == trimmed.startIndex
        else {
            return nil
        }

        let headerEnd = trimmed.index(before: trimmed.endIndex)
        let signature = String(trimmed[defRange.upperBound..<headerEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard signature.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: signature)
        else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let name = String(signature[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(name) else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }

        let parametersStart = signature.index(after: openIndex)
        let parametersText = String(signature[parametersStart..<signature.index(before: signature.endIndex)])
        return (
            name,
            try parseStarlarkFunctionParameters(parametersText, expression: trimmed)
        )
    }

    private static func parseStarlarkFunctionParameters(
        _ parametersText: String,
        expression: String
    ) throws -> [StarlarkFunctionParameter] {
        var sawDefault = false
        var sawStarMarker = false
        var sawVarargs = false
        var sawKwargs = false
        let parameters = try splitTopLevel(parametersText, separator: ",").compactMap { rawParameter -> StarlarkFunctionParameter? in
            let parameterText = rawParameter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !parameterText.isEmpty else {
                return nil
            }

            if parameterText == "*" {
                guard !sawStarMarker, !sawVarargs, !sawKwargs else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawStarMarker = true
                sawDefault = false
                return nil
            }

            let name: String
            let defaultValueExpression: String?
            let kind: StarlarkFunctionParameter.Kind
            if parameterText.hasPrefix("**") {
                guard !sawKwargs else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let nameStart = parameterText.index(parameterText.startIndex, offsetBy: 2)
                name = String(parameterText[nameStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                defaultValueExpression = nil
                kind = .kwargs
                sawKwargs = true
            } else if parameterText.hasPrefix("*") {
                guard !sawStarMarker, !sawVarargs, !sawKwargs else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let nameStart = parameterText.index(after: parameterText.startIndex)
                name = String(parameterText[nameStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                defaultValueExpression = nil
                kind = .varargs
                sawVarargs = true
                sawStarMarker = true
                sawDefault = false
            } else {
                guard !sawKwargs else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                kind = sawStarMarker ? .keywordOnly : .positionalOrKeyword
                if kind == .positionalOrKeyword,
                   sawDefault,
                   topLevelEqualsIndex(in: parameterText) == nil {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }

                if let equalsIndex = topLevelEqualsIndex(in: parameterText) {
                    sawDefault = kind == .positionalOrKeyword
                    name = String(parameterText[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let valueStart = parameterText.index(after: equalsIndex)
                    let defaultText = String(parameterText[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !defaultText.isEmpty else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    defaultValueExpression = defaultText
                } else {
                    name = parameterText
                    defaultValueExpression = nil
                }
            }
            guard isStarlarkIdentifier(name) else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return StarlarkFunctionParameter(name: name, defaultValueExpression: defaultValueExpression, kind: kind)
        }
        guard Set(parameters.map(\.name)).count == parameters.count else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        if let kwargsIndex = parameters.lastIndex(where: { $0.kind == .kwargs }),
           kwargsIndex != parameters.indices.last {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return parameters
    }

    private static func parseStarlarkFunction(
        parameters: [StarlarkFunctionParameter],
        body: [String]
    ) throws -> StarlarkFunction {
        let nonEmpty = body
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard nonEmpty.contains(where: { statement in
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            return topLevelKeywordRange("return", in: trimmed)?.lowerBound == trimmed.startIndex
        })
        else {
            throw ConfigOverrideError.invalidLiteral(body.joined(separator: "\n"))
        }
        return StarlarkFunction(parameters: parameters, body: nonEmpty)
    }

    private static func parseTopLevelForHeader(_ statement: String) throws -> (
        targets: [String],
        iterableText: String
    )? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":"),
              let forRange = topLevelKeywordRange("for", in: trimmed),
              forRange.lowerBound == trimmed.startIndex,
              let inRange = topLevelKeywordRange("in", in: trimmed, startingAt: forRange.upperBound)
        else {
            return nil
        }

        let targetText = String(trimmed[forRange.upperBound..<inRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let iterableEnd = trimmed.index(before: trimmed.endIndex)
        let iterableText = String(trimmed[inRange.upperBound..<iterableEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = try parseStarlarkLoopTargets(targetText, expression: trimmed)
        guard !iterableText.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }
        return (targets, iterableText)
    }

    private static func parseStarlarkLoopTargets(_ text: String, expression: String) throws -> [String] {
        var trimmed = strippingEnclosingParentheses(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
        if trimmed.hasPrefix("["),
           trimmed.hasSuffix("]"),
           enclosesWholeExpression(trimmed) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let targetPieces = splitTopLevel(trimmed, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !targetPieces.isEmpty,
              targetPieces.allSatisfy(isStarlarkIdentifier)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return targetPieces
    }

    private static func bindStarlarkLoopTargets(
        _ targets: [String],
        to item: ConfigValue,
        constants: inout [String: ConfigValue],
        expression: String
    ) throws {
        if targets.count == 1 {
            constants[targets[0]] = item
            return
        }

        guard case let .array(values) = item,
              values.count == targets.count
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        for (target, value) in zip(targets, values) {
            constants[target] = value
        }
    }

    private static func parseTopLevelIfHeader(_ statement: String) throws -> String? {
        try parseTopLevelConditionalHeader(statement, keyword: "if")
    }

    private static func parseTopLevelElifHeader(_ statement: String) throws -> String? {
        try parseTopLevelConditionalHeader(statement, keyword: "elif")
    }

    private static func parseTopLevelConditionalHeader(
        _ statement: String,
        keyword: String
    ) throws -> String? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":"),
              let keywordRange = topLevelKeywordRange(keyword, in: trimmed),
              keywordRange.lowerBound == trimmed.startIndex
        else {
            return nil
        }
        let conditionEnd = trimmed.index(before: trimmed.endIndex)
        let condition = String(trimmed[keywordRange.upperBound..<conditionEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condition.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(trimmed)
        }
        return condition
    }

    private static func isTopLevelElseHeader(_ statement: String) -> Bool {
        statement.trimmingCharacters(in: .whitespacesAndNewlines) == "else:"
    }

    private static func collectIndentedBlock(
        after headerIndex: Int,
        in statements: [String],
        parentIndent: Int,
        identifier: String,
        blockName: String
    ) throws -> (body: [String], nextIndex: Int) {
        var body: [String] = []
        var index = headerIndex + 1
        while index < statements.count {
            let candidate = statements[index]
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body.append(candidate)
                index += 1
                continue
            }
            guard indentationCount(candidate) > parentIndent else {
                break
            }
            body.append(candidate)
            index += 1
        }

        guard body.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ExecPolicyError.invalidSyntax("\(identifier): \(blockName) body cannot be empty")
        }
        return (body, index)
    }

    private static func indentationCount(_ statement: String) -> Int {
        var count = 0
        for character in statement {
            switch character {
            case " ":
                count += 1
            case "\t":
                count += 4
            default:
                return count
            }
        }
        return count
    }

    private static func topLevelStatements(from source: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false

        for character in source {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            case "\n" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                statements.append(current)
                current = ""
            case ";" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                statements.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        statements.append(current)
        return statements
    }

    private static func isStarlarkIdentifier(_ value: String) -> Bool {
        guard let first = value.first,
              first == "_" || first.isLetter
        else {
            return false
        }
        return value.dropFirst().allSatisfy(isStarlarkIdentifierCharacter)
    }

    private static func parseArguments(
        _ body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        positionalNames: [String]
    ) throws -> [String: ConfigValue] {
        var arguments: [String: ConfigValue] = [:]
        var positionalIndex = 0
        var sawNamedArgument = false
        for piece in splitTopLevel(body, separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key: String
            let valueText: String
            if let equalsIndex = topLevelEqualsIndex(in: trimmed) {
                sawNamedArgument = true
                key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = trimmed.index(after: equalsIndex)
                valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                guard !sawNamedArgument else {
                    throw ExecPolicyError.invalidSyntax("positional argument follows keyword argument: \(trimmed)")
                }
                guard positionalIndex < positionalNames.count else {
                    throw ExecPolicyError.invalidSyntax("too many positional arguments")
                }
                key = positionalNames[positionalIndex]
                valueText = trimmed
                positionalIndex += 1
            }

            guard arguments[key] == nil else {
                throw ExecPolicyError.invalidSyntax("duplicate argument: \(key)")
            }
            arguments[key] = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
        }
        return arguments
    }

    private static func topLevelEqualsIndex(in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            case "=" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                let previous = index > text.startIndex ? text[text.index(before: index)] : nil
                let nextIndex = text.index(after: index)
                let next = nextIndex < text.endIndex ? text[nextIndex] : nil
                guard !["=", "!", "<", ">"].contains(previous), next != "=" else {
                    return nil
                }
                return index
            default:
                break
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func topLevelAugmentedAssignmentOperator(in text: String) -> (operatorText: String, range: Range<String.Index>)? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            case "+", "-", "*", "/", "%", "|", "&", "^", "<", ">":
                guard squareDepth == 0 && braceDepth == 0 && parenDepth == 0 else {
                    break
                }
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else {
                    break
                }
                if character == "/", text[nextIndex] == "/" {
                    let equalsIndex = text.index(after: nextIndex)
                    if equalsIndex < text.endIndex, text[equalsIndex] == "=" {
                        return ("//=", index..<text.index(after: equalsIndex))
                    }
                } else if (character == "<" || character == ">"), text[nextIndex] == character {
                    let equalsIndex = text.index(after: nextIndex)
                    if equalsIndex < text.endIndex, text[equalsIndex] == "=" {
                        return ("\(character)\(character)=", index..<text.index(after: equalsIndex))
                    }
                } else if character != "<", character != ">", text[nextIndex] == "=" {
                    return ("\(character)=", index..<text.index(after: nextIndex))
                }
            default:
                break
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func requireStringArgument(
        _ arguments: [String: ConfigValue],
        key: String,
        function: String
    ) throws -> String {
        guard let value = arguments[key] else {
            throw ExecPolicyError.invalidRule("\(function) missing \(key)")
        }
        guard case let .string(raw) = value else {
            throw ExecPolicyError.invalidRule("\(function) \(key) must be a string")
        }
        return raw
    }

    private static func parseOptionalJustification(_ value: ConfigValue?) throws -> String? {
        guard let value else {
            return nil
        }
        guard case let .string(raw) = value else {
            throw ExecPolicyError.invalidRule("justification must be a string")
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExecPolicyError.invalidRule("justification cannot be empty")
        }
        return raw
    }

    private static func parsePolicyLiteral(
        _ valueText: String,
        constants: [String: ConfigValue] = [:],
        functions: [String: StarlarkFunction] = [:]
    ) throws -> ConfigValue {
        let rawTrimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tuple = try parseStarlarkTupleLiteral(rawTrimmed, constants: constants, functions: functions) {
            return tuple
        }
        let trimmed = strippingEnclosingParentheses(from: rawTrimmed)
        if trimmed == "True" {
            return .bool(true)
        }
        if trimmed == "False" {
            return .bool(false)
        }
        if trimmed == "None" {
            return ConfigValue.none
        }
        if let conditional = try parseStarlarkConditionalExpression(
            trimmed,
            constants: constants,
            functions: functions
        ) {
            return conditional
        }
        if let boolean = try parseStarlarkBooleanExpression(
            trimmed,
            constants: constants,
            functions: functions
        ) {
            return boolean
        }
        if let bitwise = try parseStarlarkBitwiseOrExpression(
            trimmed,
            constants: constants,
            functions: functions
        ) {
            return bitwise
        }
        if let bitwise = try parseStarlarkBitwiseXorExpression(trimmed, constants: constants, functions: functions) {
            return bitwise
        }
        if let bitwise = try parseStarlarkBitwiseAndExpression(trimmed, constants: constants, functions: functions) {
            return bitwise
        }
        if let shift = try parseStarlarkShiftExpression(trimmed, constants: constants, functions: functions) {
            return shift
        }
        if let additive = try parseStarlarkAdditiveExpression(trimmed, constants: constants, functions: functions) {
            return additive
        }
        if let multiplicative = try parseStarlarkMultiplicativeExpression(trimmed, constants: constants, functions: functions) {
            return multiplicative
        }
        if let unary = try parseStarlarkUnaryNumericExpression(trimmed, constants: constants, functions: functions) {
            return unary
        }
        if let constant = constants[trimmed] {
            return constant
        }
        if let range = try parseStarlarkRangeCall(trimmed, constants: constants, functions: functions) {
            return range
        }
        if let length = try parseStarlarkLenCall(trimmed, constants: constants, functions: functions) {
            return length
        }
        if let getattrMethodCall = try parseStarlarkGetAttributeMethodCall(trimmed, constants: constants, functions: functions) {
            return getattrMethodCall
        }
        if let dictMethodCall = try parseStarlarkDictMethodCall(trimmed, constants: constants, functions: functions) {
            return dictMethodCall
        }
        if let listMethodCall = try parseStarlarkListMethodCall(trimmed, constants: constants, functions: functions) {
            return listMethodCall
        }
        if let methodCall = try parseStarlarkStringMethodCall(trimmed, constants: constants, functions: functions) {
            return methodCall
        }
        if let builtinCall = try parseStarlarkBuiltinFunctionCall(trimmed, constants: constants, functions: functions) {
            return builtinCall
        }
        if let functionCall = try parseStarlarkFunctionCall(trimmed, constants: constants, functions: functions) {
            return functionCall
        }
        if let indexed = try parseStarlarkIndexExpression(trimmed, constants: constants, functions: functions) {
            return indexed
        }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let body = String(trimmed.dropFirst().dropLast())
            if let comprehension = try parseStarlarkListComprehension(
                body,
                constants: constants,
                functions: functions
            ) {
                return .array(comprehension)
            }
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .array([])
            }
            return .array(try splitTopLevel(body, separator: ",").compactMap { item in
                guard !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return try parsePolicyLiteral(item, constants: constants, functions: functions)
            })
        }
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return try parseStarlarkDictLiteral(trimmed, constants: constants, functions: functions)
        }
        if let interpolated = try parseStarlarkFStringLiteral(trimmed, constants: constants, functions: functions) {
            return .string(interpolated)
        }

        do {
            return try ConfigValueParser.parseTomlLiteral(trimmed)
        } catch {
            return try ConfigValueParser.parseTomlLiteral(removingTrailingArrayCommas(from: trimmed))
        }
    }

    private static func parseStarlarkTupleLiteral(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasPrefix("("),
              text.hasSuffix(")"),
              enclosesWholeExpression(text)
        else {
            return nil
        }

        let body = String(text.dropFirst().dropLast())
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return .array([])
        }

        let elements = splitTopLevel(body, separator: ",")
        guard elements.count > 1 else {
            return nil
        }

        return .array(try elements.compactMap { item in
            let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedItem.isEmpty else {
                return nil
            }
            return try parsePolicyLiteral(trimmedItem, constants: constants, functions: functions)
        })
    }

    private static func strippingEnclosingParentheses(from text: String) -> String {
        var result = text
        while result.hasPrefix("("), result.hasSuffix(")"), enclosesWholeExpression(result) {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func enclosesWholeExpression(_ text: String) -> Bool {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
                if parenDepth == 0 && text.index(after: index) != text.endIndex {
                    return false
                }
            default:
                break
            }

            if squareDepth < 0 || braceDepth < 0 || parenDepth < 0 {
                return false
            }
            index = text.index(after: index)
        }

        return squareDepth == 0 && braceDepth == 0 && parenDepth == 0
    }

    private static func parseStarlarkFStringLiteral(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> String? {
        guard text.count >= 3,
              let prefix = text.first,
              prefix == "f" || prefix == "F"
        else {
            return nil
        }
        let quoteIndex = text.index(after: text.startIndex)
        let quote = text[quoteIndex]
        guard quote == "\"" || quote == "'" else {
            return nil
        }
        guard index(afterQuotedStringAt: quoteIndex, in: text) == text.endIndex,
              text.index(before: text.endIndex) != quoteIndex
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = ""
        var index = text.index(after: quoteIndex)
        let end = text.index(before: text.endIndex)
        while index < end {
            let character = text[index]
            if character == "\\" {
                let nextIndex = text.index(after: index)
                guard nextIndex < end else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                result.append(unescapedFStringCharacter(text[nextIndex]))
                index = text.index(after: nextIndex)
                continue
            }
            if character == "{" {
                let nextIndex = text.index(after: index)
                if nextIndex < end, text[nextIndex] == "{" {
                    result.append("{")
                    index = text.index(after: nextIndex)
                    continue
                }
                guard let closeIndex = matchingFStringExpressionClose(from: nextIndex, end: end, in: text) else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                let expression = String(text[nextIndex..<closeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !expression.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                let value = try parsePolicyLiteral(expression, constants: constants, functions: functions)
                result.append(try starlarkInterpolatedString(value, expression: text))
                index = text.index(after: closeIndex)
                continue
            }
            if character == "}" {
                let nextIndex = text.index(after: index)
                guard nextIndex < end, text[nextIndex] == "}" else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                result.append("}")
                index = text.index(after: nextIndex)
                continue
            }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func starlarkInterpolatedString(_ value: ConfigValue, expression: String) throws -> String {
        switch value {
        case let .string(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "True" : "False"
        case let .range(start, stop, step):
            return starlarkRangeDisplay(start: start, stop: stop, step: step)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func matchingFStringExpressionClose(
        from start: String.Index,
        end: String.Index,
        in text: String
    ) -> String.Index? {
        var index = start
        var quote: Character?
        var previousWasBackslash = false
        while index < end {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "}" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func unescapedFStringCharacter(_ character: Character) -> Character {
        switch character {
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        default:
            return character
        }
    }

    private static func parseStarlarkLenCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let name = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard name == "len" else {
            return nil
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard rawArguments.count == 1,
              let argument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let value = try parsePolicyLiteral(argument, constants: constants, functions: functions)
        switch value {
        case let .string(value):
            return .integer(Int64(value.count))
        case let .array(items):
            return .integer(Int64(items.count))
        case let .table(items):
            return .integer(Int64(items.count))
        case let .range(start, stop, step):
            return .integer(Int64(starlarkRangeLength(start: start, stop: stop, step: step)))
        default:
            throw ConfigOverrideError.invalidLiteral(text)
        }
    }

    private static func parseStarlarkRangeCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let name = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard name == "range" else {
            return nil
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard (1...3).contains(rawArguments.count) else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let integers = try rawArguments.map { rawArgument in
            try parseStarlarkInt32(rawArgument, constants: constants, functions: functions, expression: text)
        }
        let start: Int
        let end: Int
        let step: Int
        switch integers.count {
        case 1:
            start = 0
            end = integers[0]
            step = 1
        case 2:
            start = integers[0]
            end = integers[1]
            step = 1
        case 3:
            start = integers[0]
            end = integers[1]
            step = integers[2]
        default:
            throw ConfigOverrideError.invalidLiteral(text)
        }
        guard step != 0 else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        return .range(start: start, stop: end, step: step)
    }

    private static func parseStarlarkStringMethodCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let callee = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodDotIndex = topLevelMethodDotIndex(in: callee) else {
            return nil
        }

        let receiverText = String(callee[..<methodDotIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let methodStart = callee.index(after: methodDotIndex)
        let methodName = String(callee[methodStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !receiverText.isEmpty,
              ["join", "elems", "codepoints", "format", "startswith", "endswith", "lower", "upper", "capitalize", "title", "strip", "lstrip", "rstrip", "split", "rsplit", "splitlines", "replace", "removeprefix", "removesuffix", "count", "find", "index", "rfind", "rindex", "partition", "rpartition", "isalnum", "isalpha", "isdigit", "islower", "isspace", "istitle", "isupper"].contains(methodName)
        else {
            return nil
        }

        let receiver = try parsePolicyLiteral(receiverText, constants: constants, functions: functions)
        guard case let .string(receiver) = receiver else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch methodName {
        case "join":
            guard rawArguments.count == 1,
                  let rawArgument = rawArguments.first
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            guard case let .array(items) = argument else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let strings = try items.map { item -> String in
                guard case let .string(value) = item else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                return value
            }
            return .string(strings.joined(separator: receiver))
        case "elems":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .array(receiver.unicodeScalars.map { .string(String($0)) })
        case "codepoints":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .array(receiver.unicodeScalars.map { .integer(Int64($0.value)) })
        case "format":
            let arguments = try parseStringFormatMethodArguments(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
            return .string(try formattingStarlarkString(receiver, arguments: arguments, expression: text))
        case "startswith":
            let prefixes = try parseStringOrTupleMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .bool(prefixes.contains { receiver.hasPrefix($0) })
        case "endswith":
            let suffixes = try parseStringOrTupleMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .bool(suffixes.contains { receiver.hasSuffix($0) })
        case "lower":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .string(receiver.lowercased())
        case "upper":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .string(receiver.uppercased())
        case "capitalize":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .string(capitalizingStarlarkString(receiver))
        case "title":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .string(titlecasingStarlarkString(receiver))
        case "strip":
            let characters = try parseOptionalStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .string(trimmingStarlarkString(receiver, characters: characters, edges: [.leading, .trailing]))
        case "lstrip":
            let characters = try parseOptionalStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .string(trimmingStarlarkString(receiver, characters: characters, edges: .leading))
        case "rstrip":
            let characters = try parseOptionalStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .string(trimmingStarlarkString(receiver, characters: characters, edges: .trailing))
        case "split":
            let arguments = try parseStringSplitMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            return .array(splittingStarlarkString(receiver, separator: arguments.separator, maxsplit: arguments.maxsplit, direction: .forward).map(ConfigValue.string))
        case "rsplit":
            let arguments = try parseStringSplitMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            return .array(splittingStarlarkString(receiver, separator: arguments.separator, maxsplit: arguments.maxsplit, direction: .reverse).map(ConfigValue.string))
        case "splitlines":
            let keepends = try parseStringSplitLinesKeependsArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .array(splittingStarlarkLines(receiver, keepends: keepends).map(ConfigValue.string))
        case "replace":
            guard rawArguments.count == 2 || rawArguments.count == 3 else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let oldValue = try parseStringMethodArgument(
                rawArguments[0],
                expression: text,
                constants: constants,
                functions: functions
            )
            let newValue = try parseStringMethodArgument(
                rawArguments[1],
                expression: text,
                constants: constants,
                functions: functions
            )
            let count = try rawArguments.count == 3
                ? parseStarlarkInteger(rawArguments[2], constants: constants, functions: functions, expression: text)
                : -1
            return .string(replacingStarlarkString(receiver, oldValue: oldValue, newValue: newValue, count: count))
        case "removeprefix":
            let prefix = try parseSingleStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .string(removingStarlarkPrefix(prefix, from: receiver))
        case "removesuffix":
            let suffix = try parseSingleStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .string(removingStarlarkSuffix(suffix, from: receiver))
        case "count":
            let arguments = try parseStringSearchMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            guard let window = starlarkStringSearchWindow(receiver, start: arguments.start, end: arguments.end) else {
                return .integer(0)
            }
            return .integer(Int64(countingStarlarkStringMatches(arguments.needle, in: window.haystack)))
        case "find":
            let arguments = try parseStringSearchMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            return .integer(Int64(findingStarlarkString(arguments.needle, in: receiver, start: arguments.start, end: arguments.end, direction: .forward) ?? -1))
        case "index":
            let arguments = try parseStringSearchMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            guard let foundIndex = findingStarlarkString(arguments.needle, in: receiver, start: arguments.start, end: arguments.end, direction: .forward) else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return .integer(Int64(foundIndex))
        case "rfind":
            let arguments = try parseStringSearchMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            return .integer(Int64(findingStarlarkString(arguments.needle, in: receiver, start: arguments.start, end: arguments.end, direction: .reverse) ?? -1))
        case "rindex":
            let arguments = try parseStringSearchMethodArguments(rawArguments, expression: text, constants: constants, functions: functions)
            guard let foundIndex = findingStarlarkString(arguments.needle, in: receiver, start: arguments.start, end: arguments.end, direction: .reverse) else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return .integer(Int64(foundIndex))
        case "partition":
            let separator = try parseSingleStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .array(try partitioningStarlarkString(receiver, separator: separator, direction: .forward, expression: text).map(ConfigValue.string))
        case "rpartition":
            let separator = try parseSingleStringMethodArgument(rawArguments, expression: text, constants: constants, functions: functions)
            return .array(try partitioningStarlarkString(receiver, separator: separator, direction: .reverse, expression: text).map(ConfigValue.string))
        case "isalnum":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsAlphanumeric(receiver))
        case "isalpha":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsAlphabetic(receiver))
        case "isdigit":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsNumeric(receiver))
        case "islower":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsLowercase(receiver))
        case "isspace":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsWhitespace(receiver))
        case "istitle":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsTitlecase(receiver))
        case "isupper":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .bool(starlarkStringIsUppercase(receiver))
        default:
            return nil
        }
    }

    private static func parseStarlarkGetAttributeMethodCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let callee = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard callee.hasSuffix(")"),
              let getattrOpenIndex = matchingTopLevelCallOpen(in: callee)
        else {
            return nil
        }

        let calleeName = String(callee[..<getattrOpenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard calleeName == "getattr" else {
            return nil
        }

        let getattrBodyStart = callee.index(after: getattrOpenIndex)
        let getattrBody = String(callee[getattrBodyStart..<callee.index(before: callee.endIndex)])
        let getattrArguments = splitTopLevel(getattrBody, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard getattrArguments.count == 2 || getattrArguments.count == 3 else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let receiverText = getattrArguments[0]
        let receiver = try parsePolicyLiteral(receiverText, constants: constants, functions: functions)
        let attribute = try parsePolicyLiteral(getattrArguments[1], constants: constants, functions: functions)
        guard case let .string(attributeName) = attribute,
              starlarkAttributeNames(for: receiver).contains(attributeName)
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let callBodyStart = text.index(after: openIndex)
        let callBody = String(text[callBodyStart..<text.index(before: text.endIndex)])
        let methodCall = "(\(receiverText)).\(attributeName)(\(callBody))"
        if let dictMethodCall = try parseStarlarkDictMethodCall(methodCall, constants: constants, functions: functions) {
            return dictMethodCall
        }
        if let listMethodCall = try parseStarlarkListMethodCall(methodCall, constants: constants, functions: functions) {
            return listMethodCall
        }
        if let stringMethodCall = try parseStarlarkStringMethodCall(methodCall, constants: constants, functions: functions) {
            return stringMethodCall
        }
        throw ConfigOverrideError.invalidLiteral(text)
    }

    private static func parseStarlarkListMethodCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let callee = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodDotIndex = topLevelMethodDotIndex(in: callee) else {
            return nil
        }

        let receiverText = String(callee[..<methodDotIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let methodStart = callee.index(after: methodDotIndex)
        let methodName = String(callee[methodStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let noneReturningMethods = starlarkListMutationMethods.filter { $0 != "pop" }
        guard !receiverText.isEmpty,
              methodName == "index" || noneReturningMethods.contains(methodName)
        else {
            return nil
        }
        if noneReturningMethods.contains(methodName),
           isStarlarkIdentifier(strippingEnclosingParentheses(from: receiverText)) {
            return nil
        }

        let receiver = try parsePolicyLiteral(receiverText, constants: constants, functions: functions)
        guard case var .array(items) = receiver else {
            return nil
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if noneReturningMethods.contains(methodName) {
            try applyStarlarkListMutation(
                methodName: methodName,
                to: &items,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: text
            )
            return ConfigValue.none
        }

        guard (1...3).contains(rawArguments.count) else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let needle = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
        let start = try rawArguments.count >= 2
            ? parseOptionalStarlarkSearchBound(
                rawArguments[1],
                constants: constants,
                functions: functions,
                expression: text
            )
            : nil
        let end = try rawArguments.count == 3
            ? parseOptionalStarlarkSearchBound(
                rawArguments[2],
                constants: constants,
                functions: functions,
                expression: text
            )
            : nil
        let lowerBound = normalizedStarlarkSearchBound(start ?? 0, count: items.count)
        let upperBound = normalizedStarlarkSearchBound(end ?? items.count, count: items.count)
        guard lowerBound <= upperBound else {
            throw ConfigOverrideError.invalidLiteral(text)
        }
        for index in lowerBound..<upperBound where items[index] == needle {
            return .integer(Int64(index))
        }
        throw ConfigOverrideError.invalidLiteral(text)
    }

    private static func parseStarlarkDictMethodCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let callee = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let methodDotIndex = topLevelMethodDotIndex(in: callee) else {
            return nil
        }

        let receiverText = String(callee[..<methodDotIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let methodStart = callee.index(after: methodDotIndex)
        let methodName = String(callee[methodStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let mutatingExpressionMethods = ["pop", "popitem", "setdefault"] + starlarkDictNoneMutationMethods
        guard !receiverText.isEmpty,
              ["get", "keys", "values", "items"].contains(methodName) ||
                mutatingExpressionMethods.contains(methodName)
        else {
            return nil
        }
        if mutatingExpressionMethods.contains(methodName),
           isStarlarkIdentifier(strippingEnclosingParentheses(from: receiverText)) {
            return nil
        }

        let receiver = try parsePolicyLiteral(receiverText, constants: constants, functions: functions)
        guard case let .table(items) = receiver else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch methodName {
        case "get":
            guard rawArguments.count == 1 || rawArguments.count == 2,
                  let rawKey = rawArguments.first
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let key = try parsePolicyLiteral(rawKey, constants: constants, functions: functions)
            guard case let .string(key) = key else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            if let value = items[key] {
                return value
            }
            if rawArguments.count == 2 {
                return try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
            }
            return ConfigValue.none
        case "keys":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .array(items.keys.map(ConfigValue.string))
        case "values":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .array(Array(items.values))
        case "items":
            try requireNoStringMethodArguments(rawArguments, expression: text)
            return .array(items.map { key, value in .array([.string(key), value]) })
        case "pop":
            var mutableItems = items
            return try popStarlarkDictValue(
                from: &mutableItems,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: text
            )
        case "popitem":
            var mutableItems = items
            return try popFirstStarlarkDictItem(from: &mutableItems, rawArguments: rawArguments, expression: text)
        case "setdefault":
            var mutableItems = items
            return try setDefaultStarlarkDictValue(
                in: &mutableItems,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: text
            )
        case "update", "clear":
            var mutableItems = items
            try applyStarlarkDictNoneMutation(
                methodName: methodName,
                to: &mutableItems,
                rawArguments: rawArguments,
                constants: constants,
                functions: functions,
                expression: text
            )
            return ConfigValue.none
        default:
            return nil
        }
    }

    private struct StarlarkTrimEdges: OptionSet {
        let rawValue: Int

        static let leading = StarlarkTrimEdges(rawValue: 1 << 0)
        static let trailing = StarlarkTrimEdges(rawValue: 1 << 1)
    }

    private static func requireNoStringMethodArguments(_ rawArguments: [String], expression: String) throws {
        guard rawArguments.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseOptionalStringMethodArgument(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> String? {
        if rawArguments.isEmpty {
            return nil
        }
        return try parseSingleStringMethodArgument(
            rawArguments,
            expression: expression,
            constants: constants,
            functions: functions
        )
    }

    private static func parseSingleStringMethodArgument(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> String {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .string(value) = argument else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return value
    }

    private static func parseStringMethodArgument(
        _ rawArgument: String,
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> String {
        let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .string(value) = argument else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return value
    }

    private static func parseStringOrTupleMethodArgument(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> [String] {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        switch argument {
        case let .string(value):
            return [value]
        case let .array(items):
            return try items.map { item in
                guard case let .string(value) = item else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                return value
            }
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStringFormatMethodArguments(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> StarlarkFormatArguments {
        var positional: [ConfigValue] = []
        var named: [String: ConfigValue] = [:]
        var sawNamedArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawNamedArgument = true
                let key = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard isStarlarkIdentifier(key), named[key] == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let valueStart = rawArgument.index(after: equalsIndex)
                let valueText = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                named[key] = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
            } else {
                guard !sawNamedArgument else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                positional.append(try parsePolicyLiteral(rawArgument, constants: constants, functions: functions))
            }
        }

        return StarlarkFormatArguments(positional: positional, named: named)
    }

    private static func parseStringSearchMethodArguments(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> (needle: String, start: Int?, end: Int?) {
        guard (1...3).contains(rawArguments.count) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let needle = try parseStringMethodArgument(
            rawArguments[0],
            expression: expression,
            constants: constants,
            functions: functions
        )
        let start = try rawArguments.count >= 2
            ? parseOptionalStarlarkSearchBound(
                rawArguments[1],
                constants: constants,
                functions: functions,
                expression: expression
            )
            : nil
        let end = try rawArguments.count == 3
            ? parseOptionalStarlarkSearchBound(
                rawArguments[2],
                constants: constants,
                functions: functions,
                expression: expression
            )
            : nil
        return (needle, start, end)
    }

    private static func parseOptionalStarlarkSearchBound(
        _ rawArgument: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> Int? {
        if rawArgument == "None" {
            return nil
        }
        return try parseStarlarkInteger(rawArgument, constants: constants, functions: functions, expression: expression)
    }

    private static func parseStringSplitMethodArguments(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> (separator: String?, maxsplit: Int?) {
        guard rawArguments.count <= 2 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let separator: String?
        if rawArguments.isEmpty || rawArguments[0] == "None" {
            separator = nil
        } else {
            separator = try parseStringMethodArgument(
                rawArguments[0],
                expression: expression,
                constants: constants,
                functions: functions
            )
            if separator?.isEmpty == true {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }

        let maxsplit = try rawArguments.count == 2
            ? parseStarlarkInteger(rawArguments[1], constants: constants, functions: functions, expression: expression)
            : nil
        return (separator, maxsplit)
    }

    private static func parseStringSplitLinesKeependsArgument(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        guard rawArguments.count <= 1 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        guard let rawArgument = rawArguments.first else {
            return false
        }
        let argument = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .bool(keepends) = argument else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return keepends
    }

    private static func trimmingStarlarkString(
        _ string: String,
        characters: String?,
        edges: StarlarkTrimEdges
    ) -> String {
        let shouldTrim: (Character) -> Bool
        if let characters {
            let trimCharacters = Set(characters)
            shouldTrim = { trimCharacters.contains($0) }
        } else {
            shouldTrim = { $0.isWhitespace || $0.isNewline }
        }

        var lowerBound = string.startIndex
        var upperBound = string.endIndex
        if edges.contains(.leading) {
            while lowerBound < upperBound, shouldTrim(string[lowerBound]) {
                lowerBound = string.index(after: lowerBound)
            }
        }
        if edges.contains(.trailing) {
            while upperBound > lowerBound {
                let previous = string.index(before: upperBound)
                guard shouldTrim(string[previous]) else {
                    break
                }
                upperBound = previous
            }
        }
        return String(string[lowerBound..<upperBound])
    }

    private static func replacingStarlarkString(
        _ string: String,
        oldValue: String,
        newValue: String,
        count: Int
    ) -> String {
        guard count != 0 else {
            return string
        }
        if oldValue.isEmpty {
            return replacingEmptyStarlarkString(string, newValue: newValue, count: count)
        }
        guard count > 0 else {
            return string.replacingOccurrences(of: oldValue, with: newValue)
        }

        var result = ""
        var cursor = string.startIndex
        var remaining = count
        while remaining > 0,
              let range = string.range(of: oldValue, range: cursor..<string.endIndex) {
            result += string[cursor..<range.lowerBound]
            result += newValue
            cursor = range.upperBound
            remaining -= 1
        }
        result += string[cursor..<string.endIndex]
        return result
    }

    private static func capitalizingStarlarkString(_ string: String) -> String {
        var result = ""
        var isFirstScalar = true
        for scalar in string.unicodeScalars {
            let scalarString = String(scalar)
            result += isFirstScalar ? scalarString.uppercased() : scalarString.lowercased()
            isFirstScalar = false
        }
        return result
    }

    private static func titlecasingStarlarkString(_ string: String) -> String {
        var lastNonAlphabetic = true
        var result = ""
        for scalar in string.unicodeScalars {
            let scalarString = String(scalar)
            if !scalar.properties.isAlphabetic {
                lastNonAlphabetic = true
                result += scalarString.lowercased()
            } else if lastNonAlphabetic {
                result += scalarString.uppercased()
                lastNonAlphabetic = false
            } else {
                result += scalarString.lowercased()
            }
        }
        return result
    }

    private static func removingStarlarkPrefix(_ prefix: String, from string: String) -> String {
        guard !prefix.isEmpty,
              let range = string.range(of: prefix, options: .anchored)
        else {
            return string
        }
        return String(string[range.upperBound...])
    }

    private static func removingStarlarkSuffix(_ suffix: String, from string: String) -> String {
        guard !suffix.isEmpty,
              let range = string.range(of: suffix, options: .backwards),
              range.upperBound == string.endIndex
        else {
            return string
        }
        return String(string[..<range.lowerBound])
    }

    private enum StarlarkStringSearchDirection {
        case forward
        case reverse
    }

    private static func starlarkStringSearchWindow(
        _ string: String,
        start rawStart: Int?,
        end rawEnd: Int?
    ) -> (start: Int, haystack: String)? {
        let characters = Array(string)
        let count = characters.count
        if rawStart == nil, rawEnd == nil {
            return (0, string)
        }
        if let start = rawStart, rawEnd == nil, start >= 0 {
            guard start <= count else {
                return nil
            }
            return (start, String(characters[start...]))
        }
        if rawStart == nil, let end = rawEnd, end >= 0 {
            return (0, String(characters[..<min(end, count)]))
        }
        if let start = rawStart, let end = rawEnd, start >= 0, end >= start {
            guard start <= count else {
                return nil
            }
            let relativeEnd = min(end - start, count - start)
            return (start, String(characters[start..<start + relativeEnd]))
        }
        if let start = rawStart, let end = rawEnd, (start >= 0) == (end >= 0), start > end {
            return nil
        }

        let start = normalizedStarlarkSearchBound(rawStart ?? 0, count: count)
        let end = normalizedStarlarkSearchBound(rawEnd ?? count, count: count)
        guard start <= end else {
            return nil
        }
        return (start, String(characters[start..<end]))
    }

    private static func normalizedStarlarkSearchBound(_ value: Int, count: Int) -> Int {
        let resolved = value < 0 ? value + count : value
        return min(max(resolved, 0), count)
    }

    private static func countingStarlarkStringMatches(_ needle: String, in haystack: String) -> Int {
        if needle.isEmpty {
            return haystack.count + 1
        }
        var count = 0
        var cursor = haystack.startIndex
        while let range = haystack.range(of: needle, range: cursor..<haystack.endIndex) {
            count += 1
            cursor = range.upperBound
        }
        return count
    }

    private static func findingStarlarkString(
        _ needle: String,
        in string: String,
        start: Int?,
        end: Int?,
        direction: StarlarkStringSearchDirection
    ) -> Int? {
        guard let window = starlarkStringSearchWindow(string, start: start, end: end) else {
            return nil
        }
        if needle.isEmpty {
            return direction == .forward ? window.start : window.start + window.haystack.count
        }
        let range: Range<String.Index>?
        switch direction {
        case .forward:
            range = window.haystack.range(of: needle)
        case .reverse:
            range = window.haystack.range(of: needle, options: .backwards)
        }
        guard let range else {
            return nil
        }
        return window.start + window.haystack.distance(from: window.haystack.startIndex, to: range.lowerBound)
    }

    private static func partitioningStarlarkString(
        _ string: String,
        separator: String,
        direction: StarlarkStringSearchDirection,
        expression: String
    ) throws -> [String] {
        guard !separator.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let range: Range<String.Index>?
        switch direction {
        case .forward:
            range = string.range(of: separator)
        case .reverse:
            range = string.range(of: separator, options: .backwards)
        }
        guard let range else {
            switch direction {
            case .forward:
                return [string, "", ""]
            case .reverse:
                return ["", "", string]
            }
        }
        return [
            String(string[..<range.lowerBound]),
            separator,
            String(string[range.upperBound...])
        ]
    }

    private static func starlarkStringIsAlphanumeric(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }
    }

    private static func starlarkStringIsAlphabetic(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { $0.properties.isAlphabetic }
    }

    private static func starlarkStringIsNumeric(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { $0.properties.numericType != nil }
    }

    private static func starlarkStringIsLowercase(_ string: String) -> Bool {
        var sawLowercase = false
        for scalar in string.unicodeScalars {
            if scalar.properties.isUppercase {
                return false
            }
            if scalar.properties.isLowercase {
                sawLowercase = true
            }
        }
        return sawLowercase
    }

    private static func starlarkStringIsWhitespace(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func starlarkStringIsTitlecase(_ string: String) -> Bool {
        var lastNonAlphabetic = true
        var sawAlphabetic = false
        for scalar in string.unicodeScalars {
            if !scalar.properties.isAlphabetic {
                lastNonAlphabetic = true
            } else {
                if lastNonAlphabetic {
                    if scalar.properties.isLowercase {
                        return false
                    }
                } else if scalar.properties.isUppercase {
                    return false
                }
                sawAlphabetic = true
                lastNonAlphabetic = false
            }
        }
        return sawAlphabetic
    }

    private static func starlarkStringIsUppercase(_ string: String) -> Bool {
        var sawUppercase = false
        for scalar in string.unicodeScalars {
            if scalar.properties.isLowercase {
                return false
            }
            if scalar.properties.isUppercase {
                sawUppercase = true
            }
        }
        return sawUppercase
    }

    private static func starlarkWhitespaceSplit(_ string: String) -> [String] {
        string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    private static func splittingStarlarkString(
        _ string: String,
        separator: String?,
        maxsplit rawMaxsplit: Int?,
        direction: StarlarkStringSearchDirection
    ) -> [String] {
        let maxPieces = rawMaxsplit.flatMap { $0 < 0 ? nil : $0 + 1 }
        guard let separator else {
            switch (direction, maxPieces) {
            case (.forward, nil):
                return starlarkWhitespaceSplit(string)
            case (.forward, let maxPieces?):
                return splittingStarlarkWhitespace(string, maxPieces: maxPieces)
            case (.reverse, nil):
                return starlarkWhitespaceSplit(string)
            case (.reverse, let maxPieces?):
                return reverseSplittingStarlarkWhitespace(string, maxPieces: maxPieces)
            }
        }

        switch direction {
        case .forward:
            return splittingStarlarkString(string, separator: separator, maxPieces: maxPieces)
        case .reverse:
            return reverseSplittingStarlarkString(string, separator: separator, maxPieces: maxPieces)
        }
    }

    private static func splittingStarlarkString(
        _ string: String,
        separator: String,
        maxPieces: Int?
    ) -> [String] {
        guard let maxPieces else {
            return string.components(separatedBy: separator)
        }
        guard maxPieces > 1 else {
            return [string]
        }

        var pieces: [String] = []
        var cursor = string.startIndex
        var remainingSplits = maxPieces - 1
        while remainingSplits > 0,
              let range = string.range(of: separator, range: cursor..<string.endIndex) {
            pieces.append(String(string[cursor..<range.lowerBound]))
            cursor = range.upperBound
            remainingSplits -= 1
        }
        pieces.append(String(string[cursor...]))
        return pieces
    }

    private static func reverseSplittingStarlarkString(
        _ string: String,
        separator: String,
        maxPieces: Int?
    ) -> [String] {
        guard let maxPieces else {
            return string.components(separatedBy: separator)
        }
        guard maxPieces > 1 else {
            return [string]
        }

        var pieces: [String] = []
        var searchUpperBound = string.endIndex
        var remainingSplits = maxPieces - 1
        while remainingSplits > 0,
              let range = string.range(of: separator, options: .backwards, range: string.startIndex..<searchUpperBound) {
            pieces.append(String(string[range.upperBound..<searchUpperBound]))
            searchUpperBound = range.lowerBound
            remainingSplits -= 1
        }
        pieces.append(String(string[..<searchUpperBound]))
        return Array(pieces.reversed())
    }

    private static func splittingStarlarkWhitespace(_ string: String, maxPieces: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        var split = 1
        var eatWhitespace = true
        for character in string {
            if split >= maxPieces, !eatWhitespace {
                current.append(character)
            } else if character.isWhitespace || character.isNewline {
                if !current.isEmpty {
                    pieces.append(current)
                    current = ""
                    split += 1
                    eatWhitespace = true
                }
            } else {
                eatWhitespace = false
                current.append(character)
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    private static func reverseSplittingStarlarkWhitespace(_ string: String, maxPieces: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        var split = 1
        var eatWhitespace = true
        for character in string.reversed() {
            if split >= maxPieces, !eatWhitespace {
                current.append(character)
            } else if character.isWhitespace || character.isNewline {
                if !current.isEmpty {
                    pieces.append(String(current.reversed()))
                    current = ""
                    split += 1
                    eatWhitespace = true
                }
            } else {
                eatWhitespace = false
                current.append(character)
            }
        }
        if !current.isEmpty {
            pieces.append(String(current.reversed()))
        }
        return Array(pieces.reversed())
    }

    private static func splittingStarlarkLines(_ string: String, keepends: Bool) -> [String] {
        var lines: [String] = []
        let scalars = string.unicodeScalars
        var lineStart = scalars.startIndex
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]
            guard scalar == "\n" || scalar == "\r" else {
                index = scalars.index(after: index)
                continue
            }

            let lineEnd = index
            var nextLineStart = scalars.index(after: index)
            if scalar == "\r",
               nextLineStart < scalars.endIndex,
               scalars[nextLineStart] == "\n" {
                nextLineStart = scalars.index(after: nextLineStart)
            }

            let sliceEnd = keepends ? nextLineStart : lineEnd
            let stringLineStart = String.Index(lineStart, within: string)!
            let stringSliceEnd = String.Index(sliceEnd, within: string)!
            lines.append(String(string[stringLineStart..<stringSliceEnd]))
            if nextLineStart == scalars.endIndex {
                return lines
            }
            lineStart = nextLineStart
            index = nextLineStart
        }

        if lineStart < scalars.endIndex {
            let stringLineStart = String.Index(lineStart, within: string)!
            lines.append(String(string[stringLineStart..<string.endIndex]))
        }
        return lines
    }

    private static func formattingStarlarkString(
        _ format: String,
        arguments: StarlarkFormatArguments,
        expression: String
    ) throws -> String {
        var result = ""
        var nextOrderedArgumentIndex = 0
        var usedOrderedFields = false
        var usedIndexedFields = false
        var index = format.startIndex

        while index < format.endIndex {
            let character = format[index]
            switch character {
            case "{":
                let nextIndex = format.index(after: index)
                if nextIndex < format.endIndex, format[nextIndex] == "{" {
                    result.append("{")
                    index = format.index(after: nextIndex)
                    continue
                }

                let capture = try parseStarlarkFormatCapture(
                    in: format,
                    startingAt: nextIndex,
                    expression: expression
                )
                let value = try resolveStarlarkFormatCapture(
                    capture.field,
                    conversion: capture.conversion,
                    arguments: arguments,
                    nextOrderedArgumentIndex: &nextOrderedArgumentIndex,
                    usedOrderedFields: &usedOrderedFields,
                    usedIndexedFields: &usedIndexedFields,
                    expression: expression
                )
                result.append(value)
                index = format.index(after: capture.closeIndex)
            case "}":
                let nextIndex = format.index(after: index)
                guard nextIndex < format.endIndex, format[nextIndex] == "}" else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                result.append("}")
                index = format.index(after: nextIndex)
            default:
                result.append(character)
                index = format.index(after: index)
            }
        }

        return result
    }

    private static func formattingStarlarkPercentString(
        _ format: String,
        argument: ConfigValue,
        expression: String
    ) throws -> String {
        let captureCount = try starlarkPercentCaptureCount(in: format, expression: expression)
        let source: StarlarkPercentArgumentSource
        if case let .table(items) = argument {
            source = .mapping(items)
        } else if case let .array(items) = argument, captureCount != 1 {
            source = .positional(items)
        } else {
            source = .positional([argument])
        }

        var nextPositionalIndex = 0
        var result = ""
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                result.append(format[index])
                index = format.index(after: index)
                continue
            }

            let markerIndex = format.index(after: index)
            guard markerIndex < format.endIndex else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if format[markerIndex] == "%" {
                result.append("%")
                index = format.index(after: markerIndex)
                continue
            }

            var key: String?
            var conversionIndex = markerIndex
            if format[markerIndex] == "(" {
                guard let closeIndex = format[markerIndex...].firstIndex(of: ")"),
                      closeIndex > markerIndex
                else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let keyStart = format.index(after: markerIndex)
                key = String(format[keyStart..<closeIndex])
                conversionIndex = format.index(after: closeIndex)
            }

            guard conversionIndex < format.endIndex else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let conversion = format[conversionIndex]
            let value: ConfigValue
            if let key {
                guard case let .mapping(items) = source,
                      let mappedValue = items[key]
                else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                value = mappedValue
            } else {
                guard case let .positional(items) = source,
                      nextPositionalIndex < items.count
                else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                value = items[nextPositionalIndex]
                nextPositionalIndex += 1
            }
            result += try starlarkPercentFormat(value, conversion: conversion, expression: expression)
            index = format.index(after: conversionIndex)
        }

        if case let .positional(items) = source,
           nextPositionalIndex != items.count {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return result
    }

    private static func starlarkPercentCaptureCount(in format: String, expression: String) throws -> Int {
        var count = 0
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            let markerIndex = format.index(after: index)
            guard markerIndex < format.endIndex else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            if format[markerIndex] == "%" {
                index = format.index(after: markerIndex)
                continue
            }
            count += 1
            if format[markerIndex] == "(" {
                guard let closeIndex = format[markerIndex...].firstIndex(of: ")"),
                      closeIndex > markerIndex
                else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                index = format.index(after: closeIndex)
            } else {
                index = markerIndex
            }
            guard index < format.endIndex else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            index = format.index(after: index)
        }
        return count
    }

    private static func starlarkPercentFormat(
        _ value: ConfigValue,
        conversion: Character,
        expression: String
    ) throws -> String {
        switch conversion {
        case "s":
            return starlarkString(value)
        case "r":
            return starlarkRepresentation(value)
        case "d", "i":
            switch value {
            case let .integer(value):
                return String(value)
            case let .double(value):
                guard let truncated = Int64(exactly: value.rounded(.towardZero)) else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                return String(truncated)
            default:
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        case "o":
            guard case let .integer(value) = value else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return String(value, radix: 8)
        case "x":
            guard case let .integer(value) = value else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return String(value, radix: 16)
        case "X":
            guard case let .integer(value) = value else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return String(value, radix: 16).uppercased()
        case "e":
            return try starlarkPercentFormatScientific(
                value,
                exponent: "e",
                stripTrailingZeros: false,
                expression: expression
            )
        case "E":
            return try starlarkPercentFormatScientific(
                value,
                exponent: "E",
                stripTrailingZeros: false,
                expression: expression
            )
        case "f", "F":
            return String(
                format: "%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                try starlarkPercentFloatingPoint(value, expression: expression)
            )
        case "g":
            return try starlarkPercentFormatCompact(value, exponent: "e", expression: expression)
        case "G":
            return try starlarkPercentFormatCompact(value, exponent: "E", expression: expression)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkPercentFloatingPoint(_ value: ConfigValue, expression: String) throws -> Double {
        switch value {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkPercentFormatCompact(
        _ value: ConfigValue,
        exponent: Character,
        expression: String
    ) throws -> String {
        let double = try starlarkPercentFloatingPoint(value, expression: expression)
        guard double.isFinite else {
            return starlarkPercentFormatNonFinite(double)
        }
        let absolute = abs(double)
        let exponentValue = double == 0 ? 0 : Int(floor(log10(absolute)))
        if abs(exponentValue) >= 6 {
            return try starlarkPercentFormatScientific(
                value,
                exponent: exponent,
                stripTrailingZeros: true,
                expression: expression
            )
        }
        if double.rounded(.towardZero) == double {
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), double)
        }
        return String(double)
    }

    private static func starlarkPercentFormatScientific(
        _ value: ConfigValue,
        exponent exponentCharacter: Character,
        stripTrailingZeros: Bool,
        expression: String
    ) throws -> String {
        let double = try starlarkPercentFloatingPoint(value, expression: expression)
        guard double.isFinite else {
            return starlarkPercentFormatNonFinite(double)
        }
        let absolute = abs(double)
        let exponent = double == 0 ? 0 : Int(floor(log10(absolute)))
        let normalized = double == 0 ? 0 : absolute / pow(10, Double(exponent))

        var result = double.sign == .minus ? "-" : ""
        result += String(Int(normalized.rounded(.towardZero)))
        var tail = UInt64((normalized.truncatingRemainder(dividingBy: 1) * 1_000_000).rounded())
        var digits: [UInt8] = []
        var removingTrailingZeros = stripTrailingZeros
        for _ in 0..<6 {
            let digit = UInt8(tail % 10)
            if digit != 0 || !removingTrailingZeros {
                removingTrailingZeros = false
                digits.append(digit)
            }
            tail /= 10
        }
        if !digits.isEmpty {
            result += "."
            for digit in digits.reversed() {
                result.append(Character(String(UnicodeScalar(UInt8(ascii: "0") + digit))))
            }
        }
        result.append(exponentCharacter)
        result += starlarkPercentFormatExponent(exponent)
        return result
    }

    private static func starlarkPercentFormatExponent(_ exponent: Int) -> String {
        let sign = exponent < 0 ? "-" : "+"
        let magnitude = abs(exponent)
        if magnitude < 10 {
            return "\(sign)0\(magnitude)"
        }
        return "\(sign)\(magnitude)"
    }

    private static func starlarkPercentFormatNonFinite(_ value: Double) -> String {
        if value.isNaN {
            return "nan"
        }
        return value.sign == .minus ? "-inf" : "+inf"
    }

    private static func parseStarlarkFormatCapture(
        in format: String,
        startingAt start: String.Index,
        expression: String
    ) throws -> (field: String, conversion: StarlarkFormatConversion, closeIndex: String.Index) {
        var index = start
        while index < format.endIndex {
            switch format[index] {
            case "}":
                return (String(format[start..<index]), .string, index)
            case "!":
                let field = String(format[start..<index])
                let conversionIndex = format.index(after: index)
                guard conversionIndex < format.endIndex else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let conversion: StarlarkFormatConversion
                switch format[conversionIndex] {
                case "r":
                    conversion = .representation
                case "s":
                    conversion = .string
                default:
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let closeIndex = format.index(after: conversionIndex)
                guard closeIndex < format.endIndex, format[closeIndex] == "}" else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                return (field, conversion, closeIndex)
            case "{":
                throw ConfigOverrideError.invalidLiteral(expression)
            default:
                index = format.index(after: index)
            }
        }

        throw ConfigOverrideError.invalidLiteral(expression)
    }

    private static func resolveStarlarkFormatCapture(
        _ field: String,
        conversion: StarlarkFormatConversion,
        arguments: StarlarkFormatArguments,
        nextOrderedArgumentIndex: inout Int,
        usedOrderedFields: inout Bool,
        usedIndexedFields: inout Bool,
        expression: String
    ) throws -> String {
        let value: ConfigValue
        if field.isEmpty {
            guard !usedIndexedFields else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            usedOrderedFields = true
            guard nextOrderedArgumentIndex < arguments.positional.count else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            value = arguments.positional[nextOrderedArgumentIndex]
            nextOrderedArgumentIndex += 1
        } else if field.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
            guard !usedOrderedFields,
                  let index = Int(field),
                  index >= 0,
                  index < arguments.positional.count
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            usedIndexedFields = true
            value = arguments.positional[index]
        } else {
            guard !field.contains("."),
                  !field.contains(","),
                  !field.contains("["),
                  !field.contains("]"),
                  let namedValue = arguments.named[field]
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            value = namedValue
        }

        switch conversion {
        case .string:
            return starlarkString(value)
        case .representation:
            return starlarkRepresentation(value)
        }
    }

    private static func replacingEmptyStarlarkString(_ string: String, newValue: String, count: Int) -> String {
        let unlimited = count < 0
        var remaining = count
        var result = ""

        func shouldInsert() -> Bool {
            unlimited || remaining > 0
        }

        func recordInsertion() {
            if !unlimited {
                remaining -= 1
            }
        }

        if shouldInsert() {
            result += newValue
            recordInsertion()
        }
        for character in string {
            result.append(character)
            if shouldInsert() {
                result += newValue
                recordInsertion()
            }
        }
        return result
    }

    private static func topLevelMethodDotIndex(in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var candidate: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            case "." where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                candidate = index
            default:
                break
            }

            index = text.index(after: index)
        }

        return squareDepth == 0 && braceDepth == 0 && parenDepth == 0 ? candidate : nil
    }

    private static func parseStarlarkFunctionCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let name = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(name),
              let function = functions[name]
        else {
            return nil
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        var scopedConstants = constants
        try bindStarlarkFunctionArguments(
            body,
            function: function,
            scopedConstants: &scopedConstants,
            constants: constants,
            functions: functions,
            expression: text
        )
        return try evaluateStarlarkFunction(function, constants: &scopedConstants, functions: functions, expression: text)
    }

    private static func bindStarlarkFunctionArguments(
        _ body: String,
        function: StarlarkFunction,
        scopedConstants: inout [String: ConfigValue],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws {
        var positionalArguments: [ConfigValue] = []
        var argumentsByName: [String: ConfigValue] = [:]
        var sawNamedArgument = false
        var sawArgsExpansion = false
        var sawKwargsExpansion = false

        for piece in splitTopLevel(body, separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if trimmed.hasPrefix("**") {
                guard !sawKwargsExpansion else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawNamedArgument = true
                sawKwargsExpansion = true
                let valueStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
                let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
                guard case let .table(items) = value else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                for (name, item) in items {
                    guard argumentsByName[name] == nil else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    argumentsByName[name] = item
                }
                continue
            }

            if trimmed.hasPrefix("*") {
                guard !sawArgsExpansion, !sawKwargsExpansion else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawArgsExpansion = true
                let valueStart = trimmed.index(after: trimmed.startIndex)
                let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
                positionalArguments.append(contentsOf: try starlarkIterableItems(value, expression: expression))
                continue
            }

            if let equalsIndex = topLevelEqualsIndex(in: trimmed) {
                guard !sawArgsExpansion, !sawKwargsExpansion else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawNamedArgument = true
                let name = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = trimmed.index(after: equalsIndex)
                let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard isStarlarkIdentifier(name), !valueText.isEmpty, argumentsByName[name] == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                argumentsByName[name] = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
            } else {
                guard !sawNamedArgument, !sawArgsExpansion, !sawKwargsExpansion else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                positionalArguments.append(try parsePolicyLiteral(trimmed, constants: constants, functions: functions))
            }
        }

        let positionalOrKeywordParameters = function.parameters.filter { $0.kind == .positionalOrKeyword }
        let keywordOnlyParameters = function.parameters.filter { $0.kind == .keywordOnly }
        let varargsParameter = function.parameters.first { $0.kind == .varargs }
        let kwargsParameter = function.parameters.first { $0.kind == .kwargs }
        var positionalIndex = 0

        for parameter in positionalOrKeywordParameters {
            if positionalIndex < positionalArguments.count {
                guard argumentsByName[parameter.name] == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                scopedConstants[parameter.name] = positionalArguments[positionalIndex]
                positionalIndex += 1
                continue
            }

            if let namedArgument = argumentsByName.removeValue(forKey: parameter.name) {
                scopedConstants[parameter.name] = namedArgument
            } else if let defaultValueExpression = parameter.defaultValueExpression {
                scopedConstants[parameter.name] = try parsePolicyLiteral(
                    defaultValueExpression,
                    constants: constants,
                    functions: functions
                )
            } else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }

        let remainingPositionalArguments = Array(positionalArguments.dropFirst(positionalIndex))
        if let varargsParameter {
            scopedConstants[varargsParameter.name] = .array(remainingPositionalArguments)
        } else if !remainingPositionalArguments.isEmpty {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        for parameter in keywordOnlyParameters {
            if let namedArgument = argumentsByName.removeValue(forKey: parameter.name) {
                scopedConstants[parameter.name] = namedArgument
            } else if let defaultValueExpression = parameter.defaultValueExpression {
                scopedConstants[parameter.name] = try parsePolicyLiteral(
                    defaultValueExpression,
                    constants: constants,
                    functions: functions
                )
            } else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }

        if let kwargsParameter {
            scopedConstants[kwargsParameter.name] = .table(argumentsByName)
        } else if !argumentsByName.isEmpty {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkFunction(
        _ function: StarlarkFunction,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        let flow = try executeStarlarkFunctionStatements(
            function.body,
            constants: &constants,
            functions: functions,
            expression: expression
        )
        guard case let .returnValue(value) = flow else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return value
    }

    private static func executeStarlarkFunctionStatements(
        _ statements: [String],
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> StarlarkFunctionFlow {
        var index = 0
        while index < statements.count {
            let statement = statements[index]
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "pass" else {
                index += 1
                continue
            }

            if let returnRange = topLevelKeywordRange("return", in: trimmed),
               returnRange.lowerBound == trimmed.startIndex {
                let returnExpression = String(trimmed[returnRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !returnExpression.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(trimmed)
                }
                return .returnValue(try parsePolicyLiteral(returnExpression, constants: constants, functions: functions))
            }

            if let forLoop = try parseTopLevelForHeader(statement) {
                let collected = try collectIndentedBlock(
                    after: index,
                    in: statements,
                    parentIndent: indentationCount(statement),
                    identifier: expression,
                    blockName: "for loop"
                )
                let iterable = try parsePolicyLiteral(
                    forLoop.iterableText,
                    constants: constants,
                    functions: functions
                )
                let items = try starlarkIterableItems(iterable, expression: forLoop.iterableText)
                var loopConstants = constants
                var shouldBreakLoop = false
                for item in items {
                    try bindStarlarkLoopTargets(
                        forLoop.targets,
                        to: item,
                        constants: &loopConstants,
                        expression: trimmed
                    )
                    let flow = try executeStarlarkFunctionStatements(
                        collected.body,
                        constants: &loopConstants,
                        functions: functions,
                        expression: expression
                    )
                    switch flow {
                    case .none:
                        break
                    case .continueLoop:
                        continue
                    case .breakLoop:
                        shouldBreakLoop = true
                    case .returnValue:
                        constants = loopConstants
                        return flow
                    }
                    if shouldBreakLoop {
                        break
                    }
                }
                constants = loopConstants
                index = collected.nextIndex
                continue
            }

            if let condition = try parseTopLevelIfHeader(statement) {
                let headerIndent = indentationCount(statement)
                let thenBlock = try collectIndentedBlock(
                    after: index,
                    in: statements,
                    parentIndent: headerIndent,
                    identifier: expression,
                    blockName: "if block"
                )
                var nextIndex = thenBlock.nextIndex
                var branches = [(condition: condition, body: thenBlock.body)]
                var elseBody: [String] = []
                while nextIndex < statements.count,
                      indentationCount(statements[nextIndex]) == headerIndent,
                      let elifCondition = try parseTopLevelElifHeader(statements[nextIndex]) {
                    let elifBlock = try collectIndentedBlock(
                        after: nextIndex,
                        in: statements,
                        parentIndent: headerIndent,
                        identifier: expression,
                        blockName: "elif block"
                    )
                    branches.append((condition: elifCondition, body: elifBlock.body))
                    nextIndex = elifBlock.nextIndex
                }
                if nextIndex < statements.count,
                   indentationCount(statements[nextIndex]) == headerIndent,
                   isTopLevelElseHeader(statements[nextIndex]) {
                    let elseBlock = try collectIndentedBlock(
                        after: nextIndex,
                        in: statements,
                        parentIndent: headerIndent,
                        identifier: expression,
                        blockName: "else block"
                    )
                    elseBody = elseBlock.body
                    nextIndex = elseBlock.nextIndex
                }

                var matchedBranch = false
                for branch in branches where try evaluateStarlarkCondition(
                    branch.condition,
                    constants: constants,
                    functions: functions
                ) {
                    let flow = try executeStarlarkFunctionStatements(
                        branch.body,
                        constants: &constants,
                        functions: functions,
                        expression: expression
                    )
                    if case .none = flow {
                        matchedBranch = true
                        break
                    }
                    return flow
                }
                if !matchedBranch, !elseBody.isEmpty {
                    let flow = try executeStarlarkFunctionStatements(
                        elseBody,
                        constants: &constants,
                        functions: functions,
                        expression: expression
                    )
                    if case .none = flow {
                        index = nextIndex
                        continue
                    }
                    return flow
                }
                index = nextIndex
                continue
            }

            if trimmed == "continue" {
                return .continueLoop
            }
            if trimmed == "break" {
                return .breakLoop
            }

            if try parseStarlarkLocalStatement(trimmed, constants: &constants, functions: functions) {
                index += 1
                continue
            }
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .none
    }

    private static func parseStarlarkLocalStatement(
        _ statement: String,
        constants: inout [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        if try parseTopLevelDestructuringAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkListPopAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkDictPopAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkCollectionNoneMutationAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkDictMutationStatement(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkListMutationStatement(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkDeleteStatement(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkIndexedAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if try parseStarlarkAugmentedAssignment(statement, constants: &constants, functions: functions) {
            return true
        }
        if let assignment = try parseTopLevelLiteralAssignment(
            statement,
            constants: constants,
            functions: functions
        ) {
            constants[assignment.key] = assignment.value
            return true
        }
        if try parseStarlarkFailStatement(statement, constants: constants, functions: functions) {
            return true
        }
        return false
    }

    private static func parseStarlarkBuiltinFunctionCall(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: text)
        else {
            return nil
        }

        let name = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["all", "any", "dir", "enumerate", "fail", "getattr", "hasattr", "zip", "list", "tuple", "dict", "sorted", "reversed", "min", "max", "sum", "abs", "hash", "chr", "ord", "repr", "type", "str", "int", "float", "bool"].contains(name) else {
            return nil
        }

        let bodyStart = text.index(after: openIndex)
        let body = String(text[bodyStart..<text.index(before: text.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch name {
        case "all":
            return try parseStarlarkAllCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "any":
            return try parseStarlarkAnyCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "dir":
            return try parseStarlarkDirCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "enumerate":
            return try parseStarlarkEnumerateCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "fail":
            return try parseStarlarkFailCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "getattr":
            return try parseStarlarkGetAttributeCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "hasattr":
            return try parseStarlarkHasAttributeCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "zip":
            return try parseStarlarkZipCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "list", "tuple":
            return try parseStarlarkIterableConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "dict":
            return try parseStarlarkDictionaryConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "sorted":
            return try parseStarlarkSortedCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "reversed":
            return try parseStarlarkReversedCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "min":
            return try parseStarlarkMinMaxCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions,
                selectsMinimum: true
            )
        case "max":
            return try parseStarlarkMinMaxCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions,
                selectsMinimum: false
            )
        case "sum":
            return try parseStarlarkSumCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "abs":
            return try parseStarlarkAbsoluteValueCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "hash":
            return try parseStarlarkHashCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "chr":
            return try parseStarlarkCharacterCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "ord":
            return try parseStarlarkOrdinalCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "repr":
            return try parseStarlarkRepresentationCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "type":
            return try parseStarlarkTypeCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "str":
            return try parseStarlarkStringConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "int":
            return try parseStarlarkIntegerConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "float":
            return try parseStarlarkFloatConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        case "bool":
            return try parseStarlarkBooleanConversionCall(
                rawArguments,
                expression: text,
                constants: constants,
                functions: functions
            )
        default:
            return nil
        }
    }

    private static func parseStarlarkFailStatement(
        _ statement: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let openIndex = matchingTopLevelCallOpen(in: trimmed),
              trimmed[..<openIndex].trimmingCharacters(in: .whitespacesAndNewlines) == "fail"
        else {
            return false
        }

        let bodyStart = trimmed.index(after: openIndex)
        let body = String(trimmed[bodyStart..<trimmed.index(before: trimmed.endIndex)])
        let rawArguments = splitTopLevel(body, separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        _ = try parseStarlarkFailCall(
            rawArguments,
            expression: trimmed,
            constants: constants,
            functions: functions
        )
        return true
    }

    private static func parseStarlarkFailCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        let parts = try rawArguments.map { rawArgument -> String in
            guard topLevelEqualsIndex(in: rawArgument) == nil else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            if case let .string(string) = value {
                return string
            }
            return starlarkRepresentation(value)
        }
        throw ExecPolicyError.invalidSyntax("fail:\(parts.isEmpty ? "" : " " + parts.joined(separator: " "))")
    }

    private static func parseStarlarkAllCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let iterable = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        let items = try starlarkIterableItems(iterable, expression: expression)
        return .bool(items.allSatisfy(truthy))
    }

    private static func parseStarlarkAnyCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let iterable = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        let items = try starlarkIterableItems(iterable, expression: expression)
        return .bool(items.contains(where: truthy))
    }

    private static func parseStarlarkDirCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        return .array(starlarkAttributeNames(for: value).map(ConfigValue.string))
    }

    private static func parseStarlarkEnumerateCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        var positionalArguments: [String] = []
        var rawStart: String?
        var sawKeywordArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawKeywordArgument = true
                let rawName = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawName == "start", rawStart == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                rawStart = rawValue
                continue
            }

            guard !sawKeywordArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            positionalArguments.append(rawArgument)
        }

        guard (1...2).contains(positionalArguments.count),
              rawStart == nil || positionalArguments.count == 1
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let start: Int64
        if positionalArguments.count == 2 {
            rawStart = positionalArguments[1]
        }
        if let rawStart {
            start = Int64(try parseStarlarkInt32(
                rawStart,
                constants: constants,
                functions: functions,
                expression: expression
            ))
        } else {
            start = 0
        }
        let iterable = try parsePolicyLiteral(positionalArguments[0], constants: constants, functions: functions)
        let items = try starlarkIterableItems(iterable, expression: expression)
        return .array(items.enumerated().map { offset, item in
            .array([.integer(start + Int64(offset)), item])
        })
    }

    private static func parseStarlarkGetAttributeCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 2 || rawArguments.count == 3 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let value = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
        let attribute = try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
        guard case let .string(attributeName) = attribute else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        guard !starlarkAttributeNames(for: value).contains(attributeName),
              rawArguments.count == 3
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return try parsePolicyLiteral(rawArguments[2], constants: constants, functions: functions)
    }

    private static func parseStarlarkHasAttributeCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 2 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let value = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
        let attribute = try parsePolicyLiteral(rawArguments[1], constants: constants, functions: functions)
        guard case let .string(attributeName) = attribute else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .bool(starlarkAttributeNames(for: value).contains(attributeName))
    }

    private static func parseStarlarkZipCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        let iterables = try rawArguments.map { rawArgument in
            try starlarkIterableItems(
                parsePolicyLiteral(rawArgument, constants: constants, functions: functions),
                expression: expression
            )
        }
        let count = iterables.map(\.count).min() ?? 0
        return .array((0..<count).map { index in
            .array(iterables.map { $0[index] })
        })
    }

    private static func parseStarlarkIterableConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count <= 1 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        guard let rawArgument = rawArguments.first else {
            return .array([])
        }
        let iterable = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        return try .array(starlarkIterableItems(iterable, expression: expression))
    }

    private static func parseStarlarkDictionaryConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        var table: [String: ConfigValue] = [:]
        var sawKeywordArgument = false
        var sawStarStarArgument = false
        var explicitKeywordKeys = Set<String>()
        var consumedPositionalArgument = false

        for rawArgument in rawArguments {
            let trimmedArgument = rawArgument.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedArgument.hasPrefix("**") {
                sawStarStarArgument = true
                let valueStart = trimmedArgument.index(
                    trimmedArgument.startIndex,
                    offsetBy: 2
                )
                let valueText = String(trimmedArgument[valueStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !valueText.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let value = try parsePolicyLiteral(valueText, constants: constants, functions: functions)
                guard case let .table(items) = value else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                guard explicitKeywordKeys.isDisjoint(with: items.keys) else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                table.merge(items) { _, new in new }
                continue
            }

            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                guard !sawStarStarArgument else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let rawKey = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard isStarlarkIdentifier(rawKey), !rawValue.isEmpty, explicitKeywordKeys.insert(rawKey).inserted else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                sawKeywordArgument = true
                table[rawKey] = try parsePolicyLiteral(rawValue, constants: constants, functions: functions)
                continue
            }

            guard !sawKeywordArgument, !sawStarStarArgument, !consumedPositionalArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            consumedPositionalArgument = true
            let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            switch value {
            case let .table(items):
                table.merge(items) { _, new in new }
            case let .array(items):
                for item in items {
                    guard case let .array(pair) = item,
                          pair.count == 2,
                          case let .string(key) = pair[0]
                    else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    table[key] = pair[1]
                }
            default:
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }

        return .table(table)
    }

    private static func parseStarlarkSortedCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        let arguments = try parseStarlarkSortArguments(
            rawArguments,
            expression: expression,
            constants: constants,
            functions: functions
        )
        guard arguments.positionalArguments.count == 1,
              let rawArgument = arguments.positionalArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let iterable = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        let items = try starlarkIterableItems(iterable, expression: expression)
        return try .array(sortedStarlarkItems(
            items,
            keyFunction: arguments.keyFunction,
            reverse: arguments.reverse,
            constants: constants,
            functions: functions,
            expression: expression
        ))
    }

    private struct StarlarkSortArguments {
        let positionalArguments: [String]
        let keyFunction: StarlarkKeyFunction?
        let reverse: Bool
    }

    private static func parseStarlarkSortArguments(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> StarlarkSortArguments {
        var positionalArguments: [String] = []
        var keyFunction: StarlarkKeyFunction?
        var reverse = false
        var sawKey = false
        var sawReverse = false
        var sawKeywordArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawKeywordArgument = true
                let rawName = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                switch rawName {
                case "key":
                    guard !sawKey else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    if rawValue != "None" {
                        keyFunction = try parseStarlarkKeyFunction(rawValue, expression: expression)
                    }
                    sawKey = true
                case "reverse":
                    guard !sawReverse else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    let value = try parsePolicyLiteral(rawValue, constants: constants, functions: functions)
                    guard case let .bool(reverseValue) = value else {
                        throw ConfigOverrideError.invalidLiteral(expression)
                    }
                    reverse = reverseValue
                    sawReverse = true
                default:
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                continue
            }

            guard !sawKeywordArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            positionalArguments.append(rawArgument)
        }

        return StarlarkSortArguments(
            positionalArguments: positionalArguments,
            keyFunction: keyFunction,
            reverse: reverse
        )
    }

    private static func sortedStarlarkItems(
        _ items: [ConfigValue],
        keyFunction: StarlarkKeyFunction?,
        reverse: Bool,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> [ConfigValue] {
        let keyedItems = try items.enumerated().map { index, item in
            (
                index: index,
                value: item,
                key: try starlarkComparableKey(
                    for: item,
                    keyFunction: keyFunction,
                    constants: constants,
                    functions: functions,
                    expression: expression
                )
            )
        }
        let sortedItems = try keyedItems.sorted { lhs, rhs in
            let comparison = try compareStarlarkValues(lhs.key, rhs.key, expression: expression)
            if comparison == 0 {
                return lhs.index < rhs.index
            }
            return reverse ? comparison > 0 : comparison < 0
        }
        return sortedItems.map(\.value)
    }

    private static func parseStarlarkReversedCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let iterable = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        return try .array(starlarkIterableItems(iterable, expression: expression).reversed())
    }

    private static func parseStarlarkMinMaxCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        selectsMinimum: Bool
    ) throws -> ConfigValue {
        var positionalArguments: [String] = []
        var keyFunction: StarlarkKeyFunction?
        var sawKeywordArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawKeywordArgument = true
                let rawName = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawName == "key", keyFunction == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                keyFunction = try parseStarlarkKeyFunction(rawValue, expression: expression)
                continue
            }

            guard !sawKeywordArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            positionalArguments.append(rawArgument)
        }

        guard !positionalArguments.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let items: [ConfigValue]
        if positionalArguments.count == 1 {
            let iterable = try parsePolicyLiteral(
                positionalArguments[0],
                constants: constants,
                functions: functions
            )
            items = try starlarkIterableItems(iterable, expression: expression)
        } else {
            items = try positionalArguments.map { rawArgument in
                try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
            }
        }
        guard let first = items.first else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        var selected = first
        var selectedKey = try starlarkComparableKey(
            for: first,
            keyFunction: keyFunction,
            constants: constants,
            functions: functions,
            expression: expression
        )
        for item in items.dropFirst() {
            let itemKey = try starlarkComparableKey(
                for: item,
                keyFunction: keyFunction,
                constants: constants,
                functions: functions,
                expression: expression
            )
            let comparison = try compareStarlarkValues(selectedKey, itemKey, expression: expression)
            if selectsMinimum ? comparison > 0 : comparison < 0 {
                selected = item
                selectedKey = itemKey
            }
        }
        return selected
    }

    private static func parseStarlarkSumCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        var positionalArguments: [String] = []
        var rawStart: String?
        var sawKeywordArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawKeywordArgument = true
                let rawName = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawName == "start", rawStart == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                rawStart = rawValue
                continue
            }

            guard !sawKeywordArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            positionalArguments.append(rawArgument)
        }

        guard (1...2).contains(positionalArguments.count),
              rawStart == nil || positionalArguments.count == 1
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let rawIterable = positionalArguments[0]
        if positionalArguments.count == 2 {
            rawStart = positionalArguments[1]
        }
        let iterable = try parsePolicyLiteral(rawIterable, constants: constants, functions: functions)
        let items = try starlarkIterableItems(iterable, expression: expression)
        var result = try rawStart.map {
            try parsePolicyLiteral($0, constants: constants, functions: functions)
        } ?? .integer(0)
        for item in items {
            result = try evaluateStarlarkAddition(result, item, expression: expression)
        }
        return result
    }

    private enum StarlarkKeyFunction {
        case identifier(String)
        case lambda(parameter: String, body: String)
    }

    private static func parseStarlarkKeyFunction(
        _ text: String,
        expression: String
    ) throws -> StarlarkKeyFunction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isStarlarkIdentifier(trimmed) {
            return .identifier(trimmed)
        }
        guard let lambdaRange = topLevelKeywordRange("lambda", in: trimmed),
              lambdaRange.lowerBound == trimmed.startIndex,
              let colonIndex = topLevelColonIndex(in: trimmed)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let parameter = String(trimmed[lambdaRange.upperBound..<colonIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(trimmed[trimmed.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStarlarkIdentifier(parameter),
              !body.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .lambda(parameter: parameter, body: body)
    }

    private static func starlarkComparableKey(
        for value: ConfigValue,
        keyFunction: StarlarkKeyFunction?,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        guard let keyFunction else {
            return value
        }
        switch keyFunction {
        case let .identifier(name):
            var scopedConstants = constants
            let keyArgumentName = "__codex_starlark_min_max_key_arg"
            scopedConstants[keyArgumentName] = value
            return try parsePolicyLiteral(
                "\(name)(\(keyArgumentName))",
                constants: scopedConstants,
                functions: functions
            )
        case let .lambda(parameter, body):
            var scopedConstants = constants
            scopedConstants[parameter] = value
            return try parsePolicyLiteral(body, constants: scopedConstants, functions: functions)
        }
    }

    private static func parseStarlarkAbsoluteValueCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        switch value {
        case let .integer(value):
            guard value != Int64.min else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return .integer(abs(value))
        case let .double(value):
            return .double(abs(value))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkHashCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .string(string) = value else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .integer(Int64(starlarkHashCode(for: string)))
    }

    private static func parseStarlarkCharacterCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .integer(codePoint) = value,
              codePoint >= 0,
              codePoint <= 0x10_FFFF,
              let scalar = UnicodeScalar(UInt32(codePoint))
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .string(String(scalar))
    }

    private static func parseStarlarkOrdinalCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        guard case let .string(string) = value,
              string.unicodeScalars.count == 1,
              let scalar = string.unicodeScalars.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .integer(Int64(scalar.value))
    }

    private static func parseStarlarkRepresentationCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        return .string(starlarkRepresentation(value))
    }

    private static func parseStarlarkTypeCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard rawArguments.count == 1,
              let rawArgument = rawArguments.first
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        let value = try parsePolicyLiteral(rawArgument, constants: constants, functions: functions)
        return .string(starlarkTypeName(value))
    }

    private static func parseStarlarkStringConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        switch rawArguments.count {
        case 0:
            return .string("")
        case 1:
            let value = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
            return .string(starlarkString(value))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkIntegerConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        guard !rawArguments.isEmpty else {
            return .integer(0)
        }

        var positionalArguments: [String] = []
        var rawBase: String?
        var sawKeywordArgument = false

        for rawArgument in rawArguments {
            if let equalsIndex = topLevelEqualsIndex(in: rawArgument) {
                sawKeywordArgument = true
                let rawName = String(rawArgument[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = rawArgument.index(after: equalsIndex)
                let rawValue = String(rawArgument[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawName == "base", rawBase == nil else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                rawBase = rawValue
                continue
            }

            guard !sawKeywordArgument else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            positionalArguments.append(rawArgument)
        }

        guard (1...2).contains(positionalArguments.count),
              rawBase == nil || positionalArguments.count == 1
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let value = try parsePolicyLiteral(positionalArguments[0], constants: constants, functions: functions)
        if positionalArguments.count == 2 {
            rawBase = positionalArguments[1]
        }

        if let rawBase {
            guard case let .string(string) = value else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let base = try parseStarlarkInteger(
                rawBase,
                constants: constants,
                functions: functions,
                expression: expression
            )
            return try .integer(starlarkInteger(string: string, base: base, expression: expression))
        } else {
            return try .integer(starlarkInteger(value, expression: expression))
        }
    }

    private static func parseStarlarkFloatConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        switch rawArguments.count {
        case 0:
            return .double(0)
        case 1:
            let value = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
            return try .double(starlarkFloat(value, expression: expression))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseStarlarkBooleanConversionCall(
        _ rawArguments: [String],
        expression: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        switch rawArguments.count {
        case 0:
            return .bool(false)
        case 1:
            let value = try parsePolicyLiteral(rawArguments[0], constants: constants, functions: functions)
            return .bool(truthy(value))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkAttributeNames(for value: ConfigValue) -> [String] {
        let names: [String]
        switch value {
        case .string:
            names = [
                "capitalize",
                "codepoints",
                "count",
                "elems",
                "endswith",
                "find",
                "format",
                "index",
                "isalnum",
                "isalpha",
                "isdigit",
                "islower",
                "isspace",
                "istitle",
                "isupper",
                "join",
                "lower",
                "lstrip",
                "partition",
                "removeprefix",
                "removesuffix",
                "replace",
                "rfind",
                "rindex",
                "rpartition",
                "rsplit",
                "rstrip",
                "split",
                "splitlines",
                "startswith",
                "strip",
                "title",
                "upper"
            ]
        case .array:
            names = ["append", "clear", "extend", "index", "insert", "pop", "remove", "reverse", "sort"]
        case .table:
            names = ["clear", "get", "items", "keys", "pop", "popitem", "setdefault", "update", "values"]
        case .range:
            names = []
        default:
            names = []
        }
        return names.sorted()
    }

    private static func starlarkTypeName(_ value: ConfigValue) -> String {
        switch value {
        case .string:
            return "string"
        case .integer:
            return "int"
        case .double:
            return "float"
        case .bool:
            return "bool"
        case .none:
            return "NoneType"
        case .array:
            return "list"
        case .table:
            return "dict"
        case .range:
            return "range"
        }
    }

    private static func starlarkFloat(_ value: ConfigValue, expression: String) throws -> Double {
        switch value {
        case let .double(value):
            return value
        case let .integer(value):
            return Double(value)
        case let .bool(value):
            return value ? 1 : 0
        case let .string(value):
            guard let double = Double(value),
                  !double.isInfinite || value.lowercased().contains("inf")
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return double
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkInteger(_ value: ConfigValue, expression: String) throws -> Int64 {
        switch value {
        case let .integer(value):
            return value
        case let .double(value):
            guard value.isFinite,
                  value >= Double(Int64.min),
                  value <= Double(Int64.max)
            else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return Int64(value.rounded(.towardZero))
        case let .bool(value):
            return value ? 1 : 0
        case let .string(value):
            return try starlarkInteger(string: value, base: 10, expression: expression)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkInteger(string rawValue: String, base rawBase: Int, expression: String) throws -> Int64 {
        guard rawBase == 0 || (2...36).contains(rawBase) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let sign: String
        if value.hasPrefix("-") {
            sign = "-"
            value.removeFirst()
        } else if value.hasPrefix("+") {
            sign = ""
            value.removeFirst()
        } else {
            sign = ""
        }

        var base = rawBase == 0 ? 10 : rawBase
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            guard rawBase == 0 || rawBase == 16 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            base = 16
            value.removeFirst(2)
        } else if value.hasPrefix("0o") || value.hasPrefix("0O") {
            guard rawBase == 0 || rawBase == 8 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            base = 8
            value.removeFirst(2)
        } else if value.hasPrefix("0b") || value.hasPrefix("0B") {
            guard rawBase == 0 || rawBase == 2 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            base = 2
            value.removeFirst(2)
        }

        let digits = value.filter { $0 != "_" }
        guard !digits.isEmpty,
              let integer = Int64(sign + digits, radix: base)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return integer
    }

    private static func starlarkHashCode(for value: String) -> Int32 {
        value.utf16.reduce(Int32(0)) { hash, codeUnit in
            hash &* 31 &+ Int32(codeUnit)
        }
    }

    private static func starlarkString(_ value: ConfigValue) -> String {
        switch value {
        case let .string(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "True" : "False"
        case .none:
            return "None"
        case let .array(items):
            return "[" + items.map(starlarkRepresentation).joined(separator: ", ") + "]"
        case let .table(items):
            return "{" + items.keys.sorted().map { key in
                "\(starlarkQuotedString(key)): \(starlarkRepresentation(items[key]!))"
            }.joined(separator: ", ") + "}"
        case let .range(start, stop, step):
            return starlarkRangeDisplay(start: start, stop: stop, step: step)
        }
    }

    private static func starlarkRepresentation(_ value: ConfigValue) -> String {
        switch value {
        case let .string(value):
            return starlarkQuotedString(value)
        default:
            return starlarkString(value)
        }
    }

    private static func starlarkQuotedString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func starlarkIterableItems(_ value: ConfigValue, expression: String) throws -> [ConfigValue] {
        switch value {
        case let .array(items):
            return items
        case let .table(items):
            return items.keys.map(ConfigValue.string)
        case let .range(start, stop, step):
            return starlarkRangeValues(start: start, stop: stop, step: step).map { .integer(Int64($0)) }
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkRangeValues(start: Int, stop: Int, step: Int) -> [Int] {
        guard step != 0 else {
            return []
        }
        var values: [Int] = []
        var current = start
        if step > 0 {
            while current < stop {
                values.append(current)
                current += step
            }
        } else {
            while current > stop {
                values.append(current)
                current += step
            }
        }
        return values
    }

    private static func starlarkRangeLength(for value: ConfigValue) -> Int {
        guard case let .range(start, stop, step) = value else {
            return 0
        }
        return starlarkRangeLength(start: start, stop: stop, step: step)
    }

    private static func starlarkRangeLength(start: Int, stop: Int, step: Int) -> Int {
        guard step != 0 else {
            return 0
        }
        if start == stop {
            return 0
        }
        if (stop >= start) != (step > 0) {
            return 0
        }
        let distance = step > 0 ? stop - start : start - stop
        let stride = abs(step)
        return (distance - 1) / stride + 1
    }

    private static func starlarkRangeDisplay(start: Int, stop: Int, step: Int) -> String {
        if step != 1 {
            return "range(\(start), \(stop), \(step))"
        }
        if start != 0 {
            return "range(\(start), \(stop))"
        }
        return "range(\(stop))"
    }

    private static func starlarkRangeContains(_ value: Int, start: Int, stop: Int, step: Int) -> Bool {
        guard starlarkRangeLength(start: start, stop: stop, step: step) > 0 else {
            return false
        }
        if step > 0 {
            guard value >= start, value < stop else {
                return false
            }
            return (value - start) % step == 0
        } else {
            guard value <= start, value > stop else {
                return false
            }
            return (start - value) % abs(step) == 0
        }
    }

    private static func matchingTopLevelCallOpen(in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var candidate: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                if squareDepth == 0, braceDepth == 0, parenDepth == 0 {
                    candidate = index
                }
                parenDepth += 1
            case ")":
                parenDepth -= 1
                if squareDepth == 0,
                   braceDepth == 0,
                   parenDepth == 0,
                   text.index(after: index) != text.endIndex {
                    candidate = nil
                }
            default:
                break
            }

            index = text.index(after: index)
        }

        return squareDepth == 0 && braceDepth == 0 && parenDepth == 0 ? candidate : nil
    }

    private static func parseStarlarkIndexExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard text.hasSuffix("]"),
              let openIndex = matchingTopLevelIndexOpen(in: text)
        else {
            return nil
        }

        let baseText = String(text[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseText.isEmpty else {
            return nil
        }
        let indexStart = text.index(after: openIndex)
        let indexText = String(text[indexStart..<text.index(before: text.endIndex)])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = try parsePolicyLiteral(baseText, constants: constants, functions: functions)
        if indexText.contains(":") {
            return try parseStarlarkSliceExpression(
                base,
                indexText: indexText,
                constants: constants,
                functions: functions,
                expression: text
            )
        }
        switch base {
        case let .array(items):
            let itemIndex = try parseStarlarkInteger(
                indexText,
                constants: constants,
                functions: functions,
                expression: text
            )
            let resolvedIndex = itemIndex >= 0 ? itemIndex : items.count + itemIndex
            guard items.indices.contains(resolvedIndex) else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return items[resolvedIndex]
        case let .range(start, stop, step):
            let itemIndex = try parseStarlarkInteger(
                indexText,
                constants: constants,
                functions: functions,
                expression: text
            )
            let length = starlarkRangeLength(start: start, stop: stop, step: step)
            let resolvedIndex = itemIndex >= 0 ? itemIndex : length + itemIndex
            guard resolvedIndex >= 0, resolvedIndex < length else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return .integer(Int64(start + step * resolvedIndex))
        case let .string(value):
            let characters = Array(value)
            let itemIndex = try parseStarlarkInteger(
                indexText,
                constants: constants,
                functions: functions,
                expression: text
            )
            let resolvedIndex = itemIndex >= 0 ? itemIndex : characters.count + itemIndex
            guard characters.indices.contains(resolvedIndex) else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return .string(String(characters[resolvedIndex]))
        case let .table(items):
            let key = try parsePolicyLiteral(indexText, constants: constants, functions: functions)
            guard case let .string(key) = key,
                  let value = items[key]
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return value
        default:
            throw ConfigOverrideError.invalidLiteral(text)
        }
    }

    private static func parseStarlarkSliceExpression(
        _ base: ConfigValue,
        indexText: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> ConfigValue {
        let pieces = splitTopLevel(indexText, separator: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...3).contains(pieces.count) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        let start = try parseOptionalStarlarkInteger(
            pieces[0],
            constants: constants,
            functions: functions,
            expression: expression
        )
        let stop = try parseOptionalStarlarkInteger(
            pieces[1],
            constants: constants,
            functions: functions,
            expression: expression
        )
        let step: Int?
        if pieces.count == 3 {
            step = try parseOptionalStarlarkInteger(
                pieces[2],
                constants: constants,
                functions: functions,
                expression: expression
            )
        } else {
            step = nil
        }

        switch base {
        case let .array(items):
            let indexes = try starlarkSliceIndexes(
                count: items.count,
                start: start,
                stop: stop,
                step: step,
                expression: expression
            )
            return .array(indexes.map { items[$0] })
        case let .range(rangeStart, _, rangeStep):
            let length = starlarkRangeLength(for: base)
            let indexes = try starlarkSliceIndexes(
                count: length,
                start: start,
                stop: stop,
                step: step,
                expression: expression
            )
            guard let first = indexes.first else {
                return .range(start: 0, stop: 0, step: 1)
            }
            let sliceStep = (indexes.dropFirst().first ?? (first + 1)) - first
            let newStart = rangeStart + rangeStep * first
            let newStep = rangeStep * sliceStep
            let newStop = rangeStart + rangeStep * (indexes.last! + sliceStep)
            return .range(start: newStart, stop: newStop, step: newStep)
        case let .string(value):
            let characters = Array(value)
            let indexes = try starlarkSliceIndexes(
                count: characters.count,
                start: start,
                stop: stop,
                step: step,
                expression: expression
            )
            return .string(String(indexes.map { characters[$0] }))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func parseOptionalStarlarkInteger(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> Int? {
        guard !text.isEmpty else {
            return nil
        }
        return try parseStarlarkInteger(text, constants: constants, functions: functions, expression: expression)
    }

    private static func starlarkSliceIndexes(
        count: Int,
        start rawStart: Int?,
        stop rawStop: Int?,
        step rawStep: Int?,
        expression: String
    ) throws -> [Int] {
        let step = rawStep ?? 1
        guard step != 0 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }

        var indexes: [Int] = []
        if step > 0 {
            let lower = normalizedPositiveSliceBound(rawStart, count: count, defaultValue: 0)
            let upper = normalizedPositiveSliceBound(rawStop, count: count, defaultValue: count)
            var index = lower
            while index < upper {
                indexes.append(index)
                index += step
            }
        } else {
            let lower = normalizedNegativeSliceBound(rawStart, count: count, defaultValue: count - 1)
            let upper = normalizedNegativeSliceBound(rawStop, count: count, defaultValue: -1)
            var index = lower
            while index > upper {
                indexes.append(index)
                index += step
            }
        }
        return indexes
    }

    private static func normalizedPositiveSliceBound(_ value: Int?, count: Int, defaultValue: Int) -> Int {
        var resolved = value ?? defaultValue
        if resolved < 0 {
            resolved += count
        }
        return min(max(resolved, 0), count)
    }

    private static func normalizedNegativeSliceBound(_ value: Int?, count: Int, defaultValue: Int) -> Int {
        var resolved = value ?? defaultValue
        if resolved < 0, value != nil {
            resolved += count
        }
        return min(max(resolved, -1), count - 1)
    }

    private static func parseStarlarkInteger(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> Int {
        let value = try parsePolicyLiteral(text, constants: constants, functions: functions)
        guard case let .integer(raw) = value,
              let integer = Int(exactly: raw)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return integer
    }

    private static func parseStarlarkInt32(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String
    ) throws -> Int {
        let integer = try parseStarlarkInteger(text, constants: constants, functions: functions, expression: expression)
        guard integer >= Int(Int32.min), integer <= Int(Int32.max) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return integer
    }

    private static func matchingTopLevelIndexOpen(in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var candidate: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                if squareDepth == 0, braceDepth == 0, parenDepth == 0 {
                    candidate = index
                }
                squareDepth += 1
            case "]":
                squareDepth -= 1
                if squareDepth == 0,
                   braceDepth == 0,
                   parenDepth == 0,
                   text.index(after: index) != text.endIndex {
                    candidate = nil
                }
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            default:
                break
            }

            index = text.index(after: index)
        }

        return squareDepth == 0 && braceDepth == 0 && parenDepth == 0 ? candidate : nil
    }

    private static func parseStarlarkListComprehension(
        _ body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> [ConfigValue]? {
        guard let forRange = topLevelKeywordRange("for", in: body) else {
            return nil
        }

        let expression = String(body[..<forRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            throw ConfigOverrideError.invalidLiteral("[\(body)]")
        }
        let clauses = try parseStarlarkComprehensionClauses(
            String(body[forRange.lowerBound...]),
            expression: "[\(body)]"
        )

        var result: [ConfigValue] = []
        try evaluateStarlarkComprehensionClauses(
            clauses,
            constants: constants,
            functions: functions,
            expression: "[\(body)]"
        ) { scopedConstants in
            result.append(try parsePolicyLiteral(expression, constants: scopedConstants, functions: functions))
        }
        return result
    }

    private static func parseStarlarkDictLiteral(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue {
        let body = String(text.dropFirst().dropLast())
        if let comprehension = try parseStarlarkDictComprehension(
            body,
            constants: constants,
            functions: functions
        ) {
            return .table(comprehension)
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .table([:])
        }

        var table: [String: ConfigValue] = [:]
        for pair in splitTopLevel(body, separator: ",") {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard let colonIndex = topLevelColonIndex(in: trimmed) else {
                throw ConfigOverrideError.invalidLiteral(text)
            }

            let rawKey = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: colonIndex)
            let rawValue = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = try parsePolicyLiteral(rawKey, constants: constants, functions: functions)
            guard case let .string(key) = key,
                  !rawValue.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            table[key] = try parsePolicyLiteral(rawValue, constants: constants, functions: functions)
        }
        return .table(table)
    }

    private static func parseStarlarkDictComprehension(
        _ body: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> [String: ConfigValue]? {
        guard let forRange = topLevelKeywordRange("for", in: body) else {
            return nil
        }

        let keyValueText = String(body[..<forRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = topLevelColonIndex(in: keyValueText) else {
            throw ConfigOverrideError.invalidLiteral("{\(body)}")
        }
        let rawKey = String(keyValueText[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStart = keyValueText.index(after: colonIndex)
        let rawValue = String(keyValueText[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawKey.isEmpty,
              !rawValue.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral("{\(body)}")
        }
        let clauses = try parseStarlarkComprehensionClauses(
            String(body[forRange.lowerBound...]),
            expression: "{\(body)}"
        )

        var table: [String: ConfigValue] = [:]
        try evaluateStarlarkComprehensionClauses(
            clauses,
            constants: constants,
            functions: functions,
            expression: "{\(body)}"
        ) { scopedConstants in
            let key = try parsePolicyLiteral(rawKey, constants: scopedConstants, functions: functions)
            guard case let .string(key) = key else {
                throw ConfigOverrideError.invalidLiteral("{\(body)}")
            }
            table[key] = try parsePolicyLiteral(rawValue, constants: scopedConstants, functions: functions)
        }
        return table
    }

    private enum StarlarkComprehensionClause {
        case forLoop(targets: [String], iterableText: String)
        case condition(String)
    }

    private static func parseStarlarkComprehensionClauses(
        _ text: String,
        expression: String
    ) throws -> [StarlarkComprehensionClause] {
        var clauses: [StarlarkComprehensionClause] = []
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while !remaining.isEmpty {
            if let forRange = topLevelKeywordRange("for", in: remaining),
               forRange.lowerBound == remaining.startIndex {
                guard let inRange = topLevelKeywordRange("in", in: remaining, startingAt: forRange.upperBound) else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let targetText = String(remaining[forRange.upperBound..<inRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let clauseRemainder = String(remaining[inRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let nextClauseRange = firstTopLevelKeywordRange(["for", "if"], in: clauseRemainder)?.range
                let iterableText: String
                if let nextClauseRange {
                    iterableText = String(clauseRemainder[..<nextClauseRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    remaining = String(clauseRemainder[nextClauseRange.lowerBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    iterableText = clauseRemainder
                    remaining = ""
                }
                guard !iterableText.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                let targets = try parseStarlarkLoopTargets(targetText, expression: expression)
                clauses.append(.forLoop(targets: targets, iterableText: iterableText))
            } else if let ifRange = topLevelKeywordRange("if", in: remaining),
                      ifRange.lowerBound == remaining.startIndex {
                let clauseRemainder = String(remaining[ifRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let nextClauseRange = firstTopLevelKeywordRange(["for", "if"], in: clauseRemainder)?.range
                let condition: String
                if let nextClauseRange {
                    condition = String(clauseRemainder[..<nextClauseRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    remaining = String(clauseRemainder[nextClauseRange.lowerBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    condition = clauseRemainder
                    remaining = ""
                }
                guard !condition.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                clauses.append(.condition(condition))
            } else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
        }

        guard !clauses.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return clauses
    }

    private static func evaluateStarlarkComprehensionClauses(
        _ clauses: [StarlarkComprehensionClause],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String,
        append: ([String: ConfigValue]) throws -> Void
    ) throws {
        try evaluateStarlarkComprehensionClause(
            at: clauses.startIndex,
            clauses: clauses,
            constants: constants,
            functions: functions,
            expression: expression,
            append: append
        )
    }

    private static func evaluateStarlarkComprehensionClause(
        at index: [StarlarkComprehensionClause].Index,
        clauses: [StarlarkComprehensionClause],
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction],
        expression: String,
        append: ([String: ConfigValue]) throws -> Void
    ) throws {
        guard index < clauses.endIndex else {
            try append(constants)
            return
        }

        switch clauses[index] {
        case let .forLoop(targets, iterableText):
            let iterable = try parsePolicyLiteral(iterableText, constants: constants, functions: functions)
            let items = try starlarkIterableItems(iterable, expression: expression)
            for item in items {
                var scopedConstants = constants
                try bindStarlarkLoopTargets(targets, to: item, constants: &scopedConstants, expression: expression)
                try evaluateStarlarkComprehensionClause(
                    at: clauses.index(after: index),
                    clauses: clauses,
                    constants: scopedConstants,
                    functions: functions,
                    expression: expression,
                    append: append
                )
            }
        case let .condition(condition):
            if try evaluateStarlarkCondition(condition, constants: constants, functions: functions) {
                try evaluateStarlarkComprehensionClause(
                    at: clauses.index(after: index),
                    clauses: clauses,
                    constants: constants,
                    functions: functions,
                    expression: expression,
                    append: append
                )
            }
        }
    }

    private static func firstTopLevelKeywordRange(
        _ keywords: [String],
        in text: String
    ) -> (keyword: String, range: Range<String.Index>)? {
        var match: (keyword: String, range: Range<String.Index>)?
        for keyword in keywords {
            guard let range = topLevelKeywordRange(keyword, in: text) else {
                continue
            }
            if match == nil || range.lowerBound < match!.range.lowerBound {
                match = (keyword, range)
            }
        }
        return match
    }

    private static func topLevelColonIndex(in text: String) -> String.Index? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            case ":" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                return index
            default:
                break
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func topLevelKeywordRange(
        _ keyword: String,
        in text: String,
        startingAt start: String.Index? = nil
    ) -> Range<String.Index>? {
        topLevelTokenRange(keyword, in: text, startingAt: start, requiresIdentifierBoundaries: true)
    }

    private static func topLevelOperatorRange(
        _ operatorText: String,
        in text: String,
        startingAt start: String.Index? = nil
    ) -> Range<String.Index>? {
        var searchStart = start
        while let range = topLevelTokenRange(
            operatorText,
            in: text,
            startingAt: searchStart,
            requiresIdentifierBoundaries: false
        ) {
            guard !isShiftTokenPart(range, operatorText: operatorText, in: text) else {
                searchStart = range.upperBound
                continue
            }
            return range
        }
        return nil
    }

    private static func isShiftTokenPart(
        _ range: Range<String.Index>,
        operatorText: String,
        in text: String
    ) -> Bool {
        guard operatorText == "<" || operatorText == ">" else {
            return false
        }
        if range.lowerBound > text.startIndex,
           text[text.index(before: range.lowerBound)] == Character(operatorText) {
            return true
        }
        if range.upperBound < text.endIndex,
           text[range.upperBound] == Character(operatorText) {
            return true
        }
        return false
    }

    private static func topLevelTokenRange(
        _ token: String,
        in text: String,
        startingAt start: String.Index? = nil,
        requiresIdentifierBoundaries: Bool
    ) -> Range<String.Index>? {
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = start ?? text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
            default:
                break
            }

            if squareDepth == 0,
               braceDepth == 0,
               parenDepth == 0,
               text[index...].hasPrefix(token) {
                let end = text.index(index, offsetBy: token.count)
                if !requiresIdentifierBoundaries ||
                    (isIdentifierBoundaryBefore(index, in: text) && isIdentifierBoundaryAfter(end, in: text)) {
                    return index..<end
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func evaluateStarlarkCondition(
        _ condition: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> Bool {
        let trimmed = strippingEnclosingParentheses(from: condition.trimmingCharacters(in: .whitespacesAndNewlines))
        let orPieces = splitTopLevelKeywordExpression(trimmed, keyword: "or")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if orPieces.count > 1 {
            for piece in orPieces {
                guard !piece.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(condition)
                }
                if try evaluateStarlarkCondition(piece, constants: constants, functions: functions) {
                    return true
                }
            }
            return false
        }

        let andPieces = splitTopLevelKeywordExpression(trimmed, keyword: "and")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if andPieces.count > 1 {
            for piece in andPieces {
                guard !piece.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(condition)
                }
                if try !evaluateStarlarkCondition(piece, constants: constants, functions: functions) {
                    return false
                }
            }
            return true
        }

        if let notRange = topLevelKeywordRange("not", in: trimmed),
           notRange.lowerBound == trimmed.startIndex {
            let operand = String(trimmed[notRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !operand.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(condition)
            }
            return try !evaluateStarlarkCondition(operand, constants: constants, functions: functions)
        }

        let comparisonPieces = splitTopLevelComparisonExpression(trimmed)
        if comparisonPieces.count > 1 {
            guard comparisonPieces[0].operator == nil,
                  !comparisonPieces[0].text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(condition)
            }

            var previous = try parsePolicyLiteral(comparisonPieces[0].text, constants: constants, functions: functions)
            for piece in comparisonPieces.dropFirst() {
                guard let operatorText = piece.operator,
                      !piece.text.isEmpty
                else {
                    throw ConfigOverrideError.invalidLiteral(condition)
                }

                let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
                let comparison: Bool
                switch operatorText {
                case "==":
                    comparison = starlarkValuesEqual(previous, next)
                case "!=":
                    comparison = !starlarkValuesEqual(previous, next)
                case "<=":
                    comparison = try compareStarlarkValues(previous, next, expression: condition) <= 0
                case ">=":
                    comparison = try compareStarlarkValues(previous, next, expression: condition) >= 0
                case "<":
                    comparison = try compareStarlarkValues(previous, next, expression: condition) < 0
                case ">":
                    comparison = try compareStarlarkValues(previous, next, expression: condition) > 0
                case "not in":
                    comparison = try !containsStarlarkValue(previous, in: next, expression: condition)
                case "in":
                    comparison = try containsStarlarkValue(previous, in: next, expression: condition)
                case "is":
                    comparison = starlarkIdentityMatches(previous, next)
                case "is not":
                    comparison = !starlarkIdentityMatches(previous, next)
                default:
                    throw ConfigOverrideError.invalidLiteral(condition)
                }

                if !comparison {
                    return false
                }
                previous = next
            }
            return true
        }

        return try truthy(parsePolicyLiteral(trimmed, constants: constants, functions: functions))
    }

    private static func splitTopLevelComparisonExpression(_ text: String) -> [(operator: String?, text: String)] {
        var pieces: [(operator: String?, text: String)] = []
        var current = ""
        var currentOperator: String?
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            default:
                if squareDepth == 0,
                   braceDepth == 0,
                   parenDepth == 0,
                   let operatorText = comparisonOperator(at: index, in: text) {
                    pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                    current = ""
                    currentOperator = operatorText
                    index = text.index(index, offsetBy: operatorText.count)
                    continue
                }
                current.append(character)
            }

            index = text.index(after: index)
        }

        pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
        return pieces
    }

    private static func comparisonOperator(at index: String.Index, in text: String) -> String? {
        for keyword in ["is not", "not in", "is", "in"] where text[index...].hasPrefix(keyword) {
            let end = text.index(index, offsetBy: keyword.count)
            if isIdentifierBoundaryBefore(index, in: text),
               isIdentifierBoundaryAfter(end, in: text) {
                return keyword
            }
        }

        for operatorText in ["==", "!=", "<=", ">="] where text[index...].hasPrefix(operatorText) {
            return operatorText
        }

        let operatorText = String(text[index])
        guard operatorText == "<" || operatorText == ">",
              !isShiftTokenPart(index..<text.index(after: index), operatorText: operatorText, in: text)
        else {
            return nil
        }
        return operatorText
    }

    private static func compareStarlarkValues(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> Int {
        switch (lhs, rhs) {
        case let (.integer(lhs), .integer(rhs)):
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        case let (.double(lhs), .double(rhs)):
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        case let (.integer(lhs), .double(rhs)):
            let lhs = Double(lhs)
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        case let (.double(lhs), .integer(rhs)):
            let rhs = Double(rhs)
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        case let (.bool(lhs), .bool(rhs)):
            return lhs == rhs ? 0 : (!lhs && rhs ? -1 : 1)
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        case let (.array(lhs), .array(rhs)):
            let sharedCount = Swift.min(lhs.count, rhs.count)
            for index in 0..<sharedCount {
                let comparison = try compareStarlarkValues(lhs[index], rhs[index], expression: expression)
                if comparison != 0 {
                    return comparison
                }
            }
            return lhs.count == rhs.count ? 0 : (lhs.count < rhs.count ? -1 : 1)
        case let (.range(lhsStart, lhsStop, lhsStep), .range(rhsStart, rhsStop, rhsStep)):
            if starlarkRangesEqual(
                lhsStart: lhsStart,
                lhsStop: lhsStop,
                lhsStep: lhsStep,
                rhsStart: rhsStart,
                rhsStop: rhsStop,
                rhsStep: rhsStep
            ) {
                return 0
            }
            throw ConfigOverrideError.invalidLiteral(expression)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkValuesEqual(_ lhs: ConfigValue, _ rhs: ConfigValue) -> Bool {
        switch (lhs, rhs) {
        case let (.range(lhsStart, lhsStop, lhsStep), .range(rhsStart, rhsStop, rhsStep)):
            return starlarkRangesEqual(
                lhsStart: lhsStart,
                lhsStop: lhsStop,
                lhsStep: lhsStep,
                rhsStart: rhsStart,
                rhsStop: rhsStop,
                rhsStep: rhsStep
            )
        case let (.array(lhs), .array(rhs)):
            guard lhs.count == rhs.count else {
                return false
            }
            return zip(lhs, rhs).allSatisfy(starlarkValuesEqual)
        case let (.table(lhs), .table(rhs)):
            guard lhs.keys == rhs.keys else {
                return false
            }
            return lhs.allSatisfy { key, value in
                guard let rhsValue = rhs[key] else {
                    return false
                }
                return starlarkValuesEqual(value, rhsValue)
            }
        default:
            return lhs == rhs
        }
    }

    private static func starlarkRangesEqual(
        lhsStart: Int,
        lhsStop: Int,
        lhsStep: Int,
        rhsStart: Int,
        rhsStop: Int,
        rhsStep: Int
    ) -> Bool {
        let lhsLength = starlarkRangeLength(start: lhsStart, stop: lhsStop, step: lhsStep)
        let rhsLength = starlarkRangeLength(start: rhsStart, stop: rhsStop, step: rhsStep)
        if lhsLength == 0 || rhsLength == 0 {
            return lhsLength == rhsLength
        }
        guard lhsStart == rhsStart else {
            return false
        }
        if lhsLength == 1 || rhsLength == 1 {
            return lhsLength == rhsLength
        }
        return lhsStep == rhsStep && lhsLength == rhsLength
    }

    private static func containsStarlarkValue(
        _ needle: ConfigValue,
        in haystack: ConfigValue,
        expression: String
    ) throws -> Bool {
        switch haystack {
        case let .array(items):
            return items.contains { starlarkValuesEqual($0, needle) }
        case let .table(items):
            guard case let .string(key) = needle else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return items[key] != nil
        case let .string(value):
            guard case let .string(needle) = needle else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return value.contains(needle)
        case let .range(start, stop, step):
            guard case let .integer(rawNeedle) = needle,
                  let needle = Int(exactly: rawNeedle)
            else {
                return false
            }
            return starlarkRangeContains(needle, start: start, stop: stop, step: step)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func starlarkIdentityMatches(_ lhs: ConfigValue, _ rhs: ConfigValue) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.bool(lhs), .bool(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    private static func splitTopLevelKeywordExpression(_ text: String, keyword: String) -> [String] {
        var pieces: [String] = []
        var start = text.startIndex
        var searchStart = text.startIndex
        while let range = topLevelKeywordRange(keyword, in: text, startingAt: searchStart) {
            pieces.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
            searchStart = range.upperBound
        }
        pieces.append(String(text[start...]))
        return pieces
    }

    private static func truthy(_ value: ConfigValue) -> Bool {
        switch value {
        case let .bool(value):
            return value
        case let .string(value):
            return !value.isEmpty
        case let .array(items):
            return !items.isEmpty
        case let .table(items):
            return !items.isEmpty
        case let .range(start, stop, step):
            return starlarkRangeLength(start: start, stop: stop, step: step) > 0
        case let .integer(value):
            return value != 0
        case let .double(value):
            return value != 0
        case .none:
            return false
        }
    }

    private static func parseStarlarkBooleanExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let orPieces = splitTopLevelKeywordExpression(text, keyword: "or")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if orPieces.count > 1 {
            var lastValue: ConfigValue = .none
            for piece in orPieces {
                guard !piece.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                let value = try parsePolicyLiteral(piece, constants: constants, functions: functions)
                lastValue = value
                if truthy(value) {
                    return value
                }
            }
            return lastValue
        }

        let andPieces = splitTopLevelKeywordExpression(text, keyword: "and")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if andPieces.count > 1 {
            var lastValue: ConfigValue = .none
            for piece in andPieces {
                guard !piece.isEmpty else {
                    throw ConfigOverrideError.invalidLiteral(text)
                }
                let value = try parsePolicyLiteral(piece, constants: constants, functions: functions)
                lastValue = value
                if !truthy(value) {
                    return value
                }
            }
            return lastValue
        }

        if let notRange = topLevelKeywordRange("not", in: text),
           notRange.lowerBound == text.startIndex {
            let operand = String(text[notRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !operand.isEmpty else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return try .bool(!truthy(parsePolicyLiteral(operand, constants: constants, functions: functions)))
        }

        if splitTopLevelComparisonExpression(text).count > 1 {
            return try .bool(evaluateStarlarkCondition(text, constants: constants, functions: functions))
        }
        return nil
    }

    private static func parseStarlarkConditionalExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard let ifRange = topLevelKeywordRange("if", in: text),
              let elseRange = topLevelKeywordRange("else", in: text, startingAt: ifRange.upperBound)
        else {
            return nil
        }

        let consequence = String(text[..<ifRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = String(text[ifRange.upperBound..<elseRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let alternative = String(text[elseRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consequence.isEmpty,
              !condition.isEmpty,
              !alternative.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        let selected = try evaluateStarlarkCondition(condition, constants: constants, functions: functions)
            ? consequence
            : alternative
        return try parsePolicyLiteral(selected, constants: constants, functions: functions)
    }

    private static func parseStarlarkAdditiveExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelAdditiveExpression(text)
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard let operatorText = piece.operator,
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            switch operatorText {
            case "+":
                result = try evaluateStarlarkAddition(result, next, expression: text)
            case "-":
                result = try evaluateStarlarkSubtraction(result, next, expression: text)
            default:
                throw ConfigOverrideError.invalidLiteral(text)
            }
        }

        return result
    }

    private static func parseStarlarkBitwiseOrExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelBitwiseExpression(text, operators: ["|"])
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard piece.operator == "|",
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            result = try evaluateStarlarkUnion(result, next, expression: text)
        }
        return result
    }

    private static func parseStarlarkBitwiseXorExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelBitwiseExpression(text, operators: ["^"])
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard piece.operator == "^",
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            result = try evaluateStarlarkIntegerBitwise(result, next, operatorText: "^", expression: text)
        }
        return result
    }

    private static func parseStarlarkBitwiseAndExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelBitwiseExpression(text, operators: ["&"])
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard piece.operator == "&",
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            result = try evaluateStarlarkIntegerBitwise(result, next, operatorText: "&", expression: text)
        }
        return result
    }

    private static func parseStarlarkShiftExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelBitwiseExpression(text, operators: ["<<", ">>"])
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard let operatorText = piece.operator,
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            result = try evaluateStarlarkIntegerShift(result, next, operatorText: operatorText, expression: text)
        }
        return result
    }

    private static func parseStarlarkUnaryNumericExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        guard let sign = text.first,
              sign == "-" || sign == "+" || sign == "~",
              text.dropFirst().first?.isWhitespace != true
        else {
            return nil
        }
        let operandText = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !operandText.isEmpty else {
            throw ConfigOverrideError.invalidLiteral(text)
        }
        let operand = try parsePolicyLiteral(operandText, constants: constants, functions: functions)
        switch operand {
        case let .integer(value):
            switch sign {
            case "-":
                return .integer(-value)
            case "~":
                return .integer(~value)
            default:
                return .integer(value)
            }
        case let .double(value):
            guard sign != "~" else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            return .double(sign == "-" ? -value : value)
        default:
            throw ConfigOverrideError.invalidLiteral(text)
        }
    }

    private static func parseStarlarkMultiplicativeExpression(
        _ text: String,
        constants: [String: ConfigValue],
        functions: [String: StarlarkFunction]
    ) throws -> ConfigValue? {
        let pieces = splitTopLevelMultiplicativeExpression(text)
        guard pieces.count > 1 else {
            return nil
        }
        guard let first = pieces.first,
              first.operator == nil,
              !first.text.isEmpty
        else {
            throw ConfigOverrideError.invalidLiteral(text)
        }

        var result = try parsePolicyLiteral(first.text, constants: constants, functions: functions)
        for piece in pieces.dropFirst() {
            guard let operatorText = piece.operator,
                  !piece.text.isEmpty
            else {
                throw ConfigOverrideError.invalidLiteral(text)
            }
            let next = try parsePolicyLiteral(piece.text, constants: constants, functions: functions)
            switch operatorText {
            case "*":
                result = try evaluateStarlarkMultiplication(result, next, expression: text)
            case "/":
                result = try evaluateStarlarkDivision(result, next, expression: text)
            case "//":
                result = try evaluateStarlarkFloorDivision(result, next, expression: text)
            case "%":
                result = try evaluateStarlarkModulo(result, next, expression: text)
            default:
                throw ConfigOverrideError.invalidLiteral(text)
            }
        }

        return result
    }

    private static func evaluateStarlarkAddition(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case let (.string(lhs), .string(rhs)):
            return .string(lhs + rhs)
        case let (.array(lhs), .array(rhs)):
            return .array(lhs + rhs)
        case let (.integer(lhs), .integer(rhs)):
            return .integer(lhs + rhs)
        case let (.double(lhs), .double(rhs)):
            return .double(lhs + rhs)
        case let (.integer(lhs), .double(rhs)):
            return .double(Double(lhs) + rhs)
        case let (.double(lhs), .integer(rhs)):
            return .double(lhs + Double(rhs))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkSubtraction(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case let (.integer(lhs), .integer(rhs)):
            return .integer(lhs - rhs)
        case let (.double(lhs), .double(rhs)):
            return .double(lhs - rhs)
        case let (.integer(lhs), .double(rhs)):
            return .double(Double(lhs) - rhs)
        case let (.double(lhs), .integer(rhs)):
            return .double(lhs - Double(rhs))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkUnion(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case (var .table(lhsItems), let .table(rhsItems)):
            for (key, value) in rhsItems {
                lhsItems[key] = value
            }
            return .table(lhsItems)
        case let (.integer(lhs), .integer(rhs)):
            return .integer(lhs | rhs)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkIntegerBitwise(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        operatorText: String,
        expression: String
    ) throws -> ConfigValue {
        guard case let .integer(lhs) = lhs,
              case let .integer(rhs) = rhs
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        switch operatorText {
        case "&":
            return .integer(lhs & rhs)
        case "^":
            return .integer(lhs ^ rhs)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkIntegerShift(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        operatorText: String,
        expression: String
    ) throws -> ConfigValue {
        guard case let .integer(lhs) = lhs,
              case let .integer(rhs) = rhs,
              rhs >= 0,
              let shift = Int(exactly: rhs)
        else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        switch operatorText {
        case "<<":
            var result = lhs
            for _ in 0..<shift {
                let (next, overflow) = result.multipliedReportingOverflow(by: 2)
                guard !overflow else {
                    throw ConfigOverrideError.invalidLiteral(expression)
                }
                result = next
            }
            return .integer(result)
        case ">>":
            return .integer(shift >= Int64.bitWidth ? (lhs < 0 ? -1 : 0) : lhs >> shift)
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func evaluateStarlarkMultiplication(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case let (.string(lhs), .integer(rhs)):
            return .string(try repeatingStarlarkString(lhs, count: rhs, expression: expression))
        case let (.integer(lhs), .string(rhs)):
            return .string(try repeatingStarlarkString(rhs, count: lhs, expression: expression))
        case let (.array(lhs), .integer(rhs)):
            return .array(try repeatingStarlarkArray(lhs, count: rhs, expression: expression))
        case let (.integer(lhs), .array(rhs)):
            return .array(try repeatingStarlarkArray(rhs, count: lhs, expression: expression))
        case let (.integer(lhs), .integer(rhs)):
            return .integer(lhs * rhs)
        case let (.double(lhs), .double(rhs)):
            return .double(lhs * rhs)
        case let (.integer(lhs), .double(rhs)):
            return .double(Double(lhs) * rhs)
        case let (.double(lhs), .integer(rhs)):
            return .double(lhs * Double(rhs))
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func repeatingStarlarkString(
        _ string: String,
        count rawCount: Int64,
        expression: String
    ) throws -> String {
        guard let count = Int(exactly: rawCount) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        guard count > 0 else {
            return ""
        }
        return String(repeating: string, count: count)
    }

    private static func repeatingStarlarkArray(
        _ items: [ConfigValue],
        count rawCount: Int64,
        expression: String
    ) throws -> [ConfigValue] {
        guard let count = Int(exactly: rawCount) else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        guard count > 0 else {
            return []
        }
        return Array(repeating: items, count: count).flatMap { $0 }
    }

    private static func evaluateStarlarkDivision(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        let denominator = try numericDouble(rhs, expression: expression)
        guard denominator != 0 else {
            throw ConfigOverrideError.invalidLiteral(expression)
        }
        return .double(try numericDouble(lhs, expression: expression) / denominator)
    }

    private static func evaluateStarlarkFloorDivision(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case let (.integer(lhs), .integer(rhs)):
            guard rhs != 0 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return .integer(floorDividing(lhs, by: rhs))
        default:
            let denominator = try numericDouble(rhs, expression: expression)
            guard denominator != 0 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return .double(floor(try numericDouble(lhs, expression: expression) / denominator))
        }
    }

    private static func evaluateStarlarkModulo(
        _ lhs: ConfigValue,
        _ rhs: ConfigValue,
        expression: String
    ) throws -> ConfigValue {
        switch (lhs, rhs) {
        case let (.string(format), rhs):
            return .string(try formattingStarlarkPercentString(format, argument: rhs, expression: expression))
        case let (.integer(lhs), .integer(rhs)):
            guard rhs != 0 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            return .integer(lhs - floorDividing(lhs, by: rhs) * rhs)
        default:
            let denominator = try numericDouble(rhs, expression: expression)
            guard denominator != 0 else {
                throw ConfigOverrideError.invalidLiteral(expression)
            }
            let numerator = try numericDouble(lhs, expression: expression)
            return .double(numerator - floor(numerator / denominator) * denominator)
        }
    }

    private static func floorDividing(_ lhs: Int64, by rhs: Int64) -> Int64 {
        let quotient = lhs / rhs
        let remainder = lhs % rhs
        if remainder != 0, (remainder > 0) != (rhs > 0) {
            return quotient - 1
        }
        return quotient
    }

    private static func numericDouble(_ value: ConfigValue, expression: String) throws -> Double {
        switch value {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        default:
            throw ConfigOverrideError.invalidLiteral(expression)
        }
    }

    private static func removingTrailingArrayCommas(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        var quote: Character?
        var previousWasBackslash = false

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                result.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "," {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex, text[lookahead] == "]" {
                    index = text.index(after: index)
                    continue
                }
            }

            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func parsePattern(_ value: ConfigValue) throws -> [PatternToken] {
        guard case let .array(items) = value else {
            throw ExecPolicyError.invalidPattern("pattern must be an array")
        }
        let tokens = try items.map(parsePatternToken)
        guard !tokens.isEmpty else {
            throw ExecPolicyError.invalidPattern("pattern cannot be empty")
        }
        return tokens
    }

    private static func parsePatternToken(_ value: ConfigValue) throws -> PatternToken {
        switch value {
        case let .string(token):
            return .single(token)
        case let .array(items):
            let alternatives = try items.map { item -> String in
                guard case let .string(token) = item else {
                    throw ExecPolicyError.invalidPattern("pattern alternative must be a string")
                }
                return token
            }
            switch alternatives.count {
            case 0:
                throw ExecPolicyError.invalidPattern("pattern alternatives cannot be empty")
            case 1:
                return .single(alternatives[0])
            default:
                return .alts(alternatives)
            }
        default:
            throw ExecPolicyError.invalidPattern("pattern element must be a string or list of strings")
        }
    }

    private static func parseExamples(_ value: ConfigValue) throws -> [[String]] {
        guard case let .array(items) = value else {
            throw ExecPolicyError.invalidExample("examples must be an array")
        }
        return try items.map(parseExample)
    }

    private static func parseExample(_ value: ConfigValue) throws -> [String] {
        switch value {
        case let .string(raw):
            let tokens = try ShellExampleParser.split(raw)
            guard !tokens.isEmpty else {
                throw ExecPolicyError.invalidExample("example cannot be an empty string")
            }
            return tokens
        case let .array(items):
            let tokens = try items.map { item -> String in
                guard case let .string(token) = item else {
                    throw ExecPolicyError.invalidExample("example tokens must be strings")
                }
                return token
            }
            guard !tokens.isEmpty else {
                throw ExecPolicyError.invalidExample("example cannot be an empty list")
            }
            return tokens
        default:
            throw ExecPolicyError.invalidExample("example must be a string or list of strings")
        }
    }

    private static func validateMatchExamples(
        policy: ExecPolicy,
        rules: [PrefixRule],
        matches: [[String]]
    ) throws {
        let unmatched = matches.filter { example in
            !policy.matchesForCommand(
                example,
                heuristicsFallback: nil,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            )
            .contains { ruleMatch in
                guard case .prefixRuleMatch = ruleMatch else {
                    return false
                }
                return true
            }
        }
        guard unmatched.isEmpty else {
            throw ExecPolicyError.exampleDidNotMatch(
                rules: rules.map(\.description),
                examples: unmatched.map(ShellExampleParser.join)
            )
        }
    }

    private static func validateNotMatchExamples(
        policy: ExecPolicy,
        rules: [PrefixRule],
        notMatches: [[String]]
    ) throws {
        for example in notMatches {
            let matches = policy.matchesForCommand(
                example,
                heuristicsFallback: nil,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            )
            if matches.contains(where: {
                guard case .prefixRuleMatch = $0 else {
                    return false
                }
                return true
            }) {
                throw ExecPolicyError.exampleDidMatch(
                    rule: rules.map(\.description).joined(separator: ", "),
                    example: ShellExampleParser.join(example)
                )
            }
        }
    }

    private static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        splitTopLevelExpression(text, separator: separator)
    }

    private static func splitTopLevelAdditiveExpression(_ text: String) -> [(operator: Character?, text: String)] {
        var pieces: [(operator: Character?, text: String)] = []
        var current = ""
        var currentOperator: Character?
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var previousSignificant: Character?

        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
                previousSignificant = character
            case "[":
                squareDepth += 1
                current.append(character)
                previousSignificant = character
            case "]":
                squareDepth -= 1
                current.append(character)
                previousSignificant = character
            case "{":
                braceDepth += 1
                current.append(character)
                previousSignificant = character
            case "}":
                braceDepth -= 1
                current.append(character)
                previousSignificant = character
            case "(":
                parenDepth += 1
                current.append(character)
                previousSignificant = character
            case ")":
                parenDepth -= 1
                current.append(character)
                previousSignificant = character
            case "+" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0 && isBinaryStarlarkAdditiveOperator(character, after: previousSignificant):
                pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                current = ""
                currentOperator = character
                previousSignificant = character
            case "-" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0 && isBinaryStarlarkAdditiveOperator(character, after: previousSignificant):
                pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                current = ""
                currentOperator = character
                previousSignificant = character
            default:
                current.append(character)
                if !character.isWhitespace {
                    previousSignificant = character
                }
            }
        }

        pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
        return pieces
    }

    private static func isBinaryStarlarkAdditiveOperator(_ operatorText: Character, after previous: Character?) -> Bool {
        guard operatorText == "+" || operatorText == "-",
              let previous
        else {
            return false
        }
        return !["+", "-", "*", "/", "%", "(", "[", "{", ",", ":", "<", ">", "=", "!"].contains(previous)
    }

    private static func splitTopLevelBitwiseExpression(
        _ text: String,
        operators: Set<String>
    ) -> [(operator: String?, text: String)] {
        var pieces: [(operator: String?, text: String)] = []
        var current = ""
        var currentOperator: String?
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            default:
                if squareDepth == 0,
                   braceDepth == 0,
                   parenDepth == 0,
                   let operatorText = bitwiseOperator(at: index, in: text, matching: operators) {
                    pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                    current = ""
                    currentOperator = operatorText
                    index = text.index(index, offsetBy: operatorText.count)
                    continue
                } else {
                    current.append(character)
                }
            }
            index = text.index(after: index)
        }

        pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
        return pieces
    }

    private static func bitwiseOperator(
        at index: String.Index,
        in text: String,
        matching operators: Set<String>
    ) -> String? {
        if operators.contains("<<") || operators.contains(">>") {
            let next = text.index(after: index)
            if next < text.endIndex {
                let twoCharacterOperator = String(text[index...next])
                if operators.contains(twoCharacterOperator) {
                    return twoCharacterOperator
                }
            }
        }
        let oneCharacterOperator = String(text[index])
        return operators.contains(oneCharacterOperator) ? oneCharacterOperator : nil
    }

    private static func splitTopLevelMultiplicativeExpression(_ text: String) -> [(operator: String?, text: String)] {
        var pieces: [(operator: String?, text: String)] = []
        var current = ""
        var currentOperator: String?
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            case "*" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                current = ""
                currentOperator = "*"
            case "/" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                let operatorText: String
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "/" {
                    operatorText = "//"
                    index = nextIndex
                } else {
                    operatorText = "/"
                }
                pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                current = ""
                currentOperator = operatorText
            case "%" where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
                current = ""
                currentOperator = "%"
            default:
                current.append(character)
            }
            index = text.index(after: index)
        }

        pieces.append((currentOperator, current.trimmingCharacters(in: .whitespacesAndNewlines)))
        return pieces
    }

    private static func splitTopLevelExpression(_ text: String, separator: Character) -> [String] {
        var pieces: [String] = []
        var current = ""
        var squareDepth = 0
        var braceDepth = 0
        var parenDepth = 0
        var quote: Character?
        var previousWasBackslash = false

        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[":
                squareDepth += 1
                current.append(character)
            case "]":
                squareDepth -= 1
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            case separator where squareDepth == 0 && braceDepth == 0 && parenDepth == 0:
                pieces.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        pieces.append(current)
        return pieces
    }
}

public enum ExecApprovalRequirement: Equatable, Sendable {
    case skip(bypassSandbox: Bool, proposedExecPolicyAmendment: ExecPolicyAmendment?)
    case needsApproval(reason: String?, proposedExecPolicyAmendment: ExecPolicyAmendment?)
    case forbidden(reason: String)

    public var proposedExecPolicyAmendment: ExecPolicyAmendment? {
        switch self {
        case let .skip(_, amendment), let .needsApproval(_, amendment):
            return amendment
        case .forbidden:
            return nil
        }
    }
}

private struct ExecPolicyCommands {
    let commands: [[String]]
    let usedComplexParsing: Bool
    let origin: ExecPolicyCommandOrigin

    var allowsAutoAmendment: Bool {
        !usedComplexParsing
    }
}

private enum ExecPolicyCommandOrigin {
    case generic
    case powerShell
}

public enum ExecPolicyInheritance {
    public static func childUsesParentExecPolicy(
        parentStack: ConfigLayerStack,
        childStack: ConfigLayerStack
    ) -> Bool {
        execPolicyConfigFolders(parentStack) == execPolicyConfigFolders(childStack) &&
            parentStack.ignoreUserAndProjectExecPolicyRules == childStack.ignoreUserAndProjectExecPolicyRules &&
            parentStack.requirements.execPolicy == childStack.requirements.execPolicy
    }

    private static func execPolicyConfigFolders(_ stack: ConfigLayerStack) -> [AbsolutePath] {
        stack.getLayers(ordering: .lowestPrecedenceFirst).compactMap { $0.configFolder() }
    }
}

public final class ExecPolicyManager: @unchecked Sendable {
    public static let rulesDirectoryName = "rules"
    public static let defaultPolicyFileName = "default.rules"
    public static let forbiddenReason = "execpolicy forbids this command"
    public static let promptConflictReason = "execpolicy requires approval for this command, but AskForApproval is set to Never"
    public static let granularSandboxApprovalConflictReason = "approval required by policy, but AskForApproval::Granular.sandbox_approval is false"
    public static let granularRulesApprovalConflictReason = "approval required by policy rule, but AskForApproval::Granular.rules is false"
    public static let promptReason = "execpolicy requires approval for this command"

    private var policy: ExecPolicy

    public init(policy: ExecPolicy = .empty()) {
        self.policy = policy
    }

    public func current() -> ExecPolicy {
        policy
    }

    public static func load(
        features: FeatureStates,
        configStack: ConfigLayerStack,
        fileManager: FileManager = .default
    ) throws -> ExecPolicyManager {
        _ = features
        return ExecPolicyManager(policy: try loadExecPolicy(configStack: configStack, fileManager: fileManager))
    }

    public static func loadWithWarning(
        features: FeatureStates,
        configStack: ConfigLayerStack,
        fileManager: FileManager = .default
    ) throws -> (manager: ExecPolicyManager, warning: ExecPolicyLoadError?) {
        _ = features
        do {
            return (
                ExecPolicyManager(policy: try loadExecPolicy(configStack: configStack, fileManager: fileManager)),
                nil
            )
        } catch let error as ExecPolicyLoadError {
            if case .parsePolicy = error {
                return (ExecPolicyManager(policy: .empty()), error)
            }
            throw error
        }
    }

    public static func checkExecPolicyForWarnings(
        configStack: ConfigLayerStack,
        fileManager: FileManager = .default
    ) throws -> ExecPolicyLoadError? {
        try loadWithWarning(features: .withDefaults(), configStack: configStack, fileManager: fileManager).warning
    }

    public static func loadExecPolicy(
        configStack: ConfigLayerStack,
        fileManager: FileManager = .default
    ) throws -> ExecPolicy {
        var policyPaths: [URL] = []
        for layer in configStack.getLayers(ordering: .lowestPrecedenceFirst) {
            if configStack.ignoreUserAndProjectExecPolicyRules {
                switch layer.name {
                case .user, .project:
                    continue
                case .mdm, .system, .sessionFlags, .legacyManagedConfigTomlFromFile, .legacyManagedConfigTomlFromMdm:
                    break
                }
            }
            guard let configFolder = layer.configFolder() else {
                continue
            }
            let policyDirectory = URL(fileURLWithPath: configFolder.path, isDirectory: true)
                .appendingPathComponent(rulesDirectoryName, isDirectory: true)
            policyPaths.append(contentsOf: try collectPolicyFiles(in: policyDirectory, fileManager: fileManager))
        }

        let parser = PolicyParser()
        for policyPath in policyPaths {
            let contents: String
            do {
                contents = try String(contentsOf: policyPath, encoding: .utf8)
            } catch {
                throw ExecPolicyLoadError.readFile(path: policyPath.path, message: String(describing: error))
            }

            do {
                try parser.parse(policyPath.path, contents)
            } catch {
                throw ExecPolicyLoadError.parsePolicy(path: policyPath.path, message: String(describing: error))
            }
        }

        let policy = parser.build()
        guard let requirementsPolicy = configStack.requirements.execPolicy else {
            return policy
        }
        return policy.mergingOverlay(requirementsPolicy)
    }

    public static func collectPolicyFiles(
        in policyDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: policyDirectory.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw ExecPolicyLoadError.readDirectory(
                dir: policyDirectory.path,
                message: "path is not a directory"
            )
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: policyDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
        } catch {
            throw ExecPolicyLoadError.readDirectory(
                dir: policyDirectory.path,
                message: String(describing: error)
            )
        }

        return try contents.filter { url in
            guard url.pathExtension == "rules" else {
                return false
            }
            do {
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            } catch {
                throw ExecPolicyLoadError.readDirectory(
                    dir: policyDirectory.path,
                    message: String(describing: error)
                )
            }
        }
        .sorted { $0.path < $1.path }
    }

    public func createExecApprovalRequirementForCommand(
        features: FeatureStates,
        command: [String],
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        sandboxPermissions: SandboxPermissions,
        prefixRule: [String]? = nil
    ) -> ExecApprovalRequirement {
        _ = features
        let policyCommands = Self.commandsForExecPolicy(command)
        let matchOptions = ExecPolicyMatchOptions(resolveHostExecutables: true)
        let execPolicyFallback: (ArraySlice<String>) -> ExecPolicyDecision = { commandSlice in
            let command = Array(commandSlice)
            switch policyCommands.origin {
            case .generic:
                return CommandSafety.requiresInitialApproval(
                    policy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    command: command,
                    sandboxPermissions: sandboxPermissions
                ) ? .prompt : .allow
            case .powerShell:
                return CommandSafety.requiresInitialApprovalForPowerShellWords(
                    policy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    command: command,
                    sandboxPermissions: sandboxPermissions
                ) ? .prompt : .allow
            }
        }
        let evaluation = PolicyEvaluation.fromMatches(policyCommands.commands.flatMap { command in
            policy.matchesForCommand(
                command,
                heuristicsFallback: execPolicyFallback,
                options: matchOptions
            )
        })
        let requestedAmendment = policyCommands.allowsAutoAmendment
            ? Self.deriveRequestedExecPolicyAmendment(
                prefixRule: prefixRule,
                matchedRules: evaluation.matchedRules,
                policy: policy,
                commands: policyCommands.commands,
                execPolicyFallback: execPolicyFallback,
                matchOptions: matchOptions
            )
            : nil

        switch evaluation.decision {
        case .forbidden:
            return .forbidden(reason: Self.forbiddenReason)
        case .prompt:
            let promptIsPolicyRule = evaluation.matchedRules.contains {
                $0.isPolicyMatch && $0.decision == .prompt
            }
            if let rejectionReason = Self.promptRejectionReason(
                approvalPolicy: approvalPolicy,
                promptIsPolicyRule: promptIsPolicyRule
            ) {
                return .forbidden(reason: rejectionReason)
            }
            return .needsApproval(
                reason: Self.derivePromptReason(evaluation),
                proposedExecPolicyAmendment: requestedAmendment
                    ?? (policyCommands.allowsAutoAmendment
                        ? Self.tryDeriveExecPolicyAmendmentForPromptRules(evaluation.matchedRules)
                        : nil)
            )
        case .allow:
            return .skip(
                bypassSandbox: Self.everyCommandSegmentMatchesAllowPolicy(
                    policy: policy,
                    commands: policyCommands.commands,
                    matchOptions: matchOptions
                ),
                proposedExecPolicyAmendment: policyCommands.allowsAutoAmendment
                    ? Self.tryDeriveExecPolicyAmendmentForAllowRules(evaluation.matchedRules)
                    : nil
            )
        }
    }

    private static func commandsForExecPolicy(_ command: [String]) -> ExecPolicyCommands {
        if let commands = BashPlainCommandParser.parseShellLcPlainCommands(command) {
            return ExecPolicyCommands(commands: commands, usedComplexParsing: false, origin: .generic)
        }
        if let commands = CommandSafety.parsePowerShellCommandIntoPlainCommands(command) {
            return ExecPolicyCommands(commands: commands, usedComplexParsing: false, origin: .powerShell)
        }
        if let command = BashPlainCommandParser.parseShellLcSingleCommandPrefix(command) {
            return ExecPolicyCommands(commands: [command], usedComplexParsing: true, origin: .generic)
        }
        return ExecPolicyCommands(commands: [command], usedComplexParsing: false, origin: .generic)
    }

    public func appendAmendmentAndUpdate(
        codexHome: URL,
        amendment: ExecPolicyAmendment
    ) throws {
        let policyPath = Self.defaultPolicyPath(codexHome: codexHome)
        try Self.blockingAppendAllowPrefixRule(policyPath: policyPath, prefix: amendment.command)
        try policy.addPrefixRule(amendment.command, decision: .allow)
    }

    public static func defaultPolicyPath(codexHome: URL) -> URL {
        codexHome
            .appendingPathComponent(rulesDirectoryName, isDirectory: true)
            .appendingPathComponent(defaultPolicyFileName, isDirectory: false)
    }

    public static func blockingAppendAllowPrefixRule(
        policyPath: URL,
        prefix: [String]
    ) throws {
        guard !prefix.isEmpty else {
            throw ExecPolicyAmendError.emptyPrefix
        }
        let tokens: [String]
        do {
            tokens = try prefix.map(jsonStringLiteral)
        } catch {
            throw ExecPolicyAmendError.serializePrefix(message: String(describing: error))
        }

        let rule = #"prefix_rule(pattern=\#("[" + tokens.joined(separator: ", ") + "]"), decision="allow")"#
        try appendRuleLine(policyPath: policyPath, rule: rule)
    }

    public static func blockingAppendNetworkRule(
        policyPath: URL,
        host rawHost: String,
        protocol: NetworkRuleProtocol,
        decision: ExecPolicyDecision,
        justification: String?
    ) throws {
        let host: String
        do {
            host = try ExecPolicy.normalizeNetworkRuleHost(rawHost)
        } catch {
            throw ExecPolicyAmendError.invalidNetworkRule(String(describing: error))
        }
        if let justification, justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExecPolicyAmendError.invalidNetworkRule("justification cannot be empty")
        }

        let hostLiteral: String
        let protocolLiteral: String
        let decisionLiteral: String
        do {
            hostLiteral = try jsonStringLiteral(host)
            protocolLiteral = try jsonStringLiteral(`protocol`.policyString)
            decisionLiteral = try jsonStringLiteral(decision.policyString)
        } catch {
            throw ExecPolicyAmendError.serializeNetworkRule(message: String(describing: error))
        }

        var arguments = [
            "host=\(hostLiteral)",
            "protocol=\(protocolLiteral)",
            "decision=\(decisionLiteral)",
        ]
        if let justification {
            do {
                arguments.append("justification=\(try jsonStringLiteral(justification))")
            } catch {
                throw ExecPolicyAmendError.serializeNetworkRule(message: String(describing: error))
            }
        }

        try appendRuleLine(policyPath: policyPath, rule: "network_rule(\(arguments.joined(separator: ", ")))")
    }

    private static func appendRuleLine(policyPath: URL, rule: String) throws {
        guard let dir = policyPath.deletingLastPathComponentIfPresent() else {
            throw ExecPolicyAmendError.missingParent(path: policyPath.path)
        }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ExecPolicyAmendError.createPolicyDirectory(dir: dir.path, message: String(describing: error))
        }

        let existing: String
        if FileManager.default.fileExists(atPath: policyPath.path) {
            do {
                existing = try String(contentsOf: policyPath, encoding: .utf8)
            } catch {
                throw ExecPolicyAmendError.readPolicyFile(path: policyPath.path, message: String(describing: error))
            }
        } else {
            existing = ""
        }

        if existing.split(separator: "\n", omittingEmptySubsequences: false).contains(Substring(rule)) {
            return
        }

        let line = rule + "\n"
        let updated = existing.isEmpty || existing.hasSuffix("\n")
            ? existing + line
            : existing + "\n" + line
        do {
            try updated.write(to: policyPath, atomically: true, encoding: .utf8)
        } catch {
            throw ExecPolicyAmendError.writePolicyFile(path: policyPath.path, message: String(describing: error))
        }
    }

    public static func tryDeriveExecPolicyAmendmentForPromptRules(
        _ matchedRules: [RuleMatch]
    ) -> ExecPolicyAmendment? {
        if matchedRules.contains(where: { $0.isPolicyMatch && $0.decision == .prompt }) {
            return nil
        }

        for ruleMatch in matchedRules {
            if case let .heuristicsRuleMatch(command, .prompt) = ruleMatch {
                return ExecPolicyAmendment(command: command)
            }
        }
        return nil
    }

    public static func tryDeriveExecPolicyAmendmentForAllowRules(
        _ matchedRules: [RuleMatch]
    ) -> ExecPolicyAmendment? {
        if matchedRules.contains(where: \.isPolicyMatch) {
            return nil
        }

        for ruleMatch in matchedRules {
            if case let .heuristicsRuleMatch(command, .allow) = ruleMatch {
                return ExecPolicyAmendment(command: command)
            }
        }
        return nil
    }

    private static let bannedPrefixSuggestions: [[String]] = [
        ["python3"],
        ["python3", "-"],
        ["python3", "-c"],
        ["python"],
        ["python", "-"],
        ["python", "-c"],
        ["py"],
        ["py", "-3"],
        ["pythonw"],
        ["pyw"],
        ["pypy"],
        ["pypy3"],
        ["git"],
        ["bash"],
        ["bash", "-lc"],
        ["sh"],
        ["sh", "-c"],
        ["sh", "-lc"],
        ["zsh"],
        ["zsh", "-lc"],
        ["/bin/zsh"],
        ["/bin/zsh", "-lc"],
        ["/bin/bash"],
        ["/bin/bash", "-lc"],
        ["pwsh"],
        ["pwsh", "-Command"],
        ["pwsh", "-c"],
        ["powershell"],
        ["powershell", "-Command"],
        ["powershell", "-c"],
        ["powershell.exe"],
        ["powershell.exe", "-Command"],
        ["powershell.exe", "-c"],
        ["env"],
        ["sudo"],
        ["node"],
        ["node", "-e"],
        ["perl"],
        ["perl", "-e"],
        ["ruby"],
        ["ruby", "-e"],
        ["php"],
        ["php", "-r"],
        ["lua"],
        ["lua", "-e"],
        ["osascript"]
    ]

    private static func deriveRequestedExecPolicyAmendment(
        prefixRule: [String]?,
        matchedRules: [RuleMatch],
        policy: ExecPolicy,
        commands: [[String]],
        execPolicyFallback: @escaping (ArraySlice<String>) -> ExecPolicyDecision,
        matchOptions: ExecPolicyMatchOptions
    ) -> ExecPolicyAmendment? {
        guard let prefixRule, !prefixRule.isEmpty else {
            return nil
        }
        guard !bannedPrefixSuggestions.contains(prefixRule) else {
            return nil
        }
        guard !matchedRules.contains(where: \.isPolicyMatch) else {
            return nil
        }

        var policyWithPrefixRule = policy
        do {
            try policyWithPrefixRule.addPrefixRule(prefixRule, decision: .allow)
        } catch {
            return nil
        }

        let approvesAllCommands = commands.allSatisfy { command in
            policyWithPrefixRule.check(
                command,
                heuristicsFallback: execPolicyFallback,
                options: matchOptions
            ).decision == .allow
        }
        return approvesAllCommands ? ExecPolicyAmendment(command: prefixRule) : nil
    }

    private static func everyCommandSegmentMatchesAllowPolicy(
        policy: ExecPolicy,
        commands: [[String]],
        matchOptions: ExecPolicyMatchOptions
    ) -> Bool {
        commands.allSatisfy { command in
            policy.matchesForCommand(
                command,
                heuristicsFallback: nil,
                options: matchOptions
            )
            .contains {
                $0.isPolicyMatch && $0.decision == .allow
            }
        }
    }

    public static func derivePromptReason(_ evaluation: PolicyEvaluation) -> String? {
        evaluation.matchedRules.contains {
            $0.isPolicyMatch && $0.decision == .prompt
        }
        ? Self.promptReason
        : nil
    }

    public static func promptRejectionReason(
        approvalPolicy: AskForApproval,
        promptIsPolicyRule: Bool
    ) -> String? {
        switch approvalPolicy {
        case .never:
            return Self.promptConflictReason
        case .onFailure, .onRequest, .unlessTrusted:
            return nil
        case let .granular(config):
            if promptIsPolicyRule {
                return config.allowsRulesApproval ? nil : Self.granularRulesApprovalConflictReason
            }
            return config.allowsSandboxApproval ? nil : Self.granularSandboxApprovalConflictReason
        }
    }

    private static func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension ExecPolicyDecision {
    var policyString: String {
        switch self {
        case .allow:
            return "allow"
        case .prompt:
            return "prompt"
        case .forbidden:
            return "deny"
        }
    }
}

public func defaultExecApprovalRequirement(
    policy: AskForApproval,
    sandboxPolicy: SandboxPolicy
) -> ExecApprovalRequirement {
    let needsApproval: Bool
    switch policy {
    case .never, .onFailure:
        needsApproval = false
    case .onRequest, .granular:
        switch sandboxPolicy {
        case .dangerFullAccess, .externalSandbox:
            needsApproval = false
        case .readOnly, .readOnlyWithNetworkAccess, .workspaceWrite:
            needsApproval = true
        }
    case .unlessTrusted:
        needsApproval = true
    }

    if needsApproval,
       case let .granular(config) = policy,
       !config.allowsSandboxApproval
    {
        return .forbidden(reason: "approval policy disallowed sandbox approval prompt")
    }

    return needsApproval
        ? .needsApproval(reason: nil, proposedExecPolicyAmendment: nil)
        : .skip(bypassSandbox: false, proposedExecPolicyAmendment: nil)
}

private enum ShellExampleParser {
    static func split(_ raw: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var previousWasBackslash = false

        for character in raw {
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                } else {
                    current.append(character)
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case " ", "\t", "\r", "\n":
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            case "'", "\"":
                quote = character
            default:
                current.append(character)
            }
        }

        guard quote == nil else {
            throw ExecPolicyError.invalidExample("example string has invalid shell syntax")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    static func join(_ tokens: [String]) -> String {
        tokens.map { token in
            if token.isEmpty {
                return "''"
            }
            if token.contains(where: \.isWhitespace) {
                return "'" + token.replacingOccurrences(of: "'", with: "''") + "'"
            }
            return token
        }
        .joined(separator: " ")
    }
}

private extension ExecPolicy {
    func replacingRules(for program: String, with rules: [PrefixRule]) -> ExecPolicy {
        var copy = self
        copy.rulesByProgram[program] = rules
        return copy
    }
}

private extension URL {
    func deletingLastPathComponentIfPresent() -> URL? {
        let parent = deletingLastPathComponent()
        return parent.path == path ? nil : parent
    }
}

private extension Character {
    var isASCIIWholeNumber: Bool {
        unicodeScalars.count == 1 && unicodeScalars.first.map { scalar in
            scalar.value >= 48 && scalar.value <= 57
        } == true
    }
}
