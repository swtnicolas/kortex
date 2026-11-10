import AppKit

final class SearchView: NSView {
    private static let width: CGFloat = 140
    private static let height: CGFloat = 20
    private static let inset: CGFloat = 6
    private static let iconSize: CGFloat = 10
    private static let clearWidth: CGFloat = 18
    private static let placeholder = "Escribe para buscar"

    private static let keepsEnd: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingHead
        return style
    }()

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.text, .paragraphStyle: keepsEnd
    ]

    private static let placeholderAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.caption
    ]

    private let clear = HoverButton("", icon: .clear, iconSize: 10, tint: Palette.caption)

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            clear.isHidden = query.isEmpty
            needsDisplay = true
        }
    }

    var onClear: (() -> Void)?

    init() {
        super.init(frame: .zero)
        clear.action = { [weak self] in self?.onClear?() }
        clear.isHidden = true
        clear.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clear)
        NSLayoutConstraint.activate([
            clear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            clear.centerYAnchor.constraint(equalTo: centerYAnchor),
            clear.widthAnchor.constraint(equalToConstant: SearchView.clearWidth),
            clear.heightAnchor.constraint(equalToConstant: SearchView.height - 2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: SearchView.width, height: SearchView.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.segment.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let icon = NSRect(x: SearchView.inset, y: (bounds.height - SearchView.iconSize) / 2,
                          width: SearchView.iconSize, height: SearchView.iconSize)
        Icon.search.draw(in: icon, color: Palette.caption)

        let left = icon.maxX + 5
        let right = query.isEmpty ? SearchView.inset : SearchView.clearWidth
        let box = NSRect(x: left, y: 0, width: max(0, bounds.width - left - right), height: bounds.height)
        let text = query.isEmpty ? SearchView.placeholder : query
        let attributes = query.isEmpty ? SearchView.placeholderAttributes : SearchView.textAttributes
        let size = text.size(withAttributes: attributes)
        text.draw(in: NSRect(x: box.minX, y: (bounds.height - size.height) / 2, width: box.width, height: size.height),
                  withAttributes: attributes)
    }
}
