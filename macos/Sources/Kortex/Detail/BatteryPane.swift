import AppKit

final class BatteryPane: NSStackView, ListPane {
    private let title = PaneHeader(color: Palette.text)
    private let bar = ProportionBar()
    private let state = DetailRowView(label: "")
    private let currentMode = DetailRowView(label: "Modo de energía")
    private let otherMode = DetailRowView(label: "")
    let list = ProcessListView(format: { Format.watts($0, places: 2) })

    private let health = DetailRowView(label: "Salud")
    private let cycles = DetailRowView(label: "Ciclos")
    private let capacity = DetailRowView(label: "Capacidad actual · diseño")
    private let temperature = DetailRowView(label: "Temperatura")

    private let systemPower = DetailRowView(label: "Consumo del sistema")
    private let batteryPower = DetailRowView(label: "Batería")
    private let current = DetailRowView(label: "Voltaje · corriente")

    private let adapter = DetailRowView(label: "")
    private let adapterCurrent = DetailRowView(label: "Voltaje · corriente")
    private let adapterHeading = Label("Adaptador")

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0

        let rows: [NSView] = [
            title, bar, state, currentMode, otherMode, list,
            Label("Estado"), health, cycles, capacity, temperature,
            Label("Energía"), systemPower, batteryPower, current,
            adapterHeading, adapter, adapterCurrent
        ]
        for row in rows {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(6, after: title)
        setCustomSpacing(8, after: bar)
        for row in [otherMode, list, temperature, current] as [NSView] {
            setCustomSpacing(12, after: row)
        }
        for row in rows where row is Label {
            setCustomSpacing(4, after: row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ snapshot: BatterySnapshot?, modes: PowerModes?, degrees: Double?) {
        guard let snapshot else {
            title.show("—")
            return
        }
        title.show(Format.percent(snapshot.percentage))
        bar.show([.init(fraction: snapshot.percentage / 100, color: Metric.gpu.color)])

        state.show(label: snapshot.state)
        state.show(snapshot.minutesRemaining.map(BatteryPane.duration) ?? "—")

        if let modes {
            currentMode.show(snapshot.connected ? modes.adapter : modes.battery)
            otherMode.show(label: snapshot.connected ? "Modo con batería" : "Modo conectado")
            otherMode.show(snapshot.connected ? modes.battery : modes.adapter)
        }
        otherMode.isHidden = modes == nil
        currentMode.isHidden = modes == nil

        health.show("\(Format.percent(snapshot.health)) · \(snapshot.health >= 80 ? "Normal" : "Reemplazar pronto")")
        cycles.show("\(snapshot.cycles) / \(snapshot.designCycles)")
        capacity.show("\(Int(snapshot.capacity)) · \(Int(snapshot.designCapacity)) mAh")
        temperature.show(degrees.map { Format.degrees($0, places: 1) } ?? "—")
        temperature.isHidden = degrees == nil

        systemPower.show(Format.watts(snapshot.systemWatts))
        batteryPower.show(Format.watts(snapshot.batteryWatts))
        current.show("\(Format.decimal(snapshot.volts)) V · \(Int(snapshot.milliamps)) mA")

        if let plug = snapshot.adapter {
            let reported = plug.delivered > 0
            adapter.show(label: plug.name)
            adapter.show("\(reported ? Format.decimal(plug.delivered, places: 1) : "—") / \(Format.watts(plug.watts))")
            adapterCurrent.show(reported ? "\(Format.decimal(plug.volts)) V · \(Format.decimal(plug.amps)) A" : "—")
        }
        adapterHeading.isHidden = snapshot.adapter == nil
        adapter.isHidden = snapshot.adapter == nil
        adapterCurrent.isHidden = snapshot.adapter == nil
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
