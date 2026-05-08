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
    case missingParent(path: String)
    case createPolicyDirectory(dir: String, message: String)
    case serializePrefix(message: String)
    case readPolicyFile(path: String, message: String)
    case writePolicyFile(path: String, message: String)

    public var description: String {
        switch self {
        case .emptyPrefix:
            return "prefix rule requires at least one token"
        case let .missingParent(path):
            return "policy path has no parent: \(path)"
        case let .createPolicyDirectory(dir, message):
            return "failed to create policy directory \(dir): \(message)"
        case let .serializePrefix(message):
            return "failed to format prefix tokens: \(message)"
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

    public init(pattern: PrefixPattern, decision: ExecPolicyDecision) {
        self.pattern = pattern
        self.decision = decision
    }

    public var program: String {
        pattern.first
    }

    public func matches(_ command: [String]) -> RuleMatch? {
        pattern.matchesPrefix(command).map {
            .prefixRuleMatch(matchedPrefix: $0, decision: decision)
        }
    }

    public var description: String {
        "PrefixRule(pattern: \(pattern), decision: \(decision.rawValue))"
    }
}

public enum RuleMatch: Equatable, Sendable {
    case prefixRuleMatch(matchedPrefix: [String], decision: ExecPolicyDecision)
    case heuristicsRuleMatch(command: [String], decision: ExecPolicyDecision)

    public var decision: ExecPolicyDecision {
        switch self {
        case let .prefixRuleMatch(_, decision), let .heuristicsRuleMatch(_, decision):
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

public struct ExecPolicy: Equatable, Sendable {
    private var rulesByProgram: [String: [PrefixRule]]

    public init(rulesByProgram: [String: [PrefixRule]] = [:]) {
        self.rulesByProgram = rulesByProgram
    }

    public static func empty() -> ExecPolicy {
        ExecPolicy()
    }

    public func rules(for program: String) -> [PrefixRule] {
        rulesByProgram[program] ?? []
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
            decision: decision
        )
        rulesByProgram[firstToken, default: []].append(rule)
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
        var matchedRules = command.first
            .flatMap { rulesByProgram[$0] }?
            .compactMap { $0.matches(command) }
            ?? []

        if matchedRules.isEmpty, let heuristicsFallback {
            matchedRules.append(.heuristicsRuleMatch(
                command: command,
                decision: heuristicsFallback(command[...])
            ))
        }

        return matchedRules
    }
}

public final class PolicyParser {
    private var policy = ExecPolicy.empty()

    public init() {}

    public func parse(_ policyIdentifier: String, _ policyFileContents: String) throws {
        let source = Self.stripLineComments(from: policyFileContents)
        let bodies = try Self.extractPrefixRuleBodies(source, identifier: policyIdentifier)
        for body in bodies {
            try addPrefixRule(from: body)
        }
    }

    public func build() -> ExecPolicy {
        policy
    }

    private func addPrefixRule(from body: String) throws {
        let arguments = try Self.parseArguments(body)
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
                decision: decision
            )
        }

        try Self.validateNotMatchExamples(rules: rules, notMatches: notMatchExamples)
        try Self.validateMatchExamples(rules: rules, matches: matchExamples)

        for rule in rules {
            var existing = policy.rules(for: rule.program)
            existing.append(rule)
            policy = policy.replacingRules(for: rule.program, with: existing)
        }
    }

    private static func extractPrefixRuleBodies(_ source: String, identifier: String) throws -> [String] {
        var bodies: [String] = []
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if character == "\"" || character == "'" {
                index = Self.index(afterQuotedStringAt: index, in: source)
                continue
            }

            guard source[index...].hasPrefix("prefix_rule"),
                  isIdentifierBoundaryBefore(index, in: source)
            else {
                index = source.index(after: index)
                continue
            }

            let functionEnd = source.index(index, offsetBy: "prefix_rule".count)
            guard isIdentifierBoundaryAfter(functionEnd, in: source) else {
                index = functionEnd
                continue
            }

            index = functionEnd
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex, source[index] == "(" else {
                throw ExecPolicyError.invalidSyntax("\(identifier): expected '(' after prefix_rule")
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
                throw ExecPolicyError.invalidSyntax("\(identifier): unterminated prefix_rule")
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

    private static func parseArguments(_ body: String) throws -> [String: ConfigValue] {
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
            arguments[key] = try parsePolicyLiteral(valueText)
        }
        return arguments
    }

    private static func parsePolicyLiteral(_ valueText: String) throws -> ConfigValue {
        do {
            return try ConfigValueParser.parseTomlLiteral(valueText)
        } catch {
            return try ConfigValueParser.parseTomlLiteral(removingTrailingArrayCommas(from: valueText))
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

    private static func validateMatchExamples(rules: [PrefixRule], matches: [[String]]) throws {
        let unmatched = matches.filter { example in
            !rules.contains { $0.matches(example) != nil }
        }
        guard unmatched.isEmpty else {
            throw ExecPolicyError.exampleDidNotMatch(
                rules: rules.map(\.description),
                examples: unmatched.map(ShellExampleParser.join)
            )
        }
    }

    private static func validateNotMatchExamples(rules: [PrefixRule], notMatches: [[String]]) throws {
        for example in notMatches {
            if let rule = rules.first(where: { $0.matches(example) != nil }) {
                throw ExecPolicyError.exampleDidMatch(
                    rule: rule.description,
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

public final class ExecPolicyManager: @unchecked Sendable {
    public static let rulesDirectoryName = "rules"
    public static let defaultPolicyFileName = "default.rules"
    public static let forbiddenReason = "execpolicy forbids this command"
    public static let promptConflictReason = "execpolicy requires approval for this command, but AskForApproval is set to Never"
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
        guard features.isEnabled(.execPolicy) else {
            return ExecPolicyManager(policy: .empty())
        }
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
        let commands = BashPlainCommandParser.parseShellLcPlainCommands(command) ?? [command]
        let evaluation = policy.checkMultiple(commands) { commandSlice in
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
            if approvalPolicy == .never {
                return .forbidden(reason: Self.promptConflictReason)
            }
            return .needsApproval(
                reason: Self.derivePromptReason(evaluation),
                proposedExecPolicyAmendment: features.isEnabled(.execPolicy)
                    ? Self.tryDeriveExecPolicyAmendmentForPromptRules(evaluation.matchedRules)
                    : nil
            )
        case .allow:
            return .skip(
                bypassSandbox: evaluation.matchedRules.contains {
                    $0.isPolicyMatch && $0.decision == .allow
                },
                proposedExecPolicyAmendment: features.isEnabled(.execPolicy)
                    ? Self.tryDeriveExecPolicyAmendmentForAllowRules(evaluation.matchedRules)
                    : nil
            )
        }
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
        guard let dir = policyPath.deletingLastPathComponentIfPresent() else {
            throw ExecPolicyAmendError.missingParent(path: policyPath.path)
        }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ExecPolicyAmendError.createPolicyDirectory(dir: dir.path, message: String(describing: error))
        }

        let tokens: [String]
        do {
            tokens = try prefix.map(jsonStringLiteral)
        } catch {
            throw ExecPolicyAmendError.serializePrefix(message: String(describing: error))
        }

        let rule = #"prefix_rule(pattern=\#("[" + tokens.joined(separator: ", ") + "]"), decision="allow")"#
        let line = rule + "\n"
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

    private static func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
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
    case .onRequest:
        switch sandboxPolicy {
        case .dangerFullAccess, .externalSandbox:
            needsApproval = false
        case .readOnly, .workspaceWrite:
            needsApproval = true
        }
    case .unlessTrusted:
        needsApproval = true
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
