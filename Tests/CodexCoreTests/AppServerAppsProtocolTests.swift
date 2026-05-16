import CodexCore
import XCTest

final class AppServerAppsProtocolTests: XCTestCase {
    func testAppsListParamsEncodeExplicitNullOptionalsAndSkipFalseRefetchLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(AppsListParams(), [
            "cursor": NSNull(),
            "limit": NSNull(),
            "threadId": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            AppsListParams(cursor: "next-page", limit: 25, threadID: "thread-1", forceRefetch: true),
            [
                "cursor": "next-page",
                "limit": 25,
                "threadId": "thread-1",
                "forceRefetch": true
            ]
        )

        let decoded = try JSONDecoder().decode(AppsListParams.self, from: Data(#"{"cursor":null,"limit":null,"threadId":null}"#.utf8))

        XCTAssertNil(decoded.cursor)
        XCTAssertNil(decoded.limit)
        XCTAssertNil(decoded.threadID)
        XCTAssertFalse(decoded.forceRefetch)
    }

    func testAppsListParamsRejectsExplicitNullForRustDefaultedRefetchFlag() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListParams.self,
                from: Data(#"{"forceRefetch":null}"#.utf8)
            )
        )
    }

    func testAppsListResponseShapeMatchesRustProtocol() throws {
        let app = AppInfo(
            id: "weather-app",
            name: "Weather",
            description: "Forecasts",
            logoURL: "https://example.test/logo.png",
            logoURLDark: nil,
            distributionChannel: "workspace",
            branding: AppBranding(
                category: "productivity",
                developer: "Example",
                website: "https://example.test",
                privacyPolicy: nil,
                termsOfService: nil,
                isDiscoverableApp: true
            ),
            appMetadata: AppMetadata(
                review: AppReview(status: "approved"),
                categories: ["productivity"],
                subCategories: nil,
                seoDescription: "Weather app",
                screenshots: [
                    AppScreenshot(url: nil, fileID: "file-1", userPrompt: "show weather")
                ],
                developer: "Example",
                version: "1.0.0",
                versionID: "version-1",
                versionNotes: nil,
                firstPartyType: nil,
                firstPartyRequiresInstall: false,
                showInComposerWhenUnlinked: true
            ),
            labels: ["tier": "beta"],
            installURL: "https://example.test/install",
            isAccessible: true,
            isEnabled: false,
            pluginDisplayNames: ["Weather Plugin"]
        )

        try XCTAssertJSONObjectEqual(
            AppsListResponse(data: [app], nextCursor: nil),
            [
                "data": [[
                    "id": "weather-app",
                    "name": "Weather",
                    "description": "Forecasts",
                    "logoUrl": "https://example.test/logo.png",
                    "logoUrlDark": NSNull(),
                    "distributionChannel": "workspace",
                    "branding": [
                        "category": "productivity",
                        "developer": "Example",
                        "website": "https://example.test",
                        "privacyPolicy": NSNull(),
                        "termsOfService": NSNull(),
                        "isDiscoverableApp": true
                    ],
                    "appMetadata": [
                        "review": ["status": "approved"],
                        "categories": ["productivity"],
                        "subCategories": NSNull(),
                        "seoDescription": "Weather app",
                        "screenshots": [[
                            "url": NSNull(),
                            "fileId": "file-1",
                            "userPrompt": "show weather"
                        ]],
                        "developer": "Example",
                        "version": "1.0.0",
                        "versionId": "version-1",
                        "versionNotes": NSNull(),
                        "firstPartyType": NSNull(),
                        "firstPartyRequiresInstall": false,
                        "showInComposerWhenUnlinked": true
                    ],
                    "labels": ["tier": "beta"],
                    "installUrl": "https://example.test/install",
                    "isAccessible": true,
                    "isEnabled": false,
                    "pluginDisplayNames": ["Weather Plugin"]
                ]],
                "nextCursor": NSNull()
            ]
        )
    }

