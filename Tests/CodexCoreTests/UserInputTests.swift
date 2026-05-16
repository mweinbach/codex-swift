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
        try XCTAssertJSONObjectEqual(UserInput.skill(name: "plan", path: "/skills/plan/SKILL.md"), [
            "type": "skill",
            "name": "plan",
            "path": "/skills/plan/SKILL.md"
        ])
        try XCTAssertJSONObjectEqual(UserInput.mention(name: "drive", path: "app://google_drive"), [
            "type": "mention",
            "name": "drive",
            "path": "app://google_drive"
        ])
    }

    func testImageInputsRejectUnsupportedDetailValuesLikeRust() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UserInput.self,
                from: Data(#"{"type":"image","image_url":"https://example.com/image.png","detail":"low"}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UserInput.self,
                from: Data(#"{"type":"local_image","path":"local/image.png","detail":"auto"}"#.utf8)
            )
        )
    }

    func testImageInputsPreserveOptionalDetailLikeRust() throws {
        let remoteJSON = #"{"type":"image","image_url":"https://example.com/image.png","detail":"original"}"#
        let decodedRemote = try JSONDecoder().decode(UserInput.self, from: Data(remoteJSON.utf8))
        XCTAssertEqual(decodedRemote, .image(imageURL: "https://example.com/image.png", detail: .original))
        try XCTAssertJSONObjectEqual(decodedRemote, [
            "type": "image",
            "image_url": "https://example.com/image.png",
            "detail": "original"
        ])

        let localJSON = #"{"type":"local_image","path":"local/image.png","detail":"original"}"#
        let decodedLocal = try JSONDecoder().decode(UserInput.self, from: Data(localJSON.utf8))
        XCTAssertEqual(decodedLocal, .localImage(path: "local/image.png", detail: .original))
        try XCTAssertJSONObjectEqual(decodedLocal, [
            "type": "local_image",
            "path": "local/image.png",
            "detail": "original"
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

    func testTextInputRejectsNullRustDefaultedTextElements() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UserInput.self,
                from: Data(#"{"type":"text","text":"hello","text_elements":null}"#.utf8)
            )
        )
    }

    func testMentionInputRoundTripsLikeRust() throws {
        let json = #"{"type":"mention","name":"figma","path":"app://figma"}"#

        let decoded = try JSONDecoder().decode(UserInput.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, .mention(name: "figma", path: "app://figma"))
        try XCTAssertJSONObjectEqual(decoded, [
            "type": "mention",
            "name": "figma",
            "path": "app://figma"
        ])
    }

    func testSkillInputRoundTripsLikeRust() throws {
        let json = #"{"type":"skill","name":"review","path":"/skills/review/SKILL.md"}"#

        let decoded = try JSONDecoder().decode(UserInput.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, .skill(name: "review", path: "/skills/review/SKILL.md"))
        try XCTAssertJSONObjectEqual(decoded, [
            "type": "skill",
            "name": "review",
            "path": "/skills/review/SKILL.md"
        ])
    }
}
