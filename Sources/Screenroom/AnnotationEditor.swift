import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, pen, arrow, rectangle, ellipse, line, text

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        }
    }

    var instruction: String {
        switch self {
        case .select: return "Click an annotation to move it. Press Delete to remove it."
        case .pen: return "Drag to draw."
        case .arrow: return "Drag toward the point you want to highlight."
        case .rectangle: return "Drag to draw a rectangle. Hold Shift for a square."
        case .ellipse: return "Drag to draw an ellipse. Hold Shift for a circle."
        case .line: return "Drag to draw a line. Hold Shift to snap its angle."
        case .text: return "Type your text, then click the image to place it."
        }
    }
}

struct AnnotationColor: Equatable, Identifiable {
    let name: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var id: String { name }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var swiftUIColor: Color { Color(nsColor: nsColor) }

    static let palette: [AnnotationColor] = [
        .init(name: "Coral", red: 0.96, green: 0.28, blue: 0.25),
        .init(name: "Amber", red: 1, green: 0.69, blue: 0.13),
        .init(name: "Green", red: 0.17, green: 0.75, blue: 0.46),
        .init(name: "Blue", red: 0.18, green: 0.52, blue: 0.98),
        .init(name: "Violet", red: 0.67, green: 0.39, blue: 0.94),
        .init(name: "White", red: 1, green: 1, blue: 1),
        .init(name: "Charcoal", red: 0.10, green: 0.11, blue: 0.13)
    ]
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    var id = UUID()
    let tool: AnnotationTool
    var points: [CGPoint]
    let color: AnnotationColor
    let strokeWidth: CGFloat
    var text = ""
    var fontSize: CGFloat = 52

    var bounds: CGRect {
        if tool == .text, let point = points.first {
            return CGRect(origin: point, size: attributedText.size())
        }
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
            CGRect(x: min(bounds.minX, point.x), y: min(bounds.minY, point.y),
                   width: max(bounds.maxX, point.x) - min(bounds.minX, point.x),
                   height: max(bounds.maxY, point.y) - min(bounds.minY, point.y))
        }
    }

    var attributedText: NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color.nsColor
        ])
    }

    var path: CGPath {
        let path = CGMutablePath()
        guard let start = points.first else { return path }
        let end = points.last ?? start
        switch tool {
        case .rectangle:
            path.addRect(bounds)
        case .ellipse:
            path.addEllipse(in: bounds)
        case .arrow:
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(max(strokeWidth * 4.5, 18), hypot(end.x - start.x, end.y - start.y) * 0.55)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x - length * cos(angle + offset),
                                        y: end.y - length * sin(angle + offset)))
            }
        case .pen, .line:
            path.move(to: start)
            for point in points.dropFirst() { path.addLine(to: point) }
            // Give a click with the pen a visible round dot.
            if points.count == 1 { path.addLine(to: CGPoint(x: start.x + 0.01, y: start.y)) }
        case .select, .text:
            break
        }
        return path
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if tool == .text || tool == .rectangle { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if tool == .ellipse, path.contains(point) { return true }
        return path.copy(strokingWithWidth: strokeWidth + tolerance * 2, lineCap: .round,
                         lineJoin: .round, miterLimit: 10).contains(point)
    }

    func translated(by delta: CGSize, inside imageSize: CGSize) -> ScreenshotAnnotation {
        let box = bounds
        let dx = min(max(delta.width, -box.minX), max(-box.minX, imageSize.width - box.maxX))
        let dy = min(max(delta.height, -box.minY), max(-box.minY, imageSize.height - box.maxY))
        var result = self
        result.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return result
    }
}

enum AnnotationGeometry {
    static func fittedRect(imageSize: CGSize, in bounds: CGRect, inset: CGFloat = 28) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let available = bounds.insetBy(dx: inset, dy: inset)
        let scale = max(0, min(available.width / imageSize.width, available.height / imageSize.height))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func imagePoint(from point: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        return CGPoint(x: min(max((point.x - imageRect.minX) / imageRect.width * imageSize.width, 0), imageSize.width),
                       y: min(max((point.y - imageRect.minY) / imageRect.height * imageSize.height, 0), imageSize.height))
    }

    static func constrainedEnd(start: CGPoint, end: CGPoint, tool: AnnotationTool) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if tool == .rectangle || tool == .ellipse {
            let side = min(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        let distance = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance)
    }
}

