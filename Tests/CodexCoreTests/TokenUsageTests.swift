import CodexCore
import XCTest

final class TokenUsageTests: XCTestCase {
    func testTokenUsageWireShape() throws {
        let usage = TokenUsage(
            inputTokens: 1,
            cachedInputTokens: 2,
            outputTokens: 3,
            reasoningOutputTokens: 4,
            totalTokens: 5
        )

        try XCTAssertJSONObjectEqual(usage, [
            "input_tokens": 1,
            "cached_input_tokens": 2,
            "output_tokens": 3,
            "reasoning_output_tokens": 4,
            "total_tokens": 5
        ])
    }

    func testTokenUsageDerivedValuesMatchRustLogic() {
        let usage = TokenUsage(
            inputTokens: 300,
            cachedInputTokens: 100,
            outputTokens: 45,
            reasoningOutputTokens: 7,
            totalTokens: 345
        )

        XCTAssertFalse(usage.isZero)
        XCTAssertEqual(usage.cachedInput, 100)
        XCTAssertEqual(usage.nonCachedInput, 200)
        XCTAssertEqual(usage.blendedTotal, 245)
        XCTAssertEqual(usage.tokensInContextWindow, 345)
    }

    func testTokenUsageClampsDisplayCounts() {
        let usage = TokenUsage(
            inputTokens: 50,
            cachedInputTokens: 100,
            outputTokens: -7,
            totalTokens: 1
        )

        XCTAssertEqual(usage.cachedInput, 100)
        XCTAssertEqual(usage.nonCachedInput, 0)
        XCTAssertEqual(usage.blendedTotal, 0)
    }

    func testTokenUsageZeroOnlyChecksTotalTokens() {
        XCTAssertTrue(TokenUsage().isZero)
        XCTAssertTrue(TokenUsage(inputTokens: 100).isZero)
        XCTAssertFalse(TokenUsage(totalTokens: 1).isZero)
    }

    func testPercentOfContextWindowRemainingMatchesBaselineLogic() {
        XCTAssertEqual(TokenUsage(totalTokens: 12_000).percentOfContextWindowRemaining(12_000), 0)
        XCTAssertEqual(TokenUsage(totalTokens: 12_000).percentOfContextWindowRemaining(22_000), 100)
        XCTAssertEqual(TokenUsage(totalTokens: 17_000).percentOfContextWindowRemaining(22_000), 50)
        XCTAssertEqual(TokenUsage(totalTokens: 25_000).percentOfContextWindowRemaining(22_000), 0)
    }

    func testTokenUsageAddAssignSumsAllFields() {
        var total = TokenUsage(
            inputTokens: 1,
            cachedInputTokens: 2,
            outputTokens: 3,
            reasoningOutputTokens: 4,
            totalTokens: 5
        )

        total.addAssign(TokenUsage(
            inputTokens: 10,
            cachedInputTokens: 20,
            outputTokens: 30,
            reasoningOutputTokens: 40,
            totalTokens: 50
        ))

        XCTAssertEqual(total, TokenUsage(
            inputTokens: 11,
            cachedInputTokens: 22,
            outputTokens: 33,
            reasoningOutputTokens: 44,
            totalTokens: 55
        ))
    }

    func testTokenUsageInfoNewOrAppend() {
        XCTAssertNil(TokenUsageInfo.newOrAppend(info: nil, last: nil, modelContextWindow: nil))

        let first = TokenUsage(inputTokens: 10, outputTokens: 2, totalTokens: 12)
        let created = TokenUsageInfo.newOrAppend(info: nil, last: first, modelContextWindow: 4_096)

        XCTAssertEqual(created?.totalTokenUsage, first)
        XCTAssertEqual(created?.lastTokenUsage, first)
        XCTAssertEqual(created?.modelContextWindow, 4_096)

        let next = TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7)
        let appended = TokenUsageInfo.newOrAppend(info: created, last: next, modelContextWindow: nil)

        XCTAssertEqual(appended?.totalTokenUsage, TokenUsage(inputTokens: 13, outputTokens: 6, totalTokens: 19))
        XCTAssertEqual(appended?.lastTokenUsage, next)
        XCTAssertEqual(appended?.modelContextWindow, 4_096)
    }

    func testTokenUsageInfoFillToContextWindow() {
        var info = TokenUsageInfo(
            totalTokenUsage: TokenUsage(totalTokens: 1_000),
            lastTokenUsage: TokenUsage(totalTokens: 1_000),
            modelContextWindow: nil
        )

        info.fillToContextWindow(4_096)

        XCTAssertEqual(info.modelContextWindow, 4_096)
        XCTAssertEqual(info.totalTokenUsage, TokenUsage(totalTokens: 4_096))
        XCTAssertEqual(info.lastTokenUsage, TokenUsage(totalTokens: 3_096))
        XCTAssertEqual(TokenUsageInfo.fullContextWindow(2_048).totalTokenUsage, TokenUsage(totalTokens: 2_048))
    }

    func testTokenUsageInfoWireShape() throws {
        let info = TokenUsageInfo(
            totalTokenUsage: TokenUsage(inputTokens: 10, totalTokens: 10),
            lastTokenUsage: TokenUsage(outputTokens: 2, totalTokens: 2),
            modelContextWindow: 4_096
        )

        let object = try JSONObject(info)

        XCTAssertNotNil(object["total_token_usage"])
        XCTAssertNotNil(object["last_token_usage"])
        XCTAssertEqual(object["model_context_window"] as? Int, 4_096)
    }

    func testFinalOutputFormatsBasicUsage() {
        let output = FinalOutput(TokenUsage(inputTokens: 10, outputTokens: 2, totalTokens: 12))

        XCTAssertEqual(output.description, "Token usage: total=12 input=10 output=2")
    }

    func testFinalOutputIncludesCachedAndReasoningDetails() {
        let output = FinalOutput(TokenUsage(
            inputTokens: 300,
            cachedInputTokens: 100,
            outputTokens: 45,
            reasoningOutputTokens: 7,
            totalTokens: 345
        ))

        XCTAssertEqual(
            output.description,
            "Token usage: total=245 input=200 (+ 100 cached) output=45 (reasoning 7)"
        )
    }
}
