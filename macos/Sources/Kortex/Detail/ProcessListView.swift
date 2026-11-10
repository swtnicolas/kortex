import AppKit

@MainActor
protocol ListPane: AnyObject {
    var list: ProcessListView { get }
}

private final class TopClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class RowsView: NSView {
    override var isFlipped: Bool { true }

    var contentHeight: CGFloat {
        subviews.reduce(0) { $0 + $1.intrinsicContentSize.height }
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 0
        for row in subviews {
            let height = row.intrinsicContentSize.height
            row.frame = NSRect(x: 0, y: top, width: bounds.width, height: height)
            top += height
        }
    }
}

private final class EmptyRow: NSView {
    private let label = Label(font: .systemFont(ofSize: 13))

    var text: String {
        get { label.text }
        set { label.text = newValue }
    }

    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ProcessRowView.height)
    }
}

final class ProcessListView: NSStackView {
    private struct Match {
        let group: ProcessGroup
        let children: [ProcessEntry]
        let throughChildren: Bool
    }

    private static let collapsed = 5
    private static let expanded = 50
    private static let maxHeight: CGFloat = 220

    private let format: (Double) -> String
    private let header = Label(lineBreakMode: .byTruncatingTail)
    private let empty = EmptyRow()
    private let search = SearchView()
    private let rows = RowsView()
    private let scroll = NSScrollView()
    private let more = HoverButton("Mostrar más")
    private var height: NSLayoutConstraint?
    private var rowsHeight: NSLayoutConstraint?
    private var pool: [ProcessRowView] = []

    private var groups: [ProcessGroup] = []
    private var matches: [Match] = []
    private var query = ""
    private var open: Set<Int32> = []
    private var folded: Set<Int32> = []
    private var showingAll = false
    private var pending: (pid: Int32, isApp: Bool)?
    private var loaded = false

    var onLayoutChange: (() -> Void)?
    var onSearch: ((String) -> Void)?

    init(format: @escaping (Double) -> String) {
        self.format = format
        super.init(frame: .zero)

        orientation = .vertical
        alignment = .leading
        spacing = 0

        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        search.onClear = { [weak self] in self?.onSearch?("") }
        search.setContentHuggingPriority(.required, for: .horizontal)

        let top = NSStackView(views: [header, search])
        top.orientation = .horizontal
        top.distribution = .fill
        top.alignment = .centerY
        top.spacing = 8

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.backgroundColor = .clear
        scroll.contentView = TopClipView()
        scroll.contentView.drawsBackground = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows

        more.action = { [weak self] in self?.toggleAll() }

        addArrangedSubview(top)
        setCustomSpacing(4, after: top)
        addArrangedSubview(scroll)
        setCustomSpacing(6, after: scroll)
        addArrangedSubview(more)

        for subview in [top, scroll] as [NSView] {
            subview.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        let height = scroll.heightAnchor.constraint(equalToConstant: 0)
        let rowsHeight = rows.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([height, rowsHeight])
        self.height = height
        self.rowsHeight = rowsHeight
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ groups: [ProcessGroup]) {
        self.groups = groups
        loaded = true
        match()
        rebuild()
    }

    func filter(_ text: String) {
        search.query = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != query else { return }
        query = trimmed
        folded = []
        pending = nil
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        match()
        rebuild()
    }

    private func toggleAll() {
        showingAll.toggle()
        rebuild()
    }

    private func toggle(_ pid: Int32) {
        if matches.contains(where: { $0.group.pid == pid && $0.throughChildren }) {
            if folded.contains(pid) { folded.remove(pid) } else { folded.insert(pid) }
        } else {
            if open.contains(pid) { open.remove(pid) } else { open.insert(pid) }
        }
        rebuild()
    }

    @discardableResult
    func dismiss() -> Bool {
        guard pending != nil else { return false }
        pending = nil
        rebuild()
        return true
    }

    private func request(_ pid: Int32, isApp: Bool) {
        if pending?.pid == pid, pending?.isApp == isApp {
            pending = nil
        } else {
            pending = (pid, isApp)
        }
        rebuild()
    }

    private func close(_ targets: [ProcessTarget], force: Bool) {
        ProcessReader.signal(targets, force: force)
        pending = nil
        rebuild()
    }

    private func confirmation(question: String, accept: String, targets: [ProcessTarget]) -> ConfirmView {
        ConfirmView(
            question: question,
            accept: accept,
            onCancel: { [weak self] in _ = self?.dismiss() },
            onAccept: { [weak self] in self?.close(targets, force: false) },
            onForce: { [weak self] in self?.close(targets, force: true) }
        )
    }

    private func match() {
        guard !query.isEmpty else {
            matches = groups.map { Match(group: $0, children: $0.children, throughChildren: false) }
            return
        }
        matches = groups.compactMap { group in
            if group.name.localizedStandardContains(query) {
                return Match(group: group, children: group.children, throughChildren: false)
            }
            let children = group.children.filter { $0.name.localizedStandardContains(query) }
            return children.isEmpty ? nil : Match(group: group, children: children, throughChildren: true)
        }
    }

    private func rebuild() {
        let limit = showingAll ? ProcessListView.expanded : ProcessListView.collapsed
        var views: [NSView] = []
        var used = 0
        func nextRow() -> ProcessRowView {
            defer { used += 1 }
            if used < pool.count { return pool[used] }
            let row = ProcessRowView()
            row.onToggle = { [weak self] pid in self?.toggle(pid) }
            row.onClose = { [weak self] pid, isApp in self?.request(pid, isApp: isApp) }
            pool.append(row)
            return row
        }

        for match in matches.prefix(limit) {
            let group = match.group
            let row = nextRow()
            let expandable = match.throughChildren || group.children.count > 1
            row.show(pid: group.pid, name: group.name, value: format(group.value),
                     isApp: true, expandable: expandable, owned: !group.targets.isEmpty)
            row.expanded = expandable
                && (match.throughChildren ? !folded.contains(group.pid) : open.contains(group.pid))
            row.armed = pending?.pid == group.pid && pending?.isApp == true
            views.append(row)
            if row.armed {
                let several = group.targets.count > 1
                views.append(confirmation(
                    question: several ? "¿Cerrar \(group.name) y todos sus procesos?" : "¿Terminar \(group.name)?",
                    accept: several ? "Cerrar app" : "Terminar proceso",
                    targets: group.targets
                ))
            }
            guard row.expanded else { continue }
            for child in match.children {
                let childRow = nextRow()
                childRow.show(pid: child.pid, name: child.name, value: format(child.value),
                              isApp: false, expandable: false, owned: child.target != nil)
                childRow.expanded = false
                childRow.armed = pending?.pid == child.pid && pending?.isApp == false
                views.append(childRow)
                if childRow.armed {
                    views.append(confirmation(question: "¿Terminar \(child.name)?",
                                              accept: "Terminar proceso",
                                              targets: child.target.map { [$0] } ?? []))
                }
            }
        }
        pool.removeSubrange(used...)
        if loaded && matches.isEmpty {
            empty.text = query.isEmpty ? "Ninguna app en uso" : "Ninguna app coincide"
            views.append(empty)
        }
        rows.subviews = views
        rows.needsLayout = true

        let total = rows.contentHeight
        rowsHeight?.constant = total
        height?.constant = min(total, ProcessListView.maxHeight)
        header.text = loaded ? "Apps · \(min(limit, matches.count)) de \(matches.count)" : "Apps"
        more.title = showingAll ? "Mostrar menos" : "Mostrar más"
        more.isHidden = matches.count <= ProcessListView.collapsed
        onLayoutChange?()
    }
}
