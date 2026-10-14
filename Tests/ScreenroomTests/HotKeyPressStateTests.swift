import Carbon
import XCTest
@testable import Screenroom

final class HotKeyPressStateTests: XCTestCase {
    func testHoldingRecordingShortcutOnlyActivatesOnce() {
        var state = HotKeyPressState()
        var recording = false
        var activations = 0

        for _ in 0..<30 {
            if state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)) {
                recording.toggle()
                activations += 1
            }
        }

        XCTAssertTrue(recording, "Key repeat must not stop the recording it just started.")
        XCTAssertEqual(activations, 1)
        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyReleased)))
        if state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)) {
            recording.toggle()
            activations += 1
        }
        XCTAssertFalse(recording, "The next deliberate press must stop recording immediately.")
        XCTAssertEqual(activations, 2)
    }

    func testDifferentShortcutsHaveIndependentPressState() {
        var state = HotKeyPressState()

        XCTAssertTrue(state.shouldActivate(keyID: 1, eventKind: UInt32(kEventHotKeyPressed)))
        XCTAssertTrue(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)))
        XCTAssertFalse(state.shouldActivate(keyID: 1, eventKind: UInt32(kEventHotKeyReleased)))
        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)))
        XCTAssertTrue(state.shouldActivate(keyID: 1, eventKind: UInt32(kEventHotKeyPressed)))
    }

    func testUnmatchedAndDuplicateReleasesDoNotActivateShortcut() {
        var state = HotKeyPressState()

        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyReleased)))
        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyReleased)))
        XCTAssertTrue(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)))
        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventRawKeyDown)))
        XCTAssertFalse(state.shouldActivate(keyID: 2, eventKind: UInt32(kEventHotKeyPressed)))
    }
}
