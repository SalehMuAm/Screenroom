import XCTest
@testable import Screenroom

final class AppModelTests: XCTestCase {
    @MainActor
    private func withModel(_ test: (AppModel, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(library: CaptureLibrary(rootDirectory: root), registerHotKeys: false)
        try test(model, root)
    }

    @MainActor
    func testRecordingCompletionKeepsUnsavedScreenshotAndIndexesVideo() throws {
        try withModel { model, root in
            let screenshot = model.library.add(url: root.appendingPathComponent("original.png"), kind: .screenshot)
            model.selectedItem = screenshot
            model.page = .library
            model.editorIsDirty = true
            let video = root.appendingPathComponent("recording.mp4")

            model.capture.onRecordingFinished?(video)

            XCTAssertEqual(model.selectedItem, screenshot)
            XCTAssertTrue(model.editorIsDirty)
            XCTAssertEqual(model.library.items.first?.url, video)
            XCTAssertEqual(CaptureLibrary(rootDirectory: root).items.first?.url, video)
            XCTAssertEqual(model.notice, "Recording saved to library")
        }
    }

    @MainActor
    func testRecordingCompletionKeepsEditorBeforeDirtyNotificationArrives() throws {
        try withModel { model, root in
            let screenshot = model.library.add(url: root.appendingPathComponent("original.png"), kind: .screenshot)
            model.selectedItem = screenshot
            XCTAssertFalse(model.editorIsDirty)

            model.capture.onRecordingFinished?(root.appendingPathComponent("recording.mp4"))

            XCTAssertEqual(model.selectedItem, screenshot)
        }
    }

    @MainActor
    func testRecordingCompletionOpensPreviewWhenNoEditorIsOpen() throws {
        try withModel { model, root in
            let video = root.appendingPathComponent("recording.mp4")

            model.capture.onRecordingFinished?(video)

            XCTAssertEqual(model.selectedItem?.url, video)
            XCTAssertEqual(model.selectedItem?.kind, .recording)
            XCTAssertEqual(model.page, .library)
        }
    }

    @MainActor
    func testReopeningCurrentImagePreservesUnsavedStateAndLibraryEntry() throws {
        try withModel { model, root in
            let url = root.appendingPathComponent("original.png")
            model.openImage(at: url)
            let original = model.selectedItem
            model.editorIsDirty = true

            model.openImage(at: root.appendingPathComponent("./original.png"))

            XCTAssertEqual(model.selectedItem, original)
            XCTAssertTrue(model.editorIsDirty)
            XCTAssertEqual(model.library.items.count, 1)
        }
    }
}
