import XCTest
@testable import Screenroom

final class CaptureGeometryTests: XCTestCase {
    func testRegionConvertsBottomLeftSelectionToTopLeftCrop() {
        let rect = CaptureGeometry.sourceRect(selection: CGRect(x: 120, y: 80, width: 640, height: 360), displayHeight: 900)
        XCTAssertEqual(rect, CGRect(x: 120, y: 460, width: 640, height: 360))
    }

    func testWholeDisplayDoesNotShiftCrop() {
        let rect = CaptureGeometry.sourceRect(selection: CGRect(x: 0, y: 0, width: 1440, height: 900), displayHeight: 900)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func testRetinaRecordingFits4KAndPreservesAspectRatio() {
        let size = CaptureGeometry.recordingSize(points: CGSize(width: 3024, height: 1964), scale: 2)
        XCTAssertEqual(size.width, 3840)
        XCTAssertLessThanOrEqual(size.height, 3840)
        XCTAssertEqual(size.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertEqual(size.height.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertEqual(size.width / size.height, 3024.0 / 1964.0, accuracy: 0.002)
    }

    func testPortraitRecordingBoundsLongestDimension() {
        let size = CaptureGeometry.recordingSize(points: CGSize(width: 1440, height: 2560), scale: 2)
        XCTAssertEqual(size, CGSize(width: 2160, height: 3840))
    }

    func testOddDimensionsBecomeValidEncoderDimensions() {
        XCTAssertEqual(CaptureGeometry.recordingSize(points: CGSize(width: 321, height: 201), scale: 1), CGSize(width: 320, height: 200))
    }
}
