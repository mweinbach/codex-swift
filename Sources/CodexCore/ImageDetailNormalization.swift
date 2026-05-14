public func canRequestOriginalImageDetail(_ modelInfo: ModelInfo) -> Bool {
    modelInfo.supportsImageDetailOriginal
}

public func normalizeOutputImageDetail(
    modelInfo: ModelInfo,
    detail: ImageDetail?
) -> ImageDetail? {
    switch detail {
    case .original where canRequestOriginalImageDetail(modelInfo):
        return .original
    case .original,
         .none:
        return nil
    case .auto,
         .low,
         .high:
        return detail
    }
}

public func sanitizeOriginalImageDetail(
    canRequestOriginalImageDetail: Bool,
    items: [FunctionCallOutputContentItem]
) -> [FunctionCallOutputContentItem] {
    guard !canRequestOriginalImageDetail else {
        return items
    }

    return items.map { item in
        switch item {
        case let .inputImage(imageURL, .original):
            return .inputImage(imageURL: imageURL, detail: defaultImageDetail)
        case .inputText,
             .inputImage:
            return item
        }
    }
}
