import Foundation

public struct AgentJobCSVDocument: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public enum AgentJobCSV {
    public static func parse(_ content: String) throws -> AgentJobCSVDocument {
        var records = try parseRecords(content)
        guard !records.isEmpty else {
            return AgentJobCSVDocument(headers: [], rows: [])
        }

        var headers = records.removeFirst()
        if let first = headers.first, first.hasPrefix("\u{feff}") {
            headers[0] = String(first.dropFirst())
        }
        let rows = records.filter { row in
            !row.allSatisfy(\.isEmpty)
        }
        return AgentJobCSVDocument(headers: headers, rows: rows)
    }

    public static func ensureUniqueHeaders(_ headers: [String]) throws {
        var seen = Set<String>()
        for header in headers {
            if !seen.insert(header).inserted {
                throw FunctionCallError.respondToModel("csv header \(header) is duplicated")
            }
        }
    }

    public static func makeItems(
        headers: [String],
        rows: [[String]],
        idColumn: String?
    ) throws -> [AgentJobItemCreateParams] {
        let idColumnIndex: Int?
        if let idColumn {
            guard let index = headers.firstIndex(of: idColumn) else {
                throw FunctionCallError.respondToModel("id_column \(idColumn) was not found in csv headers")
            }
            idColumnIndex = index
        } else {
            idColumnIndex = nil
        }

        var seenIDs = Set<String>()
        return try rows.enumerated().map { index, row in
            if row.count != headers.count {
                let rowIndex = index + 2
                throw FunctionCallError.respondToModel(
                    "csv row \(rowIndex) has \(row.count) fields but header has \(headers.count)"
                )
            }

            let sourceID = idColumnIndex.flatMap { columnIndex -> String? in
                guard columnIndex < row.count else {
                    return nil
                }
                let value = row[columnIndex]
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
            let rowNumber = index + 1
            let baseItemID = sourceID ?? "row-\(rowNumber)"
            var itemID = baseItemID
            var suffix = 2
            while !seenIDs.insert(itemID).inserted {
                itemID = "\(baseItemID)-\(suffix)"
                suffix = suffix == Int.max ? Int.max : suffix + 1
            }

            let rowObject = Dictionary(uniqueKeysWithValues: zip(headers, row).map { header, value in
                (header, JSONValue.string(value))
            })
            return AgentJobItemCreateParams(
                itemID: itemID,
                rowIndex: Int64(index),
                sourceID: sourceID,
                rowJSON: .object(rowObject)
            )
        }
    }

    public static func renderInstructionTemplate(_ instruction: String, rowJSON: JSONValue) -> String {
        let openBraceSentinel = "__CODEX_OPEN_BRACE__"
        let closeBraceSentinel = "__CODEX_CLOSE_BRACE__"
        var rendered = instruction
            .replacingOccurrences(of: "{{", with: openBraceSentinel)
            .replacingOccurrences(of: "}}", with: closeBraceSentinel)

        if case let .object(row) = rowJSON {
            for (key, value) in row {
                let placeholder = "{\(key)}"
                rendered = rendered.replacingOccurrences(
                    of: placeholder,
                    with: templateReplacement(for: value)
                )
            }
        }

        return rendered
            .replacingOccurrences(of: openBraceSentinel, with: "{")
            .replacingOccurrences(of: closeBraceSentinel, with: "}")
    }

    public static func renderJobCSV(inputHeaders: [String], items: [AgentJobItem]) throws -> String {
        var csv = ""
        let outputHeaders = inputHeaders + [
            "job_id",
            "item_id",
            "row_index",
            "source_id",
            "status",
            "attempt_count",
            "last_error",
            "result_json",
            "reported_at",
            "completed_at",
        ]
        csv += outputHeaders.map(csvEscape).joined(separator: ",")
        csv += "\n"

        for item in items {
            guard case let .object(rowObject) = item.rowJSON else {
                throw FunctionCallError.respondToModel("row_json for item \(item.itemID) is not a JSON object")
            }
            var rowValues: [String] = []
            for header in inputHeaders {
                rowValues.append(rowObject[header].map(valueToCSVString) ?? "")
            }
            rowValues.append(item.jobID)
            rowValues.append(item.itemID)
            rowValues.append(String(item.rowIndex))
            rowValues.append(item.sourceID ?? "")
            rowValues.append(item.status.rawValue)
            rowValues.append(String(item.attemptCount))
            rowValues.append(item.lastError ?? "")
            rowValues.append(item.resultJSON.map(compactJSONString) ?? "")
            rowValues.append(item.reportedAt.map(formatRFC3339) ?? "")
            rowValues.append(item.completedAt.map(formatRFC3339) ?? "")
            csv += rowValues.map(csvEscape).joined(separator: ",")
            csv += "\n"
        }

        return csv
    }

    public static func defaultOutputCSVPath(inputCSVPath: String, jobID: String) -> String {
        let inputURL = URL(fileURLWithPath: inputCSVPath)
        let stem = inputURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "agent_job_output"
            : inputURL.deletingPathExtension().lastPathComponent
        let parent = inputURL.deletingLastPathComponent()
        let suffix = String(jobID.prefix(8))
        return parent.appendingPathComponent("\(stem).agent-job-\(suffix).csv").path
    }

    public static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\r") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    public static func compactJSONString(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .string(value):
            return encodedJSONString(value)
        case let .array(values):
            return "[\(values.map(compactJSONString).joined(separator: ","))]"
        case let .object(values):
            let fields = values.keys.sorted().map { key in
                "\(encodedJSONString(key)):\(compactJSONString(values[key]!))"
            }
            return "{\(fields.joined(separator: ","))}"
        }
    }

    public static func prettyJSONString(_ value: JSONValue) -> String {
        switch value {
        case .null, .bool, .integer, .double, .string:
            return compactJSONString(value)
        case let .array(values):
            if values.isEmpty {
                return "[]"
            }
            let body = values
                .map { indent(prettyJSONString($0), by: 2) }
                .joined(separator: ",\n")
            return "[\n\(body)\n]"
        case let .object(values):
            if values.isEmpty {
                return "{}"
            }
            let body = values.keys.sorted().map { key in
                let value = values[key]!
                return "  \(encodedJSONString(key)): \(indentContinuation(prettyJSONString(value), by: 2))"
            }
            .joined(separator: ",\n")
            return "{\n\(body)\n}"
        }
    }

    private static func parseRecords(_ content: String) throws -> [[String]] {
        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]
            let nextIndex = content.index(after: index)

            if inQuotes {
                if character == "\"" {
                    if nextIndex < content.endIndex, content[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = content.index(after: nextIndex)
                    } else {
                        inQuotes = false
                        index = nextIndex
                    }
                } else {
                    currentField.append(character)
                    index = nextIndex
                }
                continue
            }

            switch character {
            case "\"":
                if currentField.isEmpty {
                    inQuotes = true
                    index = nextIndex
                } else {
                    throw FunctionCallError.respondToModel("bare quote in non-quoted CSV field")
                }
            case ",":
                currentRecord.append(currentField)
                currentField = ""
                index = nextIndex
            case "\n":
                currentRecord.append(currentField)
                records.append(currentRecord)
                currentRecord = []
                currentField = ""
                index = nextIndex
            case "\r":
                currentRecord.append(currentField)
                records.append(currentRecord)
                currentRecord = []
                currentField = ""
                if nextIndex < content.endIndex, content[nextIndex] == "\n" {
                    index = content.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            default:
                currentField.append(character)
                index = nextIndex
            }
        }

        if inQuotes {
            throw FunctionCallError.respondToModel("unterminated quoted CSV field")
        }
        if !currentField.isEmpty || !currentRecord.isEmpty {
            currentRecord.append(currentField)
            records.append(currentRecord)
        }
        return records
    }

    private static func templateReplacement(for value: JSONValue) -> String {
        if case let .string(value) = value {
            return value
        }
        return compactJSONString(value)
    }

    private static func valueToCSVString(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return ""
        case let .string(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case .array, .object:
            return compactJSONString(value)
        }
    }

    private static func encodedJSONString(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                encoded += "\\\""
            case 0x5C:
                encoded += "\\\\"
            case 0x08:
                encoded += "\\b"
            case 0x0C:
                encoded += "\\f"
            case 0x0A:
                encoded += "\\n"
            case 0x0D:
                encoded += "\\r"
            case 0x09:
                encoded += "\\t"
            case 0x00...0x1F:
                encoded += String(format: "\\u%04X", scalar.value)
            default:
                encoded.unicodeScalars.append(scalar)
            }
        }
        encoded += "\""
        return encoded
    }

    private static func indent(_ value: String, by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return prefix + value.replacingOccurrences(of: "\n", with: "\n\(prefix)")
    }

    private static func indentContinuation(_ value: String, by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return value.replacingOccurrences(of: "\n", with: "\n\(prefix)")
    }

    private static func formatRFC3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
