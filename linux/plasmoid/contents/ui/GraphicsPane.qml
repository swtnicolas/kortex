import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: pane

    required property var monitor
    readonly property var d: monitor.bar.detail && monitor.bar.detail.vramTotal !== undefined ? monitor.bar.detail : ({})

    spacing: Kirigami.Units.smallSpacing / 2

    PaneHeader {
        value: Format.percent(pane.monitor.bar.gpu)
        tint: pane.monitor.colors.gpu
        detail: pane.d.name || ""
    }

    ProportionBar {
        segments: [
            { value: pane.monitor.bar.gpu, color: pane.monitor.colors.gpu },
            { value: 100 - (pane.monitor.bar.gpu || 0), color: "transparent" }
        ]
    }

    DetailRow {
        name: "Codificador · Decodificador"
        value: Format.pair(Format.percent(pane.d.encoder), Format.percent(pane.d.decoder))
    }

    DetailRow {
        name: "Controlador de memoria"
        value: Format.percent(pane.d.memoryController)
    }

    DetailRow {
        name: "Frecuencia actual · máxima"
        value: Format.pair(Format.gigahertz(pane.d.clock), Format.gigahertz(pane.d.clockMax, true))
    }

    DetailRow {
        name: "Consumo · límite"
        value: Format.pair(Format.watts(pane.d.power), Format.number(pane.d.powerLimit, "W"))
    }

    DetailRow {
        name: "Memoria en uso · total"
        value: Format.pair(Format.bytes(pane.d.vram), Format.bytes(pane.d.vramTotal))
    }

    DetailRow {
        name: "Temperatura"
        value: Format.celsius(pane.d.temperature)
    }

    DetailRow {
        name: "Núcleos"
        value: Format.number(pane.d.cores)
    }

    ProcessList {
        monitor: pane.monitor
        kind: "gpu"
    }
}