enum AnnotationRenderer {
    static func draw(_ annotations: [ScreenshotAnnotation], in context: CGContext) {
        context.saveGState()
        for annotation in annotations {
            context.setStrokeColor(annotation.color.nsColor.cgColor)
            context.setLineWidth(annotation.strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if annotation.tool == .text, let point = annotation.points.first {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                annotation.attributedText.draw(at: point)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                context.addPath(annotation.path)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    static func renderedImage(_ image: CGImage, annotations: [ScreenshotAnnotation]) throws -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AnnotationEditorError.renderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        draw(annotations, in: context)
        guard let output = context.makeImage() else { throw AnnotationEditorError.renderFailed }
        return output
    }
}

enum AnnotationImageLoader {
    static func uprightImage(from source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard (2...8).contains(orientation) else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        // ImageIO applies EXIF rotation and mirroring for JPEG, HEIC, and TIFF.
        // Always decode the full image, ignoring any embedded preview; omitting
        // a maximum pixel size preserves the source's full pixel resolution.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum AnnotationEditorError: LocalizedError {
    case unreadableImage, renderFailed, clipboardFailed
    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "This image could not be opened. Try taking another screenshot."
        case .renderFailed: return "The edited image could not be created. Try again with a smaller image."
        case .clipboardFailed: return "The image could not be copied to the clipboard."
        }
    }
}

@MainActor
final class AnnotationEditorModel: ObservableObject {
    let imageURL: URL
    let image: CGImage?
    let history = UndoManager()
    @Published var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var savedAnnotations: [ScreenshotAnnotation] = []
    @Published var selectedID: UUID?
    @Published var tool: AnnotationTool = .arrow
    @Published var color = AnnotationColor.palette[0]
    @Published var strokeWidth: CGFloat = 6
    @Published var fontSize: CGFloat = 52
    @Published var textToPlace = ""
    @Published var errorMessage: String?
    @Published var status = ""

    var imageSize: CGSize { CGSize(width: image?.width ?? 0, height: image?.height ?? 0) }
    var isDirty: Bool { annotations != savedAnnotations }

    init(imageURL: URL) {
        self.imageURL = imageURL
        if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
            image = AnnotationImageLoader.uprightImage(from: source)
        } else {
            image = nil
        }
        history.groupsByEvent = false
        history.levelsOfUndo = 60
    }

    func change(_ updated: [ScreenshotAnnotation], action: String) {
        let previous = annotations
        annotations = updated
        registerUndo(previous, action: action)
        if !updated.contains(where: { $0.id == selectedID }) { selectedID = nil }
        status = ""
    }

    func registerUndo(_ previous: [ScreenshotAnnotation], action: String) {
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self) { target in target.change(previous, action: action) }
        history.setActionName(action)
        history.endUndoGrouping()
        objectWillChange.send()
    }

    func append(_ annotation: ScreenshotAnnotation) {
        change(annotations + [annotation], action: "Add \(annotation.tool.title)")
        selectedID = annotation.id
    }

    func deleteSelection() {
        guard let selectedID else { return }
        change(annotations.filter { $0.id != selectedID }, action: "Delete Annotation")
    }

