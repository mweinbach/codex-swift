import Foundation

public enum TextEncoding {
    /// Port of codex-rs/core/src/text_encoding.rs `bytes_to_string_smart`.
    public static func bytesToStringSmart(_ bytes: [UInt8]) -> String {
        bytesToStringSmart(Data(bytes))
    }

    /// Attempts to convert arbitrary shell-output bytes to UTF-8 with best-effort legacy encoding detection.
    public static func bytesToStringSmart(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let utf16 = decodeUTF16WithBOM(data) {
            return utf16
        }
        if hasUTF16ByteOrderMark(data) {
            return String(decoding: data, as: UTF8.self)
        }

        if looksLikeWindows1252Punctuation(data),
           let decoded = String(data: data, encoding: .windowsCP1252) {
            return decoded
        }

        var candidates = candidateEncodings()
        let detectedEncoding = foundationDetectedEncoding(for: data)
        if let detectedEncoding {
            candidates.insert(detectedEncoding, at: 0)
        }
        candidates = uniqueEncodings(candidates)

        let best = candidates.compactMap { encoding -> DecodedCandidate? in
            guard let decoded = String(data: data, encoding: encoding), !decoded.isEmpty else {
                return nil
            }
            return DecodedCandidate(
                text: decoded,
                score: score(decoded, detected: encoding == detectedEncoding)
            )
        }.max { lhs, rhs in
            lhs.score < rhs.score
        }

        if let best, best.score >= 12 {
            return best.text
        }

        return String(decoding: data, as: UTF8.self)
    }
}

private struct DecodedCandidate {
    let text: String
    let score: Int
}

private let windows1252PunctuationBytes: Set<UInt8> = [
    0x91,
    0x92,
    0x93,
    0x94,
    0x95,
    0x96,
    0x97,
    0x99
]

private func looksLikeWindows1252Punctuation(_ data: Data) -> Bool {
    var sawExtendedPunctuation = false
    var sawASCIIWord = false

    for byte in data {
        if byte >= 0xA0 {
            return false
        }
        if (0x80...0x9F).contains(byte) {
            guard windows1252PunctuationBytes.contains(byte) else {
                return false
            }
            sawExtendedPunctuation = true
        }
        if byte.isASCIIAlphabetic {
            sawASCIIWord = true
        }
    }

    return sawExtendedPunctuation && sawASCIIWord
}

private func decodeUTF16WithBOM(_ data: Data) -> String? {
    guard hasUTF16ByteOrderMark(data) else {
        return nil
    }
    guard let decoded = String(data: data, encoding: .utf16) else {
        return nil
    }

    let stripped = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    guard !stripped.isEmpty || data.count <= 2 else {
        return nil
    }
    return stripped
}

private func hasUTF16ByteOrderMark(_ data: Data) -> Bool {
    data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
}

private func foundationDetectedEncoding(for data: Data) -> String.Encoding? {
    var converted: NSString?
    var lossy = ObjCBool(false)
    let raw = NSString.stringEncoding(
        for: data,
        encodingOptions: nil,
        convertedString: &converted,
        usedLossyConversion: &lossy
    )
    guard raw != 0, !lossy.boolValue else {
        return nil
    }
    return String.Encoding(rawValue: raw)
}

private func candidateEncodings() -> [String.Encoding] {
    [
        .windowsCP1251,
        cfEncoding(.dosRussian),
        cfEncoding(.KOI8_R),
        .windowsCP1252,
        .isoLatin1,
        .windowsCP1250,
        cfEncoding(.isoLatin2),
        cfEncoding(.isoLatin3),
        cfEncoding(.isoLatin4),
        cfEncoding(.isoLatinCyrillic),
        cfEncoding(.isoLatinArabic),
        cfEncoding(.windowsArabic),
        cfEncoding(.isoLatinGreek),
        .windowsCP1253,
        cfEncoding(.isoLatinHebrew),
        cfEncoding(.windowsHebrew),
        .windowsCP1254,
        cfEncoding(.isoLatin5),
        cfEncoding(.isoLatin6),
        cfEncoding(.dosThai),
        cfEncoding(.isoLatinThai),
        cfEncoding(.isoLatin7),
        cfEncoding(.windowsBalticRim),
        cfEncoding(.windowsVietnamese),
        .shiftJIS,
        cfEncoding(.GB_18030_2000),
        cfEncoding(.EUC_KR),
        cfEncoding(.big5)
    ]
}

private func cfEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
    String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
    )
}

private func uniqueEncodings(_ encodings: [String.Encoding]) -> [String.Encoding] {
    var seen = Set<UInt>()
    var result: [String.Encoding] = []
    for encoding in encodings where seen.insert(encoding.rawValue).inserted {
        result.append(encoding)
    }
    return result
}

private func score(_ value: String, detected: Bool) -> Int {
    var score = detected ? 12 : 0
    var sawASCIIWord = false
    var sawNonASCII = false
    var previousCyrillicWasLowercase = false

    for scalar in value.unicodeScalars {
        let scalarValue = scalar.value
        if scalarValue < 0x80 {
            score += scoreASCII(scalar, sawASCIIWord: &sawASCIIWord)
            previousCyrillicWasLowercase = false
            continue
        }

        sawNonASCII = true

        if isCyrillic(scalarValue) {
            score += scoreCyrillic(scalar, previousWasLowercase: previousCyrillicWasLowercase)
            previousCyrillicWasLowercase = isLowercaseLike(scalar)
            continue
        }

        previousCyrillicWasLowercase = false

        if isHiraganaOrKatakana(scalarValue) || isHangul(scalarValue) {
            score += 20
        } else if isCJK(scalarValue) {
            score += 12
        } else if isGreek(scalarValue) || isHebrew(scalarValue) || isThai(scalarValue) {
            score += 12
        } else if isArabic(scalarValue) {
            score += 12 + arabicFrequencyBonus(scalar)
        } else if isExtendedLatin(scalarValue) {
            score += scoreExtendedLatin(scalar)
        } else if isCombiningMark(scalarValue) {
            score += 2
        } else if isBoxDrawingOrBlock(scalarValue) || isBopomofo(scalarValue) {
            score -= 18
        } else if isBadControl(scalarValue) {
            score -= 50
        } else if isSuspiciousSymbol(scalar) {
            score -= 12
        } else if isCommonPunctuation(scalar) {
            score += 1
        } else {
            score -= 4
        }
    }

    if sawASCIIWord {
        score += 4
    }
    if !sawNonASCII {
        score -= 8
    }

    return score
}

