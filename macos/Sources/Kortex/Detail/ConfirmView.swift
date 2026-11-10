import AppKit

final class ConfirmView: NSView {
    private static let inset: CGFloat = 10
    private static let spacing: CGFloat = 8
    private static let font = NSFont.systemFont(ofSize: 12)

    private let question: NSAttributedString
    private let buttons: NSStackView

    init(question: String, accept: String,
         onCancel: @escaping () -> Void,
         onAccept: @escaping () -> Void,
         onForce: @escaping () -> Void) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        self.question = NSAttributedString(string: question, attributes: [
            .font: ConfirmView.font, .foregroundColor: Palette.text, .paragraphStyle: style
        ])
        buttons = NSStackView(views: [
            HoverButton("Cancelar", style: .cancel, action: onCancel),
            HoverButton(accept, style: .accept, action: onAccept),
            HoverButton("Forzar cierre", style: .force, action: onForce)
        ])
        super.init(frame: .zero)

        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ConfirmView.inset),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ConfirmView.inset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let width = (superview?.bounds.width ?? bounds.width) - ConfirmView.inset * 2
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ConfirmView.inset + textHeight(width) + ConfirmView.spacing
                          + buttons.fittingSize.height + ConfirmView.inset)
    }

    private func textHeight(_ width: CGFloat) -> CGFloat {
        guard width > 0 else { return Label.height(of: ConfirmView.font) }
        let box = question.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(box.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width - ConfirmView.inset * 2
        question.draw(with: NSRect(x: ConfirmView.inset, y: ConfirmView.inset,
                                   width: width, height: textHeight(width)),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { question.string }
}
