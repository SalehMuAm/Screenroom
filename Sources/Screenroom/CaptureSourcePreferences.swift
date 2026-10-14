import Foundation

/// Screenshot framing must not change the target used by the recording shortcut.
struct CaptureSourcePreferences {
    private let defaults: UserDefaults
    private(set) var screenshot: CaptureSource
    private(set) var recording: CaptureSource

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        screenshot = defaults.string(forKey: "screenshotSource").flatMap(CaptureSource.init(rawValue:)) ?? .region
        recording = defaults.string(forKey: "recordingSource").flatMap(CaptureSource.init(rawValue:)) ?? .display
    }

    func source(for kind: CaptureKind) -> CaptureSource {
        kind == .recording ? recording : screenshot
    }

    mutating func select(_ source: CaptureSource, for kind: CaptureKind) {
        if kind == .recording { recording = source }
        else { screenshot = source }
        defaults.set(source.rawValue, forKey: kind == .recording ? "recordingSource" : "screenshotSource")
    }
}