    func testAppInfoDecodeDefaultsAndScreenshotAliasesMatchRustProtocol() throws {
        let response = try JSONDecoder().decode(
            AppsListResponse.self,
            from: Data(
                #"""
                {
                  "data": [{
                    "id": "weather-app",
                    "name": "Weather",
                    "appMetadata": {
                      "screenshots": [{
                        "url": "https://example.test/screenshot.png",
                        "file_id": "legacy-file",
                        "user_prompt": "legacy prompt"
                      }]
                    }
                  }],
                  "nextCursor": "next"
                }
                """#.utf8
            )
        )

        let app = try XCTUnwrap(response.data.first)
        XCTAssertEqual(app.description, nil)
        XCTAssertFalse(app.isAccessible)
        XCTAssertTrue(app.isEnabled)
        XCTAssertEqual(app.pluginDisplayNames, [])
        XCTAssertEqual(app.appMetadata?.screenshots?.first?.fileID, "legacy-file")
        XCTAssertEqual(app.appMetadata?.screenshots?.first?.userPrompt, "legacy prompt")
        XCTAssertEqual(response.nextCursor, "next")
    }

    func testAppScreenshotRejectsDuplicateRustAliases() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListResponse.self,
                from: Data(
                    #"""
                    {
                      "data": [{
                        "id": "weather-app",
                        "name": "Weather",
                        "appMetadata": {
                          "screenshots": [{
                            "fileId": "file-camel",
                            "file_id": "file-snake",
                            "userPrompt": "show weather"
                          }]
                        }
                      }],
                      "nextCursor": null
                    }
                    """#.utf8
                )
            )
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListResponse.self,
                from: Data(
                    #"""
                    {
                      "data": [{
                        "id": "weather-app",
                        "name": "Weather",
                        "appMetadata": {
                          "screenshots": [{
                            "file_id": "file-1",
                            "userPrompt": "show weather",
                            "user_prompt": "legacy prompt"
                          }]
                        }
                      }],
                      "nextCursor": null
                    }
                    """#.utf8
                )
            )
        )
    }

    func testAppInfoRejectsExplicitNullForRustDefaultedAccessFlags() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListResponse.self,
                from: Data(#"{"data":[{"id":"weather-app","name":"Weather","isAccessible":null}],"nextCursor":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListResponse.self,
                from: Data(#"{"data":[{"id":"weather-app","name":"Weather","isEnabled":null}],"nextCursor":null}"#.utf8)
            )
        )
    }

    func testAppInfoRejectsExplicitNullForRustDefaultedPluginDisplayNames() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppsListResponse.self,
                from: Data(#"{"data":[{"id":"weather-app","name":"Weather","pluginDisplayNames":null}],"nextCursor":null}"#.utf8)
            )
        )
    }

    func testAppBrandingRequiresDiscoverableFlagLikeRustProtocol() {
        for payload in [
            #"{"data":[{"id":"weather-app","name":"Weather","branding":{}}],"nextCursor":null}"#,
            #"{"data":[{"id":"weather-app","name":"Weather","branding":{"isDiscoverableApp":null}}],"nextCursor":null}"#,
            #"{"data":[{"id":"weather-app","name":"Weather","branding":{"isDiscoverableApp":"true"}}],"nextCursor":null}"#
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    AppsListResponse.self,
                    from: Data(payload.utf8)
                )
            )
        }
    }

    func testAppListUpdatedNotificationShapeMatchesRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            AppListUpdatedNotification(data: [
                AppInfo(id: "weather-app", name: "Weather", isAccessible: false, isEnabled: true)
            ]),
            [
                "data": [[
                    "id": "weather-app",
                    "name": "Weather",
                    "description": NSNull(),
                    "logoUrl": NSNull(),
                    "logoUrlDark": NSNull(),
                    "distributionChannel": NSNull(),
                    "branding": NSNull(),
                    "appMetadata": NSNull(),
                    "labels": NSNull(),
                    "installUrl": NSNull(),
                    "isAccessible": false,
                    "isEnabled": true,
                    "pluginDisplayNames": []
                ]]
            ]
        )
    }
}
