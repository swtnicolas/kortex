import AppKit

final class ToggleView: NSView {
    private static let size = NSSize(width: 32, height: 18)
    private static let knob: CGFloat = 14

    var isOn = false {
        didSet { if isOn != oldValue { needsDisplay = true } }
    }

    var onChange: ((Bool) -> Void)?

    override var intrinsicContentSize: NSSize { ToggleView.size }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        toggle()
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(origin: .zero, size: ToggleView.size)
        (isOn ? Metric.gpu.color : Palette.segmentBorder).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        let inset = (track.height - ToggleView.knob) / 2
        let left = isOn ? track.width - inset - ToggleView.knob : inset
        Palette.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: left, y: inset, width: ToggleView.knob, height: ToggleView.knob)).fill()
    }

    private func toggle() {
        isOn.toggle()
        onChange?(isOn)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .switch }
    override func accessibilityValue() -> Any? { isOn ? 1 : 0 }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }
}
