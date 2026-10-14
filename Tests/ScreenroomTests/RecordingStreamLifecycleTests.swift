import XCTest
@testable import Screenroom

final class RecordingStreamLifecycleTests: XCTestCase {
    @MainActor
    func testFinishingRecordingCannotStopStreamTwice() {
        let lifecycle = RecordingStreamLifecycle()
        lifecycle.didStart()
        lifecycle.requestStop()

        XCTAssertTrue(lifecycle.beginStop())
        // The file-finished delegate can arrive while stopCapture is still awaiting.
        XCTAssertFalse(lifecycle.beginStop())
        lifecycle.didStop()
        XCTAssertFalse(lifecycle.beginStop())
    }

    @MainActor
    func testStopRequestedDuringStartupWaitsForStartCompletion() {
        let lifecycle = RecordingStreamLifecycle()
        lifecycle.requestStop()

        XCTAssertFalse(lifecycle.beginStop())
        lifecycle.didStart()

        XCTAssertTrue(lifecycle.stopRequested)
        XCTAssertTrue(lifecycle.beginStop())
        XCTAssertFalse(lifecycle.beginStop())
    }

    @MainActor
    func testSystemStopDoesNotIssueAnotherStop() {
        let lifecycle = RecordingStreamLifecycle()
        lifecycle.didStart()
        lifecycle.didStop()

        XCTAssertFalse(lifecycle.beginStop())
    }

    @MainActor
    func testLateStartupCompletionCannotReviveAStoppedStream() {
        let lifecycle = RecordingStreamLifecycle()
        lifecycle.didStop()
        lifecycle.didStart()

        XCTAssertFalse(lifecycle.beginStop())
    }

    @MainActor
    func testCleanupOfPreviousRecordingCannotStopNewRecording() {
        let previous = RecordingStreamLifecycle()
        previous.didStart()
        XCTAssertTrue(previous.beginStop())
        let current = RecordingStreamLifecycle()
        current.didStart()

        previous.didStop()

        XCTAssertFalse(previous.beginStop())
        XCTAssertTrue(current.beginStop())
    }
}
