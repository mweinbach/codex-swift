import CodexCore
import XCTest

final class UserInputTests: XCTestCase {
    func testUserInputTaggedEncoding() throws {
        try XCTAssertJSONObjectEqual(UserInput.text("hello"), [
            "type": "text",
            "text": "hello",
            "text_elements": []
        ])
        try XCTAssertJSONObjectEqual(UserInput.image(imageURL: "data:image/png;base64,abc"), [
            "type": "image",
            "image_url": "data:image/png;base64,abc"
        ])
        try XCTAssertJSONObjectEqual(UserInput.localImage(path: "/tmp/a.png"), [
            "type": "local_image",
            "path": "/tmp/a.png"
        ])
    }

    func testTextInputCarriesTextElementsWithRustDefaults() throws {
        let input = UserInput.text(
            "see [image]",
            textElements: [TextElement(
                byteRange: ByteRange(start: 4, end: 11),
                placeholder: nil
            )]
        )

        try XCTAssertJSONObjectEqual(input, [
            "type": "text",
            "text": "see [image]",
            "text_elements": [[
                "byte_range": [
                    "start": 4,
                    "end": 11
                ],
                "placeholder": NSNull()
            ]]
        ])

        let decoded = try JSONDecoder().decode(UserInput.self, from: Data(#"{"type":"text","text":"hello"}"#.utf8))
        XCTAssertEqual(decoded, .text("hello", textElements: []))
    }
}
