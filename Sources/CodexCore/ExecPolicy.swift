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

public final class PolicyParser {
    private var policy = ExecPolicy.empty()
    private var pendingExampleValidations: [(rules: [PrefixRule], matches: [[String]], notMatches: [[String]])] = []

    public init() {}

    public func parse(_ policyIdentifier: String, _ policyFileContents: String) throws {
        let pendingValidationStartIndex = pendingExampleValidations.count
        let source = Self.stripLineComments(from: policyFileContents)
        var constants: [String: ConfigValue] = [:]
        for statement in Self.topLevelStatements(from: source) {
            if let assignment = try Self.parseTopLevelLiteralAssignment(statement, constants: constants) {
                constants[assignment.key] = assignment.value
                continue
            }

            let prefixRuleBodies = try Self.extractCallBodies(
                named: "prefix_rule",
                from: statement,
                identifier: policyIdentifier
            )
            for body in prefixRuleBodies {
                try addPrefixRule(from: body, constants: constants)
            }
            let networkRuleBodies = try Self.extractCallBodies(
                named: "network_rule",
                from: statement,
                identifier: policyIdentifier
            )
            for body in networkRuleBodies {
                try addNetworkRule(from: body, constants: constants)
            }
            let hostExecutableBodies = try Self.extractCallBodies(
                named: "host_executable",
                from: statement,
                identifier: policyIdentifier
            )
            for body in hostExecutableBodies {
                try addHostExecutable(from: body, constants: constants)
            }
        }
        try validatePendingExamples(from: pendingValidationStartIndex)
    }

    public func build() -> ExecPolicy {
        policy
    }

    private func addPrefixRule(from body: String, constants: [String: ConfigValue]) throws {
        let arguments = try Self.parseArguments(body, constants: constants)
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

    private func addNetworkRule(from body: String, constants: [String: ConfigValue]) throws {
        let arguments = try Self.parseArguments(body, constants: constants)
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

    private func addHostExecutable(from body: String, constants: [String: ConfigValue]) throws {
        let arguments = try Self.parseArguments(body, constants: constants)
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

    private static func parseTopLevelLiteralAssignment(
        _ statement: String,
        constants: [String: ConfigValue]
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
            return (key, try parsePolicyLiteral(valueText, constants: constants))
        } catch {
            return nil
        }
    }

    private static func topLevelStatements(from source: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var squareDepth = 0
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
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            case "\n" where squareDepth == 0 && parenDepth == 0:
                statements.append(current)
                current = ""
            case ";" where squareDepth == 0 && parenDepth == 0:
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

    private static func parseArguments(_ body: String, constants: [String: ConfigValue]) throws -> [String: ConfigValue] {
        var arguments: [String: ConfigValue] = [:]
        for piece in splitTopLevel(body, separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                throw ExecPolicyError.invalidSyntax("expected key=value argument: \(trimmed)")
            }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: equalsIndex)
            let valueText = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            arguments[key] = try parsePolicyLiteral(valueText, constants: constants)
        }
        return arguments
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
        constants: [String: ConfigValue] = [:]
    ) throws -> ConfigValue {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let constant = constants[trimmed] {
            return constant
        }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let body = String(trimmed.dropFirst().dropLast())
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .array([])
            }
            return .array(try splitTopLevel(body, separator: ",").compactMap { item in
                guard !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return try parsePolicyLiteral(item, constants: constants)
            })
        }

        do {
            return try ConfigValueParser.parseTomlLiteral(trimmed)
        } catch {
            return try ConfigValueParser.parseTomlLiteral(removingTrailingArrayCommas(from: trimmed))
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
        var pieces: [String] = []
        var current = ""
        var bracketDepth = 0
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
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth -= 1
                current.append(character)
            case separator where bracketDepth == 0:
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
    let allowsAutoAmendment: Bool
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

    public static func loadExecPolicy(
        configStack: ConfigLayerStack,
        fileManager: FileManager = .default
    ) throws -> ExecPolicy {
        var policyPaths: [URL] = []
        for layer in configStack.getLayers(ordering: .lowestPrecedenceFirst) {
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

        return parser.build()
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
        sandboxPermissions: SandboxPermissions
    ) -> ExecApprovalRequirement {
        _ = features
        let policyCommands = Self.commandsForExecPolicy(command)
        let evaluation = policy.checkMultiple(policyCommands.commands) { commandSlice in
            CommandSafety.requiresInitialApproval(
                policy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                command: Array(commandSlice),
                sandboxPermissions: sandboxPermissions
            )
            ? .prompt
            : .allow
        }

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
                proposedExecPolicyAmendment: policyCommands.allowsAutoAmendment
                    ? Self.tryDeriveExecPolicyAmendmentForPromptRules(evaluation.matchedRules)
                    : nil
            )
        case .allow:
            return .skip(
                bypassSandbox: evaluation.matchedRules.contains {
                    $0.isPolicyMatch && $0.decision == .allow
                },
                proposedExecPolicyAmendment: policyCommands.allowsAutoAmendment
                    ? Self.tryDeriveExecPolicyAmendmentForAllowRules(evaluation.matchedRules)
                    : nil
            )
        }
    }

    private static func commandsForExecPolicy(_ command: [String]) -> ExecPolicyCommands {
        if let commands = BashPlainCommandParser.parseShellLcPlainCommands(command) {
            return ExecPolicyCommands(commands: commands, allowsAutoAmendment: true)
        }
        if let command = BashPlainCommandParser.parseShellLcSingleCommandPrefix(command) {
            return ExecPolicyCommands(commands: [command], allowsAutoAmendment: false)
        }
        return ExecPolicyCommands(commands: [command], allowsAutoAmendment: true)
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
        case .readOnly, .workspaceWrite:
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
