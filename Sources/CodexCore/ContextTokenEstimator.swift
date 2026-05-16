import CoreGraphics
import Foundation
import ImageIO

public enum ContextTokenEstimator {
    public static let resizedImageBytesEstimate = 7_373
    public static let originalImagePatchSize = 32
    public static let originalImageMaxPatches = 10_000

    public static func estimateResponseItemModelVisibleBytes(_ item: ResponseItem) -> Int {
        switch item {
        case let .reasoning(_, _, _, encryptedContent?),
             let .compaction(encryptedContent),
             let .contextCompaction(encryptedContent?):
            return estimateReasoningLength(encodedLength: encryptedContent.count)

        case .reasoning,
             .contextCompaction,
             .message,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .functionCallOutput,
             .customToolCall,
             .customToolCallOutput,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .ghostSnapshot,
             .knownPersisted,
             .other:
            let rawBytes = encodedByteCount(item)
            let adjustment = imageDataURLEstimateAdjustment(item)
            guard adjustment.payloadBytes > 0, adjustment.replacementBytes > 0 else {
                return rawBytes
            }
            return rawBytes
                .subtractingClamped(adjustment.payloadBytes)
                .addingClamped(adjustment.replacementBytes)
        }
    }

    static func estimateReasoningLength(encodedLength: Int) -> Int {
        encodedLength
            .multipliedClamped(by: 3)
            .dividedReportingZero(by: 4)
            .subtractingClamped(650)
    }

    private static func encodedByteCount<T: Encodable>(_ value: T) -> Int {
        (try? JSONEncoder().encode(value).count) ?? 0
    }

    private static func imageDataURLEstimateAdjustment(_ item: ResponseItem) -> (payloadBytes: Int, replacementBytes: Int) {
        var payloadBytes = 0
        var replacementBytes = 0

        func accumulate(imageURL: String, detail: ImageDetail?) {
            guard let payload = parseBase64ImageDataURL(imageURL) else {
                return
            }
            payloadBytes = payloadBytes.addingClamped(payload.count)
            let replacement = switch detail {
            case .original:
                estimateOriginalImageBytes(imageURL: imageURL) ?? resizedImageBytesEstimate
            case .auto,
                 .low,
                 .high,
                 .none:
                resizedImageBytesEstimate
            }
            replacementBytes = replacementBytes.addingClamped(replacement)
        }

        switch item {
        case let .message(_, _, content, _):
            for contentItem in content {
                if case let .inputImage(imageURL, detail) = contentItem {
                    accumulate(imageURL: imageURL, detail: detail)
                }
            }

        case let .functionCallOutput(_, output),
             let .customToolCallOutput(_, _, output):
            guard let contentItems = output.contentItems else {
                break
            }
            for contentItem in contentItems {
                if case let .inputImage(imageURL, detail) = contentItem {
                    accumulate(imageURL: imageURL, detail: detail)
                }
            }

        case .reasoning,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .customToolCall,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted,
             .other:
            break
        }

        return (payloadBytes, replacementBytes)
    }

    private static func parseBase64ImageDataURL(_ url: String) -> Substring? {
        guard url.prefix("data:".count).lowercased() == "data:",
              let commaIndex = url.firstIndex(of: ",")
        else {
            return nil
        }

        let metadata = url[..<commaIndex]
        let payload = url[url.index(after: commaIndex)...]
        let metadataWithoutScheme = metadata.dropFirst("data:".count)
        var parts = metadataWithoutScheme.split(separator: ";", omittingEmptySubsequences: false)
        let mimeType = parts.isEmpty ? "" : parts.removeFirst()
        guard mimeType.prefix("image/".count).lowercased() == "image/",
              parts.contains(where: { $0.lowercased() == "base64" })
        else {
            return nil
        }
        return payload
    }

    private static func estimateOriginalImageBytes(imageURL: String) -> Int? {
        guard let payload = parseBase64ImageDataURL(imageURL),
              let data = Data(base64Encoded: String(payload))
        else {
            return nil
        }

        let dimensions: ImageDimensions
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            dimensions = ImageDimensions(width: image.width, height: image.height)
        } else if let webPDimensions = parseWebPImageDimensions(data) {
            dimensions = webPDimensions
        } else {
            return nil
        }

