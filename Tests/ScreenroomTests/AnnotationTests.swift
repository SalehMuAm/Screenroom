import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Screenroom

final class AnnotationTests: XCTestCase {
    func testJPEGImportAppliesEveryEXIFOrientationAtFullResolution() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors = [NSColor.red, .green, .blue, .yellow]
        let rawCorners = [CGRect(x: 0, y: 32, width: 48, height: 32), CGRect(x: 48, y: 32, width: 48, height: 32),
                          CGRect(x: 0, y: 0, width: 48, height: 32), CGRect(x: 48, y: 0, width: 48, height: 32)]
        for (color, rect) in zip(colors, rawCorners) {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        let rawImage = try XCTUnwrap(context.makeImage())
        let reference = NSBitmapImageRep(cgImage: rawImage)
        let referencePoints = [(24, 16), (72, 16), (24, 48), (72, 48)]
        let referenceColors = try referencePoints.map { point in
            try XCTUnwrap(reference.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
        }
        // Corner order is top-left, top-right, bottom-left, bottom-right.
        let expectedCorners = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                               [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]]
        for orientation in 1...8 {
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, rawImage, [kCGImagePropertyOrientation: orientation,
                                                               kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
            let image = try XCTUnwrap(AnnotationImageLoader.uprightImage(from: source))
            XCTAssertEqual(image.width, orientation >= 5 ? 64 : 96, "Orientation \(orientation)")
            XCTAssertEqual(image.height, orientation >= 5 ? 96 : 64, "Orientation \(orientation)")
            let bitmap = NSBitmapImageRep(cgImage: image)
            let samplePoints = [(image.width / 4, image.height / 4), (image.width * 3 / 4, image.height / 4),
                                (image.width / 4, image.height * 3 / 4), (image.width * 3 / 4, image.height * 3 / 4)]
            for (corner, point) in samplePoints.enumerated() {
                let actual = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
                let expected = referenceColors[expectedCorners[orientation - 1][corner]]
                XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.08, "Orientation \(orientation), corner \(corner)")
                XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.08, "Orientation \(orientation), corner \(corner)")
                XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.08, "Orientation \(orientation), corner \(corner)")
            }
        }
    }

    func testFittedImageCoordinatesPreservePixelsAndClampOutsideDrags() {
        let imageSize = CGSize(width: 2400, height: 1600)
        let rect = AnnotationGeometry.fittedRect(imageSize: imageSize,
                                                 in: CGRect(x: 0, y: 0, width: 1000, height: 800), inset: 20)
        XCTAssertEqual(rect, CGRect(x: 20, y: 80, width: 960, height: 640))
        XCTAssertEqual(AnnotationGeometry.imagePoint(from: CGPoint(x: 500, y: 400), imageRect: rect, imageSize: imageSize),
                       CGPoint(x: 1200, y: 800))
        XCTAssertEqual(AnnotationGeometry.imagePoint(from: CGPoint(x: -100, y: 1000), imageRect: rect, imageSize: imageSize),
                       CGPoint(x: 0, y: 1600))
    }

    func testMovingAnnotationKeepsItsShapeInsideImage() {
        let annotation = ScreenshotAnnotation(tool: .rectangle,
                                              points: [CGPoint(x: 20, y: 30), CGPoint(x: 70, y: 90)],
                                              color: AnnotationColor.palette[0], strokeWidth: 6)
        let moved = annotation.translated(by: CGSize(width: 100, height: -100), inside: CGSize(width: 100, height: 100))
        XCTAssertEqual(moved.bounds, CGRect(x: 50, y: 0, width: 50, height: 60))
        XCTAssertEqual(moved.id, annotation.id)
    }

    func testArrowPointsTowardDragEndAndSupportsSelection() {
        let arrow = ScreenshotAnnotation(tool: .arrow,
                                         points: [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 20)],
                                         color: AnnotationColor.palette[0], strokeWidth: 4)
        XCTAssertTrue(arrow.contains(CGPoint(x: 105, y: 20), tolerance: 2))
        XCTAssertFalse(arrow.contains(CGPoint(x: 60, y: 60), tolerance: 2))
        XCTAssertEqual(arrow.path.boundingBoxOfPath.maxX, 110, accuracy: 0.001)
        XCTAssertLessThan(arrow.path.boundingBoxOfPath.minY, 20)
        XCTAssertGreaterThan(arrow.path.boundingBoxOfPath.maxY, 20)
    }

    func testPNGRenderingKeepsOriginalResolutionAndCoordinateSpace() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        let image = try XCTUnwrap(context.makeImage())
        let line = ScreenshotAnnotation(tool: .line, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20)],
                                        color: AnnotationColor.palette[0], strokeWidth: 8)
        let output = try AnnotationRenderer.renderedImage(image, annotations: [line])
        XCTAssertEqual(output.width, 200)
        XCTAssertEqual(output.height, 120)
        let bitmap = NSBitmapImageRep(cgImage: output)
        // CG coordinates start at the bottom; bitmap rows start at the top.
        let marked = try XCTUnwrap(bitmap.colorAt(x: 50, y: 99)?.usingColorSpace(.deviceRGB))
        let unmarked = try XCTUnwrap(bitmap.colorAt(x: 50, y: 20)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(marked.redComponent, 0.85)
        XCTAssertLessThan(marked.greenComponent, 0.5)
        XCTAssertGreaterThan(unmarked.greenComponent, 0.95)
        XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    func testUndoRedoClearAndMoveRestoreCompleteAnnotations() {
        let model = AnnotationEditorModel(imageURL: URL(fileURLWithPath: "/nonexistent-screenshot.png"))
        let annotation = ScreenshotAnnotation(tool: .pen,
                                              points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 50)],
                                              color: AnnotationColor.palette[0], strokeWidth: 6)
        XCTAssertFalse(model.isDirty)
        model.append(annotation)
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.history.canUndo)
        model.history.undo()
        XCTAssertTrue(model.annotations.isEmpty)
        XCTAssertFalse(model.isDirty)
        model.history.redo()
        XCTAssertEqual(model.annotations, [annotation])
        let original = model.annotations
        model.annotations[0] = annotation.translated(by: CGSize(width: 5, height: 10), inside: CGSize(width: 100, height: 100))
        model.registerUndo(original, action: "Move Annotation")
        model.history.undo()
        XCTAssertEqual(model.annotations, original)
        model.history.redo()
        XCTAssertEqual(model.annotations[0].points[0], CGPoint(x: 15, y: 30))
        let moved = model.annotations
        model.change([], action: "Clear Annotations")
        model.history.undo()
        XCTAssertEqual(model.annotations, moved)
    }
}
