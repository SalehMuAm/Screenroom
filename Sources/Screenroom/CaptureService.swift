import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import UniformTypeIdentifiers
import ImageIO

enum CaptureState: Equatable {
    case idle, choosing, starting, recording, stopping
}

private enum CaptureError: LocalizedError {
    case busy, noDisplay, invalidSelection, cannotSaveImage, fileExists, recordingTimedOut

    var errorDescription: String? {
        switch self {
        case .busy: return "Finish the current capture before starting another."
        case .noDisplay: return "That display is no longer available. Choose another display."
        case .invalidSelection: return "Select a larger area to capture."
        case .cannotSaveImage: return "The screenshot could not be saved."
        case .fileExists: return "A recording already exists at this destination. Choose a different filename."
        case .recordingTimedOut: return "macOS did not finish the recording in time. Any incomplete file has been kept in your capture folder."
        }
    }
}

/// Uses Apple's capture and hardware-backed file recording pipeline without copying frames into app memory.
@MainActor
final class CaptureService: NSObject, ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var startedAt: Date?
    @Published var errorMessage: String?
    var onRecordingFinished: ((URL) -> Void)?
    var isBusy: Bool { state != .idle }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var recordingURL: URL?
    private var captureStarted = false
    private var stopRequested = false
    private var stopIssued = false
    private var operationID = UUID()
    private var captureTask: Task<Void, Never>?
    private var transitionTimeout: Task<Void, Never>?
    private var pickerContinuation: CheckedContinuation<SCContentFilter?, Error>?
    private var regionSelector: RegionSelector?
    private var pickerObserver: CapturePickerObserver?

    private struct Selection {
        let filter: SCContentFilter
        var sourceRect: CGRect?
        var size: CGSize { sourceRect?.size ?? filter.contentRect.size }
    }

    func takeScreenshot(source: CaptureSource) async throws -> URL? {
        guard !isBusy else { throw CaptureError.busy }
        let token = beginOperation()
        defer {
            if operationID == token { reset() }
        }
        guard let selection = try await selectContent(source: source, token: token) else { return nil }
        try Task.checkCancellation()
        guard operationID == token else { return nil }
        state = .starting
        let config = configuration(for: selection, recording: false)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: selection.filter, configuration: config)
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Screenroom-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.cannotSaveImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.cannotSaveImage }
        return url
    }

    func startRecording(source: CaptureSource, capturesSystemAudio: Bool, framesPerSecond: Int, destination: URL) {
        guard !isBusy else { return }
        let token = beginOperation()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let selection = try await selectContent(source: source, token: token) else {
                    if operationID == token { reset() }
                    return
                }
                try Task.checkCancellation()
                guard operationID == token else { return }
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CaptureError.fileExists }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                state = .starting
                let config = configuration(for: selection, recording: true)
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(min(60, max(15, framesPerSecond))))
                config.capturesAudio = capturesSystemAudio
                config.excludesCurrentProcessAudio = true
                config.captureMicrophone = false
                config.sampleRate = 48_000
                config.channelCount = 2
                let outputConfig = SCRecordingOutputConfiguration()
                outputConfig.outputURL = destination
                outputConfig.videoCodecType = .h264
                outputConfig.outputFileType = .mp4
                let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
                let newStream = SCStream(filter: selection.filter, configuration: config, delegate: self)
                recordingURL = destination
                recordingOutput = output
                stream = newStream
                try newStream.addRecordingOutput(output)
                armTransitionTimeout(for: token)
                try await newStream.startCapture()
                guard operationID == token else { try? await newStream.stopCapture(); return }
                captureStarted = true
                if stopRequested { stopActiveStream() }
            } catch is CancellationError {
                if operationID == token, stream == nil { reset() }
            } catch {
                guard operationID == token else { return }
                errorMessage = friendlyMessage(error)
                let failedStream = stream
                // Delegate callbacks can run while stopCapture suspends. Retire this operation
                // first so a late cleanup can never reset a subsequent capture.
                reset()
                if let failedStream { try? await failedStream.stopCapture() }
            }
        }
    }

    func stopRecording() {
        if state == .choosing { cancelSelection(); return }
        guard state == .recording || state == .starting, stream != nil else { return }
        stopRequested = true
        state = .stopping
        armTransitionTimeout(for: operationID)
        // Starting and stopping the same SCStream concurrently can leave a capture running.
        if captureStarted { stopActiveStream() }
    }

    private func stopActiveStream() {
        guard !stopIssued, let currentStream = stream else { return }
        stopIssued = true
        let token = operationID
        Task { [weak self] in
            do {
                try await currentStream.stopCapture()
                // The file is still being finalized. Only the recording delegate may publish it.
            } catch {
                guard let self, operationID == token else { return }
                errorMessage = friendlyMessage(error)
                if let recordingOutput { try? currentStream.removeRecordingOutput(recordingOutput) }
                // Keep the finalization timeout active in case the delegate cannot complete.
            }
        }
    }

    func cancelSelection() {
        guard state == .choosing else { return }
        captureTask?.cancel()
        regionSelector?.cancel()
        finishPicker(with: .success(nil))
        reset()
    }

    private func beginOperation() -> UUID {
        operationID = UUID()
        errorMessage = nil
        state = .choosing
        return operationID
    }

    private func selectContent(source: CaptureSource, token: UUID) async throws -> Selection? {
        if source == .region {
            // Enumerating displays also asks macOS for Screen Recording access when needed.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard state == .choosing, operationID == token else { return nil }
            let selector = RegionSelector()
            regionSelector = selector
            let region = await selector.select()
            if regionSelector === selector { regionSelector = nil }
            guard let region else { return nil }
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
                throw CaptureError.noDisplay
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let rect = CaptureGeometry.sourceRect(selection: region.rect, displayHeight: region.displayHeight)
            guard rect.width >= 4, rect.height >= 4 else { throw CaptureError.invalidSelection }
            return Selection(filter: filter, sourceRect: rect)
        }
        guard let filter = try await chooseUsingSystemPicker(source: source, token: token) else { return nil }
        return Selection(filter: filter)
    }

    private func chooseUsingSystemPicker(source: CaptureSource, token: UUID) async throws -> SCContentFilter? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled, operationID == token else { continuation.resume(returning: nil); return }
                pickerContinuation = continuation
                let picker = SCContentSharingPicker.shared
                var config = SCContentSharingPickerConfiguration()
                config.allowedPickerModes = source == .window ? [.singleWindow] : [.singleDisplay]
                config.allowsChangingSelectedContent = false
                if let bundleID = Bundle.main.bundleIdentifier { config.excludedBundleIDs = [bundleID] }
                picker.defaultConfiguration = config
                picker.maximumStreamCount = 1
                let observer = CapturePickerObserver { [weak self] result in
                    guard let self, operationID == token else { return }
                    finishPicker(with: result)
                }
                pickerObserver = observer
                picker.add(observer)
                picker.isActive = true
                picker.present(using: source == .window ? .window : .display)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, operationID == token else { return }
                finishPicker(with: .success(nil))
            }
        }
    }

    private func configuration(for selection: Selection, recording: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = CGFloat(selection.filter.pointPixelScale)
        let dimensions = recording
            ? CaptureGeometry.recordingSize(points: selection.size, scale: scale)
            : CGSize(width: max(1, selection.size.width * scale), height: max(1, selection.size.height * scale))
        config.width = Int(dimensions.width)
        config.height = Int(dimensions.height)
        config.queueDepth = 3
        config.captureDynamicRange = .SDR
        config.captureResolution = .best
        config.preservesAspectRatio = true
        config.showsCursor = true
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = true
        config.capturesAudio = false
        config.captureMicrophone = false
        config.excludesCurrentProcessAudio = true
        if let rect = selection.sourceRect { config.sourceRect = rect }
        return config
    }

    private func finishPicker(with result: Result<SCContentFilter?, Error>) {
        let continuation = pickerContinuation
        pickerContinuation = nil
        continuation?.resume(with: result)
    }

    private func armTransitionTimeout(for token: UUID) {
        transitionTimeout?.cancel()
        transitionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, operationID == token, state == .starting || state == .stopping else { return }
            errorMessage = CaptureError.recordingTimedOut.localizedDescription
            let oldStream = stream
            reset()
            if let oldStream { try? await oldStream.stopCapture() }
        }
    }

    private func reset() {
        transitionTimeout?.cancel()
        transitionTimeout = nil
        captureTask = nil
        stream = nil
        recordingOutput = nil
        recordingURL = nil
        captureStarted = false
        stopRequested = false
        stopIssued = false
        startedAt = nil
        operationID = UUID()
        if let pickerObserver {
            SCContentSharingPicker.shared.isActive = false
            SCContentSharingPicker.shared.remove(pickerObserver)
            self.pickerObserver = nil
        }
        state = .idle
    }

    func friendlyMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return "Allow Screenroom in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. macOS may ask you to reopen the app."
        }
        return error.localizedDescription
    }
}

