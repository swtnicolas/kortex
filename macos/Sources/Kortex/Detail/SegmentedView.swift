import AppKit

private final class SegmentElement: NSAccessibilityElement {
    private let index: Int
    private weak var owner: SegmentedView?

    init(index: Int, owner: SegmentedView) {
        self.index = index
        self.owner = owner
        super.init()
    }

    override func accessibilityValue() -> Any? {
        let owner = self.owner, index = self.index
        let selected = MainActor.assumeIsolated { owner?.selected == index }
        return selected ? 1 : 0
    }

    override func accessibilityPerformPress() -> Bool {
        let owner = self.owner, index = self.index
        MainActor.assumeIsolated { owner?.choose(index) }
        return true
    }
}

final class SegmentedView: NSView {
    private static let font = NSFont.systemFont(ofSize: 12)
    private static let inset: CGFloat = 2
    private static let gap: CGFloat = 2
    private static let padding: CGFloat = 4

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: Palette.text, .paragraphStyle: centered
    ]

    private let labels: [String]
    private var hovered: Int?

    var selected = 0 {
        didSet { if selected != oldValue { needsDisplay = true } }
    }

    var onSelect: ((Int) -> Void)?

    init(_ labels: [String]) {
        self.labels = labels
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let height = Label.height(of: SegmentedView.font) + (SegmentedView.inset + SegmentedView.padding) * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        for index in labels.indices {
            addTrackingArea(NSTrackingArea(
                rect: frame(of: index),
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["segment": index]
            ))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = event.trackingArea?.userInfo?["segment"] as? Int
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hovered == event.trackingArea?.userInfo?["segment"] as? Int else { return }
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = labels.indices.first(where: { frame(of: $0).contains(point) }) else { return }
        choose(index)
    }

    func choose(_ index: Int) {
        selected = index
        onSelect?(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.segment.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let height = Label.height(of: SegmentedView.font)
        for (index, label) in labels.enumerated() {
            let frame = frame(of: index)
            if index == selected {
                let shape = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
                Palette.segmentSelected.setFill()
                shape.fill()
                Palette.segmentBorder.setStroke()
                shape.lineWidth = 0.5
                shape.stroke()
            } else if index == hovered {
                Palette.segmentHover.setFill()
                NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
            }
            label.draw(in: NSRect(x: frame.minX, y: frame.minY + ((frame.height - height) / 2).rounded(),
                                  width: frame.width, height: height),
                       withAttributes: SegmentedView.attributes)
        }
    }

    private func frame(of index: Int) -> NSRect {
        let count = CGFloat(labels.count)
        let width = (bounds.width - SegmentedView.inset * 2 - SegmentedView.gap * (count - 1)) / count
        return NSRect(
            x: SegmentedView.inset + CGFloat(index) * (width + SegmentedView.gap),
            y: SegmentedView.inset,
            width: width,
            height: bounds.height - SegmentedView.inset * 2
        )
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }

    override func accessibilityChildren() -> [Any]? {
        labels.indices.map { index in
            let element = SegmentElement(index: index, owner: self)
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(labels[index])
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame(of: index))
            return element
        }
    }
}