        let patchSize = originalImagePatchSize
        let patchesWide = dimensions.width.addingClamped(patchSize - 1) / patchSize
        let patchesHigh = dimensions.height.addingClamped(patchSize - 1) / patchSize
        let patchCount = min(patchesWide.multipliedClamped(by: patchesHigh), originalImageMaxPatches)
        return Truncation.approxBytesForTokens(patchCount)
    }

    private static func parseWebPImageDimensions(_ data: Data) -> ImageDimensions? {
        guard data.count >= 20,
              data.matchesASCII("RIFF", at: 0),
              data.matchesASCII("WEBP", at: 8)
        else {
            return nil
        }

        var chunkOffset = 12
        while chunkOffset.addingClamped(8) <= data.count {
            let chunkType = data.asciiString(in: chunkOffset..<chunkOffset + 4)
            let chunkSize = data.littleEndianUInt32(at: chunkOffset + 4)
            let payloadOffset = chunkOffset + 8
            let payloadEnd = payloadOffset.addingClamped(Int(chunkSize))
            guard payloadEnd <= data.count else {
                return nil
            }

            switch chunkType {
            case "VP8 ":
                return parseLossyWebPDimensions(data, payloadOffset: payloadOffset, payloadEnd: payloadEnd)
            case "VP8L":
                return parseLosslessWebPDimensions(data, payloadOffset: payloadOffset, payloadEnd: payloadEnd)
            case "VP8X":
                return parseExtendedWebPDimensions(data, payloadOffset: payloadOffset, payloadEnd: payloadEnd)
            default:
                let paddedSize = Int(chunkSize) + (Int(chunkSize) % 2)
                chunkOffset = payloadOffset.addingClamped(paddedSize)
            }
        }

        return nil
    }

    private static func parseLossyWebPDimensions(
        _ data: Data,
        payloadOffset: Int,
        payloadEnd: Int
    ) -> ImageDimensions? {
        guard payloadOffset.addingClamped(10) <= payloadEnd,
              data[payloadOffset + 3] == 0x9d,
              data[payloadOffset + 4] == 0x01,
              data[payloadOffset + 5] == 0x2a
        else {
            return nil
        }

        let width = Int(data.littleEndianUInt16(at: payloadOffset + 6) & 0x3fff)
        let height = Int(data.littleEndianUInt16(at: payloadOffset + 8) & 0x3fff)
        return ImageDimensions(width: width, height: height)
    }

    private static func parseLosslessWebPDimensions(
        _ data: Data,
        payloadOffset: Int,
        payloadEnd: Int
    ) -> ImageDimensions? {
        guard payloadOffset.addingClamped(5) <= payloadEnd,
              data[payloadOffset] == 0x2f
        else {
            return nil
        }

        let bits = UInt32(data[payloadOffset + 1])
            | (UInt32(data[payloadOffset + 2]) << 8)
            | (UInt32(data[payloadOffset + 3]) << 16)
            | (UInt32(data[payloadOffset + 4]) << 24)
        let width = Int(bits & 0x3fff) + 1
        let height = Int((bits >> 14) & 0x3fff) + 1
        return ImageDimensions(width: width, height: height)
    }

    private static func parseExtendedWebPDimensions(
        _ data: Data,
        payloadOffset: Int,
        payloadEnd: Int
    ) -> ImageDimensions? {
        guard payloadOffset.addingClamped(10) <= payloadEnd else {
            return nil
        }

        let width = Int(data.uint24LittleEndian(at: payloadOffset + 4)) + 1
        let height = Int(data.uint24LittleEndian(at: payloadOffset + 7)) + 1
        return ImageDimensions(width: width, height: height)
    }
}

private struct ImageDimensions {
    let width: Int
    let height: Int
}

private extension Data {
    func matchesASCII(_ value: String, at offset: Int) -> Bool {
        guard let ascii = value.data(using: .ascii),
              offset.addingClamped(ascii.count) <= count
        else {
            return false
        }
        return self[offset..<offset + ascii.count].elementsEqual(ascii)
    }

    func asciiString(in range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            return nil
        }
        return String(data: self[range], encoding: .ascii)
    }

    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func uint24LittleEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
    }
}

private extension Int {
    func addingClamped(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : result
    }

    func subtractingClamped(_ other: Int) -> Int {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow || result < 0 ? 0 : result
    }

    func multipliedClamped(by other: Int) -> Int {
        let (result, overflow) = multipliedReportingOverflow(by: other)
        return overflow ? Int.max : result
    }

    func dividedReportingZero(by divisor: Int) -> Int {
        guard divisor != 0 else {
            return 0
        }
        return self / divisor
    }
}
