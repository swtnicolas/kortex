import AppKit

final class TabsView: NSView {
    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let valueFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let inset: CGFloat = 2
    private static let gap: CGFloat = 2
    private static let height: CGFloat = 42

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    private var values: [String] = Tab.allCases.map { _ in "—" }
    private var hovered: Int?

    var selected: Tab = .ram {
        didSet { needsDisplay = true }
    }

    var onSelect: ((Tab) -> Void)?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: TabsView.height)
    }

    func show(_ reading: Reading?) {
        let updated = Tab.allCases.map { $0.text(reading) }
        guard updated != values else { return }
        values = updated
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        for index in Tab.allCases.indices {
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
        guard let index = segment(at: convert(event.locationInWindow, from: nil)) else { return }
        let tab = Tab.allCases[index]
        selected = tab
        onSelect?(tab)
    }

    private func segment(at point: NSPoint) -> Int? {
        let index = Int((point.x - TabsView.inset) / segmentStride)
        return index >= 0 && index < Tab.allCases.count ? index : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.segment.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let titleHeight = ceil(TabsView.titleFont.ascender - TabsView.titleFont.descender)
        let valueHeight = ceil(TabsView.valueFont.ascender - TabsView.valueFont.descender)
        let top = ((bounds.height - titleHeight - valueHeight) / 2).rounded()

        for (index, tab) in Tab.allCases.enumerated() {
            let frame = frame(of: index)
            if tab == selected {
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
            draw(tab.title, font: TabsView.titleFont, color: tab.color,
                 in: NSRect(x: frame.minX, y: top, width: frame.width, height: titleHeight))
            draw(values[index], font: TabsView.valueFont, color: tab.color,
                 in: NSRect(x: frame.minX, y: top + titleHeight, width: frame.width, height: valueHeight))
        }
    }

    private func frame(of index: Int) -> NSRect {
        NSRect(
            x: TabsView.inset + CGFloat(index) * segmentStride,
            y: TabsView.inset,
            width: segmentWidth,
            height: bounds.height - TabsView.inset * 2
        )
    }

    private var segmentWidth: CGFloat {
        let count = CGFloat(Tab.allCases.count)
        return (bounds.width - TabsView.inset * 2 - TabsView.gap * (count - 1)) / count
    }

    private var segmentStride: CGFloat {
        segmentWidth + TabsView.gap
    }

    private func draw(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        text.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: TabsView.centered
        ])
    }
}
