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

    func testAdditionalFileSystemPermissionsPreserveCanonicalEntriesLikeRustProtocol() throws {
        let corePermissions = FileSystemPermissions(
            entries: [
                FileSystemSandboxEntry(
                    path: .special(FileSystemSpecialPath.root.jsonValue),
                    access: .write
                ),
                FileSystemSandboxEntry(
                    path: .globPattern("**/*.env"),
                    access: .none
                )
            ],
            globScanMaxDepth: 2
        )
        let permissions = AppServerAdditionalFileSystemPermissions(corePermissions)

        XCTAssertNil(permissions.read)
        XCTAssertNil(permissions.write)
        XCTAssertEqual(permissions.globScanMaxDepth, 2)
        XCTAssertEqual(permissions.fileSystemPermissions, corePermissions)
        try XCTAssertJSONObjectEqual(permissions, [
            "read": NSNull(),
            "write": NSNull(),
            "globScanMaxDepth": 2,
            "entries": [
                [
                    "path": [
                        "type": "special",
                        "value": [
                            "kind": "root"
                        ]
                    ],
                    "access": "write"
                ],
                [
                    "path": [
                        "type": "glob_pattern",
                        "pattern": "**/*.env"
                    ],
                    "access": "none"
                ]
            ]
        ])
    }

    func testDecodedReadWriteOnlyAdditionalFileSystemPermissionsPreserveLegacyCoreShape() throws {
        let decoded = try JSONDecoder().decode(
            AppServerAdditionalFileSystemPermissions.self,
            from: Data(#"{"read":["/repo"],"write":null}"#.utf8)
        )

        XCTAssertEqual(decoded.fileSystemPermissions, FileSystemPermissions(read: ["/repo"]))
    }

    func testAdditionalFileSystemPermissionsRejectRelativeLegacyPathsLikeRustProtocol() {
        let payloads = [
            #"{"read":["relative/path"],"write":null}"#,
            #"{"read":null,"write":["relative/path"]}"#,
        ]

        for payload in payloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    AppServerAdditionalFileSystemPermissions.self,
                    from: Data(payload.utf8)
                ),
                "Rust decodes legacy read/write roots as AbsolutePathBuf: \(payload)"
            ) { error in
                XCTAssertTrue(
                    String(describing: error).contains("AbsolutePathBuf deserialized without a base path"),
                    "expected Rust-shaped absolute-path error, got \(error)"
                )
            }
        }
    }

    func testFileSystemPathRejectsRelativePathVariantLikeRustProtocol() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerAdditionalFileSystemPermissions.self,
                from: Data(
                    #"{"entries":[{"path":{"type":"path","path":"relative/path"},"access":"read"}]}"#.utf8
                )
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("AbsolutePathBuf deserialized without a base path"),
                "expected Rust-shaped absolute-path error, got \(error)"
            )
        }
    }

    func testPermissionsRequestApprovalUsesRequestPermissionProfileLikeRustProtocol() throws {
        let decoded = try JSONDecoder().decode(
            AppServerProtocol.PermissionsRequestApprovalParams.self,
            from: Data(
                #"""
                {
                  "threadId": "thr_123",
                  "turnId": "turn_123",
                  "itemId": "call_123",
                  "startedAtMs": 1,
                  "cwd": "/repo",
                  "reason": "Select a workspace root",
                  "permissions": {
                    "network": {
                      "enabled": true
                    },
                    "fileSystem": {
                      "read": ["/tmp/read-only"],
                      "write": ["/tmp/read-write"]
                    }
                  }
                }
                """#.utf8
            )
        )

        XCTAssertEqual(decoded.cwd.path, "/repo")
        XCTAssertEqual(decoded.permissions.network?.requestPermissions, RequestPermissionNetworkPermissions(enabled: true))
        XCTAssertEqual(
            decoded.permissions.fileSystem?.fileSystemPermissions,
            FileSystemPermissions(read: ["/tmp/read-only"], write: ["/tmp/read-write"])
        )
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

    func testSpecialFilesystemPathCanonicalizesLegacyCurrentWorkingDirectoryAliasLikeRust() throws {
        let decoded = try JSONDecoder().decode(
            AppServerPermissionProfileFileSystemPermissions.self,
            from: Data(
                #"""
                {
                  "type": "restricted",
                  "entries": [{
                    "path": {
                      "type": "special",
                      "value": {
                        "kind": "current_working_directory"
                      }
                    },
                    "access": "write"
                  }]
                }
                """#.utf8
            )
        )

        XCTAssertEqual(
            decoded,
            .restricted(entries: [
                FileSystemSandboxEntry(
                    path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue),
                    access: .write
                )
            ])
        )
        try XCTAssertJSONObjectEqual(decoded, [
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

    func testActivePermissionProfileDecodesRustDefaultedModifications() throws {
        let missingModifications = try JSONDecoder().decode(
            AppServerActivePermissionProfile.self,
            from: Data(#"{"id":":workspace"}"#.utf8)
        )
        XCTAssertEqual(
            missingModifications,
            AppServerActivePermissionProfile(id: ":workspace")
        )

        let explicitNullExtends = try JSONDecoder().decode(
            AppServerActivePermissionProfile.self,
            from: Data(#"{"id":":workspace","extends":null}"#.utf8)
        )
        XCTAssertEqual(
            explicitNullExtends,
            AppServerActivePermissionProfile(id: ":workspace")
        )

        let explicitEmptyModifications = try JSONDecoder().decode(
            AppServerActivePermissionProfile.self,
            from: Data(#"{"id":":workspace","modifications":[]}"#.utf8)
        )
        XCTAssertEqual(
            explicitEmptyModifications,
            AppServerActivePermissionProfile(id: ":workspace")
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerActivePermissionProfile.self,
                from: Data(#"{"id":":workspace","modifications":null}"#.utf8)
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

        let strictAutoReview = try JSONDecoder().decode(
            AppServerProtocol.PermissionsRequestApprovalResponse.self,
            from: Data(#"{"permissions":{},"strictAutoReview":true}"#.utf8)
        )
        XCTAssertEqual(strictAutoReview.scope, .turn)
        XCTAssertEqual(strictAutoReview.strictAutoReview, true)
    }

    func testPermissionsRequestApprovalRejectsMacOSPermissionFieldLikeRust() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerProtocol.PermissionsRequestApprovalParams.self,
                from: Data(
                    #"""
                    {
                      "threadId": "thr_123",
                      "turnId": "turn_123",
                      "itemId": "call_123",
                      "startedAtMs": 1,
                      "cwd": "/repo",
                      "reason": "Select a workspace root",
                      "permissions": {
                        "network": null,
                        "fileSystem": null,
                        "macos": {
                          "preferences": "read_only",
                          "automations": "none",
                          "launchServices": false,
                          "accessibility": false,
                          "calendar": false,
                          "reminders": false,
                          "contacts": "none"
                        }
                      }
                    }
                    """#.utf8
                )
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("unknown field `macos`"),
                "expected Rust-shaped unknown macos field error, got \(error)"
            )
        }
    }

    func testRequestPermissionProfileRejectsUnknownFieldsLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            RequestPermissionProfile.self,
            from: Data(#"{"network":{"enabled":true},"extra":true}"#.utf8)
        )) { error in
            XCTAssertTrue(String(describing: error).contains("unknown field `extra`"))
        }
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