private final class CapturePickerObserver: NSObject, SCContentSharingPickerObserver {
    let completion: @MainActor (Result<SCContentFilter?, Error>) -> Void

    init(completion: @escaping @MainActor (Result<SCContentFilter?, Error>) -> Void) {
        self.completion = completion
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in completion(.success(nil)) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in completion(.success(filter)) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in completion(.failure(error)) }
    }
}

extension CaptureService: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, recordingOutput === output, state == .starting else { return }
            transitionTimeout?.cancel()
            transitionTimeout = nil
            startedAt = Date()
            state = .recording
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, recordingOutput === output, let url = recordingURL else { return }
            let oldStream = stream
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            reset()
            if size > 0 { onRecordingFinished?(url) }
            else { errorMessage = "The recording ended before a video could be saved. Try recording for a little longer." }
            // A system stop can finish the file before the stream's stop callback arrives.
            if let oldStream { try? await oldStream.stopCapture() }
        }
    }

    nonisolated func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, recordingOutput === output else { return }
            errorMessage = friendlyMessage(error)
            let oldStream = stream
            reset()
            if let oldStream { try? await oldStream.stopCapture() }
        }
    }
}

extension CaptureService: SCStreamDelegate {
    nonisolated func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, stream === stoppedStream else { return }
            let nsError = error as NSError
            if !(nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userStopped.rawValue) {
                errorMessage = "Recording stopped: \(friendlyMessage(error))"
            }
            state = .stopping
            // Keep output alive until the system has finalized it, including Control Center stops.
            armTransitionTimeout(for: operationID)
        }
    }
}

