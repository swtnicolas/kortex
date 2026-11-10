pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: pane

    required property var monitor
    readonly property var d: monitor.listTab === "temp" && monitor.list ? monitor.list : ({ zones: [], fans: [] })

    spacing: Kirigami.Units.smallSpacing / 2

    PaneHeader {
        value: Format.celsius(pane.monitor.bar.temp)
        tint: pane.monitor.colors.temperature
        detail: "Máximo de CPU y GPU"
    }

    SectionTitle {
        text: "Zonas · máximo · promedio"
    }

    Repeater {
        model: pane.d.zones.length

        DetailRow {
            id: zoneRow
            required property int index
            readonly property var zone: pane.d.zones[zoneRow.index] || ({})
            name: zoneRow.zone.name ?? ""
            value: Format.pair(Format.preciseCelsius(zoneRow.zone.max), Format.preciseCelsius(zoneRow.zone.average))
        }
    }

    SectionTitle {
        visible: pane.d.fans.length > 0
        text: "Ventiladores"
    }

    Repeater {
        model: pane.d.fans.length

        DetailRow {
            id: fanRow
            required property int index
            readonly property var fan: pane.d.fans[fanRow.index] || ({})
            name: fanRow.fan.name ?? ""
            value: fanRow.fan.rpm === 0 ? "Parado"
                : Format.known(fanRow.fan.percent) ? Format.pair(Format.number(fanRow.fan.rpm, "RPM"), Format.percent(fanRow.fan.percent))
                : Format.number(fanRow.fan.rpm, "RPM")
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
