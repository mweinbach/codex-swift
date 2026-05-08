import XCTest
@testable import CodexCore

final class TextEncodingTests: XCTestCase {
    func testUTF8Passthrough() {
        let text = "Hello, мир! 世界"

        XCTAssertEqual(TextEncoding.bytesToStringSmart(Array(text.utf8)), text)
    }

    func testEmptyBytesReturnEmptyString() {
        XCTAssertEqual(TextEncoding.bytesToStringSmart([]), "")
    }

    func testCP1251RussianText() {
        let bytes: [UInt8] = [0xEF, 0xF0, 0xE8, 0xEC, 0xE5, 0xF0]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "пример")
    }

    func testCP1251PrivetWord() {
        let bytes: [UInt8] = [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "Привет")
    }

    func testKOI8RPrivetWord() {
        let bytes: [UInt8] = [0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "Привет")
    }

    func testCP866RussianText() {
        let bytes: [UInt8] = [0xAF, 0xE0, 0xA8, 0xAC, 0xA5, 0xE0]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "пример")
    }

    func testCP866UppercaseText() {
        let bytes: [UInt8] = [0x8F, 0x90, 0x88]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "ПРИ")
    }

    func testCP866UppercaseFollowedByASCII() {
        let bytes: [UInt8] = [0x8F, 0x90, 0x88, 0x20, 0x74, 0x65, 0x73, 0x74]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "ПРИ test")
    }

    func testWindows1252Quotes() {
        let bytes: [UInt8] = [0x93, 0x94, 0x74, 0x65, 0x73, 0x74]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "\u{201C}\u{201D}test")
    }

    func testWindows1252MultipleQuotes() {
        let bytes: [UInt8] = [
            0x93, 0x66, 0x6F, 0x6F, 0x94, 0x20, 0x96, 0x20, 0x93, 0x62, 0x61, 0x72, 0x94
        ]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "\u{201C}foo\u{201D} \u{2013} \u{201C}bar\u{201D}")
    }

    func testWindows1252PrivetGibberishIsPreserved() {
        let text = "ÐŸÑ€Ð¸Ð²ÐµÑ‚"

        XCTAssertEqual(TextEncoding.bytesToStringSmart(Array(text.utf8)), text)
    }

    func testLatin1Cafe() {
        let bytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "café")
    }

    func testPreservesANSISequences() {
        let bytes: [UInt8] = [0x1B, 0x5B, 0x33, 0x31, 0x6D, 0x72, 0x65, 0x64, 0x1B, 0x5B, 0x30, 0x6D]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), "\u{1B}[31mred\u{1B}[0m")
    }

    func testFallbackToLossyUTF8() {
        let bytes: [UInt8] = [0xFF, 0xFE, 0xFD]

        XCTAssertEqual(TextEncoding.bytesToStringSmart(bytes), String(decoding: bytes, as: UTF8.self))
    }
}
