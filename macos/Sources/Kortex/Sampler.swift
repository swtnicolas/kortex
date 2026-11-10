import AppKit

struct Reading {
    let memory: MemorySnapshot?
    let processor: Double?
    let clusters: [ClusterUsage]
    let graphics: GraphicsSnapshot?
    let battery: BatterySnapshot?
    let temperature: Double?
    let graphicsTemperature: Double?
    let selfFootprint: Double?
    let selfUsage: Double?
    let selfClosedFootprint: Double?
    let selfClosedUsage: Double?

    func value(of metric: Metric) -> Double? {
        switch metric {
        case .ram: memory?.usage
        case .cpu: processor
        case .gpu: graphics?.usage
        case .temperature: temperature
        }
    }
}

@MainActor
final class Sampler: NSObject {
    private static let firstReading: TimeInterval = 1

    private let memory = MemoryReader()
    private let processor = ProcessorReader()
    private let graphics = GraphicsReader()
    private let temperature = TemperatureReader()
    private let own = SelfReader()

    let fans = FanControl()

    private var timer: Timer?
    private var closedFootprint: Double?
    private var usage = SelfUsage()
    private var asleep = false

    var detailOpen: Bool {
        get { usage.detailOpen }
        set { usage.detailOpen = newValue }
    }
    var onReading: ((Reading) -> Void)?

    func start() {
        observeSleep()
        timer?.invalidate()
        let timer = Timer(timeInterval: Sampler.firstReading, target: self,
                          selector: #selector(begin), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        sample()
        repeatEvery()
    }

    func zones() -> [ZoneReading] {
        temperature.zones()
    }

    @objc private func begin() {
        sample()
        repeatEvery()
    }

    func applyInterval() {
        guard timer?.isValid == true else { return }
        repeatEvery()
    }

    private func repeatEvery() {
        timer?.invalidate()
        let interval = Settings.bar
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        sample()
    }

    private func sample() {
        let degrees = temperature.peak()
        fans.follow(degrees)
        guard !asleep else { return }

        let children = fans.helper.map { [$0] } ?? []
        usage.add(own.time(with: children))
        let footprint = own.footprint(with: children)
        if !detailOpen { closedFootprint = footprint }

        onReading?(Reading(
            memory: memory.snapshot(),
            processor: processor.usage(),
            clusters: processor.clusters(),
            graphics: graphics.snapshot(),
            battery: detailOpen ? BatteryReader.snapshot() : nil,
            temperature: degrees,
            graphicsTemperature: temperature.graphicsPeak,
            selfFootprint: footprint,
            selfUsage: usage.latest,
            selfClosedFootprint: closedFootprint,
            selfClosedUsage: usage.closed
        ))
    }

    private func observeSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(pause),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(rest),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume),
                              name: NSWorkspace.didWakeNotification, object: nil)

        let session = DistributedNotificationCenter.default()
        session.addObserver(self, selector: #selector(pause),
                            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        session.addObserver(self, selector: #selector(resume),
                            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func pause() {
        asleep = true
        guard fans.mode != .curve else { return }
        timer?.invalidate()
        timer = nil
    }

    @objc private func rest() {
        asleep = true
        timer?.invalidate()
        timer = nil
        fans.release()
    }

    @objc private func resume() {
        let waking = asleep
        asleep = false
        guard waking || timer?.isValid != true else { return }
        sample()
        repeatEvery()
    }
}
