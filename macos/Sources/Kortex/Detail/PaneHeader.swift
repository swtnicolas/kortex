import AppKit

final class PaneHeader: NSView {
    private static let valueFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private static let contextFont = NSFont.systemFont(ofSize: 13)

    private let color: NSColor
    private var value = NSAttributedString()
    private var context = NSAttributedString()

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Label.height(of: PaneHeader.valueFont))
    }

    func show(_ value: String, context: String = "") {
        let valueText = NSAttributedString(string: value, attributes: [
            .font: PaneHeader.valueFont, .foregroundColor: color
        ])
        let contextText = NSAttributedString(string: context, attributes: [
            .font: PaneHeader.contextFont, .foregroundColor: Palette.text
        ])
        guard !valueText.isEqual(to: self.value) || !contextText.isEqual(to: self.context) else { return }
        self.value = valueText
        self.context = contextText
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let valueFont = PaneHeader.valueFont
        let contextFont = PaneHeader.contextFont
        let baseline = ((bounds.height - Label.height(of: valueFont)) / 2).rounded() + valueFont.ascender
        value.draw(at: NSPoint(x: 0, y: baseline - valueFont.ascender))
        let width = ceil(context.size().width)
        context.draw(at: NSPoint(x: bounds.width - width, y: baseline - contextFont.ascender))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? {
        context.length > 0 ? "\(value.string), \(context.string)" : value.string
    }
}
