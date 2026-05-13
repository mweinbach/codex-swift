import CryptoKit
import Foundation

enum NaClSealedBox {
    static func open(ciphertext sealedBox: Data, recipientSecretKey: Data) throws -> Data {
        guard sealedBox.count > 32 else {
            throw NaClSealedBoxError.openFailed
        }
        let recipientPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientSecretKey)
        let recipientPublicKey = recipientPrivateKey.publicKey.rawRepresentation
        let ephemeralPublicKeyBytes = sealedBox.prefix(32)
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyBytes)
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }
        let precomputedKey = Salsa20.hsalsa20(key: sharedSecretBytes, nonce: Data(repeating: 0, count: 16))
        let nonce = Blake2b.digest24(Data(ephemeralPublicKeyBytes) + recipientPublicKey)
        return try SecretBox.open(ciphertext: sealedBox.dropFirst(32), key: precomputedKey, nonce: nonce)
    }
}

enum NaClSealedBoxError: Error {
    case openFailed
}

private enum SecretBox {
    static func open(ciphertext: Data.SubSequence, key: Data, nonce: Data) throws -> Data {
        guard ciphertext.count >= 16, key.count == 32, nonce.count == 24 else {
            throw NaClSealedBoxError.openFailed
        }
        let tag = Data(ciphertext.prefix(16))
        var encrypted = [UInt8](ciphertext.dropFirst(16))
        let subkey = Salsa20.hsalsa20(key: key, nonce: nonce.prefix(16))
        var cipher = Salsa20(key: subkey, nonce: nonce.suffix(8))
        let macKey = cipher.nextBytes(count: 32)
        let expectedTag = Poly1305.authenticate(encrypted, key: macKey)
        guard constantTimeEquals(tag, expectedTag) else {
            throw NaClSealedBoxError.openFailed
        }
        cipher.xor(&encrypted)
        return Data(encrypted)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

private struct Salsa20 {
    private var key: [UInt8]
    private var nonce: [UInt8]
    private var counter: UInt64 = 0
    private var buffer: [UInt8] = []
    private var bufferIndex = 64

    init(key: Data, nonce: Data.SubSequence) {
        self.key = Array(key)
        self.nonce = Array(nonce)
    }

    mutating func nextBytes(count: Int) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(count)
        while output.count < count {
            if bufferIndex >= buffer.count {
                buffer = Self.block(key: key, nonce: nonce, counter: counter)
                counter &+= 1
                bufferIndex = 0
            }
            let take = min(count - output.count, buffer.count - bufferIndex)
            output.append(contentsOf: buffer[bufferIndex..<bufferIndex + take])
            bufferIndex += take
        }
        return output
    }

    mutating func xor(_ bytes: inout [UInt8]) {
        let stream = nextBytes(count: bytes.count)
        for index in bytes.indices {
            bytes[index] ^= stream[index]
        }
    }

    static func hsalsa20(key: Data, nonce: Data.SubSequence) -> Data {
        precondition(key.count == 32)
        precondition(nonce.count == 16)
        var state = baseState(key: Array(key))
        let nonceBytes = Array(nonce)
        state[6] = load32(nonceBytes, 0)
        state[7] = load32(nonceBytes, 4)
        state[8] = load32(nonceBytes, 8)
        state[9] = load32(nonceBytes, 12)
        let output = rounds(state)
        var data = Data()
        for word in [output[0], output[5], output[10], output[15], output[6], output[7], output[8], output[9]] {
            append32(word, to: &data)
        }
        return data
    }

    private static func block(key: [UInt8], nonce: [UInt8], counter: UInt64) -> [UInt8] {
        var state = baseState(key: key)
        state[6] = load32(nonce, 0)
        state[7] = load32(nonce, 4)
        state[8] = UInt32(truncatingIfNeeded: counter)
        state[9] = UInt32(truncatingIfNeeded: counter >> 32)
        let working = rounds(state)
        var data = Data()
        for index in 0..<16 {
            append32(working[index] &+ state[index], to: &data)
        }
        return Array(data)
    }

    private static func baseState(key: [UInt8]) -> [UInt32] {
        let constants = Array("expand 32-byte k".utf8)
        return [
            load32(constants, 0), load32(key, 0), load32(key, 4), load32(key, 8),
            load32(key, 12), load32(constants, 4), 0, 0,
            0, 0, load32(constants, 8), load32(key, 16),
            load32(key, 20), load32(key, 24), load32(key, 28), load32(constants, 12),
        ]
    }

    private static func rounds(_ input: [UInt32]) -> [UInt32] {
        var x = input
        for _ in 0..<10 {
            quarterRound(&x, 0, 4, 8, 12)
            quarterRound(&x, 5, 9, 13, 1)
            quarterRound(&x, 10, 14, 2, 6)
            quarterRound(&x, 15, 3, 7, 11)
            quarterRound(&x, 0, 1, 2, 3)
            quarterRound(&x, 5, 6, 7, 4)
            quarterRound(&x, 10, 11, 8, 9)
            quarterRound(&x, 15, 12, 13, 14)
        }
        return x
    }

    private static func quarterRound(_ x: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        x[b] ^= (x[a] &+ x[d]).rotatedLeft(7)
        x[c] ^= (x[b] &+ x[a]).rotatedLeft(9)
        x[d] ^= (x[c] &+ x[b]).rotatedLeft(13)
        x[a] ^= (x[d] &+ x[c]).rotatedLeft(18)
    }

    private static func load32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func append32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

private enum Poly1305 {
    static func authenticate(_ message: [UInt8], key: [UInt8]) -> Data {
        precondition(key.count == 32)
        var r = Array(key.prefix(16))
        r[3] &= 15
        r[4] &= 252
        r[7] &= 15
        r[8] &= 252
        r[11] &= 15
        r[12] &= 252
        r[15] &= 15
        let rValue = LittleInt(littleEndianBytes: r)
        let sValue = LittleInt(littleEndianBytes: Array(key[16..<32]))
        var accumulator = LittleInt()
        var offset = 0
        while offset < message.count {
            let blockCount = min(16, message.count - offset)
            var block = Array(message[offset..<offset + blockCount])
            block.append(1)
            accumulator.add(LittleInt(littleEndianBytes: block))
            accumulator.multiply(by: rValue)
            accumulator.reducePoly1305()
            offset += blockCount
        }
        accumulator.add(sValue)
        return Data(accumulator.littleEndianBytes(count: 16))
    }
}

private struct LittleInt {
    private var limbs: [UInt32]

    init() {
        self.limbs = []
    }

    init(littleEndianBytes bytes: [UInt8]) {
        var limbs: [UInt32] = []
        var index = 0
        while index < bytes.count {
            let low = UInt32(bytes[index])
            let high = index + 1 < bytes.count ? UInt32(bytes[index + 1]) << 8 : 0
            limbs.append(low | high)
            index += 2
        }
        self.limbs = limbs
        normalize()
    }

    mutating func add(_ other: LittleInt) {
        let count = max(limbs.count, other.limbs.count)
        if limbs.count < count {
            limbs.append(contentsOf: repeatElement(0, count: count - limbs.count))
        }
        var carry: UInt32 = 0
        for index in 0..<count {
            let sum = limbs[index] + (index < other.limbs.count ? other.limbs[index] : 0) + carry
            limbs[index] = sum & 0xffff
            carry = sum >> 16
        }
        if carry != 0 {
            limbs.append(carry)
        }
    }

    mutating func multiply(by other: LittleInt) {
        guard !limbs.isEmpty, !other.limbs.isEmpty else {
            limbs = []
            return
        }
        var product = [UInt64](repeating: 0, count: limbs.count + other.limbs.count)
        for leftIndex in limbs.indices {
            for rightIndex in other.limbs.indices {
                product[leftIndex + rightIndex] += UInt64(limbs[leftIndex]) * UInt64(other.limbs[rightIndex])
            }
        }
        var carry: UInt64 = 0
        var result: [UInt32] = []
        for value in product {
            let total = value + carry
            result.append(UInt32(total & 0xffff))
            carry = total >> 16
        }
        while carry != 0 {
            result.append(UInt32(carry & 0xffff))
            carry >>= 16
        }
        limbs = result
        normalize()
    }

    mutating func reducePoly1305() {
        while bitLength > 130 {
            let high = shiftedRight(bitCount: 130)
            maskLow(bitCount: 130)
            var folded = high
            folded.multiply(bySmall: 5)
            add(folded)
        }
        let modulus = LittleInt.poly1305Modulus
        while compare(to: modulus) >= 0 {
            subtract(modulus)
        }
    }

    func littleEndianBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            let limb = index / 2
            guard limb < limbs.count else {
                break
            }
            bytes[index] = UInt8((limbs[limb] >> UInt32((index % 2) * 8)) & 0xff)
        }
        return bytes
    }

