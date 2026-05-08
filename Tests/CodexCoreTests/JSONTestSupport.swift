import XCTest

func JSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func XCTAssertJSONObjectEqual<T: Encodable>(
    _ value: T,
    _ expected: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let object = try JSONObject(value)
    XCTAssertEqual(NSDictionary(dictionary: object), NSDictionary(dictionary: expected), file: file, line: line)
}
