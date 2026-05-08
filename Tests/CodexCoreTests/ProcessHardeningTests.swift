import CodexCore
import XCTest

final class ProcessHardeningTests: XCTestCase {
    func testEnvironmentKeysWithPrefixPreservesNonUTF8MatchingKeys() {
        let nonUTF8Key = Array("R".utf8) + [0xD6] + Array("DBURK".utf8)
        let matchingNonUTF8Key = Array("LD_".utf8) + [0xF0]
        let nonUTF8Value: [UInt8] = [0xF0, 0x9F, 0x92, 0xA9]

        XCTAssertEqual(
            ProcessHardening.environmentKeysWithPrefix(
                [
                    (key: nonUTF8Key, value: nonUTF8Value),
                    (key: matchingNonUTF8Key, value: nonUTF8Value)
                ],
                prefix: Array("LD_".utf8)
            ),
            [matchingNonUTF8Key]
        )
    }

    func testEnvironmentKeysWithPrefixFiltersOnlyMatchingKeys() {
        XCTAssertEqual(
            ProcessHardening.environmentKeysWithPrefix(
                [
                    (key: Array("PATH".utf8), value: Array("/usr/bin".utf8)),
                    (key: Array("LD_TEST".utf8), value: Array("1".utf8)),
                    (key: Array("DYLD_FOO".utf8), value: Array("bar".utf8))
                ],
                prefix: Array("LD_".utf8)
            ),
            [Array("LD_TEST".utf8)]
        )
    }

    func testMacOSHardeningRunsDenyAttachCoreLimitThenDYLDRemoval() {
        let recorder = ProcessHardeningRecorder(
            environmentKeys: [
                Array("DYLD_INSERT_LIBRARIES".utf8),
                Array("DYLD_PRINT_LIBRARIES".utf8)
            ]
        )

        XCTAssertNil(ProcessHardening.runMacOSHardening(actions: recorder.actions()))
        XCTAssertEqual(recorder.calls, [
            "ptrace",
            "setrlimit",
            "remove:DYLD_INSERT_LIBRARIES",
            "remove:DYLD_PRINT_LIBRARIES"
        ])
    }

    func testMacOSHardeningStopsWhenDenyAttachFails() {
        let recorder = ProcessHardeningRecorder(
            denyResult: -1,
            errorDescription: "operation not permitted"
        )

        XCTAssertEqual(
            ProcessHardening.runMacOSHardening(actions: recorder.actions()),
            .ptraceDenyAttach(message: "operation not permitted")
        )
        XCTAssertEqual(recorder.calls, ["ptrace", "lastError"])
    }

    func testMacOSHardeningStopsWhenCoreLimitFails() {
        let recorder = ProcessHardeningRecorder(
            setLimitResult: -1,
            errorDescription: "bad file descriptor"
        )

        XCTAssertEqual(
            ProcessHardening.runMacOSHardening(actions: recorder.actions()),
            .setRLimitCore(message: "bad file descriptor")
        )
        XCTAssertEqual(recorder.calls, ["ptrace", "setrlimit", "lastError"])
    }
}

private final class ProcessHardeningRecorder {
    private let denyResult: Int32
    private let setLimitResult: Int32
    private let environmentKeys: [[UInt8]]
    private let errorDescription: String

    private(set) var calls: [String] = []

    init(
        denyResult: Int32 = 0,
        setLimitResult: Int32 = 0,
        environmentKeys: [[UInt8]] = [],
        errorDescription: String = "boom"
    ) {
        self.denyResult = denyResult
        self.setLimitResult = setLimitResult
        self.environmentKeys = environmentKeys
        self.errorDescription = errorDescription
    }

    func actions() -> ProcessHardening.MacOSActions {
        ProcessHardening.MacOSActions(
            denyDebuggerAttach: {
                self.calls.append("ptrace")
                return self.denyResult
            },
            setCoreFileSizeLimitToZero: {
                self.calls.append("setrlimit")
                return self.setLimitResult
            },
            environmentKeysWithPrefix: { prefix in
                ProcessHardening.environmentKeysWithPrefix(
                    self.environmentKeys.map { (key: $0, value: []) },
                    prefix: prefix
                )
            },
            removeEnvironmentVariable: { key in
                self.calls.append("remove:\(String(decoding: key, as: UTF8.self))")
            },
            lastErrorDescription: {
                self.calls.append("lastError")
                return self.errorDescription
            }
        )
    }
}
