import SwiftUI

@main
struct ScreenroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Screenroom", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 920, minHeight: 640)
                .background(WindowAccessor { window in
                    model.mainWindow = window
                    delegate.model = model
                    window.title = "Screenroom"
                    window.isReleasedWhenClosed = false
                    window.setFrameAutosaveName("Screenroom.Main")
                })
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Screenshot") { model.takeScreenshot() }
                    .disabled(model.busy)
                Button(model.isRecording ? "Stop Recording" : "New Recording") { model.toggleRecording() }
                    .disabled(model.isTakingScreenshot || model.capture.state == .stopping)
                Divider()
                Button("Open Image…") { model.openImage() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showMainWindow(); model.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "rectangle.dashed")
                .symbolRenderingMode(.palette)
                .foregroundStyle(model.isRecording ? Color.red : Color.primary)
                .accessibilityLabel(model.isRecording ? "Screenroom is recording" : "Screenroom")
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = WindowReader()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class WindowReader: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.isRecording {
            Text("Recording in progress")
            Button("Stop & Save Recording    ⇧⌘7") { model.toggleRecording() }
            Divider()
        } else if model.capture.isBusy {
            Text(model.capture.state == .stopping ? "Saving recording…" : "Preparing capture…")
            if model.capture.state == .choosing {
                Button("Cancel Capture") { model.capture.cancelSelection() }
            }
            Divider()
        }
        Button("Take Screenshot    ⇧⌘6") { model.takeScreenshot() }.disabled(model.busy)
        Button("Start Recording    ⇧⌘7") { model.startRecording() }.disabled(model.busy)
        Divider()
        Button("Open Screenroom") { model.showMainWindow() }
        Button("Open Screenshots Folder") { model.revealFolder(for: .screenshot) }
        Button("Open Recordings Folder") { model.revealFolder(for: .recording) }
        Divider()
        Button("Quit Screenroom") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
