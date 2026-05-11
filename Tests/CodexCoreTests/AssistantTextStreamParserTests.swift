import CodexCore
import XCTest

final class AssistantTextStreamParserTests: XCTestCase {
    func testCitationParserStreamsAcrossChunkBoundaries() {
        let (visible, citations) = collectCitations([
            "Hello <oai-mem-",
            "citation>source A</oai-mem-",
            "citation> world"
        ])

        XCTAssertEqual(visible, "Hello  world")
        XCTAssertEqual(citations, ["source A"])
    }

    func testCitationParserAutoClosesUnterminatedTagOnFinish() {
        let (visible, citations) = collectCitations(["x<oai-mem-citation>source"])

        XCTAssertEqual(visible, "x")
        XCTAssertEqual(citations, ["source"])
    }

    func testCitationParserPreservesPartialOpenTagAtEOF() {
        let (visible, citations) = collectCitations(["hello <oai-mem-"])

        XCTAssertEqual(visible, "hello <oai-mem-")
        XCTAssertEqual(citations, [])
    }

    func testCitationParserDoesNotSupportNestedTags() {
        let (visible, citations) = stripAssistantCitations(
            "a<oai-mem-citation>x<oai-mem-citation>y</oai-mem-citation>z</oai-mem-citation>b"
        )

        XCTAssertEqual(visible, "az</oai-mem-citation>b")
        XCTAssertEqual(citations, ["x<oai-mem-citation>y"])
    }

    func testProposedPlanParserStreamsSegmentsAndVisibleText() {
        let (visible, segments) = collectPlanSegments([
            "Intro text\n<prop",
            "osed_plan>\n- step 1\n",
            "</proposed_plan>\nOutro"
        ])

        XCTAssertEqual(visible, "Intro text\nOutro")
        XCTAssertEqual(segments, [
            .normal("Intro text\n"),
            .proposedPlanStart,
            .proposedPlanDelta("- step 1\n"),
            .proposedPlanEnd,
            .normal("Outro")
        ])
    }

    func testProposedPlanParserPreservesNonTagLines() {
        let (visible, segments) = collectPlanSegments(["  <proposed_plan> extra\n"])

        XCTAssertEqual(visible, "  <proposed_plan> extra\n")
        XCTAssertEqual(segments, [.normal("  <proposed_plan> extra\n")])
    }

    func testProposedPlanParserClosesUnterminatedBlockOnFinish() {
        let (visible, segments) = collectPlanSegments(["<proposed_plan>\n- step 1\n"])

        XCTAssertEqual(visible, "")
        XCTAssertEqual(segments, [
            .proposedPlanStart,
            .proposedPlanDelta("- step 1\n"),
            .proposedPlanEnd
        ])
    }

    func testExtractProposedPlanText() {
        let text = "before\n<proposed_plan>\n- step\n</proposed_plan>\nafter"

        XCTAssertEqual(stripProposedPlanBlocks(text), "before\nafter")
        XCTAssertEqual(extractProposedPlanText(text), "- step\n")
    }

    func testAssistantParserParsesCitationsAcrossSeedAndDeltaBoundaries() {
        var parser = AssistantTextStreamParser(planMode: false)

        let seeded = parser.pushString("hello <oai-mem-citation>doc")
        let parsed = parser.pushString("1</oai-mem-citation> world")
        let tail = parser.finish()

        XCTAssertEqual(seeded.visibleText, "hello ")
        XCTAssertEqual(seeded.citations, [])
        XCTAssertEqual(parsed.visibleText, " world")
        XCTAssertEqual(parsed.citations, ["doc1"])
        XCTAssertEqual(tail.visibleText, "")
        XCTAssertEqual(tail.citations, [])
    }

    func testAssistantParserParsesPlanSegmentsAfterCitationStripping() {
        var parser = AssistantTextStreamParser(planMode: true)

        let seeded = parser.pushString("Intro\n<proposed")
        let parsed = parser.pushString("_plan>\n- step <oai-mem-citation>doc</oai-mem-citation>\n")
        let tail = parser.pushString("</proposed_plan>\nOutro")
        let finish = parser.finish()

        XCTAssertEqual(seeded.visibleText, "Intro\n")
        XCTAssertEqual(seeded.planSegments, [.normal("Intro\n")])
        XCTAssertEqual(parsed.visibleText, "")
        XCTAssertEqual(parsed.citations, ["doc"])
        XCTAssertEqual(parsed.planSegments, [
            .proposedPlanStart,
            .proposedPlanDelta("- step \n")
        ])
        XCTAssertEqual(tail.visibleText, "Outro")
        XCTAssertEqual(tail.planSegments, [
            .proposedPlanEnd,
            .normal("Outro")
        ])
        XCTAssertTrue(finish.isEmpty)
    }

    private func collectCitations(_ chunks: [String]) -> (String, [String]) {
        var visible = ""
        var citations: [String] = []
        var parser = AssistantTextStreamParser(planMode: false)

        for chunk in chunks {
            let parsed = parser.pushString(chunk)
            visible.append(parsed.visibleText)
            citations.append(contentsOf: parsed.citations)
        }
        let tail = parser.finish()
        visible.append(tail.visibleText)
        citations.append(contentsOf: tail.citations)
        return (visible, citations)
    }

    private func collectPlanSegments(_ chunks: [String]) -> (String, [ProposedPlanSegment]) {
        var visible = ""
        var segments: [ProposedPlanSegment] = []
        var parser = AssistantTextStreamParser(planMode: true)

        for chunk in chunks {
            let parsed = parser.pushString(chunk)
            visible.append(parsed.visibleText)
            segments.append(contentsOf: parsed.planSegments)
        }
        let tail = parser.finish()
        visible.append(tail.visibleText)
        segments.append(contentsOf: tail.planSegments)
        return (visible, segments)
    }
}
