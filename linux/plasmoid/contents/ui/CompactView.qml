pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "format.js" as Format

MouseArea {
    id: compact

    required property var monitor
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int padding: Kirigami.Units.smallSpacing
    readonly property int gap: 2
    readonly property real labelSize: Kirigami.Theme.smallFont.pointSize * 0.85
    readonly property real valueSize: Kirigami.Theme.defaultFont.pointSize * 0.9
    readonly property real inkHeight: labelInk.tightBoundingRect.height + valueInk.tightBoundingRect.height
    readonly property real fit: vertical || height <= 0 ? 1 : Math.min(1.25, (height * 0.9 - gap) / inkHeight)
    readonly property real labelCap: labelInk.tightBoundingRect.height * fit
    readonly property real valueCap: valueInk.tightBoundingRect.height * fit

    Layout.minimumWidth: vertical ? 0 : grid.implicitWidth + padding * 2
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? grid.implicitHeight + padding * 2 : 0
    Layout.maximumHeight: vertical ? Layout.minimumHeight : Infinity

    acceptedButtons: Qt.LeftButton
    onClicked: monitor.expanded = !monitor.expanded

    Accessible.role: Accessible.Button
    Accessible.name: Plasmoid.title
    Accessible.description: ["ram", "cpu", "gpu", "temp"].map(key => key.toUpperCase() + " " + Format.barValue(monitor.bar[key], key === "temp" ? "°C" : "%")).join(", ")

    TextMetrics {
        id: labelInk
        font.pointSize: compact.labelSize
        font.weight: Font.Medium
        text: "RAMCPUGTE"
    }

    TextMetrics {
        id: valueInk
        font.pointSize: compact.valueSize
        font.features: { "tnum": 1 }
        text: "0123456789%°C"
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        columns: compact.vertical ? 1 : 4
        columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.5 * compact.fit)
        rowSpacing: Kirigami.Units.smallSpacing * 2

        Repeater {
            model: [
                { name: "RAM", key: "ram", unit: "%" },
                { name: "CPU", key: "cpu", unit: "%" },
                { name: "GPU", key: "gpu", unit: "%" },
                { name: "TEMP", key: "temp", unit: "°C" }
            ]

            delegate: Item {
                id: column

                required property var modelData
                readonly property color tint: compact.monitor.colors.metric(column.modelData.key)

                width: Math.max(label.implicitWidth, value.implicitWidth, reserve.advanceWidth)
                height: Math.round(compact.labelCap + compact.gap + compact.valueCap)

                Text {
                    id: label
                    y: Math.round(compact.labelCap - baselineOffset)
                    text: column.modelData.name
                    color: column.tint
                    renderType: Text.NativeRendering
                    font.pointSize: compact.labelSize * compact.fit
                    font.weight: Font.Medium
                }

                Text {
                    id: value
                    y: Math.round(compact.labelCap + compact.gap + compact.valueCap - baselineOffset)
                    text: Format.barValue(compact.monitor.bar[column.modelData.key], column.modelData.unit)
                    color: column.tint
                    renderType: Text.NativeRendering
                    font.pointSize: compact.valueSize * compact.fit
                    font.features: { "tnum": 1 }
                }

                TextMetrics {
                    id: reserve
                    font: value.font
                    text: "00" + column.modelData.unit
                }
            }
        }
    }
}
