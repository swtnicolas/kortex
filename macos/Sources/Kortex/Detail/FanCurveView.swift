import AppKit

final class FanCurveView: NSView {
    private enum Elbow {
        case start, full
    }

    private enum Side {
        case middle, before, after
    }

    private static let gutter: CGFloat = 36
    private static let inset: CGFloat = 7
    private static let top: CGFloat = 20
    private static let base: CGFloat = 96
    private static let bottom: CGFloat = 108
    private static let tall: CGFloat = 126
    private static let knob: CGFloat = 14
    private static let halo: CGFloat = 20
    private static let dot: CGFloat = 7
    private static let marker: CGFloat = 2
    private static let gap: CGFloat = 11
    private static let chip: CGFloat = 15
    private static let ruleStep: Double = 2000

    var range = FanControl.standardRange {
        didSet { redraw(range != oldValue) }
    }

    var temperature: Double? {
        didSet { redraw(temperature != oldValue) }
    }

    var speeds: ClosedRange<Double>? {
        didSet { redraw(speeds != oldValue) }
    }

    var onChange: ((ClosedRange<Double>) -> Void)?

    private var dragging: Elbow?
    private var hovering: Elbow?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: FanCurveView.tall)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        for elbow in [Elbow.start, .full] {
            let center = point(of: elbow)
            addCursorRect(NSRect(x: center.x - FanCurveView.halo / 2, y: 0,
                                 width: FanCurveView.halo, height: FanCurveView.bottom),
                          cursor: .resizeLeftRight)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let elbow = nearest(to: convert(event.locationInWindow, from: nil).x)
        redraw(elbow != hovering)
        hovering = elbow
    }

    override func mouseExited(with event: NSEvent) {
        hovering = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil).x
        dragging = nearest(to: point)
        move(to: point)
    }

    override func mouseDragged(with event: NSEvent) {
        move(to: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for rule in rules {
            Palette.line.setFill()
            NSRect(x: left, y: y(of: rule), width: right - left, height: 0.5).fill()
            let text = "\(Int(rule))"
            let size = text.size(withAttributes: FanCurveView.axis)
            text.draw(at: NSPoint(x: FanCurveView.gutter - 6 - size.width, y: y(of: rule) - size.height / 2),
                      withAttributes: FanCurveView.axis)
        }

        let start = point(of: .start)
        let full = point(of: .full)

        let system = NSBezierPath()
        system.move(to: NSPoint(x: left, y: FanCurveView.bottom))
        system.line(to: NSPoint(x: start.x, y: FanCurveView.bottom))
        system.lineWidth = 1.5
        Palette.caption.setStroke()
        system.stroke()

        let curve = NSBezierPath()
        curve.move(to: start)
        curve.line(to: full)
        curve.line(to: NSPoint(x: right, y: full.y))
        let area = curve.copy() as! NSBezierPath
        area.line(to: NSPoint(x: right, y: FanCurveView.base))
        area.line(to: NSPoint(x: start.x, y: FanCurveView.base))
        area.close()
        Palette.curveArea.setFill()
        area.fill()
        curve.lineWidth = 2
        curve.lineJoinStyle = .round
        Metric.temperature.color.setStroke()
        curve.stroke()

        caption("Empiezan a subir", at: left, aligned: .left)
        caption("Llegan al máximo", at: right, aligned: .right)

        if let temperature {
            Palette.text.setFill()
            let line = NSRect(x: x(of: temperature) - FanCurveView.marker / 2, y: 14,
                              width: FanCurveView.marker, height: FanCurveView.bottom - 12)
            NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
        }

        chip(reading, at: NSPoint(x: x(of: temperature ?? range.lowerBound), y: 7), side: .middle)
        chip(Format.degrees(range.lowerBound), at: start, side: .before)
        chip(Format.degrees(range.upperBound), at: full, side: .after)

        if let temperature, temperature >= range.lowerBound {
            let center = NSPoint(x: x(of: temperature), y: y(of: asked(at: temperature)))
            Metric.temperature.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - FanCurveView.dot / 2, y: center.y - FanCurveView.dot / 2,
                                        width: FanCurveView.dot, height: FanCurveView.dot)).fill()
        }

        for (elbow, center) in [(Elbow.start, start), (Elbow.full, full)] {
            if elbow == dragging || (dragging == nil && elbow == hovering) {
                Palette.hover.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - FanCurveView.halo / 2, y: center.y - FanCurveView.halo / 2,
                                            width: FanCurveView.halo, height: FanCurveView.halo)).fill()
            }
            let knob = NSRect(x: center.x - FanCurveView.knob / 2, y: center.y - FanCurveView.knob / 2,
                              width: FanCurveView.knob, height: FanCurveView.knob)
            Palette.white.setFill()
            NSBezierPath(ovalIn: knob).fill()
            let edge = NSBezierPath(ovalIn: knob.insetBy(dx: 0.25, dy: 0.25))
            edge.lineWidth = 0.5
            Palette.segmentBorder.setStroke()
            edge.stroke()
        }
    }

    private var reading: String {
        guard let temperature else { return "—" }
        guard temperature >= range.lowerBound else { return Format.degrees(temperature) }
        return "\(Format.degrees(temperature)) · \(Int(asked(at: temperature).rounded())) RPM"
    }

    private var rules: [Double] {
        guard let speeds else { return [] }
        let first = (speeds.lowerBound / FanCurveView.ruleStep).rounded(.up) * FanCurveView.ruleStep
        return [0, speeds.lowerBound]
            + stride(from: first, to: speeds.upperBound, by: FanCurveView.ruleStep)
            + [speeds.upperBound]
    }

    private var left: CGFloat { FanCurveView.gutter }
    private var right: CGFloat { max(left + 1, bounds.width - FanCurveView.inset) }

    private func asked(at temperature: Double) -> Double {
        guard let speeds else { return 0 }
        let fraction = (temperature - range.lowerBound) / (range.upperBound - range.lowerBound)
        return speeds.lowerBound + (speeds.upperBound - speeds.lowerBound) * min(max(fraction, 0), 1)
    }

    private func x(of degrees: Double) -> CGFloat {
        let scale = FanControl.scale
        let fraction = (degrees - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
        return left + (right - left) * CGFloat(min(max(fraction, 0), 1))
    }

    private func y(of rpm: Double) -> CGFloat {
        guard let speeds, rpm > speeds.lowerBound else {
            return rpm > 0 ? FanCurveView.base : FanCurveView.bottom
        }
        let fraction = (rpm - speeds.lowerBound) / (speeds.upperBound - speeds.lowerBound)
        return FanCurveView.base - (FanCurveView.base - FanCurveView.top) * CGFloat(min(max(fraction, 0), 1))
    }

    private func point(of elbow: Elbow) -> NSPoint {
        switch elbow {
        case .start: NSPoint(x: x(of: range.lowerBound), y: y(of: speeds?.lowerBound ?? 0))
        case .full: NSPoint(x: x(of: range.upperBound), y: FanCurveView.top)
        }
    }

    private func degrees(at x: CGFloat) -> Double {
        let scale = FanControl.scale
        let fraction = Double((x - left) / (right - left))
        return (scale.lowerBound + (scale.upperBound - scale.lowerBound) * min(max(fraction, 0), 1)).rounded()
    }

    private func nearest(to x: CGFloat) -> Elbow {
        let degrees = degrees(at: x)
        return abs(degrees - range.lowerBound) <= abs(degrees - range.upperBound) ? .start : .full
    }

    private func move(to x: CGFloat) {
        guard let dragging else { return }
        let value = degrees(at: x)
        switch dragging {
        case .start: range = min(value, range.upperBound - FanControl.shortestSpan)...range.upperBound
        case .full: range = range.lowerBound...max(value, range.lowerBound + FanControl.shortestSpan)
        }
        onChange?(range)
    }

    private func chip(_ text: String, at center: NSPoint, side: Side) {
        let size = text.size(withAttributes: FanCurveView.value)
        let width = size.width + 8
        var origin: CGFloat = switch side {
        case .middle: center.x - width / 2
        case .before: center.x - FanCurveView.gap - width
        case .after: center.x + FanCurveView.gap
        }
        if side == .before, origin < left { origin = center.x + FanCurveView.gap }
        if side == .after, origin + width > right { origin = center.x - FanCurveView.gap - width }
        origin = min(right - width, max(left, origin))

        let box = NSRect(x: origin, y: center.y - FanCurveView.chip / 2, width: width, height: FanCurveView.chip)
        Palette.background.setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                  withAttributes: FanCurveView.value)
    }

    private func caption(_ text: String, at x: CGFloat, aligned: NSTextAlignment) {
        let size = text.size(withAttributes: FanCurveView.axis)
        text.draw(at: NSPoint(x: aligned == .left ? x : x - size.width, y: FanCurveView.tall - size.height - 1),
                  withAttributes: FanCurveView.axis)
    }

    private func redraw(_ changed: Bool) {
        guard changed else { return }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private static let axis: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: Palette.caption
    ]

    private static let value: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: Palette.text
    ]
}
