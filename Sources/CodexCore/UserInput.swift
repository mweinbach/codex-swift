import Foundation

public enum UserInput: Equatable, Codable, Sendable {
    case text(String)
    case image(imageURL: String)
    case localImage(path: String)
    case skill(name: String, path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
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
            self = .text(try container.decode(String.self, forKey: .text))
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
        case let .text(text):
            try container.encode(InputType.text, forKey: .type)
            try container.encode(text, forKey: .text)
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
