import Foundation

public struct FuzzyMatchResult: Equatable, Sendable {
    public let indices: [Int]
    public let score: Int32

    public init(indices: [Int], score: Int32) {
        self.indices = indices
        self.score = score
    }
}

public enum FuzzyMatcher {
    public static func match(haystack: String, needle: String) -> FuzzyMatchResult? {
        if needle.isEmpty {
            return FuzzyMatchResult(indices: [], score: Int32.max)
        }

        var loweredScalars: [UnicodeScalar] = []
        var loweredToOriginalCharacterIndex: [Int] = []
        for (originalIndex, character) in haystack.enumerated() {
            for scalar in String(character).lowercased().unicodeScalars {
                loweredScalars.append(scalar)
                loweredToOriginalCharacterIndex.append(originalIndex)
            }
        }

        let loweredNeedle = Array(needle.lowercased().unicodeScalars)
        var resultOriginalIndices: [Int] = []
        var lastLowerPosition: Int?
        var cursor = 0

        for needleScalar in loweredNeedle {
            var foundAt: Int?
            while cursor < loweredScalars.count {
                if loweredScalars[cursor] == needleScalar {
                    foundAt = cursor
                    cursor += 1
                    break
                }
                cursor += 1
            }
            guard let position = foundAt else {
                return nil
            }
            resultOriginalIndices.append(loweredToOriginalCharacterIndex[position])
            lastLowerPosition = position
        }

        let firstLowerPosition: Int
        if let firstOriginal = resultOriginalIndices.first {
            firstLowerPosition = loweredToOriginalCharacterIndex.firstIndex(of: firstOriginal) ?? 0
        } else {
            firstLowerPosition = 0
        }

        let last = lastLowerPosition ?? firstLowerPosition
        let window = Int32(last - firstLowerPosition + 1 - loweredNeedle.count)
        var score = max(window, 0)
        if firstLowerPosition == 0 {
            score -= 100
        }

        let indices = Array(Set(resultOriginalIndices)).sorted()
        return FuzzyMatchResult(indices: indices, score: score)
    }

    public static func indices(haystack: String, needle: String) -> [Int]? {
        match(haystack: haystack, needle: needle)?.indices
    }
}
