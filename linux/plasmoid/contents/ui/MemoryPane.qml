import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: pane

    required property var monitor
    readonly property var colors: monitor.colors
    readonly property var d: monitor.bar.detail && monitor.bar.detail.apps !== undefined ? monitor.bar.detail : ({})
    readonly property real pressure: Format.known(d.pressure) ? d.pressure : 0

    spacing: Kirigami.Units.smallSpacing / 2

    PaneHeader {
        value: Format.percent(pane.monitor.bar.ram)
        tint: pane.colors.ram
        detail: Format.pair(Format.bytes(pane.d.used), Format.bytes(pane.d.total), " / ")
    }

    ProportionBar {
        segments: [
            { value: pane.d.apps, color: pane.colors.ram },
            { value: pane.d.system, color: pane.colors.system },
            { value: pane.d.compressed, color: pane.colors.compressed },
            { value: pane.d.cache, color: pane.colors.cache },
            { value: pane.d.free, color: pane.colors.free }
        ]
    }

    DetailRow {
        swatch: pane.colors.ram
        name: "Apps"
        value: Format.bytes(pane.d.apps)
    }

    DetailRow {
        swatch: pane.colors.system
        name: "Sistema"
        value: Format.bytes(pane.d.system)
    }

    DetailRow {
        swatch: pane.colors.compressed
        name: "Comprimida"
        value: Format.bytes(pane.d.compressed)
    }

    DetailRow {
        swatch: pane.colors.cache
        name: "Caché"
        value: Format.bytes(pane.d.cache)
    }

    DetailRow {
        swatch: pane.colors.free
        name: "Libre"
        value: Format.bytes(pane.d.free)
    }

    DetailRow {
        name: "Swap"
        value: Format.pair(Format.bytes(pane.d.swap), Format.bytes(pane.d.swapTotal), " / ")
        valueColor: pane.d.swapDisk > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
    }

    DetailRow {
        name: "Presión"
        value: Format.known(pane.d.pressure)
            ? Format.pair(pane.pressure >= 60 ? "Crítica" : pane.pressure >= 10 ? "Advertencia" : "Normal", Format.listPercent(pane.pressure))
            : "—"
        valueColor: pane.pressure >= 60 ? Kirigami.Theme.negativeTextColor
            : pane.pressure >= 10 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
    }

    ProcessList {
        monitor: pane.monitor
        kind: "ram"
    }
}
