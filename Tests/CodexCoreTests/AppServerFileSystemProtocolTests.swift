import CodexCore
import XCTest

final class AppServerFileSystemProtocolTests: XCTestCase {
    func testFileReadWriteAndMetadataPayloadsEncodeRustWireShapes() throws {
        let file = try AbsolutePath(absolutePath: "/tmp/codex-fs/file.txt")

        try XCTAssertJSONObjectEqual(FsReadFileParams(path: file), ["path": "/tmp/codex-fs/file.txt"])
        try XCTAssertJSONObjectEqual(FsReadFileResponse(dataBase64: "aGVsbG8="), ["dataBase64": "aGVsbG8="])
        try XCTAssertJSONObjectEqual(
            FsWriteFileParams(path: file, dataBase64: "aGVsbG8="),
            [
                "path": "/tmp/codex-fs/file.txt",
                "dataBase64": "aGVsbG8="
            ]
        )
        try XCTAssertJSONObjectEqual(FsWriteFileResponse(), [:])
        try XCTAssertJSONObjectEqual(FsGetMetadataParams(path: file), ["path": "/tmp/codex-fs/file.txt"])
        try XCTAssertJSONObjectEqual(
            FsGetMetadataResponse(
                isDirectory: false,
                isFile: true,
                isSymlink: false,
                createdAtMs: 1_700_000_000_001,
                modifiedAtMs: 1_700_000_000_002
            ),
            [
                "isDirectory": false,
                "isFile": true,
                "isSymlink": false,
                "createdAtMs": 1_700_000_000_001,
                "modifiedAtMs": 1_700_000_000_002
            ]
        )
    }

