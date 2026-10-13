import AppKit
import AVKit
import ImageIO
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var filter: LibraryFilter = .all
    @State private var query = ""

    private var visibleItems: [CaptureItem] {
        model.library.items.filter { item in
            (filter == .all || item.kind.rawValue == filter.rawValue)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("A place for your captures.").font(.system(size: 26, weight: .medium, design: .rounded)).tracking(-0.7)
                    Text("Open a screenshot to annotate, or replay a recording.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Screenshots") { model.revealFolder(for: .screenshot) }
                    Button("Recordings") { model.revealFolder(for: .recording) }
                } label: { Image(systemName: "folder") }
                .menuStyle(.borderlessButton).frame(width: 28)
                .help("Open capture folders").accessibilityLabel("Open capture folders")
            }
            HStack {
                Picker("Filter captures", selection: $filter) {
                    Text("All").tag(LibraryFilter.all)
                    Text("Screenshots").tag(LibraryFilter.screenshot)
                    Text("Recordings").tag(LibraryFilter.recording)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                Spacer()
                TextField("Search captures", text: $query)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 210)
            }
            if visibleItems.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: query.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                        .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text(query.isEmpty ? "Room for your first capture." : "No matching captures")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                    Text(query.isEmpty ? "Everything you capture will appear here,\nready for a quick edit or another look." : "Try a different name or capture type.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                    if query.isEmpty {
                        Button("Make a capture") { model.page = .capture }
                            .buttonStyle(.borderedProminent).padding(.top, 6)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 16)], spacing: 20) {
                        ForEach(visibleItems) { item in
                            CaptureCard(item: item) { model.open(item) }
                                .contextMenu {
                                    Button("Open") { model.open(item) }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                    Divider()
                                    Button("Remove from Library") { model.library.removeFromLibrary(item) }
                                }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }.padding(30)
    }
    private enum LibraryFilter: String { case all, screenshot, recording }
}

private struct CaptureCard: View {
    let item: CaptureItem
    let open: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color(red: 0.88, green: 0.88, blue: 0.86)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().padding(10)
                    } else {
                        Image(systemName: item.exists ? item.kind.symbol : "exclamationmark.triangle")
                            .font(.system(size: 25)).foregroundStyle(.secondary)
                    }
                    if item.kind == .recording {
                        Image(systemName: "play.fill").font(.system(size: 18))
                            .foregroundStyle(.white).padding(15).background(.black.opacity(0.55), in: Circle())
                    }
                }.frame(height: 145).clipped()
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Label(item.kind == .screenshot ? "PNG / Image" : "MP4", systemImage: item.kind.symbol)
                        Spacer()
                        Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(13)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.kind.title): \(item.title)")
        .task(id: item.url) {
            thumbnail = await makeThumbnail(url: item.url, isVideo: item.kind == .recording)
        }
    }

    private func makeThumbnail(url: URL, isVideo: Bool) async -> NSImage? {
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 300)
            guard let result = try? await generator.image(at: .zero) else { return nil }
            return NSImage(cgImage: result.image, size: .zero)
        }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: .zero)
        }.value
    }
}

struct RecordingPreview: View {
    let item: CaptureItem
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(red: 0.12, green: 0.13, blue: 0.14)
                if let player {
                    VideoPlayer(player: player)
                        .padding(24)
                } else { ProgressView().tint(.white) }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("Saved to \(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open in QuickTime") { NSWorkspace.shared.open([item.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/QuickTime Player.app"), configuration: NSWorkspace.OpenConfiguration()) }
                ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    .buttonStyle(.borderedProminent)
            }.padding(20).background(.white)
        }
        .task(id: item.url) { player?.pause(); player = AVPlayer(url: item.url) }
        .onDisappear { player?.pause(); player = nil }
    }
}
