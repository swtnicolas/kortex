import AppKit

final class GraphicsPane: NSStackView, ListPane {
    private let title = PaneHeader(color: Metric.gpu.color)
    private let bar = ProportionBar()
    private let split = DetailRowView(label: "Renderizado · Tiler")
    private let frequency = DetailRowView(label: "Frecuencia actual · máxima")
    private let power = DetailRowView(label: "Consumo")
    private let memory = DetailRowView(label: "Memoria en uso · asignada")
    private let maximum = DetailRowView(label: "Máximo para GPU")
    private let temperature = DetailRowView(label: "Temperatura")
    private let cores = DetailRowView(label: "Núcleos")
    let list = ProcessListView(format: Format.share)

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0

        for row in [title, bar, split, frequency, power, memory, maximum, temperature, cores, list] as [NSView] {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(6, after: title)
        setCustomSpacing(8, after: bar)
        setCustomSpacing(12, after: cores)
        for row in [frequency, power, temperature] {
            row.show("—")
        }
    }

    func show(_ detail: GraphicsDetail) {
        frequency.show(detail.megahertz > 0
            ? "\(Format.gigahertz(detail.megahertz)) · \(Format.gigahertz(detail.maximumMegahertz)) GHz"
            : "—")
        power.show(Format.watts(detail.watts))
    }

    func show(degrees: Double?) {
        temperature.show(degrees.map { Format.degrees($0) } ?? "—")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ snapshot: GraphicsSnapshot?) {
        guard let snapshot else {
            title.show("—")
            return
        }
        title.show(Format.percent(snapshot.usage), context: snapshot.name)
        bar.show([.init(fraction: snapshot.usage / 100, color: Metric.gpu.color)])
        split.show("\(Format.percent(snapshot.renderer)) · \(Format.percent(snapshot.tiler))")
        memory.show("\(Format.size(snapshot.inUse)) · \(Format.size(snapshot.allocated))")
        maximum.show(snapshot.maximum > 0 ? Format.size(snapshot.maximum) : "—")
        cores.show(snapshot.cores > 0 ? "\(snapshot.cores)" : "—")
    }
}
