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
}