private struct SelectedRegion {
    let displayID: CGDirectDisplayID
    let displayHeight: CGFloat
    let rect: CGRect
}

@MainActor
private final class RegionSelector {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<SelectedRegion?, Never>?
    private var keyMonitor: Any?

    func select() async -> SelectedRegion? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                NSApp.activate(ignoringOtherApps: true)
                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                    let window = RegionOverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                    window.backgroundColor = .clear
                    window.isOpaque = false
                    window.hasShadow = false
                    window.level = .screenSaver
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    window.isReleasedWhenClosed = false
                    let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                    view.onSelection = { [weak self] rect in
                        self?.finish(SelectedRegion(displayID: number.uint32Value, displayHeight: screen.frame.height, rect: rect))
                    }
                    view.onCancel = { [weak self] in self?.cancel() }
                    window.contentView = view
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(view)
                    windows.append(window)
                }
                guard !windows.isEmpty else { finish(nil); return }
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if event.keyCode == 53 { self?.cancel(); return nil }
                    return event
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() { finish(nil) }

    private func finish(_ region: SelectedRegion?) {
        guard let continuation else { return }
        self.continuation = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        continuation.resume(returning: region)
    }
}

private final class RegionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RegionSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var anchor: NSPoint?
    private var selectedRect: NSRect?
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selectedRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectedRect = NSRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                              width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selectedRect, selectedRect.width >= 4, selectedRect.height >= 4 else {
            anchor = nil
            self.selectedRect = nil
            needsDisplay = true
            return
        }
        onSelection?(selectedRect.integral)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let selectedRect { shade.append(NSBezierPath(rect: selectedRect)); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.38).setFill()
        shade.fill()
        if let selectedRect {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selectedRect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
        let message = selectedRect.map { "\(Int($0.width)) × \(Int($0.height))  ·  Release to capture" }
            ?? "Drag to select an area  ·  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = (message as NSString).size(withAttributes: attributes)
        let labelRect = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - 90, width: size.width, height: size.height)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect.insetBy(dx: -18, dy: -12), xRadius: 12, yRadius: 12).fill()
        (message as NSString).draw(in: labelRect, withAttributes: attributes)
    }
}
