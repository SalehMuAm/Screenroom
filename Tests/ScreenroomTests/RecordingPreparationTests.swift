import Combine
import XCTest
@testable import Screenroom

final class RecordingPreparationTests: XCTestCase {
    private struct PreparationError: LocalizedError {
        var errorDescription: String? { "Could not restore the captured app." }
    }

    @MainActor
    func testPreparationFailureReturnsToIdleWithoutStartingCapture() async {
        let service = CaptureService()
        let idle = expectation(description: "Preparation failure finishes the operation")
        let subscription = service.$state.dropFirst().sink {
            if $0 == .idle { idle.fulfill() }
        }
        defer { subscription.cancel() }

        service.startRecording(source: .display, capturesSystemAudio: false, framesPerSecond: 30,
                               destination: unusedDestination()) {
            throw PreparationError()
        }
        XCTAssertEqual(service.state, .choosing)

        await fulfillment(of: [idle], timeout: 2)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, PreparationError().localizedDescription)
        XCTAssertNil(service.startedAt)
        XCTAssertFalse(service.needsPermissionHelp)
    }

    @MainActor
    func testCancelledPreparationCannotResetReplacementRecording() async {
        let service = CaptureService()
        let firstStarted = expectation(description: "First preparation is waiting")
        let firstFinished = expectation(description: "Cancelled preparation resumes late")
        var firstContinuation: CheckedContinuation<Void, Never>?
        service.startRecording(source: .display, capturesSystemAudio: false, framesPerSecond: 30,
                               destination: unusedDestination()) {
            await withCheckedContinuation {
                firstContinuation = $0
                firstStarted.fulfill()
            }
            firstFinished.fulfill()
        }
        // The operation must be busy before the asynchronous handoff begins.
        XCTAssertTrue(service.isBusy)
        service.startRecording(source: .display, capturesSystemAudio: false, framesPerSecond: 30,
                               destination: unusedDestination()) {
            XCTFail("A repeated start must not create a second capture")
            throw PreparationError()
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        service.stopRecording()
        XCTAssertEqual(service.state, .idle)

        let replacementStarted = expectation(description: "Replacement is preparing")
        let replacementFinished = expectation(description: "Replacement is cancelled")
        var replacementContinuation: CheckedContinuation<Void, Never>?
        service.startRecording(source: .display, capturesSystemAudio: false, framesPerSecond: 30,
                               destination: unusedDestination()) {
            await withCheckedContinuation {
                replacementContinuation = $0
                replacementStarted.fulfill()
            }
            replacementFinished.fulfill()
        }
        await fulfillment(of: [replacementStarted], timeout: 2)
        firstContinuation?.resume()
        await fulfillment(of: [firstFinished], timeout: 2)
        XCTAssertEqual(service.state, .choosing)
        XCTAssertNil(service.errorMessage)

        service.cancelSelection()
        replacementContinuation?.resume()
        await fulfillment(of: [replacementFinished], timeout: 2)
        XCTAssertEqual(service.state, .idle)
    }

    private func unusedDestination() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Screenroom-test-\(UUID()).mp4")
    }
}
