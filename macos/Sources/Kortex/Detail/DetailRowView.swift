import AppKit

final class Separator: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 0.5)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.line.setFill()
        bounds.fill()
    }
}

final class DetailRowView: NSView {
    private static let height: CGFloat = 20
    private static let dotSize: CGFloat = 10
    private static let dotGap: CGFloat = 7
    private static let gap: CGFloat = 8

    private static let truncating: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private let font: NSFont
    private let dot: NSColor?
    private let color: NSColor
    private var valueColor: NSColor
    private var labelText: NSAttributedString
    private var valueText = NSAttributedString()

    init(label: String, dot: NSColor? = nil, color: NSColor = Palette.text,
         weight: NSFont.Weight = .regular, size: CGFloat = 13) {
        font = NSFont.systemFont(ofSize: size, weight: weight)
        self.dot = dot
        self.color = color
        valueColor = color
        labelText = NSAttributedString()
        super.init(frame: .zero)
        labelText = attributed(label, color: color, style: DetailRowView.truncating)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DetailRowView.height)
    }

    func show(_ value: String, color: NSColor? = nil) {
        if let color { valueColor = color }
        show(attributed(value, color: valueColor))
    }

    func show(_ value: NSAttributedString) {
        guard !valueText.isEqual(to: value) else { return }
        valueText = value
        needsDisplay = true
    }

    func show(label: String) {
        guard labelText.string != label else { return }
        labelText = attributed(label, color: color, style: DetailRowView.truncating)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        var left: CGFloat = 0
        if let dot {
            dot.setFill()
            let box = NSRect(x: 0, y: (bounds.height - DetailRowView.dotSize) / 2,
                             width: DetailRowView.dotSize, height: DetailRowView.dotSize)
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            left = DetailRowView.dotSize + DetailRowView.dotGap
        }

        let height = Label.height(of: font)
        let top = ((bounds.height - height) / 2).rounded()
        let valueWidth = ceil(valueText.size().width)
        valueText.draw(at: NSPoint(x: bounds.width - valueWidth, y: top))
        let labelWidth = max(0, bounds.width - left - valueWidth - DetailRowView.gap)
        labelText.draw(in: NSRect(x: left, y: top, width: labelWidth, height: height))
    }

    private func attributed(_ text: String, color: NSColor,
                            style: NSParagraphStyle = .default) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { labelText.string }
    override func accessibilityValue() -> Any? { valueText.string }
}