    func pngData() throws -> Data {
        guard let image else { throw AnnotationEditorError.unreadableImage }
        let rendered = try AnnotationRenderer.renderedImage(image, annotations: annotations)
        guard let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
            throw AnnotationEditorError.renderFailed
        }
        return data
    }

    func copy() {
        do {
            let data = try pngData()
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setData(data, forType: .png) else { throw AnnotationEditorError.clipboardFailed }
            status = "Copied to clipboard"
        } catch { errorMessage = error.localizedDescription }
    }

    func save(onSave: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = imageURL.deletingPathExtension().lastPathComponent + " Edited.png"
        panel.canCreateDirectories = true
        panel.title = "Save Edited Screenshot"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.pngData().write(to: url, options: .atomic)
                self.savedAnnotations = self.annotations
                self.status = "Saved \(url.lastPathComponent)"
                onSave(url)
            } catch { self.errorMessage = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

struct ScreenshotEditor: View {
    @StateObject private var model: AnnotationEditorModel
    @State private var showingClearConfirmation = false
    private let onSave: (URL) -> Void
    private let onDirtyChange: (Bool) -> Void

    init(imageURL: URL, onSave: @escaping (URL) -> Void, onDirtyChange: @escaping (Bool) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: AnnotationEditorModel(imageURL: imageURL))
        self.onSave = onSave
        self.onDirtyChange = onDirtyChange
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            if model.image != nil {
                AnnotationCanvas(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Unable to Open Screenshot", systemImage: "photo.badge.exclamationmark",
                                       description: Text(AnnotationEditorError.unreadableImage.localizedDescription))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            Divider()
            HStack(spacing: 12) {
                Text(model.status.isEmpty ? model.tool.instruction : model.status)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                if let image = model.image {
                    Text("\(image.width) × \(image.height) px")
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(\.colorScheme, .light)
        .onAppear { onDirtyChange(model.isDirty) }
        .onChange(of: model.isDirty) { _, dirty in onDirtyChange(dirty) }
        .alert("Remove All Annotations?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) { model.change([], action: "Clear Annotations") }
        } message: {
            Text("The original screenshot stays intact. You can undo this change.")
        }
        .alert("Screenshot Editor", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var editorToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button { model.tool = tool } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 31, height: 29)
                            .foregroundStyle(model.tool == tool ? Color.accentColor : Color.primary)
                            .background(model.tool == tool ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                }
                Divider().frame(height: 20).padding(.horizontal, 7)
                Button { model.history.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.history.canUndo)
                    .help("Undo (⌘Z)")
                    .accessibilityLabel("Undo")
                Button { model.history.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.history.canRedo)
                    .help("Redo (⇧⌘Z)")
                    .accessibilityLabel("Redo")
                Button { showingClearConfirmation = true } label: { Image(systemName: "trash") }
                    .disabled(model.annotations.isEmpty)
                    .help("Remove all annotations")
                    .accessibilityLabel("Remove all annotations")
                Spacer(minLength: 8)
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.image == nil)
                Button {
                    model.save { url in
                        onDirtyChange(false)
                        onSave(url)
                    }
                } label: { Label("Save PNG", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.image == nil)
            }
            HStack(spacing: 8) {
                ForEach(AnnotationColor.palette) { color in
                    Button { model.color = color } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .overlay(Circle().strokeBorder(.black.opacity(color.name == "White" ? 0.2 : 0.08), lineWidth: 1))
                            .frame(width: 17, height: 17)
                            .padding(3)
                            .overlay(Circle().strokeBorder(model.color == color ? Color.primary.opacity(0.7) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel("\(color.name) ink")
                    .accessibilityAddTraits(model.color == color ? .isSelected : [])
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                if model.tool == .text {
                    TextField("Text to place", text: $model.textToPlace)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100, maxWidth: 250)
                        .accessibilityLabel("Annotation text")
                    Picker("Size", selection: $model.fontSize) {
                        Text("Small").tag(CGFloat(28))
                        Text("Medium").tag(CGFloat(52))
                        Text("Large").tag(CGFloat(80))
                        Text("Extra Large").tag(CGFloat(120))
                    }
                    .frame(width: 135)
                } else {
                    Picker("Stroke", selection: $model.strokeWidth) {
                        Text("Fine").tag(CGFloat(3))
                        Text("Regular").tag(CGFloat(6))
                        Text("Bold").tag(CGFloat(12))
                        Text("Heavy").tag(CGFloat(20))
                    }
                    .frame(width: 145)
                }
                Spacer(minLength: 0)
                Text("\(model.annotations.count) annotation\(model.annotations.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var model: AnnotationEditorModel

    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(model: model) }
    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.model = model
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
private final class AnnotationCanvasView: NSView, NSUserInterfaceValidations {
    var model: AnnotationEditorModel
    private var draft: ScreenshotAnnotation?
    private var dragStart: CGPoint?
    private var movingOriginal: ScreenshotAnnotation?
    private var beforeMove: [ScreenshotAnnotation]?

    init(model: AnnotationEditorModel) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot annotation canvas")
        setAccessibilityHelp("Use the toolbar to choose an annotation tool, then draw on the screenshot.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { model.history }

    @objc func undo(_ sender: Any?) { model.history.undo() }
    @objc func redo(_ sender: Any?) { model.history.redo() }
    @objc func copy(_ sender: Any?) { model.copy() }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return model.history.canUndo
        case #selector(redo(_:)): return model.history.canRedo
        case #selector(copy(_:)): return model.image != nil
        default: return true
        }
    }

    private var imageRect: CGRect { AnnotationGeometry.fittedRect(imageSize: model.imageSize, in: bounds) }
    private var scale: CGFloat { imageRect.width / max(model.imageSize.width, 1) }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageRect, cursor: model.tool == .select ? .arrow : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.105, green: 0.112, blue: 0.125, alpha: 1).setFill()
        bounds.fill()
        guard let image = model.image, let context = NSGraphicsContext.current?.cgContext, scale > 0 else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 16, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(imageRect)
        context.restoreGState()
        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: scale, y: scale)
        let pixelRect = CGRect(origin: .zero, size: model.imageSize)
        context.clip(to: pixelRect)
        context.draw(image, in: pixelRect)
        AnnotationRenderer.draw(model.annotations, in: context)
        if let draft { AnnotationRenderer.draw([draft], in: context) }
        if model.tool == .select, let selected = model.annotations.first(where: { $0.id == model.selectedID }) {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5 / scale)
            context.setLineDash(phase: 0, lengths: [5 / scale, 4 / scale])
            context.stroke(selected.bounds.insetBy(dx: -5 / scale, dy: -5 / scale))
        }
        context.restoreGState()
    }

    private func point(for event: NSEvent) -> CGPoint {
        AnnotationGeometry.imagePoint(from: convert(event.locationInWindow, from: nil), imageRect: imageRect, imageSize: model.imageSize)
    }

    override func mouseDown(with event: NSEvent) {
        guard model.image != nil, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        dragStart = point
        if model.tool == .select {
            let hit = model.annotations.reversed().first { $0.contains(point, tolerance: 7 / max(scale, 0.01)) }
            model.selectedID = hit?.id
            movingOriginal = hit
            beforeMove = hit == nil ? nil : model.annotations
        } else if model.tool == .text {
            placeText(at: point)
        } else {
            draft = ScreenshotAnnotation(tool: model.tool, points: [point], color: model.color,
                                         strokeWidth: model.strokeWidth)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        var point = point(for: event)
        if let original = movingOriginal, let index = model.annotations.firstIndex(where: { $0.id == original.id }) {
            model.annotations[index] = original.translated(by: CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y), inside: model.imageSize)
        } else if var draft {
            if draft.tool == .pen {
                if let last = draft.points.last, hypot(last.x - point.x, last.y - point.y) < 0.75 / max(scale, 0.01) { return }
                draft.points.append(point)
            } else {
                if event.modifierFlags.contains(.shift) {
                    point = AnnotationGeometry.constrainedEnd(start: dragStart, end: point, tool: draft.tool)
                    point.x = min(max(point.x, 0), model.imageSize.width)
                    point.y = min(max(point.y, 0), model.imageSize.height)
                }
                draft.points = [dragStart, point]
            }
            self.draft = draft
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let draft {
            if draft.tool == .pen || (draft.points.count > 1 && hypot(draft.points[0].x - draft.points[1].x, draft.points[0].y - draft.points[1].y) > 1) {
                model.append(draft)
            }
        }
        if let beforeMove, beforeMove != model.annotations { model.registerUndo(beforeMove, action: "Move Annotation") }
        self.draft = nil
        dragStart = nil
        movingOriginal = nil
        beforeMove = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            draft = nil
            if let beforeMove { model.annotations = beforeMove }
            movingOriginal = nil
            beforeMove = nil
            dragStart = nil
            model.selectedID = nil
            needsDisplay = true
        } else if event.keyCode == 51 || event.keyCode == 117 {
            model.deleteSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            event.modifierFlags.contains(.shift) ? model.history.redo() : model.history.undo()
            needsDisplay = true
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "c" {
            model.copy()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func placeText(at point: CGPoint) {
        let value = model.textToPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { appendText(value, at: point); return }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Add Text"
        alert.informativeText = "Enter the text to place on your screenshot."
        alert.addButton(withTitle: "Add Text")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "Your text"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self?.model.textToPlace = text
            self?.appendText(text, at: point)
        }
    }

    private func appendText(_ text: String, at point: CGPoint) {
        var annotation = ScreenshotAnnotation(tool: .text, points: [point], color: model.color,
                                              strokeWidth: model.strokeWidth, text: text, fontSize: model.fontSize)
        let size = annotation.attributedText.size()
        annotation.points = [CGPoint(x: min(point.x, max(0, model.imageSize.width - size.width)),
                                     y: min(point.y, max(0, model.imageSize.height - size.height)))]
        model.append(annotation)
    }
}
