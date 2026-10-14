import Foundation

/// Uses space available now, rather than space macOS might reclaim later.
struct RecordingStorage {
    static let minimumAvailableBytes: Int64 = 1_073_741_824
    static let warningAvailableBytes = minimumAvailableBytes * 5

    let availableBytes: Int64?

    init(availableBytes: Int64?) {
        self.availableBytes = availableBytes.flatMap { $0 >= 0 ? $0 : nil }
    }

    static func inspect(folder: URL) -> RecordingStorage {
        if let capacity = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
            return RecordingStorage(availableBytes: Int64(capacity))
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: folder.path)
        return RecordingStorage(availableBytes: (attributes?[.systemFreeSize] as? NSNumber)?.int64Value)
    }

    var warning: String? {
        guard let availableBytes, availableBytes < Self.warningAvailableBytes else { return nil }
        return "Low disk space: \(Self.format(availableBytes)) free. macOS may stop recording early. Free up space for longer recordings."
    }

    func validateForRecording() throws {
        guard let availableBytes, availableBytes < Self.minimumAvailableBytes else { return }
        throw RecordingStorageError.insufficientSpace(availableBytes: availableBytes)
    }

    fileprivate static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum RecordingStorageError: LocalizedError {
    case insufficientSpace(availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .insufficientSpace(let availableBytes):
            return "Not enough space to record. Only \(RecordingStorage.format(availableBytes)) is free on the recording disk. Keep at least \(RecordingStorage.format(RecordingStorage.minimumAvailableBytes)) free before recording."
        }
    }
}
