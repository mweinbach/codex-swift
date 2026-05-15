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

    func decodeRustUsize(forKey key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "invalid value: integer `\(value)`, expected usize"
            )
        }
        return value
    }

    func decodeRustUsizeIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        return try decodeRustUsize(forKey: key)
    }
}
