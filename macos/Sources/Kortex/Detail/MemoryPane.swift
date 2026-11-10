import AppKit

final class MemoryPane: NSStackView, ListPane {
    private let title = PaneHeader(color: Metric.ram.color)
    private let bar = ProportionBar()
    private let apps = DetailRowView(label: "Apps", dot: Metric.ram.color)
    private let wired = DetailRowView(label: "Sistema", dot: Palette.wired)
    private let compressed = DetailRowView(label: "Comprimida", dot: Palette.compressed)
    private let cache = DetailRowView(label: "Caché", dot: Palette.cache)
    private let free = DetailRowView(label: "Libre", dot: Palette.free)
    private let swap = DetailRowView(label: "Swap")
    private let pressure = DetailRowView(label: "Presión")
    let list = ProcessListView(format: Format.size)

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0

        for row in [title, bar, apps, wired, compressed, cache, free, swap, pressure, list] as [NSView] {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(6, after: title)
        setCustomSpacing(8, after: bar)
        setCustomSpacing(12, after: pressure)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ snapshot: MemorySnapshot) {
        title.show(Format.percent(snapshot.usage),
                   context: "\(Format.size(snapshot.used)) / \(Format.size(snapshot.total))")
        bar.show([
            .init(fraction: snapshot.apps / snapshot.total, color: Metric.ram.color),
            .init(fraction: snapshot.wired / snapshot.total, color: Palette.wired),
            .init(fraction: snapshot.compressed / snapshot.total, color: Palette.compressed),
            .init(fraction: snapshot.cache / snapshot.total, color: Palette.cache),
            .init(fraction: snapshot.free / snapshot.total, color: Palette.free)
        ])
        apps.show(Format.size(snapshot.apps))
        wired.show(Format.size(snapshot.wired))
        compressed.show(Format.size(snapshot.compressed))
        cache.show(Format.size(snapshot.cache))
        free.show(Format.size(snapshot.free))
        swap.show(Format.size(snapshot.swap),
                  color: snapshot.swap > 0 ? Metric.temperature.color : Palette.text)
        pressure.show(snapshot.pressure.name, color: Palette.pressure(snapshot.pressure))
    }
}
