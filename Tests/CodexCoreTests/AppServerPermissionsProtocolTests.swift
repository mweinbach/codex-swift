import XCTest
@testable import CodexCore

final class AppServerPermissionsProtocolTests: XCTestCase {
    func testAdditionalPermissionProfileUsesV2CamelCaseAndExplicitNulls() throws {
        let profile = AppServerProtocol.AdditionalPermissionProfile(
            network: RequestPermissionNetworkPermissions(enabled: nil),
            fileSystem: FileSystemPermissions(
                entries: [
                    FileSystemSandboxEntry(path: .globPattern("**/*.secret"), access: .none)
                ],
                globScanMaxDepth: 3
            )
        )

        try XCTAssertJSONObjectEqual(profile, [
            "network": [
                "enabled": NSNull()
            ],
            "fileSystem": [
                "read": NSNull(),
                "write": NSNull(),
                "globScanMaxDepth": 3,
                "entries": [
                    [
                        "path": [
                            "type": "glob_pattern",
                            "pattern": "**/*.secret"
                        ],
                        "access": "none"
                    ]
                ]
            ]
        ])
    }

    func testRequestAndGrantedPermissionProfilesKeepRustNullAndSkipRules() throws {
        try XCTAssertJSONObjectEqual(AppServerProtocol.PermissionsProfile(), [
            "network": NSNull(),
            "fileSystem": NSNull()
        ])

        try XCTAssertJSONObjectEqual(AppServerProtocol.GrantedPermissionProfile(), [:])
    }

    func testLegacyFileSystemPermissionsMaterializeEntriesLikeRustV2Conversion() throws {
        let permissions = AppServerAdditionalFileSystemPermissions(
            FileSystemPermissions(read: ["/repo"], write: ["/repo/Sources"])
        )

        try XCTAssertJSONObjectEqual(permissions, [
            "read": ["/repo"],
            "write": ["/repo/Sources"],
            "entries": [
                [
                    "path": [
                        "type": "path",
                        "path": "/repo"
                    ],
                    "access": "read"
                ],
                [
                    "path": [
                        "type": "path",
                        "path": "/repo/Sources"
                    ],
                    "access": "write"
                ]
            ]
        ])

        XCTAssertEqual(
            permissions.fileSystemPermissions,
            FileSystemPermissions(
                entries: [
                    FileSystemSandboxEntry(path: .path("/repo"), access: .read),
                    FileSystemSandboxEntry(path: .path("/repo/Sources"), access: .write)
                ]
            )
        )
    }

    func testDecodedReadWriteOnlyAdditionalFileSystemPermissionsPreserveLegacyCoreShape() throws {
        let decoded = try JSONDecoder().decode(
            AppServerAdditionalFileSystemPermissions.self,
            from: Data(#"{"read":["/repo"],"write":null}"#.utf8)
        )

        XCTAssertEqual(decoded.fileSystemPermissions, FileSystemPermissions(read: ["/repo"]))
    }

    func testManagedPermissionProfileUsesAppServerCamelCaseFilesystemFields() throws {
        let profile = AppServerPermissionProfile.managed(
            network: AppServerPermissionProfileNetworkPermissions(enabled: false),
            fileSystem: .restricted(
                entries: [FileSystemSandboxEntry(path: .path("/repo"), access: .read)],
                globScanMaxDepth: 4
            )
        )

        try XCTAssertJSONObjectEqual(profile, [
            "type": "managed",
            "network": [
                "enabled": false
            ],
            "fileSystem": [
                "type": "restricted",
                "entries": [
                    [
                        "path": [
                            "type": "path",
                            "path": "/repo"
                        ],
                        "access": "read"
                    ]
                ],
                "globScanMaxDepth": 4
            ]
        ])
    }

    func testSpecialFilesystemPathEncodesNullSubpathLikeRustTaggedEnum() throws {
        let profile = AppServerPermissionProfile.managed(
            network: AppServerPermissionProfileNetworkPermissions(enabled: false),
            fileSystem: .restricted(
                entries: [
                    FileSystemSandboxEntry(
                        path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue),
                        access: .write
                    )
                ]
            )
        )

        try XCTAssertJSONObjectEqual(profile, [
            "type": "managed",
            "network": [
                "enabled": false
            ],
            "fileSystem": [
                "type": "restricted",
                "entries": [
                    [
                        "path": [
                            "type": "special",
                            "value": [
                                "kind": "project_roots",
                                "subpath": NSNull()
                            ]
                        ],
                        "access": "write"
                    ]
                ]
            ]
        ])
    }

    func testActivePermissionProfileUsesAppServerCamelCaseModificationTags() throws {
        let profile = AppServerActivePermissionProfile(
            ActivePermissionProfile(
                id: ":workspace",
                modifications: [.additionalWritableRoot(path: "/repo/tmp")]
            )
        )

        try XCTAssertJSONObjectEqual(profile, [
            "id": ":workspace",
            "extends": NSNull(),
            "modifications": [
                [
                    "type": "additionalWritableRoot",
                    "path": "/repo/tmp"
                ]
            ]
        ])

        XCTAssertEqual(
            profile.activePermissionProfile,
            ActivePermissionProfile(
                id: ":workspace",
                modifications: [.additionalWritableRoot(path: "/repo/tmp")]
            )
        )
    }

    func testPermissionProfileSelectionParamsEncodesNullableModifications() throws {
        try XCTAssertJSONObjectEqual(
            AppServerPermissionProfileSelectionParams.profile(id: "limited"),
            [
                "type": "profile",
                "id": "limited",
                "modifications": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            AppServerPermissionProfileSelectionParams.profile(
                id: "limited",
                modifications: [.additionalWritableRoot(path: "/repo/tmp")]
            ),
            [
                "type": "profile",
                "id": "limited",
                "modifications": [
                    [
                        "type": "additionalWritableRoot",
                        "path": "/repo/tmp"
                    ]
                ]
            ]
        )
    }

    func testPermissionsRequestApprovalResponseConvertsGrantedProfileBackToCoreShape() throws {
        let decoded = try JSONDecoder().decode(
            AppServerProtocol.PermissionsRequestApprovalResponse.self,
            from: Data(
                #"{"permissions":{"network":{"enabled":true},"fileSystem":{"read":null,"write":null,"globScanMaxDepth":2,"entries":[{"path":{"type":"path","path":"/repo"},"access":"read"}]}}}"#.utf8
            )
        )

        XCTAssertEqual(decoded.scope, .turn)
        XCTAssertNil(decoded.strictAutoReview)
        XCTAssertEqual(decoded.permissions.network?.requestPermissions, RequestPermissionNetworkPermissions(enabled: true))
        XCTAssertEqual(
            decoded.permissions.fileSystem?.fileSystemPermissions,
            FileSystemPermissions(
                entries: [FileSystemSandboxEntry(path: .path("/repo"), access: .read)],
                globScanMaxDepth: 2
            )
        )
    }

    func testRequestPermissionProfileRejectsUnknownFieldsLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            RequestPermissionProfile.self,
            from: Data(#"{"network":{"enabled":true},"extra":true}"#.utf8)
        ))
    }

    func testManagedPermissionProfileRejectsZeroGlobScanDepthLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerPermissionProfile.self,
            from: Data(
                #"{"type":"managed","network":{"enabled":true},"fileSystem":{"type":"restricted","entries":[],"globScanMaxDepth":0}}"#.utf8
            )
        ))
    }
}
