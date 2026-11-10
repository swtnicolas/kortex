import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let barView = MenuBarView()
    private let sampler = Sampler()
    private var statusItem: NSStatusItem?
    private var panel: DetailPanel?
    private var detail: DetailController?
    private var latest: Reading?
    private var outsideClicks: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
        sampler.onReading = { [weak self] reading in self?.show(reading) }
        Settings.onChange = { [weak self] in
            self?.sampler.applyInterval()
            self?.detail?.applyInterval()
            self?.applyDockIcon()
        }
        sampler.start()
    }

    private func applyDockIcon() {
        let policy: NSApplication.ActivationPolicy = Settings.showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    private func show(_ reading: Reading) {
        latest = reading
        detail?.show(reading)
        let texts = Metric.allCases.map { $0.text(reading.value(of: $0)) }
        barView.show(texts)
        let item = statusItem ?? makeStatusItem()
        item.button?.setAccessibilityLabel(zip(Metric.allCases, texts).map { "\($0.label) \($1)" }.joined(separator: ", "))
        guard item.length != barView.width else { return }
        item.length = barView.width
        if let button = item.button { barView.frame = button.bounds }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.addSubview(barView)
        item.button?.target = self
        item.button?.action = #selector(toggleDetail)
        statusItem = item
        pinColorSpaces()
        NotificationCenter.default.addObserver(self, selector: #selector(pinColorSpaces),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        return item
    }

    @objc private func pinColorSpaces() {
        for window in NSApp.windows where window.colorSpace != .sRGB {
            window.colorSpace = .sRGB
        }
    }

    @objc private func toggleDetail() {
        if panel == nil {
            openDetail()
        } else {
            closeDetail()
        }
    }

    private func openDetail() {
        guard let button = statusItem?.button else { return }

        let controller = DetailController(fans: sampler.fans)
        controller.onRefresh = { [weak self] in self?.sampler.refresh() }
        controller.onQuit = { NSApp.terminate(nil) }
        controller.onZones = { [weak self] in self?.sampler.zones() ?? [] }

        let panel = DetailPanel(content: controller, anchor: button)
        controller.onResize = { [weak panel] size in panel?.fit(size) }
        panel.onCancel = { [weak self, weak controller] in
            guard controller?.cancel() != true else { return }
            self?.closeDetail()
        }
        panel.onResignKey = { [weak self] in self?.closeUnlessOnStatusItem() }
        panel.onType = { [weak controller] text in controller?.type(text) }
        panel.onErase = { [weak controller] in controller?.erase() }
        panel.fit(controller.contentSize)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        detail = controller
        sampler.detailOpen = true
        barView.highlighted = true
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessOnStatusItem() }
        }

        if let latest { controller.show(latest) }
        sampler.refresh()
    }

    private func closeUnlessOnStatusItem() {
        guard !pressesStatusItem else { return }
        closeDetail()
    }

    private var pressesStatusItem: Bool {
        guard NSEvent.pressedMouseButtons != 0,
              let button = statusItem?.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    private func closeDetail() {
        guard let panel else { return }
        self.panel = nil
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        panel.onResignKey = nil
        panel.orderOut(nil)
        panel.contentViewController = nil
        detail = nil
        sampler.detailOpen = false
        barView.highlighted = false
    }
}
