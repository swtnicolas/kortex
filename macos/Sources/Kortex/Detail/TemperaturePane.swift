import AppKit

final class TemperaturePane: NSStackView {
    private let title = PaneHeader(color: Metric.temperature.color)
    private let zonesCaption = Label("Zonas · máximo · promedio")
    private let rows: [TemperatureZone: DetailRowView]

    private let fansCaption = Label("Ventiladores")
    private var speeds: [DetailRowView] = []
    private let modes = SegmentedView(["Automático", "Según temperatura"])
    private let curve = FanCurveView()
    private let problem = Label(font: .systemFont(ofSize: 12))

    private let fans: FanControl
    private let reader = FanReader()

    var onLayoutChange: (() -> Void)?

    init(fans: FanControl) {
        self.fans = fans
        rows = Dictionary(uniqueKeysWithValues: TemperatureZone.allCases.map {
            ($0, DetailRowView(label: $0.title))
        })
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        speeds = (0..<reader.count).map { DetailRowView(label: "Ventilador \($0 + 1)") }

        modes.onSelect = { [weak self] index in self?.pick(index) }

        curve.onChange = { [weak self] range in self?.fans.range = range }

        var views: [NSView] = [title, zonesCaption]
        views.append(contentsOf: TemperatureZone.allCases.compactMap { rows[$0] })
        let lastZone = views[views.count - 1]
        views.append(fansCaption)
        views.append(contentsOf: speeds as [NSView])
        views.append(contentsOf: [modes, curve, problem])
        for row in views {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(12, after: title)
        setCustomSpacing(4, after: zonesCaption)
        setCustomSpacing(12, after: lastZone)
        setCustomSpacing(4, after: fansCaption)
        if let last = speeds.last { setCustomSpacing(6, after: last) }
        setCustomSpacing(6, after: modes)
        setCustomSpacing(4, after: curve)

        showFans()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ readings: [ZoneReading]) {
        for zone in TemperatureZone.allCases {
            guard let row = rows[zone] else { continue }
            guard let reading = readings.first(where: { $0.zone == zone }) else {
                row.isHidden = true
                continue
            }
            row.isHidden = false
            row.show("\(Format.degrees(reading.peak, places: 1)) · \(Format.degrees(reading.average, places: 1))")
        }
        showFans()
    }

    func show(temperature: Double?) {
        title.show(temperature.map { Format.degrees($0) } ?? "—", context: "Máximo de CPU y GPU")
        curve.temperature = temperature
    }

    private func showFans() {
        let current = reader.current()
        fansCaption.isHidden = current.isEmpty
        modes.isHidden = current.isEmpty
        for row in speeds {
            row.isHidden = current.isEmpty
        }
        for (row, speed) in zip(speeds, current) {
            row.show(speed.map(TemperaturePane.rpm) ?? "—")
        }
        modes.selected = fans.mode == .curve ? 1 : 0
        curve.speeds = reader.limits
        showCurve()
    }

    private func showCurve() {
        let visible = fans.mode == .curve && !modes.isHidden
        curve.isHidden = !visible
        curve.range = fans.range
        let trouble = visible ? trouble() : nil
        problem.isHidden = trouble == nil
        guard let trouble else { return }
        problem.text = trouble.text
        problem.color = trouble.color
    }

    private func trouble() -> (text: String, color: NSColor)? {
        switch fans.problem {
        case .missing: ("Falta el ayudante: scripts/install-fans.sh", Metric.temperature.color)
        case .failed(2): ("El ayudante no tiene root", Metric.cpu.color)
        case .failed(5): ("El SMC rechazó el cambio", Metric.cpu.color)
        case .failed(let code): ("Falló el ayudante (\(code))", Metric.cpu.color)
        case nil: fans.installed
            ? nil
            : ("Falta el ayudante: scripts/install-fans.sh", Metric.temperature.color)
        }
    }

    private func pick(_ index: Int) {
        fans.mode = index == 1 ? .curve : .automatic
        showCurve()
        onLayoutChange?()
    }

    private static func rpm(_ speed: Double) -> String {
        speed > 0 ? "\(Int(speed.rounded())) RPM" : "Parado"
    }
}