    private var bitLength: Int {
        guard let lastIndex = limbs.lastIndex(where: { $0 != 0 }) else {
            return 0
        }
        return lastIndex * 16 + (32 - limbs[lastIndex].leadingZeroBitCount)
    }

    private func shiftedRight(bitCount: Int) -> LittleInt {
        let limbShift = bitCount / 16
        let bitShift = bitCount % 16
        guard limbShift < limbs.count else {
            return LittleInt()
        }
        var result = [UInt32]()
        for index in limbShift..<limbs.count {
            var value = limbs[index] >> UInt32(bitShift)
            if bitShift != 0, index + 1 < limbs.count {
                value |= (limbs[index + 1] << UInt32(16 - bitShift)) & 0xffff
            }
            result.append(value & 0xffff)
        }
        var shifted = LittleInt()
        shifted.limbs = result
        shifted.normalize()
        return shifted
    }

    private mutating func maskLow(bitCount: Int) {
        let fullLimbs = bitCount / 16
        let extraBits = bitCount % 16
        let keepCount = fullLimbs + (extraBits == 0 ? 0 : 1)
        if limbs.count > keepCount {
            limbs.removeSubrange(keepCount..<limbs.count)
        }
        if extraBits != 0, limbs.count == keepCount {
            limbs[keepCount - 1] &= (UInt32(1) << UInt32(extraBits)) - 1
        }
        normalize()
    }

