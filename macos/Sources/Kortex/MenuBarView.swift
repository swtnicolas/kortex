import AppKit

final class MenuBarView: NSView {
    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let columnGap: CGFloat = 6
    private static let sideInset: CGFloat = 3
    private static let lineGap: CGFloat = 3
    private static let reservedDigits = 2
    private static let digitWidth = ceil("0".size(withAttributes: [.font: valueFont]).width)
    private static let lineHeight = ceil("0".size(withAttributes: [.font: valueFont]).height)
    private static let capsule = NSColor.adaptive(dark: 0xFFFFFF, light: 0x000000, alpha: 0.12)

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    private let labels: [NSAttributedString]
    private let labelWidths: [CGFloat]
    private let valueAttributes: [[NSAttributedString.Key: Any]]
    private var columnWidths: [CGFloat]
    private var texts: [String]
    private var values: [NSAttributedString]

    private(set) var width: CGFloat

    var highlighted = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    init() {
        labels = Metric.allCases.map {
            NSAttributedString(string: $0.label, attributes: MenuBarView.attributes(MenuBarView.labelFont, $0))
        }
        labelWidths = labels.map { ceil($0.size().width) }
        valueAttributes = Metric.allCases.map { MenuBarView.attributes(MenuBarView.valueFont, $0) }
        columnWidths = labelWidths
        texts = Array(repeating: "", count: Metric.allCases.count)
        values = texts.map { NSAttributedString(string: $0) }
        width = MenuBarView.total(of: labelWidths)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ newTexts: [String]) {
        guard newTexts != texts else { return }
        texts = newTexts
        values = zip(newTexts, valueAttributes).map { NSAttributedString(string: $0, attributes: $1) }
        columnWidths = zip(labelWidths, zip(newTexts, values)).map { label, value in
            let digits = value.0.reduce(0) { $1.isNumber ? $0 + 1 : $0 }
            let reserve = CGFloat(max(0, MenuBarView.reservedDigits - digits)) * MenuBarView.digitWidth
            return ceil(max(label, value.1.size().width + reserve))
        }
        width = MenuBarView.total(of: columnWidths)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            MenuBarView.capsule.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }

        let labelCap = MenuBarView.labelFont.capHeight
        let valueCap = MenuBarView.valueFont.capHeight
        let inkHeight = labelCap + MenuBarView.lineGap + valueCap
        let labelBaseline = ((bounds.height - inkHeight) / 2 + labelCap).rounded()
        let valueBaseline = (labelBaseline + MenuBarView.lineGap + valueCap).rounded()
        let labelTop = labelBaseline - MenuBarView.labelFont.ascender
        let valueTop = valueBaseline - MenuBarView.valueFont.ascender

        var x = MenuBarView.sideInset
        for index in labels.indices {
            let columnWidth = columnWidths[index]
            labels[index].draw(in: NSRect(x: x, y: labelTop, width: columnWidth, height: MenuBarView.lineHeight))
            values[index].draw(in: NSRect(x: x, y: valueTop, width: columnWidth, height: MenuBarView.lineHeight))
            x += columnWidth + MenuBarView.columnGap
        }
    }

    private static func total(of widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + columnGap * CGFloat(widths.count - 1) + sideInset * 2
    }

    private static func attributes(_ font: NSFont, _ metric: Metric) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: metric.color, .paragraphStyle: centered]
    }
}
