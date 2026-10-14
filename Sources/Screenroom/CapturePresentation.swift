import AppKit

/// Keeps capture on the user's working desktop, even when started from our window.
@MainActor
final class CapturePresentation {
    private var previousApplication: NSRunningApplication?
    private let notificationCenter = NSWorkspace.shared.notificationCenter
    private var observers: [NSObjectProtocol] = []

    init() {
        remember(NSWorkspace.shared.frontmostApplication)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                }
            })
        }
    }

    func prepareForCapture(hiding window: NSWindow?) async throws {
        try Task.checkCancellation()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownsFocus = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || (frontmost == nil && NSRunningApplication.current.isActive)
        remember(frontmost)

        if ownsFocus {
            guard let target = previousApplication, isRestorable(target) else {
                throw PresentationError.noPreviousApplication
            }
            // Yield while our window still owns focus. Ordering the last window
            // out first can give focus to a different app and invalidate the handoff.
            NSApplication.shared.yieldActivation(to: target)
            _ = target.activate(from: .current, options: [])
            window?.orderOut(nil)
            // The request result is not the resulting focus state; the target
            // may also become active naturally as our window leaves the screen.
            let deadline = ContinuousClock.now + .seconds(1)
            while !target.isActive {
                try Task.checkCancellation()
                guard isRestorable(target), ContinuousClock.now < deadline else {
                    throw PresentationError.activationFailed(target.localizedName)
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            // App activation can precede the animation back to its full-screen Space.
            try await Task.sleep(for: .milliseconds(500))
            guard isRestorable(target), target.isActive else {
                throw PresentationError.activationFailed(target.localizedName)
            }
        } else {
            // A shortcut or menu-bar capture must leave the current app in place.
            window?.orderOut(nil)
            try await Task.sleep(for: .milliseconds(200))
        }
        try Task.checkCancellation()
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              !application.isTerminated else { return }
        previousApplication = application
    }

    private func isRestorable(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && application.activationPolicy == .regular
            && !application.isTerminated && !application.isHidden
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    private enum PresentationError: LocalizedError {
        case noPreviousApplication
        case activationFailed(String?)

        var errorDescription: String? {
            switch self {
            case .noPreviousApplication:
                return "Switch to the app you want to capture, then press ⇧⌘6 for a screenshot or ⇧⌘7 to record."
            case .activationFailed(let name):
                return "Could not return to \(name ?? "the app you were using"). Switch to it, then press ⇧⌘6 for a screenshot or ⇧⌘7 to record."
            }
        }
    }
}
