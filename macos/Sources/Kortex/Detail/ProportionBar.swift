import AppKit

final class ProportionBar: NSView {
    struct Segment {
        let fraction: Double
        let color: NSColor
    }

    private var segments: [Segment] = []

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 6)
    }

    func show(_ segments: [Segment]) {
        self.segments = segments
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        Palette.line.setFill()
        shape.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        shape.setClip()
        var x: CGFloat = 0
        for segment in segments {
            let width = (bounds.width * CGFloat(min(max(0, segment.fraction), 1))).rounded()
            segment.color.setFill()
            NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
            x += width
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
