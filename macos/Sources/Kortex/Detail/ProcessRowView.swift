import AppKit

final class ProcessRowView: NSView {
    static let height: CGFloat = 24

    private static let font = NSFont.systemFont(ofSize: 13)
    private static let valueWidth: CGFloat = 78
    private static let chevronWidth: CGFloat = 14
    private static let childIndent: CGFloat = 20

    private static let actionWidth: CGFloat = 24

    private static let nameStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private static let valueStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    private var pid: Int32 = 0
    private var name = ""
    private var value = ""
    private var isApp = true
    private var expandable = true
    private var owned = false
    private var hovering = false

    var expanded = false {
        didSet { if expanded != oldValue { needsDisplay = true } }
    }

    var armed = false {
        didSet { if armed != oldValue { needsDisplay = true } }
    }

    var onToggle: ((Int32) -> Void)?
    var onClose: ((Int32, Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ProcessRowView.height)
    }

    func show(pid: Int32, name: String, value: String,
              isApp: Bool, expandable: Bool, owned: Bool) {
        guard pid != self.pid || name != self.name || value != self.value
            || isApp != self.isApp || expandable != self.expandable
            || owned != self.owned else { return }
        self.pid = pid
        self.name = name
        self.value = value
        self.isApp = isApp
        self.expandable = expandable
        self.owned = owned
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hovering = false
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x >= bounds.width - ProcessRowView.actionWidth {
            if owned { onClose?(pid, isApp) }
            return
        }
        guard isApp, expandable else { return }
        onToggle?(pid)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || armed {
            Palette.hover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }

        let font = ProcessRowView.font
        var left = isApp ? CGFloat(0) : ProcessRowView.childIndent

        if !isApp {
            Palette.caption.setFill()
            NSRect(x: (ProcessRowView.chevronWidth / 2).rounded(), y: 0, width: 1, height: bounds.height).fill()
        }

        if isApp {
            if expandable {
                let size = NSSize(width: 9, height: 9)
                let box = NSRect(
                    x: left + (ProcessRowView.chevronWidth - size.width) / 2,
                    y: (bounds.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                (expanded ? Icon.expanded : Icon.collapsed).draw(in: box, color: Palette.caption)
            }
            left += ProcessRowView.chevronWidth
        }

        let baseline = ((bounds.height - font.capHeight) / 2).rounded()
        let columns = ProcessRowView.valueWidth + ProcessRowView.actionWidth
        let nameBox = NSRect(
            x: left,
            y: baseline - font.ascender + font.capHeight,
            width: max(0, bounds.width - left - columns - 8),
            height: font.ascender - font.descender
        )
        name.draw(in: nameBox, withAttributes: [
            .font: font, .foregroundColor: Palette.text, .paragraphStyle: ProcessRowView.nameStyle
        ])

        value.draw(in: NSRect(x: bounds.width - columns, y: nameBox.minY,
                              width: ProcessRowView.valueWidth, height: nameBox.height),
                   withAttributes: [
                       .font: font, .foregroundColor: Palette.text, .paragraphStyle: ProcessRowView.valueStyle
                   ])

        guard hovering || armed else { return }
        let tint = armed ? Metric.cpu.color : Palette.caption
        let size = NSSize(width: 10, height: 10)
        (owned ? Icon.close : Icon.lock).draw(in: NSRect(
            x: bounds.width - ProcessRowView.actionWidth + (ProcessRowView.actionWidth - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ), color: tint)
    }
}
