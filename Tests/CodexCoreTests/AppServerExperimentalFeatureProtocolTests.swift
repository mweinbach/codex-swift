import CodexCore
import XCTest

final class AppServerExperimentalFeatureProtocolTests: XCTestCase {
    func testExperimentalFeatureListParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ExperimentalFeatureListParams(), [
            "cursor": NSNull(),
            "limit": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            ExperimentalFeatureListParams(cursor: "2", limit: 50),
            [
                "cursor": "2",
                "limit": 50
            ]
        )
    }

    func testExperimentalFeaturePayloadsEncodeRustV2Shape() throws {
        let feature = ExperimentalFeature(
            name: "memories",
            stage: .beta,
            displayName: "Memories",
            description: nil,
            announcement: "",
            enabled: true,
            defaultEnabled: false
        )

        try XCTAssertJSONObjectEqual(feature, [
            "name": "memories",
            "stage": "beta",
            "displayName": "Memories",
            "description": NSNull(),
            "announcement": "",
            "enabled": true,
            "defaultEnabled": false
        ])

        try XCTAssertJSONObjectEqual(
            ExperimentalFeatureListResponse(data: [feature], nextCursor: nil),
            [
                "data": [[
                    "name": "memories",
                    "stage": "beta",
                    "displayName": "Memories",
                    "description": NSNull(),
                    "announcement": "",
                    "enabled": true,
                    "defaultEnabled": false
                ]],
                "nextCursor": NSNull()
            ]
        )
    }

    func testExperimentalFeaturePayloadsConvertFromCoreFeatureSpec() throws {
        var features = FeatureStates.withDefaults()
        features.set(.memoryTool, enabled: true)

        let spec = FeatureSpec(
            id: .memoryTool,
            key: "memories",
            stage: .experimental,
            defaultEnabled: false,
            displayName: "Memories",
            description: "Remember useful details.",
            announcement: "New"
        )

        try XCTAssertJSONObjectEqual(ExperimentalFeature(core: spec, features: features), [
            "name": "memories",
            "stage": "beta",
            "displayName": "Memories",
            "description": "Remember useful details.",
            "announcement": "New",
            "enabled": true,
            "defaultEnabled": false
        ])

        XCTAssertEqual(ExperimentalFeatureStage(core: .underDevelopment), .underDevelopment)
        XCTAssertEqual(ExperimentalFeatureStage(core: .stable), .stable)
        XCTAssertEqual(ExperimentalFeatureStage(core: .deprecated), .deprecated)
        XCTAssertEqual(ExperimentalFeatureStage(core: .removed), .removed)
    }

    func testExperimentalFeatureEnablementPayloadsEncodeRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            ExperimentalFeatureEnablementSetParams(enablement: [
                "memories": true,
                "plugins": false
            ]),
            [
                "enablement": [
                    "memories": true,
                    "plugins": false
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            ExperimentalFeatureEnablementSetResponse(enablement: [
                "memories": true
            ]),
            [
                "enablement": [
                    "memories": true
                ]
            ]
        )
    }
}
