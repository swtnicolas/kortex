import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: pane

    required property var monitor
    readonly property var d: monitor.bar.detail && monitor.bar.detail.threads !== undefined ? monitor.bar.detail : ({})

    spacing: Kirigami.Units.smallSpacing / 2

    PaneHeader {
        value: Format.percent(pane.monitor.bar.cpu)
        tint: pane.monitor.colors.cpu
        detail: Format.pair(Format.number(pane.d.cores, "núcleos"), Format.number(pane.d.threads, "hilos"))
    }

    ProportionBar {
        segments: [
            { value: pane.monitor.bar.cpu, color: pane.monitor.colors.cpu },
            { value: 100 - (pane.monitor.bar.cpu || 0), color: "transparent" }
        ]
    }

    DetailRow {
        name: "Frecuencia media · máxima"
        value: Format.pair(Format.gigahertz(pane.d.frequency), Format.gigahertz(pane.d.frequencyMax, true))
    }

    ProcessList {
        monitor: pane.monitor
        kind: "cpu"
    }
}
