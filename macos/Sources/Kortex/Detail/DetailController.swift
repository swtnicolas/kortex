import AppKit

private final class BackgroundStack: NSStackView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.background.cgColor
        layer?.borderColor = Palette.line.cgColor
    }
}

final class DetailController: NSViewController {
    private static let width: CGFloat = 372
    private static let inset: CGFloat = 16
    private static let contentWidth = width - inset * 2
    private static let tabKey = "detailTab"

    private static var savedTab: Tab {
        get { UserDefaults.standard.string(forKey: tabKey).flatMap(Tab.init(rawValue:)) ?? .ram }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: tabKey) }
    }

    private let root = BackgroundStack()
    private let tabs = TabsView()
    private let openUsage = DetailRowView(label: "Con la ventana abierta", size: 11)
    private let closedUsage = DetailRowView(label: "Con la ventana cerrada", size: 11)
    private let refresh = HoverButton("Actualizar · ahora")
    private let settingsButton = HoverButton("Ajustes", icon: .settings)

    private var panes: [Tab: NSView] = [:]
    private var ageTimer: Timer?
    private var listTimer: Timer?
    private var lastReading = Date()
    private lazy var settingsPane = makeSettingsPane()
    private lazy var graphics = GraphicsDetailReader()
    private var latest: Reading?
    private var modes: PowerModes?
    private var resizing = false
    private var query = ""
    private let fans: FanControl

    private var memoryPane: MemoryPane? { panes[.ram] as? MemoryPane }
    private var processorPane: ProcessorPane? { panes[.cpu] as? ProcessorPane }
    private var graphicsPane: GraphicsPane? { panes[.gpu] as? GraphicsPane }
    private var temperaturePane: TemperaturePane? { panes[.temperature] as? TemperaturePane }
    private var batteryPane: BatteryPane? { panes[.battery] as? BatteryPane }

    var onRefresh: (() -> Void)?
    var onResize: ((NSSize) -> Void)?
    var onQuit: (() -> Void)?
    var onZones: (() -> [ZoneReading])?

    init(fans: FanControl) {
        self.fans = fans
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.detachesHiddenViews = true
        root.edgeInsets = NSEdgeInsets(top: 10, left: DetailController.inset,
                                       bottom: 8, right: DetailController.inset)

        add(tabs, spacingAfter: 12)
        add(Separator(), spacingAfter: 8)
        add(Label("Consumo de Kortex"), spacingAfter: 3)
        add(openUsage)
        add(closedUsage, spacingAfter: 12)
        add(footer())

        root.widthAnchor.constraint(equalToConstant: DetailController.width).isActive = true
        root.wantsLayer = true
        root.layer?.borderWidth = 0.5
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        view = root

        tabs.onSelect = { [weak self] tab in self?.select(tab) }
        tabs.selected = DetailController.savedTab
        apply(tabs.selected)
    }

    var contentSize: NSSize {
        loadViewIfNeeded()
        root.layoutSubtreeIfNeeded()
        return NSSize(width: DetailController.width, height: height(of: root))
    }

    private func resize() {
        guard !resizing else { return }
        resizing = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            resizing = false
            onResize?(contentSize)
        }
    }

    private func height(of stack: NSStackView) -> CGFloat {
        let visible = stack.arrangedSubviews.filter { !$0.isHidden }
        var height = stack.edgeInsets.top + stack.edgeInsets.bottom
        for (index, subview) in visible.enumerated() {
            height += subview.fittingSize.height
            guard index < visible.count - 1 else { continue }
            let custom = stack.customSpacing(after: subview)
            height += custom > 1e6 ? stack.spacing : custom
        }
        return height
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(showAge),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        ageTimer = timer

        applyInterval()
        loadList()
    }

    func applyInterval() {
        listTimer?.invalidate()
        let interval = Settings.detail
        let list = Timer(timeInterval: interval, target: self,
                         selector: #selector(loadList), userInfo: nil, repeats: true)
        list.tolerance = interval * 0.2
        RunLoop.main.add(list, forMode: .common)
        listTimer = list
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        ageTimer?.invalidate()
        ageTimer = nil
        listTimer?.invalidate()
        listTimer = nil
    }

    @objc private func loadList() {
        switch tabs.selected {
        case .ram:
            Task { [weak self] in
                let groups = await ProcessReader.memory()
                self?.memoryPane?.list.show(groups)
            }
        case .cpu:
            Task { [weak self] in
                let groups = await ProcessReader.processor()
                self?.processorPane?.list.show(groups)
            }
        case .temperature:
            temperaturePane?.show(onZones?() ?? [])
            resize()
        case .battery:
            Task { [weak self] in
                let modes = await BatteryReader.modes()
                self?.modes = modes
                self?.showBattery()
                let groups = await ProcessReader.energy()
                self?.batteryPane?.list.show(groups)
            }
        case .gpu:
            Task { [weak self] in
                guard let detail = await self?.graphics.detail() else { return }
                self?.graphicsPane?.show(detail)
                self?.resize()
                let groups = await ProcessReader.groups(of: detail.processes)
                self?.graphicsPane?.list.show(groups)
            }
        }
    }

    func type(_ text: String) {
        guard visibleList != nil, !(query.isEmpty && text.allSatisfy(\.isWhitespace)) else { return }
        search(query + text)
    }

    func erase() {
        guard visibleList != nil, !query.isEmpty else { return }
        search(String(query.dropLast()))
    }

    func cancel() -> Bool {
        if visibleList?.dismiss() == true { return true }
        guard visibleList != nil, !query.isEmpty else { return false }
        search("")
        return true
    }

    private var visibleList: ProcessListView? {
        tabs.isHidden ? nil : (panes[tabs.selected] as? ListPane)?.list
    }

    private func search(_ text: String) {
        query = text
        visibleList?.filter(text)
    }

    private func showBattery() {
        let degrees = onZones?().first { $0.zone == .battery }?.peak
        batteryPane?.show(latest?.battery, modes: modes, degrees: degrees)
        resize()
    }

    func show(_ reading: Reading) {
        lastReading = Date()
        latest = reading
        showAge()
        tabs.show(reading)
        showReading()
        openUsage.show(selfUsage(footprint: reading.selfFootprint, processor: reading.selfUsage))
        closedUsage.show(selfUsage(footprint: reading.selfClosedFootprint, processor: reading.selfClosedUsage))
        resize()
    }

    private func showReading() {
        guard let reading = latest else { return }
        switch tabs.selected {
        case .ram:
            if let memory = reading.memory { memoryPane?.show(memory) }
        case .cpu:
            processorPane?.show(usage: reading.processor, clusters: reading.clusters)
        case .gpu:
            graphicsPane?.show(reading.graphics)
            graphicsPane?.show(degrees: reading.graphicsTemperature)
        case .battery:
            showBattery()
        case .temperature:
            temperaturePane?.show(temperature: reading.temperature)
        }
    }

    private func select(_ tab: Tab) {
        DetailController.savedTab = tab
        apply(tab)
        loadList()
    }

    private func apply(_ tab: Tab) {
        let visible = pane(for: tab)
        for pane in panes.values {
            (pane as? ListPane)?.list.dismiss()
            pane.isHidden = pane !== visible
        }
        (visible as? ListPane)?.list.filter(query)
        showReading()
        resize()
    }

    private func pane(for tab: Tab) -> NSView {
        if let pane = panes[tab] { return pane }
        let pane: NSView = switch tab {
        case .ram: MemoryPane()
        case .cpu: ProcessorPane()
        case .gpu: GraphicsPane()
        case .temperature: TemperaturePane(fans: fans)
        case .battery: BatteryPane()
        }
        if let list = (pane as? ListPane)?.list {
            list.onLayoutChange = { [weak self] in self?.resize() }
            list.onSearch = { [weak self] text in self?.search(text) }
        }
        (pane as? TemperaturePane)?.onLayoutChange = { [weak self] in self?.resize() }
        add(pane, at: 1, spacingAfter: 12)
        panes[tab] = pane
        return pane
    }

    private func selfUsage(footprint: Double?, processor: Double?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: footprint.map(Format.size) ?? "—", attributes: [
            .font: font, .foregroundColor: Metric.ram.color
        ]))
        text.append(NSAttributedString(string: " RAM · ", attributes: [
            .font: font, .foregroundColor: Palette.caption
        ]))
        let processorText = processor.map { Format.fixed($0, places: 2) + "%" } ?? "—"
        text.append(NSAttributedString(string: processorText, attributes: [
            .font: font, .foregroundColor: Metric.cpu.color
        ]))
        text.append(NSAttributedString(string: " CPU", attributes: [
            .font: font, .foregroundColor: Palette.caption
        ]))
        return text
    }

    @objc private func showAge() {
        let seconds = Int(Date().timeIntervalSince(lastReading))
        refresh.title = seconds < 1 ? "Actualizar · ahora" : "Actualizar · hace \(seconds) s"
    }

    private func showSettings(_ visible: Bool) {
        loadViewIfNeeded()
        if visible { settingsPane.show() }
        tabs.isHidden = visible
        settingsButton.isHidden = visible
        settingsPane.isHidden = !visible
        if visible {
            panes.values.forEach { $0.isHidden = true }
        } else {
            apply(tabs.selected)
        }
        resize()
    }

    private func makeSettingsPane() -> SettingsPane {
        let pane = SettingsPane()
        pane.onBack = { [weak self] in self?.showSettings(false) }
        add(pane, at: 1, spacingAfter: 12)
        return pane
    }

    private func add(_ subview: NSView, at index: Int? = nil, spacingAfter: CGFloat = 0) {
        if let index {
            root.insertArrangedSubview(subview, at: index)
        } else {
            root.addArrangedSubview(subview)
        }
        subview.widthAnchor.constraint(equalToConstant: DetailController.contentWidth).isActive = true
        if spacingAfter > 0 { root.setCustomSpacing(spacingAfter, after: subview) }
    }

    private func footer() -> NSView {
        refresh.action = { [weak self] in self?.onRefresh?() }
        settingsButton.action = { [weak self] in self?.showSettings(true) }

        let right = NSStackView(views: [
            settingsButton,
            HoverButton("Salir", icon: .power) { [weak self] in self?.onQuit?() }
        ])
        right.orientation = .horizontal
        right.alignment = .centerY
        right.spacing = 8
        right.translatesAutoresizingMaskIntoConstraints = false
        refresh.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(refresh)
        container.addSubview(right)
        NSLayoutConstraint.activate([
            refresh.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            refresh.topAnchor.constraint(equalTo: container.topAnchor),
            refresh.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            right.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: refresh.centerYAnchor)
        ])
        return container
    }
}