    func testFileReadWriteAndMetadataPayloadsRoundTripLikeRustProtocol() throws {
        let readParams = try JSONDecoder().decode(
            FsReadFileParams.self,
            from: Data(#"{"path":"/tmp/codex-fs/file.txt"}"#.utf8)
        )
        XCTAssertEqual(readParams.path.path, "/tmp/codex-fs/file.txt")
        try XCTAssertJSONObjectEqual(readParams, ["path": "/tmp/codex-fs/file.txt"])

        let readResponse = try JSONDecoder().decode(
            FsReadFileResponse.self,
            from: Data(#"{"dataBase64":"aGVsbG8="}"#.utf8)
        )
        XCTAssertEqual(readResponse, FsReadFileResponse(dataBase64: "aGVsbG8="))
        try XCTAssertJSONObjectEqual(readResponse, ["dataBase64": "aGVsbG8="])

        let writeParams = try JSONDecoder().decode(
            FsWriteFileParams.self,
            from: Data(#"{"path":"/tmp/codex-fs/file.bin","dataBase64":"AAE="}"#.utf8)
        )
        XCTAssertEqual(writeParams, FsWriteFileParams(
            path: try AbsolutePath(absolutePath: "/tmp/codex-fs/file.bin"),
            dataBase64: "AAE="
        ))
        try XCTAssertJSONObjectEqual(writeParams, [
            "path": "/tmp/codex-fs/file.bin",
            "dataBase64": "AAE="
        ])

        let metadata = try JSONDecoder().decode(
            FsGetMetadataResponse.self,
            from: Data(
                #"{"isDirectory":false,"isFile":true,"isSymlink":false,"createdAtMs":123,"modifiedAtMs":456}"#.utf8
            )
        )
        XCTAssertEqual(metadata, FsGetMetadataResponse(
            isDirectory: false,
            isFile: true,
            isSymlink: false,
            createdAtMs: 123,
            modifiedAtMs: 456
        ))
        try XCTAssertJSONObjectEqual(metadata, [
            "isDirectory": false,
            "isFile": true,
            "isSymlink": false,
            "createdAtMs": 123,
            "modifiedAtMs": 456
        ])
    }

    func testCreateRemoveAndCopyPayloadsPreserveRustOptionalRules() throws {
        let source = try AbsolutePath(absolutePath: "/tmp/codex-fs/source")
        let destination = try AbsolutePath(absolutePath: "/tmp/codex-fs/destination")

        try XCTAssertJSONObjectEqual(
            FsCreateDirectoryParams(path: source),
            [
                "path": "/tmp/codex-fs/source",
                "recursive": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            FsCreateDirectoryParams(path: source, recursive: false),
            [
                "path": "/tmp/codex-fs/source",
                "recursive": false
            ]
        )
        try XCTAssertJSONObjectEqual(FsCreateDirectoryResponse(), [:])

        try XCTAssertJSONObjectEqual(
            FsRemoveParams(path: source),
            [
                "path": "/tmp/codex-fs/source",
                "recursive": NSNull(),
                "force": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            FsRemoveParams(path: source, recursive: false, force: true),
            [
                "path": "/tmp/codex-fs/source",
                "recursive": false,
                "force": true
            ]
        )
        try XCTAssertJSONObjectEqual(FsRemoveResponse(), [:])

        try XCTAssertJSONObjectEqual(
            FsCopyParams(sourcePath: source, destinationPath: destination),
            [
                "sourcePath": "/tmp/codex-fs/source",
                "destinationPath": "/tmp/codex-fs/destination"
            ]
        )
        try XCTAssertJSONObjectEqual(
            FsCopyParams(sourcePath: source, destinationPath: destination, recursive: true),
            [
                "sourcePath": "/tmp/codex-fs/source",
                "destinationPath": "/tmp/codex-fs/destination",
                "recursive": true
            ]
        )
        try XCTAssertJSONObjectEqual(FsCopyResponse(), [:])
    }

    func testDirectoryAndWatchPayloadsEncodeRustWireShapes() throws {
        let directory = try AbsolutePath(absolutePath: "/tmp/codex-fs")
        let changed = try AbsolutePath(absolutePath: "/tmp/codex-fs/file.txt")

        try XCTAssertJSONObjectEqual(FsReadDirectoryParams(path: directory), ["path": "/tmp/codex-fs"])
        try XCTAssertJSONObjectEqual(
            FsReadDirectoryResponse(entries: [
                FsReadDirectoryEntry(fileName: "file.txt", isDirectory: false, isFile: true),
                FsReadDirectoryEntry(fileName: "nested", isDirectory: true, isFile: false)
            ]),
            [
                "entries": [
                    [
                        "fileName": "file.txt",
                        "isDirectory": false,
                        "isFile": true
                    ],
                    [
                        "fileName": "nested",
                        "isDirectory": true,
                        "isFile": false
                    ]
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            FsWatchParams(watchID: "watch-1", path: directory),
            [
                "watchId": "watch-1",
                "path": "/tmp/codex-fs"
            ]
        )
        try XCTAssertJSONObjectEqual(FsWatchResponse(path: directory), ["path": "/tmp/codex-fs"])
        try XCTAssertJSONObjectEqual(FsUnwatchParams(watchID: "watch-1"), ["watchId": "watch-1"])
        try XCTAssertJSONObjectEqual(FsUnwatchResponse(), [:])
        try XCTAssertJSONObjectEqual(
            FsChangedNotification(watchID: "watch-1", changedPaths: [changed]),
            [
                "watchId": "watch-1",
                "changedPaths": ["/tmp/codex-fs/file.txt"]
            ]
        )
    }

    func testFileSystemParamsDecodeRustDefaultsAndNulls() throws {
        let create = try JSONDecoder().decode(
            FsCreateDirectoryParams.self,
            from: Data(#"{"path":"/tmp/codex-fs","recursive":null}"#.utf8)
        )
        XCTAssertEqual(create.path.path, "/tmp/codex-fs")
        XCTAssertNil(create.recursive)

        let remove = try JSONDecoder().decode(
            FsRemoveParams.self,
            from: Data(#"{"path":"/tmp/codex-fs","recursive":null,"force":null}"#.utf8)
        )
        XCTAssertEqual(remove.path.path, "/tmp/codex-fs")
        XCTAssertNil(remove.recursive)
        XCTAssertNil(remove.force)

        let copy = try JSONDecoder().decode(
            FsCopyParams.self,
            from: Data(#"{"sourcePath":"/tmp/codex-fs/source","destinationPath":"/tmp/codex-fs/destination"}"#.utf8)
        )
        XCTAssertEqual(copy.sourcePath.path, "/tmp/codex-fs/source")
        XCTAssertEqual(copy.destinationPath.path, "/tmp/codex-fs/destination")
        XCTAssertFalse(copy.recursive)
    }

    func testFsCopyRejectsExplicitNullForRustDefaultedRecursiveFlag() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                FsCopyParams.self,
                from: Data(
                    #"{"sourcePath":"/tmp/codex-fs/source","destinationPath":"/tmp/codex-fs/destination","recursive":null}"#.utf8
                )
            )
        )
    }
}
