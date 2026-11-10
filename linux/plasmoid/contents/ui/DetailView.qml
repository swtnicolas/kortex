pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "format.js" as Format

Item {
    id: detail

    required property var monitor
    readonly property var tabs: [
        { key: "ram", text: "RAM", value: Format.percent(monitor.bar.ram), color: monitor.colors.ram },
        { key: "cpu", text: "CPU", value: Format.percent(monitor.bar.cpu), color: monitor.colors.cpu },
        { key: "gpu", text: "GPU", value: Format.percent(monitor.bar.gpu), color: monitor.colors.gpu },
        { key: "temp", text: "Temp", value: Format.celsius(monitor.bar.temp), color: monitor.colors.temperature }
    ]
    readonly property real fixedWidth: Kirigami.Units.gridUnit * 20
    readonly property real fixedHeight: Math.min(
        Kirigami.Units.gridUnit * 28 + (monitor.tall ? Math.round(monitor.rowHeight * 5.5) : 0),
        Screen.desktopAvailableHeight - Kirigami.Units.gridUnit * 4)

    Layout.minimumWidth: fixedWidth
    Layout.preferredWidth: fixedWidth
    Layout.maximumWidth: fixedWidth
    Layout.minimumHeight: fixedHeight
    Layout.preferredHeight: fixedHeight
    Layout.maximumHeight: fixedHeight

    Timer {
        id: keep
        interval: 1000
    }

    Connections {
        target: detail.monitor
        function onExpandedChanged() {
            if (!detail.monitor.expanded) {
                keep.restart();
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: detail.monitor.expanded || keep.running

        sourceComponent: QQC2.Control {
            padding: Kirigami.Units.smallSpacing * 2
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
            background: null

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Segmented {
                    Layout.fillWidth: true
                    visible: !detail.monitor.settings
                    options: detail.tabs
                    current: detail.monitor.tab
                    onPicked: key => detail.monitor.selectTab(key)
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: detail.monitor.settings

                    PlasmaComponents3.ToolButton {
                        icon.name: "go-previous"
                        text: "Ajustes"
                        focusPolicy: Qt.NoFocus
                        onClicked: detail.monitor.settings = false
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents3.ToolButton {
                        text: "Restablecer"
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            Plasmoid.configuration.barInterval = 3;
                            Plasmoid.configuration.detailInterval = 3;
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: detail.monitor.settings ? settingsPane
                        : detail.monitor.tab === "cpu" ? processorPane
                        : detail.monitor.tab === "gpu" ? graphicsPane
                        : detail.monitor.tab === "temp" ? temperaturePane
                        : memoryPane
                }

                Footer {
                    Layout.fillWidth: true
                    monitor: detail.monitor
                }
            }
        }
    }

    Component {
        id: memoryPane
        MemoryPane { monitor: detail.monitor }
    }

    Component {
        id: processorPane
        ProcessorPane { monitor: detail.monitor }
    }

    Component {
        id: graphicsPane
        GraphicsPane { monitor: detail.monitor }
    }

    Component {
        id: temperaturePane
        TemperaturePane { monitor: detail.monitor }
    }

    Component {
        id: settingsPane
        SettingsPane { monitor: detail.monitor }
    }
}
