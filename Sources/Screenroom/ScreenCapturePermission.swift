import CoreGraphics
import Foundation

enum ScreenCapturePermissionError: LocalizedError {
    case accessUnavailable

    var errorDescription: String? {
        "This capture needs Screen Recording access. Enable Screenroom in System Settings → Privacy & Security → Screen & System Audio Recording, then quit Screenroom and reopen it from Applications. If it is already enabled, quit and reopen Screenroom before trying again."
    }
}

/// Broad permission is needed for area capture and immediate display recording. The system picker grants
/// its own access to a chosen window or display and must not be gated by this check.
@MainActor
final class ScreenCapturePermission {
    private let preflight: () -> Bool
    private let request: () -> Bool
    private var hasRequested = false

    init(preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.preflight = preflight
        self.request = request
    }

    func ensure(for source: CaptureSource, directDisplay: Bool = false) throws {
        guard source == .region || (source == .display && directDisplay) else { return }
        if preflight() { return }

        // Repeated captures must not repeatedly ask macOS while the user is
        // granting permission in Settings or needs to restart this process.
        if !hasRequested {
            hasRequested = true
            _ = request()
            if preflight() { return }
        }

        throw ScreenCapturePermissionError.accessUnavailable
    }
}
