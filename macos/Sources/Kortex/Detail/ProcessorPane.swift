import AppKit

final class ProcessorPane: NSStackView, ListPane {
    private let title = PaneHeader(color: Metric.cpu.color)
    private let bar = ProportionBar()
    private let clusters = DetailRowView(label: "")
    let list = ProcessListView(format: Format.share)

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0

        for row in [title, bar, clusters, list] as [NSView] {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(6, after: title)
        setCustomSpacing(8, after: bar)
        setCustomSpacing(12, after: clusters)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(usage: Double?, clusters split: [ClusterUsage]) {
        title.show(Metric.cpu.text(usage))
        bar.show([.init(fraction: (usage ?? 0) / 100, color: Metric.cpu.color)])
        clusters.show(label: split.map(\.name).joined(separator: " · "))
        clusters.show(split.map { Format.percent($0.usage) }.joined(separator: " · "))
        clusters.isHidden = split.isEmpty
    }
}
