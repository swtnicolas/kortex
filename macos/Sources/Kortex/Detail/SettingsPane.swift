import AppKit

final class SettingsPane: NSStackView {
    private static let barReadingCost = 0.7
    private static let detailBaseCost = 0.8
    private static let detailReadingCost = 24.4
    private static let intervalLabels = Settings.intervals.map { "\(Int($0)) s" }

    private let barIntervals = SegmentedView(SettingsPane.intervalLabels)
    private let detailIntervals = SegmentedView(SettingsPane.intervalLabels)
    private let barCost = Label(font: .systemFont(ofSize: 11))
    private let detailCost = Label(font: .systemFont(ofSize: 11))
    private let login = ToggleView()
    private let dock = ToggleView()

    var onBack: (() -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0

        let loginRow = SettingsPane.switchRow("Abrir al iniciar sesión", login)
        let dockRow = SettingsPane.switchRow("Mostrar icono en el Dock", dock)
        let version = Label("Kortex \(SettingsPane.version)", font: .systemFont(ofSize: 11))
        let rows: [NSView] = [
            header(),
            Label("Actualizar la barra de menú cada"), barIntervals, barCost,
            Label("Actualizar el detalle cada"), detailIntervals, detailCost,
            Label("Sistema"), loginRow, dockRow,
            version
        ]
        for row in rows {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        for row in rows.dropLast() where row is Label {
            setCustomSpacing(4, after: row)
        }
        setCustomSpacing(12, after: rows[0])
        setCustomSpacing(6, after: barIntervals)
        setCustomSpacing(6, after: detailIntervals)
        setCustomSpacing(12, after: barCost)
        setCustomSpacing(12, after: detailCost)
        setCustomSpacing(4, after: loginRow)
        setCustomSpacing(12, after: dockRow)

        barIntervals.onSelect = { [weak self] index in
            Settings.bar = Settings.intervals[index]
            self?.show()
        }
        detailIntervals.onSelect = { [weak self] index in
            Settings.detail = Settings.intervals[index]
            self?.show()
        }
        login.onChange = { [weak self] on in
            Settings.opensAtLogin = on
            self?.show()
        }
        dock.onChange = { [weak self] on in
            Settings.showsDockIcon = on
            self?.show()
        }

        show()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        barIntervals.selected = Settings.intervals.firstIndex(of: Settings.bar) ?? 2
        detailIntervals.selected = Settings.intervals.firstIndex(of: Settings.detail) ?? 2
        barCost.text = Format.cost(SettingsPane.barReadingCost / Settings.bar)
        let detailUsage = SettingsPane.detailBaseCost + SettingsPane.detailReadingCost / Settings.detail
        detailCost.text = Format.cost(detailUsage) + " con la lista de RAM abierta"
        login.isOn = Settings.opensAtLogin
        dock.isOn = Settings.showsDockIcon
    }

    private func header() -> NSView {
        let back = HoverButton("Ajustes", icon: .back, font: .systemFont(ofSize: 13, weight: .medium)) { [weak self] in
            self?.onBack?()
        }
        let restore = HoverButton("Restablecer") { [weak self] in
            Settings.reset()
            self?.show()
        }
        return SettingsPane.spread(back, restore)
    }

    private static func switchRow(_ title: String, _ control: ToggleView) -> NSView {
        let label = Label(title, font: .systemFont(ofSize: 13), color: Palette.text)
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func spread(_ left: NSView, _ right: NSView) -> NSView {
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(left)
        container.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            left.topAnchor.constraint(equalTo: container.topAnchor),
            left.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            right.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: left.centerYAnchor)
        ])
        return container
    }
}
