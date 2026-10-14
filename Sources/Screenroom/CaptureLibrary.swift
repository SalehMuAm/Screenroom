import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum CaptureSource: String, CaseIterable, Identifiable {
    case region, window, display

    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return "Area"
        case .window: return "Window"
        case .display: return "Screen"
        }
    }
    var symbol: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .display: return "display"
        }
    }
    var detail: String {
        switch self {
        case .region: return "Drag to select exactly what you need."
        case .window: return "Choose a single app window."
        case .display: return "Capture an entire display."
        }
    }
}

enum CaptureKind: String, Codable, CaseIterable {
    case screenshot, recording
    var title: String { self == .screenshot ? "Screenshot" : "Recording" }
    var symbol: String { self == .screenshot ? "photo" : "video" }
}

struct CaptureItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var url: URL
    var kind: CaptureKind
    var createdAt: Date = Date()
    var title: String { url.deletingPathExtension().lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published var persistenceError: String?
    private let indexURL: URL
    private let picturesDirectory: URL
    private let moviesDirectory: URL
    private var needsIndexBackup = false
    private var indexBackupURL: URL?

    init(rootDirectory: URL? = nil) {
        let files = FileManager.default
        if let rootDirectory {
            indexURL = rootDirectory.appendingPathComponent("library.json")
            picturesDirectory = rootDirectory.appendingPathComponent("Pictures")
            moviesDirectory = rootDirectory.appendingPathComponent("Movies")
        } else {
            let home = files.homeDirectoryForCurrentUser
            indexURL = home.appendingPathComponent("Library/Application Support/Screenroom/library.json")
            picturesDirectory = home.appendingPathComponent("Pictures/Screenroom", isDirectory: true)
            moviesDirectory = home.appendingPathComponent("Movies/Screenroom", isDirectory: true)
        }
        if files.fileExists(atPath: indexURL.path) {
            do {
                items = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: indexURL))
            } catch {
                needsIndexBackup = true
                persistenceError = "The capture library could not be loaded. Your original files are still in Pictures/Screenroom and Movies/Screenroom. \(error.localizedDescription)"
            }
        }
    }

    func directory(for kind: CaptureKind) throws -> URL {
        let directory = kind == .screenshot ? picturesDirectory : moviesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func newDestination(for kind: CaptureKind) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "\(kind.title) \(formatter.string(from: Date())) \(UUID().uuidString.prefix(4))"
        return try directory(for: kind).appendingPathComponent(name).appendingPathExtension(kind == .screenshot ? "png" : "mp4")
    }

    @discardableResult
    func storeScreenshot(from temporaryURL: URL) throws -> CaptureItem {
        let destination = try newDestination(for: .screenshot)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return add(url: destination, kind: .screenshot)
    }

    @discardableResult
    func add(url: URL, kind: CaptureKind) -> CaptureItem {
        if let existing = items.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            return existing
        }
        let item = CaptureItem(url: url, kind: kind)
        items.insert(item, at: 0)
        persist()
        return item
    }

    func removeFromLibrary(_ item: CaptureItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if needsIndexBackup {
                let backup = indexURL.deletingLastPathComponent()
                    .appendingPathComponent("library-unreadable-\(UUID().uuidString).json")
                // Never replace an index we could not read until its contents
                // have been preserved. A failed copy leaves persistence blocked.
                try FileManager.default.copyItem(at: indexURL, to: backup)
                indexBackupURL = backup
                needsIndexBackup = false
                persistenceError = "The previous library index could not be loaded. A backup was saved at \(backup.path). Your media files were not deleted."
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: indexURL, options: .atomic)
        } catch {
            if needsIndexBackup {
                persistenceError = "Your capture is saved, but the unreadable library index at \(indexURL.path) could not be backed up. It has been left unchanged. \(error.localizedDescription)"
            } else {
                let recovery = indexBackupURL.map { " The previous library index is backed up at \($0.path)." } ?? ""
                persistenceError = "Your capture is saved, but the library index could not be updated.\(recovery) \(error.localizedDescription)"
            }
        }
    }
}
