import AppKit
import SwiftUI

enum ScreenroomStyle {
    static let accent = Color(red: 0.79, green: 0.30, blue: 0.21)
    static let ink = Color(red: 0.15, green: 0.17, blue: 0.17)
    static let canvas = Color(red: 0.965, green: 0.958, blue: 0.943)
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                topBar
                Divider()
                if let item = model.selectedItem {
                    if item.kind == .screenshot {
                        ScreenshotEditor(imageURL: item.url, onSave: model.didSaveEdit, onDirtyChange: { model.editorIsDirty = $0 })
                            .id(item.id)
                    } else {
                        RecordingPreview(item: item)
                    }
                } else if model.page == .capture {
                    CapturePanel(model: model)
                } else {
                    LibraryView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScreenroomStyle.canvas)
        }
        .tint(ScreenroomStyle.accent)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.showingSettings) { SettingsSheet(model: model) }
        .alert("Screenroom", isPresented: Binding(
            get: { model.errorMessage != nil || model.library.persistenceError != nil },
            set: { if !$0 { model.errorMessage = nil; model.library.persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil; model.library.persistenceError = nil }
            if model.errorMessage?.contains("Privacy") == true {
                Button("Open Screen Recording Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    model.errorMessage = nil
                }
            }
        } message: {
            Text(model.errorMessage ?? model.library.persistenceError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(ScreenroomStyle.accent)
                Text("Screenroom").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .padding(.top, 42)
            .padding(.bottom, 35)
            .padding(.horizontal, 22)

            Text("WORKSPACE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            navigationButton("Capture", symbol: "viewfinder", page: .capture)
            navigationButton("Library", symbol: "square.stack", page: .library)

            Spacer()

            if model.isRecording || model.capture.state == .stopping {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text(model.isRecording ? "Recording" : "Saving…").font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let start = model.capture.startedAt {
                            Text(start, style: .timer).font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Button { model.capture.stopRecording() } label: {
                        Label("Stop & save", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isRecording)
                }
                .padding(14)
                .background(ScreenroomStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 16) {
                Button { model.openImage() } label: {
                    Label("Open image…", systemImage: "folder").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                Button { model.showingSettings = true } label: {
                    Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                Divider()
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0.32, green: 0.48, blue: 0.37)).frame(width: 5, height: 5)
                    Text("Local. Private. Yours.").font(.system(size: 10))
                }.foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .frame(width: 196)
        .background(Color(red: 0.94, green: 0.936, blue: 0.923))
    }

    private func navigationButton(_ title: String, symbol: String, page: WorkspacePage) -> some View {
        Button { navigate { model.selectedItem = nil; model.page = page; model.notice = nil } } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if page == .library {
                    Text("\(model.library.items.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(model.page == page ? Color.white.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if model.selectedItem != nil {
                Button { navigate { model.selectedItem = nil } } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("Back to library")
                    .accessibilityLabel("Back to library")
                Text(model.selectedItem?.kind == .screenshot ? "Quick edit" : "Recording preview")
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text(model.page == .capture ? "New capture" : "Your library").font(.system(size: 13, weight: .medium))
            }
            Spacer()
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("A little less friction. A lot more clarity.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let item = model.selectedItem {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder").accessibilityLabel("Show in Finder")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background(Color.white.opacity(0.55))
    }

    private func navigate(_ action: @escaping () -> Void) {
        guard model.confirmLeavingEditor() else { return }
        model.editorIsDirty = false
        action()
    }
}

private struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("A few preferences").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section("Recording") {
                    Picker("Frame rate", selection: $model.framesPerSecond) {
                        Text("30 fps · smaller files").tag(30)
                        Text("60 fps · smoother motion").tag(60)
                    }
                    Toggle("Include system audio", isOn: $model.systemAudio)
                    Text("Records sound from the selected apps or display. Microphone capture is always off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Global shortcuts") {
                    LabeledContent("Take screenshot", value: "⇧⌘6")
                    LabeledContent("Start / stop recording", value: "⇧⌘7")
                    Text("Available while Screenroom is running. Close its window to keep it in the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.shortcutsAvailable {
                        Text("A shortcut is in use by another app. Use the menu bar controls, or free ⇧⌘6 and ⇧⌘7 then restart Screenroom.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Saved on your Mac") {
                    Button("Open Pictures/Screenroom") { model.revealFolder(for: .screenshot) }
                    Button("Open Movies/Screenroom") { model.revealFolder(for: .recording) }
                }
            }
            .formStyle(.grouped)
            .disabled(model.busy)
        }
        .padding(24)
        .frame(width: 500, height: 530)
    }
}
