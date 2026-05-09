import Foundation

public struct ByteRange: Equatable, Codable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct TextElement: Equatable, Codable, Sendable {
    public let byteRange: ByteRange
    public let placeholder: String?

    private enum CodingKeys: String, CodingKey {
        case byteRange = "byte_range"
        case placeholder
    }

    public init(byteRange: ByteRange, placeholder: String? = nil) {
        self.byteRange = byteRange
        self.placeholder = placeholder
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byteRange, forKey: .byteRange)
        try container.encode(placeholder, forKey: .placeholder)
    }

    public func rebased(by offset: Int, in text: String) -> TextElement {
        TextElement(
            byteRange: ByteRange(start: offset + byteRange.start, end: offset + byteRange.end),
            placeholder: placeholder ?? text.utf8Substring(in: byteRange)
        )
    }
}

public enum UserInput: Equatable, Codable, Sendable {
    case text(String, textElements: [TextElement] = [])
    case image(imageURL: String)
    case localImage(path: String)
    case skill(name: String, path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements = "text_elements"
        case imageURL = "image_url"
        case path
        case name
    }

    private enum InputType: String, Codable {
        case text
        case image
        case localImage = "local_image"
        case skill
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(InputType.self, forKey: .type) {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                textElements: try container.decodeIfPresent([TextElement].self, forKey: .textElements) ?? []
            )
        case .image:
            self = .image(imageURL: try container.decode(String.self, forKey: .imageURL))
        case .localImage:
            self = .localImage(path: try container.decode(String.self, forKey: .path))
        case .skill:
            self = .skill(
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text, textElements):
            try container.encode(InputType.text, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(textElements, forKey: .textElements)
        case let .image(imageURL):
            try container.encode(InputType.image, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        case let .localImage(path):
            try container.encode(InputType.localImage, forKey: .type)
            try container.encode(path, forKey: .path)
        case let .skill(name, path):
            try container.encode(InputType.skill, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        }
    }
}

private extension String {
    func utf8Substring(in range: ByteRange) -> String? {
        guard range.start >= 0, range.end >= range.start else {
            return nil
        }

        let bytes = Array(utf8)
        guard range.end <= bytes.count else {
            return nil
        }

        return String(decoding: bytes[range.start..<range.end], as: UTF8.self)
    }
}
