import XCTest
@testable import Screenroom

final class RecordingStorageTests: XCTestCase {
    func testCriticalSpacePreventsRecording() {
        for bytes: Int64 in [0, RecordingStorage.minimumAvailableBytes - 1] {
            let storage = RecordingStorage(availableBytes: bytes)
            XCTAssertThrowsError(try storage.validateForRecording()) { error in
                guard case RecordingStorageError.insufficientSpace(let reportedBytes) = error else {
                    return XCTFail("Expected the actionable storage error")
                }
                XCTAssertEqual(reportedBytes, bytes)
                XCTAssertTrue(error.localizedDescription.contains("free before recording"))
            }
        }
    }

    func testMinimumFreeSpaceAllowsRecordingWithWarning() throws {
        let storage = RecordingStorage(availableBytes: RecordingStorage.minimumAvailableBytes)
        try storage.validateForRecording()
        XCTAssertNotNil(storage.warning)
    }

    func testWarningCoversTheObservedSystemStopCapacity() throws {
        // macOS stopped the reported recording during an urgent purge at this capacity.
        let bytes: Int64 = 4_357_902_336
        let storage = RecordingStorage(availableBytes: bytes)
        try storage.validateForRecording()
        XCTAssertTrue(storage.warning?.contains(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) == true)
        XCTAssertTrue(storage.warning?.contains("may stop recording early") == true)
    }

    func testWarningThresholdAllowsRecordingWithoutWarning() throws {
        let storage = RecordingStorage(availableBytes: RecordingStorage.warningAvailableBytes)
        try storage.validateForRecording()
        XCTAssertNil(storage.warning)
    }

    func testUnknownCapacityDoesNotInventAStorageFailure() throws {
        for bytes: Int64? in [nil, -1] {
            let storage = RecordingStorage(availableBytes: bytes)
            try storage.validateForRecording()
            XCTAssertNil(storage.availableBytes)
            XCTAssertNil(storage.warning)
        }
    }
}
