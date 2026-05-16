import CoreGraphics
import CodexCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ContextTokenEstimatorTests: XCTestCase {
    func testEncryptedReasoningAndCompactionUseRustLengthHeuristic() {
        let encrypted = String(repeating: "A", count: 2_000)
        let expected = 850

        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(.reasoning(
                id: "rs_1",
                summary: [],
                encryptedContent: encrypted
            )),
            expected
        )
        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(.compaction(encryptedContent: encrypted)),
            expected
        )
        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(.contextCompaction(encryptedContent: encrypted)),
            expected
        )
    }

    func testShortEncryptedReasoningSaturatesAtZeroLikeRust() {
        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(.reasoning(
                id: "rs_1",
                summary: [],
                encryptedContent: "short"
            )),
            0
        )
    }

    func testNilEncryptedReasoningAndContextCompactionUseSerializedSize() throws {
        let reasoning = ResponseItem.reasoning(id: "rs_1", summary: [], encryptedContent: nil)
        let contextCompaction = ResponseItem.contextCompaction(encryptedContent: nil)

        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(reasoning),
            try encodedByteCount(reasoning)
        )
        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(contextCompaction),
            try encodedByteCount(contextCompaction)
        )
    }

    func testImageDataURLPayloadDoesNotDominateMessageEstimateLikeRust() throws {
        let payload = String(repeating: "B", count: 50_000)
        let imageURL = "data:image/png;base64,\(payload)"
        let item = ResponseItem.message(role: "user", content: [
            .inputText(text: "Here is the screenshot"),
            .inputImage(imageURL: imageURL, detail: .high)
        ])

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expected = rawBytes - payload.count + ContextTokenEstimator.resizedImageBytesEstimate

        XCTAssertEqual(estimated, expected)
        XCTAssertLessThan(estimated, rawBytes)
    }

    func testImageDataURLPayloadDoesNotDominateToolOutputEstimateLikeRust() throws {
        let payload = String(repeating: "C", count: 50_000)
        let imageURL = "data:image/png;base64,\(payload)"
        let item = ResponseItem.functionCallOutput(
            callID: "call-1",
            output: FunctionCallOutputPayload(content: "Screenshot captured", contentItems: [
                .inputText(text: "Screenshot captured"),
                .inputImage(imageURL: imageURL, detail: .high)
            ])
        )

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expected = rawBytes - payload.count + ContextTokenEstimator.resizedImageBytesEstimate

        XCTAssertEqual(estimated, expected)
        XCTAssertLessThan(estimated, rawBytes)
    }

    func testImageDataURLPayloadDoesNotDominateCustomToolOutputEstimateLikeRust() throws {
        let payload = String(repeating: "D", count: 50_000)
        let imageURL = "data:image/png;base64,\(payload)"
        let item = ResponseItem.customToolCallOutput(
            callID: "call-js-repl",
            output: FunctionCallOutputPayload(content: "Screenshot captured", contentItems: [
                .inputText(text: "Screenshot captured"),
                .inputImage(imageURL: imageURL, detail: .high)
            ])
        )

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expected = rawBytes - payload.count + ContextTokenEstimator.resizedImageBytesEstimate

        XCTAssertEqual(estimated, expected)
        XCTAssertLessThan(estimated, rawBytes)
    }

    func testNonBase64AndNonImageDataURLsAreUnchangedLikeRust() throws {
        let remoteImage = ResponseItem.message(role: "user", content: [
            .inputImage(imageURL: "https://example.com/foo.png", detail: .high)
        ])
        let nonImageDataURL = ResponseItem.functionCallOutput(
            callID: "call-octet",
            output: FunctionCallOutputPayload(content: "binary", contentItems: [
                .inputImage(
                    imageURL: "data:application/octet-stream;base64,\(String(repeating: "D", count: 4_096))",
                    detail: .high
                )
            ])
        )

        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(remoteImage),
            try encodedByteCount(remoteImage)
        )
        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(nonImageDataURL),
            try encodedByteCount(nonImageDataURL)
        )
    }

    func testMixedCaseDataURLMarkersAndMultipleImagesMatchRustAdjustment() throws {
        let payloadOne = String(repeating: "E", count: 100)
        let payloadTwo = String(repeating: "F", count: 200)
        let item = ResponseItem.message(role: "user", content: [
            .inputImage(imageURL: "DATA:image/png;BASE64,\(payloadOne)", detail: .high),
            .inputImage(imageURL: "data:image/jpeg;base64,\(payloadTwo)", detail: .auto)
        ])

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expected = rawBytes
            - payloadOne.count
            - payloadTwo.count
            + (2 * ContextTokenEstimator.resizedImageBytesEstimate)

        XCTAssertEqual(estimated, expected)
    }

    func testTextOnlyItemsUseRawSerializedSizeLikeRust() throws {
        let item = ResponseItem.message(role: "assistant", content: [
            .outputText(text: "Hello world, this is a response.")
        ])

        XCTAssertEqual(
            ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item),
            try encodedByteCount(item)
        )
    }

    func testOriginalDetailImagesScaleWithDimensionsLikeRust() throws {
        let imageData = try makePNG(width: 2_304, height: 864)
        let payload = imageData.base64EncodedString()
        let imageURL = "data:image/png;base64,\(payload)"
        let item = ResponseItem.functionCallOutput(
            callID: "call-original",
            output: FunctionCallOutputPayload(content: "image", contentItems: [
                .inputImage(imageURL: imageURL, detail: .original)
            ])
        )

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expectedOriginalDetailImageBytes = 7_776
        let expected = rawBytes - payload.count + expectedOriginalDetailImageBytes

        XCTAssertEqual(estimated, expected)
    }

    func testOriginalDetailWebPImagesScaleWithDimensionsLikeRust() throws {
        let imageData = makeWebP2304By864()
        let payload = imageData.base64EncodedString()
        let imageURL = "data:image/webp;base64,\(payload)"
        let item = ResponseItem.functionCallOutput(
            callID: "call-original-webp",
            output: FunctionCallOutputPayload(content: "image", contentItems: [
                .inputImage(imageURL: imageURL, detail: .original)
            ])
        )

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expectedOriginalDetailImageBytes = 7_776
        let expected = rawBytes - payload.count + expectedOriginalDetailImageBytes

        XCTAssertEqual(estimated, expected)
    }

    func testOriginalDetailImageEstimateIsCappedLikeRust() throws {
        let imageData = try makePNG(width: 3_201, height: 3_201)
        let payload = imageData.base64EncodedString()
        let imageURL = "data:image/png;base64,\(payload)"
        let item = ResponseItem.functionCallOutput(
            callID: "call-original-capped",
            output: FunctionCallOutputPayload(content: "image", contentItems: [
                .inputImage(imageURL: imageURL, detail: .original)
            ])
        )

        let rawBytes = try encodedByteCount(item)
        let estimated = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        let expectedCappedImageBytes = Truncation.approxBytesForTokens(
            ContextTokenEstimator.originalImageMaxPatches
        )
        let expected = rawBytes - payload.count + expectedCappedImageBytes

        XCTAssertEqual(estimated, expected)
    }
}

private func encodedByteCount<T: Encodable>(_ value: T) throws -> Int {
    try JSONEncoder().encode(value).count
}

private func makePNG(width: Int, height: Int) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestImageError.contextCreation
    }

    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ),
          let image = context.makeImage()
    else {
        throw TestImageError.imageEncoding
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestImageError.imageEncoding
    }
    return data as Data
}

private func makeWebP2304By864() -> Data {
    Data([
        0x52, 0x49, 0x46, 0x46, 0x16, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20,
        0x0a, 0x00, 0x00, 0x00, 0x30, 0xa7, 0x01, 0x9d,
        0x01, 0x2a, 0x00, 0x09, 0x60, 0x03,
    ])
}

private enum TestImageError: Error {
    case contextCreation
    case imageEncoding
}
