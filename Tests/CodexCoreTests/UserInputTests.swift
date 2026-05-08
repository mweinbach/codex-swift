import CodexCore
import XCTest

final class UserInputTests: XCTestCase {
    func testUserInputTaggedEncoding() throws {
        try XCTAssertJSONObjectEqual(UserInput.text("hello"), ["type": "text", "text": "hello"])
        try XCTAssertJSONObjectEqual(UserInput.image(imageURL: "data:image/png;base64,abc"), [
            "type": "image",
            "image_url": "data:image/png;base64,abc"
        ])
        try XCTAssertJSONObjectEqual(UserInput.localImage(path: "/tmp/a.png"), [
            "type": "local_image",
            "path": "/tmp/a.png"
        ])
    }
}
