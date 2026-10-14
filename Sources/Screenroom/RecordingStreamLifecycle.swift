/// Coordinates startup and shutdown for one stream, including callbacks that arrive
/// after CaptureService has already moved on to another recording.
@MainActor
final class RecordingStreamLifecycle {
    private enum Phase { case starting, capturing, stopping, stopped }
    private var phase: Phase = .starting
    private(set) var stopRequested = false

    func requestStop() {
        stopRequested = true
    }

    func didStart() {
        // A system stop may arrive before startCapture's completion resumes.
        if phase == .starting { phase = .capturing }
    }

    /// Returns true exactly once, and only after startup has completed.
    func beginStop() -> Bool {
        guard phase == .capturing else { return false }
        phase = .stopping
        return true
    }

    func didStop() {
        phase = .stopped
    }
}
