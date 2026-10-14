import XCTest
@testable import Screenroom

final class CaptureLibraryTests: XCTestCase {
    @MainActor
    func testStoreScreenshotPersistsOriginalAndRestoresIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("capture.png")
        let content = Data([1, 2, 3, 4])
        try content.write(to: input)
        let library = CaptureLibrary(rootDirectory: root)
        let item = try library.storeScreenshot(from: input)
        XCTAssertEqual(try Data(contentsOf: item.url), content)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        XCTAssertEqual(CaptureLibrary(rootDirectory: root).items, [item])
    }

    @MainActor
    func testRemoveFromLibraryKeepsOriginalFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("important.png")
        try Data([7]).write(to: file)
        let library = CaptureLibrary(rootDirectory: root)
        let item = library.add(url: file, kind: .screenshot)
        library.removeFromLibrary(item)
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertTrue(CaptureLibrary(rootDirectory: root).items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testRepeatedSaveOfSameURLDoesNotDuplicateLibraryEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CaptureLibrary(rootDirectory: root)
        let url = root.appendingPathComponent("Screenshot.png")
        let first = library.add(url: url, kind: .screenshot)
        let second = library.add(url: url, kind: .screenshot)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(library.items.count, 1)
    }

    @MainActor
    func testCorruptIndexSurfacesErrorWithoutCrashing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("library.json"))
        let library = CaptureLibrary(rootDirectory: root)
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertNotNil(library.persistenceError)
    }

    @MainActor
    func testAddingAfterCorruptIndexPreservesOriginalBytesInOneBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent("library.json")
        let original = Data("[{\"url\":\"a recoverable old path\",\"kind\":\"unknown\"}]".utf8)
        try original.write(to: index)
        let library = CaptureLibrary(rootDirectory: root)

        let first = library.add(url: root.appendingPathComponent("first.png"), kind: .screenshot)
        let second = library.add(url: root.appendingPathComponent("second.png"), kind: .screenshot)

        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-unreadable-") }
        XCTAssertEqual(backups.count, 1)
        let backup = try XCTUnwrap(backups.first)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let recoveryMessage = try XCTUnwrap(library.persistenceError)
        // Enumeration may return /private/var while the caller supplied /var.
        // Verify the reported path through the original root actually opens the backup.
        let expectedBackup = root.appendingPathComponent(backup.lastPathComponent)
        XCTAssertTrue(recoveryMessage.contains(expectedBackup.path), "Expected path \(expectedBackup.path) in: \(recoveryMessage)")
        XCTAssertEqual(try Data(contentsOf: expectedBackup), original)
        XCTAssertEqual(CaptureLibrary(rootDirectory: root).items, [second, first])
    }

    @MainActor
    func testBackupFailureDoesNotOverwriteUnreadableIndexAndCanRetry() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let index = root.appendingPathComponent("library.json")
        defer {
            try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
            try? files.removeItem(at: root)
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("unreadable library contents".utf8)
        try original.write(to: index)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: index.path)
        guard !files.isReadableFile(atPath: index.path) else {
            throw XCTSkip("This environment can read files despite their POSIX permissions.")
        }
        let library = CaptureLibrary(rootDirectory: root)

        let first = library.add(url: root.appendingPathComponent("first.png"), kind: .screenshot)

        XCTAssertTrue(try XCTUnwrap(library.persistenceError).contains("could not be backed up"))
        XCTAssertTrue(try XCTUnwrap(library.persistenceError).contains(index.path))
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
        XCTAssertEqual(try Data(contentsOf: index), original)

        let second = library.add(url: root.appendingPathComponent("second.png"), kind: .screenshot)
        let backups = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-unreadable-") }
        XCTAssertTrue(backups.contains { (try? Data(contentsOf: $0)) == original })
        XCTAssertEqual(CaptureLibrary(rootDirectory: root).items, [second, first])
    }
}
