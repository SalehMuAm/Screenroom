import SwiftUI

struct CapturePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LESS FRICTION, MORE FOCUS").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(ScreenroomStyle.accent)
                        Text("Make your point.")
                            .font(.system(size: 37, weight: .medium, design: .rounded)).tracking(-1.3)
                        Text("Capture the moment. Add a little clarity.\nGet back to what you were doing.")
                            .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    Spacer(minLength: 20)
                    CaptureIllustration().frame(width: 190, height: 135).accessibilityHidden(true)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 22) {
                    Picker("Capture type", selection: $model.mode) {
                        Label("Screenshot", systemImage: "camera").tag(CaptureKind.screenshot)
                        Label("Recording", systemImage: "record.circle").tag(CaptureKind.recording)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 270)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What would you like to capture?").font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 12) {
                            ForEach(CaptureSource.allCases) { source in
                                sourceButton(source)
                            }
                        }
                        if model.mode == .recording && model.source == .display {
                            Text("Starts immediately on the display under your pointer. Press ⇧⌘7 again to stop.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    if model.mode == .recording {
                        HStack(spacing: 14) {
                            Image(systemName: model.systemAudio ? "speaker.wave.2" : "speaker.slash")
                                .font(.system(size: 19)).frame(width: 28)
                                .foregroundStyle(ScreenroomStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.systemAudio ? "System audio is on" : "System audio is off")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(model.systemAudio
                                     ? "App sounds will be recorded. Microphone stays off."
                                     : "This recording will be silent. Turn on to include app sounds.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("System audio", isOn: $model.systemAudio).labelsHidden().toggleStyle(.switch)
                                .accessibilityLabel("Include system audio in recording")
                        }
                        .padding(16)
                        .background(ScreenroomStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        HStack(spacing: 14) {
                            Image(systemName: "pencil.tip.crop.circle").font(.system(size: 23)).foregroundStyle(ScreenroomStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Straight into the editor").font(.system(size: 13, weight: .semibold))
                                Text("Draw, add arrows and shapes, then copy or export.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(ScreenroomStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 18) {
                        Button {
                            if model.mode == .screenshot { model.takeScreenshot() }
                            else { model.startRecording() }
                        } label: {
                            Label(model.mode == .screenshot ? "Take screenshot" : "Start recording",
                                  systemImage: model.mode == .screenshot ? "camera" : "record.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 15).padding(.vertical, 9)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text(model.mode == .screenshot ? "⇧ ⌘ 6" : "⇧ ⌘ 7")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Text(model.mode == .screenshot ? "PNG · Original resolution" : "MP4 · Up to 4K · \(model.framesPerSecond) fps")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if model.mode == .recording, let warning = model.recordingStorage.warning {
                        Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.055), lineWidth: 1))
                .disabled(model.busy)

                HStack(alignment: .top, spacing: 24) {
                    footnote("bolt", title: "Ready when you are", detail: "Capture from the menu bar\nor with a keyboard shortcut.")
                    footnote("pencil.and.outline", title: "A quicker way to explain", detail: "A clean set of tools.\nJust the edits you need.")
                    footnote("internaldrive", title: "Stays on your Mac", detail: "No account. No uploads.\nYour files, in your folders.")
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .frame(maxWidth: 790)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshRecordingStorage() }
    }

    private func sourceButton(_ source: CaptureSource) -> some View {
        let selected = model.source == source
        return Button { model.source = source } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: source.symbol).font(.system(size: 23, weight: .regular))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14)).foregroundStyle(selected ? ScreenroomStyle.accent : .gray.opacity(0.35))
                }
                Text(source.title).font(.system(size: 13, weight: .semibold))
                Text(source.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(height: 30, alignment: .top)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ScreenroomStyle.accent.opacity(0.045) : .white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? ScreenroomStyle.accent : .black.opacity(0.13), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(source.title). \(source.detail)")
    }

    private func footnote(_ symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CaptureIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.88, green: 0.89, blue: 0.86))
                .frame(width: 162, height: 104).rotationEffect(.degrees(-7)).offset(x: -9, y: -4)
            RoundedRectangle(cornerRadius: 10)
                .fill(ScreenroomStyle.ink).frame(width: 158, height: 105)
                .shadow(color: .black.opacity(0.14), radius: 12, y: 7)
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 4, height: 4) }
                    Spacer()
                }
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.09)).frame(width: 35, height: 44)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(.white.opacity(0.75)).frame(width: 55, height: 4)
                        Capsule().fill(.white.opacity(0.18)).frame(width: 68, height: 3)
                        Capsule().fill(.white.opacity(0.18)).frame(width: 45, height: 3)
                        Capsule().fill(ScreenroomStyle.accent).frame(width: 34, height: 9)
                    }
                }
            }.padding(16).frame(width: 158, height: 105)
            RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.93, green: 0.62, blue: 0.41), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 79, height: 65).offset(x: 25, y: 4)
            Image(systemName: "arrow.up.left").font(.system(size: 36, weight: .medium))
                .foregroundStyle(ScreenroomStyle.accent).rotationEffect(.degrees(-10)).offset(x: 78, y: 56)
        }
    }
}
