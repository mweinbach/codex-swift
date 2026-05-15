extension KeyedDecodingContainer {
    func decodeRustDefaulted<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        defaultValue: T
    ) throws -> T {
        guard contains(key) else {
            return defaultValue
        }
        return try decode(type, forKey: key)
    }
}
