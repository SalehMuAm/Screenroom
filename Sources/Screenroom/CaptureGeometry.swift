import CoreGraphics

enum CaptureGeometry {
    /// AppKit selections are bottom-left based; ScreenCaptureKit crops from the top-left.
    static func sourceRect(selection: CGRect, displayHeight: CGFloat) -> CGRect {
        CGRect(x: selection.minX, y: displayHeight - selection.maxY,
               width: selection.width, height: selection.height)
    }

    /// H.264 needs even pixel dimensions. Bound the longest edge to 3840 to keep memory low.
    static func recordingSize(points: CGSize, scale: CGFloat) -> CGSize {
        let width = max(2, points.width * max(1, scale))
        let height = max(2, points.height * max(1, scale))
        let reduction = min(1, 3840 / max(width, height))
        return CGSize(width: max(2, floor(width * reduction / 2) * 2),
                      height: max(2, floor(height * reduction / 2) * 2))
    }
}
