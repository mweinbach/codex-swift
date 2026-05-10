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
              let data = Data(base64Encoded: String(payload)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let patchSize = originalImagePatchSize
        let patchesWide = image.width.addingClamped(patchSize - 1) / patchSize
        let patchesHigh = image.height.addingClamped(patchSize - 1) / patchSize
        let patchCount = min(patchesWide.multipliedClamped(by: patchesHigh), originalImageMaxPatches)
        return Truncation.approxBytesForTokens(patchCount)
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