    private mutating func multiply(bySmall factor: UInt32) {
        var carry: UInt32 = 0
        for index in limbs.indices {
            let product = limbs[index] * factor + carry
            limbs[index] = product & 0xffff
            carry = product >> 16
        }
        while carry != 0 {
            limbs.append(carry & 0xffff)
            carry >>= 16
        }
        normalize()
    }

    private func compare(to other: LittleInt) -> Int {
        let lhsCount = limbs.lastIndex(where: { $0 != 0 }).map { $0 + 1 } ?? 0
        let rhsCount = other.limbs.lastIndex(where: { $0 != 0 }).map { $0 + 1 } ?? 0
        if lhsCount != rhsCount {
            return lhsCount < rhsCount ? -1 : 1
        }
        guard lhsCount > 0 else {
            return 0
        }
        for index in stride(from: lhsCount - 1, through: 0, by: -1) {
            if limbs[index] != other.limbs[index] {
                return limbs[index] < other.limbs[index] ? -1 : 1
            }
        }
        return 0
    }

    private mutating func subtract(_ other: LittleInt) {
        var borrow: Int32 = 0
        for index in limbs.indices {
            let subtrahend = Int32(index < other.limbs.count ? other.limbs[index] : 0) + borrow
            var value = Int32(limbs[index]) - subtrahend
            if value < 0 {
                value += 1 << 16
                borrow = 1
            } else {
                borrow = 0
            }
            limbs[index] = UInt32(value)
        }
        normalize()
    }

    private mutating func normalize() {
        while limbs.last == 0 {
            limbs.removeLast()
        }
    }

    private static let poly1305Modulus = LittleInt(littleEndianBytes: [
        0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x03,
    ])
}

private enum Blake2b {
    static func digest24(_ message: Data) -> Data {
        var h = iv
        h[0] ^= 0x01010000 ^ 24
        var block = [UInt8](repeating: 0, count: 128)
        let bytes = Array(message)
        for index in bytes.indices {
            block[index] = bytes[index]
        }
        compress(h: &h, block: block, byteCount: UInt64(bytes.count), isLast: true)
        var output = Data()
        for word in h {
            append64(word, to: &output)
        }
        return output.prefix(24)
    }

    private static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
        0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    ]

    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    ]

    private static func compress(h: inout [UInt64], block: [UInt8], byteCount: UInt64, isLast: Bool) {
        var m = [UInt64](repeating: 0, count: 16)
        for index in 0..<16 {
            m[index] = load64(block, index * 8)
        }
        var v = h + iv
        v[12] ^= byteCount
        if isLast {
            v[14] = ~v[14]
        }
        for round in 0..<12 {
            let s = sigma[round]
            mix(&v, 0, 4, 8, 12, m[s[0]], m[s[1]])
            mix(&v, 1, 5, 9, 13, m[s[2]], m[s[3]])
            mix(&v, 2, 6, 10, 14, m[s[4]], m[s[5]])
            mix(&v, 3, 7, 11, 15, m[s[6]], m[s[7]])
            mix(&v, 0, 5, 10, 15, m[s[8]], m[s[9]])
            mix(&v, 1, 6, 11, 12, m[s[10]], m[s[11]])
            mix(&v, 2, 7, 8, 13, m[s[12]], m[s[13]])
            mix(&v, 3, 4, 9, 14, m[s[14]], m[s[15]])
        }
        for index in 0..<8 {
            h[index] ^= v[index] ^ v[index + 8]
        }
    }

    private static func mix(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = (v[d] ^ v[a]).rotatedRight(32)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(24)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = (v[d] ^ v[a]).rotatedRight(16)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(63)
    }

    private static func load64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    private static func append64(_ value: UInt64, to data: inout Data) {
        for index in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(index * 8)))
        }
    }
}

private extension UInt32 {
    func rotatedLeft(_ amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}

private extension UInt64 {
    func rotatedRight(_ amount: UInt64) -> UInt64 {
        (self >> amount) | (self << (64 - amount))
    }
}
