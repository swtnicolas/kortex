pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: footer

    required property var monitor
    property double now: Date.now()

    spacing: 0

    Timer {
        interval: 1000
        repeat: true
        running: footer.visible
        onTriggered: footer.now = Date.now()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    SectionTitle {
        text: "Consumo de Kortex"
    }

    Repeater {
        model: [
            { name: "Con la ventana abierta", key: "own" },
            { name: "Con la ventana cerrada", key: "closed" }
        ]

        RowLayout {
            id: usageRow
            required property var modelData
            readonly property var usage: footer.monitor.bar[usageRow.modelData.key] || ({})

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: usageRow.modelData.name
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                text: Format.bytes(usageRow.usage.ram)
                color: footer.monitor.colors.ram
                font.features: { "tnum": 1 }
            }

            PlasmaComponents3.Label {
                text: "RAM ·"
                color: Kirigami.Theme.disabledTextColor
            }

            PlasmaComponents3.Label {
                text: Format.known(usageRow.usage.cpu) ? usageRow.usage.cpu.toFixed(2).replace(".", ",") + "%" : "—"
                color: footer.monitor.colors.cpu
                font.features: { "tnum": 1 }
            }

            PlasmaComponents3.Label {
                text: "CPU"
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    PlasmaComponents3.Label {
        visible: !footer.monitor.available
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
        color: Kirigami.Theme.negativeTextColor
        text: "El servicio de Kortex no responde"
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing

        PlasmaComponents3.ToolButton {
            text: Format.pair("Actualizar", Format.ago(Math.max(0, Math.floor((footer.now - footer.monitor.updated) / 1000))))
            focusPolicy: Qt.NoFocus
            onClicked: footer.monitor.refresh()
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents3.ToolButton {
            visible: !footer.monitor.settings
            text: "Ajustes"
            icon.name: "configure"
            focusPolicy: Qt.NoFocus
            onClicked: footer.monitor.settings = true
        }
    }
}
