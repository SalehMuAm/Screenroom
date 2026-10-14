import AppKit
import Combine
import SwiftUI

enum WorkspacePage: String { case capture, library }

@MainActor
final class AppModel: ObservableObject {
    let capture = CaptureService()
    let library = CaptureLibrary()
    @Published var page: WorkspacePage = .capture
    @Published var selectedItem: CaptureItem?
    @Published var mode: CaptureKind = .screenshot
    @Published private var sourcePreferences = CaptureSourcePreferences()
    var source: CaptureSource {
        get { sourcePreferences.source(for: mode) }
        set { sourcePreferences.select(newValue, for: mode) }
    }
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var isTakingScreenshot = false
    @Published var showingSettings = false
    @Published var editorIsDirty = false
    @Published private(set) var recordingStorage = RecordingStorage(availableBytes: nil)
    @AppStorage("systemAudio") var systemAudio = false
    @AppStorage("framesPerSecond") var framesPerSecond = 30
    weak var mainWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var hotKeys: HotKeyManager?

    init() {
        refreshRecordingStorage()
        capture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        library.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        capture.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            Task { @MainActor in
                guard let self, !self.capture.isBusy else { return }
                self.errorMessage = message
                if self.selectedItem?.kind == .recording {
                    self.notice = "Recording ended early · video saved"
                }
                self.showMainWindow()
            }
        }.store(in: &subscriptions)
        capture.$state.dropFirst().sink { [weak self] state in
            if state == .idle {
                Task { @MainActor in
                    guard let self, self.capture.state == .idle, !self.isTakingScreenshot else { return }
                    // Errors can arrive while the video is still being finalized.
                    // Surface them once idle instead of silently reporting success.
                    if let message = self.capture.errorMessage { self.errorMessage = message }
                    self.refreshRecordingStorage()
                    self.showMainWindow()
                }
            }
        }.store(in: &subscriptions)
        capture.onRecordingFinished = { [weak self] url in
            guard let self else { return }
            let item = self.library.add(url: url, kind: .recording)
            self.selectedItem = item
            self.page = .library
            self.notice = self.capture.errorMessage == nil ? "Recording saved" : "Recording ended early · video saved"
            self.showMainWindow()
        }
        hotKeys = HotKeyManager(onScreenshot: { [weak self] in
            self?.takeScreenshot()
        }, onRecording: { [weak self] in
            self?.toggleRecording()
        })
    }

    var busy: Bool { isTakingScreenshot || capture.isBusy }
    var isRecording: Bool { capture.state == .recording }
    var shortcutsAvailable: Bool { hotKeys?.allRegistered == true }

    func confirmLeavingEditor() -> Bool {
        guard editorIsDirty else { return true }
        showMainWindow()
        let alert = NSAlert()
        alert.messageText = "Leave your unsaved annotations?"
        alert.informativeText = "Your original screenshot is saved. Export the edited image before leaving to keep your annotations."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Annotations")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func takeScreenshot() {
        guard !busy, mainWindow?.attachedSheet == nil, NSApp.modalWindow == nil, confirmLeavingEditor() else { return }
        let chosenSource = sourcePreferences.screenshot
        guard verifyCaptureAccess(for: chosenSource) else { return }
        mode = .screenshot
        editorIsDirty = false
        selectedItem = nil
        errorMessage = nil
        notice = nil
        isTakingScreenshot = true
        mainWindow?.orderOut(nil)
        Task {
            defer {
                isTakingScreenshot = false
                showMainWindow()
            }
            do {
                try await Task.sleep(for: .milliseconds(200))
                if let url = try await capture.takeScreenshot(source: chosenSource) {
                    let item = try library.storeScreenshot(from: url)
                    try? FileManager.default.removeItem(at: url)
                    selectedItem = item
                    page = .library
                    notice = "Screenshot saved · ready to annotate"
                }
            } catch {
                errorMessage = capture.friendlyMessage(error)
            }
        }
    }

    func startRecording() {
        guard !busy, mainWindow?.attachedSheet == nil, NSApp.modalWindow == nil, confirmLeavingEditor() else { return }
        let chosenSource = sourcePreferences.recording
        guard verifyCaptureAccess(for: chosenSource, directDisplay: chosenSource == .display) else { return }
        mode = .recording
        editorIsDirty = false
        selectedItem = nil
        errorMessage = nil
        notice = nil
        do {
            let destination = try library.newDestination(for: .recording)
            refreshRecordingStorage()
            try recordingStorage.validateForRecording()
            mainWindow?.orderOut(nil)
            capture.startRecording(source: chosenSource, capturesSystemAudio: systemAudio,
                                   framesPerSecond: framesPerSecond, destination: destination)
        } catch {
            errorMessage = error.localizedDescription
            showMainWindow()
        }
    }

    func toggleRecording() {
        guard !isTakingScreenshot else { return }
        switch capture.state {
        case .idle: startRecording()
        case .choosing: capture.cancelSelection()
        case .starting, .recording: capture.stopRecording()
        case .stopping: break
        }
    }

    func refreshRecordingStorage() {
        if let folder = try? library.directory(for: .recording) {
            recordingStorage = RecordingStorage.inspect(folder: folder)
        }
    }

    func openImage() {
        guard !busy, mainWindow?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Open an image to annotate"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmLeavingEditor() else { return }
        editorIsDirty = false
        selectedItem = library.add(url: url, kind: .screenshot)
        page = .library
    }

    private func verifyCaptureAccess(for source: CaptureSource, directDisplay: Bool = false) -> Bool {
        do {
            // Request while the main window is visible; keep the current editor
            // intact if macOS needs the user to grant access or relaunch first.
            try capture.ensurePermission(for: source, directDisplay: directDisplay)
            return true
        } catch {
            errorMessage = capture.friendlyMessage(error)
            showMainWindow()
            return false
        }
    }

    func revealFolder(for kind: CaptureKind) {
        do { NSWorkspace.shared.open(try library.directory(for: kind)) }
        catch { errorMessage = error.localizedDescription }
    }

    func open(_ item: CaptureItem) {
        guard item.exists else {
            errorMessage = "This file was moved or deleted. You can remove its entry from the library."
            return
        }
        selectedItem = item
        page = .library
    }

    func didSaveEdit(_ url: URL) {
        library.add(url: url, kind: .screenshot)
        notice = "Edited screenshot saved"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.capture.state == .choosing {
            model.capture.cancelSelection()
            return .terminateCancel
        }
        guard model.busy else { return model.confirmLeavingEditor() ? .terminateNow : .terminateCancel }
        model.showMainWindow()
        let alert = NSAlert()
        alert.messageText = model.isRecording ? "Finish your recording first" : "A capture is in progress"
        alert.informativeText = model.isRecording
            ? "Stop the recording and let Screenroom save your video before quitting."
            : "Finish or cancel the current capture before quitting Screenroom."
        if model.isRecording { alert.addButton(withTitle: "Stop Recording") }
        alert.addButton(withTitle: "Keep Screenroom Open")
        if alert.runModal() == .alertFirstButtonReturn && model.isRecording {
            model.capture.stopRecording()
        }
        return .terminateCancel
    }
}
