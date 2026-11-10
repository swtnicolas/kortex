import AppKit

final class HoverButton: NSView {
    enum Style {
        case link, cancel, accept, force
    }

    private static let gap: CGFloat = 4
    private static let confirmHeight: CGFloat = 24

    private let icon: Icon?
    private let iconSize: CGFloat
    private let font: NSFont
    private let style: Style
    private let tint: NSColor
    private var content = NSAttributedString()
    private var contentWidth: CGFloat = 0
    private var hovering = false

    var title: String {
        didSet {
            guard title != oldValue else { return }
            restyle()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var action: (() -> Void)?

    init(_ title: String, icon: Icon? = nil, iconSize: CGFloat = 13, font: NSFont = .systemFont(ofSize: 12),
         tint: NSColor = Palette.text, style: Style = .link, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.iconSize = iconSize
        self.font = font
        self.style = style
        self.tint = style == .accept || style == .force ? Palette.white : tint
        self.action = action
        super.init(frame: .zero)
        restyle()
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
        let padding: CGFloat = style == .link ? 4 : 10
        let height = style == .link ? max(Label.height(of: font), iconSize) + 2 : HoverButton.confirmHeight
        return NSSize(width: contentWidth + padding * 2, height: height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = style == .link ? 4 : 6
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        if let fill {
            fill.setFill()
            shape.fill()
        }
        if let edge {
            edge.setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }

        var left = ((bounds.width - contentWidth) / 2).rounded()
        if let icon {
            icon.draw(in: NSRect(x: left, y: ((bounds.height - iconSize) / 2).rounded(), width: iconSize, height: iconSize),
                      color: tint)
            left += iconSize + HoverButton.gap
        }
        guard !title.isEmpty else { return }
        let height = Label.height(of: font)
        content.draw(at: NSPoint(x: left, y: ((bounds.height - height) / 2).rounded()))
    }

    private var fill: NSColor? {
        switch style {
        case .link: hovering ? Palette.hover : nil
        case .cancel: hovering ? Palette.cancelHover : nil
        case .accept: hovering ? Palette.acceptHover : Palette.accept
        case .force: hovering ? Palette.forceHover : Palette.force
        }
    }

    private var edge: NSColor? {
        switch style {
        case .link, .cancel: nil
        case .accept: Palette.acceptEdge
        case .force: Palette.forceEdge
        }
    }

    private func restyle() {
        content = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: tint])
        let text = title.isEmpty ? 0 : ceil(content.size().width)
        let image = icon == nil ? 0 : iconSize + (title.isEmpty ? 0 : HoverButton.gap)
        contentWidth = text + image
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityTitle() -> String? { title }

    override func accessibilityPerformPress() -> Bool {
        action?()
        return true
    }
}
