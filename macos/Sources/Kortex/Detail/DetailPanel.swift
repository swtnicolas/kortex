import AppKit

final class DetailPanel: NSPanel {
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8
    private static let deleteKey: UInt16 = 51
    private static let typed = CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
        .union(CharacterSet(charactersIn: " "))

    private weak var anchor: NSView?

    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?
    var onType: ((String) -> Void)?
    var onErase: (() -> Void)?

    init(content: NSViewController, anchor: NSView) {
        self.anchor = anchor
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        colorSpace = .sRGB
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        contentViewController = content
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        let text = event.characters ?? ""
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            return super.keyDown(with: event)
        }
        if event.keyCode == DetailPanel.deleteKey {
            onErase?()
        } else if !text.isEmpty, text.unicodeScalars.allSatisfy(DetailPanel.typed.contains) {
            onType?(text)
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    func fit(_ size: NSSize) {
        guard let anchor, let window = anchor.window, let screen = window.screen ?? NSScreen.main else { return }
        let item = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let top = min(item.minY, visible.maxY) - DetailPanel.gap
        let height = min(size.height, top - visible.minY - DetailPanel.margin)
        let left = min(max(item.midX - size.width / 2, visible.minX + DetailPanel.margin),
                       visible.maxX - DetailPanel.margin - size.width)
        let target = NSRect(x: left, y: top - height, width: size.width, height: height)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }
}
