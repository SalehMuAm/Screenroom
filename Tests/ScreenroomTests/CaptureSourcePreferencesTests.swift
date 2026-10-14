import XCTest
@testable import Screenroom

final class CaptureSourcePreferencesTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let name = "ScreenroomTests.Sources.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(defaults)
    }

    func testFirstRecordingUsesEntireDisplayAndScreenshotUsesArea() {
        withDefaults { defaults in
            let preferences = CaptureSourcePreferences(defaults: defaults)
            XCTAssertEqual(preferences.source(for: .recording), .display)
            XCTAssertEqual(preferences.source(for: .screenshot), .region)
        }
    }

    func testExplicitRecordingChoiceSurvivesRelaunchAndScreenshotChanges() {
        withDefaults { defaults in
            var preferences = CaptureSourcePreferences(defaults: defaults)
            preferences.select(.region, for: .recording)
            preferences.select(.window, for: .screenshot)

            let restored = CaptureSourcePreferences(defaults: defaults)
            XCTAssertEqual(restored.recording, .region)
            XCTAssertEqual(restored.screenshot, .window)
        }
    }

    func testScreenshotChoiceCannotCropDefaultRecording() {
        withDefaults { defaults in
            var preferences = CaptureSourcePreferences(defaults: defaults)
            preferences.select(.region, for: .screenshot)
            XCTAssertEqual(preferences.source(for: .recording), .display)
        }
    }

    func testInvalidStoredSourceFallsBackToFullDisplay() {
        withDefaults { defaults in
            defaults.set("removed-source", forKey: "recordingSource")
            XCTAssertEqual(CaptureSourcePreferences(defaults: defaults).recording, .display)
        }
    }
}