private func scoreASCII(_ scalar: UnicodeScalar, sawASCIIWord: inout Bool) -> Int {
    if scalar.properties.isAlphabetic {
        sawASCIIWord = true
        return 3
    }
    if scalar.properties.numericType != nil {
        return 2
    }
    if scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar == "\u{1B}" {
        return 1
    }
    if scalar.value < 0x20 || scalar.value == 0x7F {
        return -40
    }
    if isCommonPunctuation(scalar) || scalar == " " {
        return 1
    }
    return 0
}

private func scoreCyrillic(_ scalar: UnicodeScalar, previousWasLowercase: Bool) -> Int {
    var value = 12
    if isLowercaseLike(scalar) {
        value += 1
    } else if previousWasLowercase {
        value -= 8
    }
    if isRareCyrillic(scalar) {
        value -= 10
    }
    if scalar == "Ё" || scalar == "ё" {
        value -= 3
    }
    return value
}

private func scoreExtendedLatin(_ scalar: UnicodeScalar) -> Int {
    if scalar == "»" || scalar == "«" {
        return -6
    }
    if scalar == "Ð" || scalar == "Ñ" || scalar == "ð" || scalar == "þ" || scalar == "ý" {
        return -2
    }
    if scalar.properties.isAlphabetic {
        return 5
    }
    return isCommonPunctuation(scalar) ? 1 : -4
}

private func arabicFrequencyBonus(_ scalar: UnicodeScalar) -> Int {
    switch scalar {
    case "م":
        return 3
    case "ا", "ب", "ح", "ر":
        return 2
    case "ه":
        return 1
    default:
        return 0
    }
}

private func isLowercaseLike(_ scalar: UnicodeScalar) -> Bool {
    scalar.properties.lowercaseMapping.unicodeScalars.first == scalar
        && scalar.properties.uppercaseMapping.unicodeScalars.first != scalar
}

private func isRareCyrillic(_ scalar: UnicodeScalar) -> Bool {
    switch scalar {
    case "Ђ", "ђ", "Ѓ", "ѓ", "Є", "є", "Ѕ", "ѕ", "І", "і", "Ї", "ї",
         "Ј", "ј", "Љ", "љ", "Њ", "њ", "Ћ", "ћ", "Ќ", "ќ", "Ў", "ў",
         "Џ", "џ", "Ґ", "ґ":
        return true
    default:
        return false
    }
}

private func isCyrillic(_ value: UInt32) -> Bool {
    (0x0400...0x052F).contains(value)
}

private func isGreek(_ value: UInt32) -> Bool {
    (0x0370...0x03FF).contains(value)
}

private func isHebrew(_ value: UInt32) -> Bool {
    (0x0590...0x05FF).contains(value)
}

private func isArabic(_ value: UInt32) -> Bool {
    (0x0600...0x06FF).contains(value) || (0x0750...0x077F).contains(value)
}

private func isThai(_ value: UInt32) -> Bool {
    (0x0E00...0x0E7F).contains(value)
}

private func isHangul(_ value: UInt32) -> Bool {
    (0xAC00...0xD7AF).contains(value)
}

private func isHiraganaOrKatakana(_ value: UInt32) -> Bool {
    (0x3040...0x30FF).contains(value) || (0xFF66...0xFF9F).contains(value)
}

private func isCJK(_ value: UInt32) -> Bool {
    (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
}

private func isBopomofo(_ value: UInt32) -> Bool {
    (0x3100...0x312F).contains(value) || (0x31A0...0x31BF).contains(value)
}

private func isExtendedLatin(_ value: UInt32) -> Bool {
    (0x00C0...0x024F).contains(value) || (0x1E00...0x1EFF).contains(value)
}

private func isCombiningMark(_ value: UInt32) -> Bool {
    (0x0300...0x036F).contains(value)
}

private func isBoxDrawingOrBlock(_ value: UInt32) -> Bool {
    (0x2500...0x259F).contains(value)
}

private func isBadControl(_ value: UInt32) -> Bool {
    (value < 0x20 && value != 0x09 && value != 0x0A && value != 0x0D && value != 0x1B)
        || (0x7F...0x9F).contains(value)
}

private func isSuspiciousSymbol(_ scalar: UnicodeScalar) -> Bool {
    switch scalar {
    case "¬", "¤", "¦", "€", "™", "®", "¯", "¨", "¥", "×", "÷":
        return true
    default:
        return false
    }
}

private func isCommonPunctuation(_ scalar: UnicodeScalar) -> Bool {
    switch scalar {
    case " ", ".", ",", ":", ";", "!", "?", "'", "\"", "`", "(", ")", "[", "]", "{", "}",
         "-", "_", "/", "\\", "|", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}",
         "\u{2013}", "\u{2014}", "\u{2022}":
        return true
    default:
        return false
    }
}

private extension UInt8 {
    var isASCIIAlphabetic: Bool {
        (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}
