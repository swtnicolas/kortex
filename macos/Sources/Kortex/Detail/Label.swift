import AppKit

final class Label: NSView {
    private let font: NSFont
    private let style: NSParagraphStyle
    private var content = NSAttributedString()
    private var width: CGFloat = 0

    var text = "" {
        didSet { if text != oldValue { restyle() } }
    }

    var color: NSColor {
        didSet { if color != oldValue { restyle() } }
    }

    init(_ text: String = "", font: NSFont = .systemFont(ofSize: 11), color: NSColor = Palette.caption,
         alignment: NSTextAlignment = .left, lineBreakMode: NSLineBreakMode = .byClipping) {
        self.text = text
        self.font = font
        self.color = color
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
        self.style = style
        super.init(frame: .zero)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: Label.height(of: font))
    }

    static func height(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    func show(_ attributed: NSAttributedString) {
        guard !content.isEqual(to: attributed) else { return }
        content = attributed
        changed()
    }

    private func restyle() {
        content = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ])
        changed()
    }

    private func changed() {
        width = ceil(content.size().width * 2) / 2
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        content.draw(in: bounds)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { content.string }
}
