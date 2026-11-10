pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: list

    required property var monitor
    required property string kind
    readonly property var reply: monitor.listTab === kind ? monitor.list : null
    readonly property var groups: reply ? reply.groups : []
    property string confirming: ""
    readonly property int rowHeight: monitor.rowHeight

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.smallSpacing

    function format(item) {
        if (kind === "ram") {
            return Format.bytes(item.value);
        }
        if (kind === "gpu") {
            return Format.pair(Format.listPercent(item.value), Format.bytes(item.vram));
        }
        return Format.listPercent(item.value);
    }

    function confirm(key) {
        confirming = confirming === key ? "" : key;
    }

    function dismiss() {
        if (confirming) {
            confirming = "";
        } else if (field.text) {
            field.text = "";
        } else {
            monitor.expanded = false;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing

        SectionTitle {
            Layout.topMargin: 0
            text: list.reply ? Format.pair("Apps", Math.min(list.groups.length, list.monitor.limit) + " de " + list.reply.total) : "Apps"
        }

        PlasmaExtras.SearchField {
            id: field
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            placeholderText: "Escribe para buscar"
            text: list.monitor.query
            focus: true
            onTextChanged: list.monitor.query = text
            Keys.onEscapePressed: event => {
                list.dismiss();
                event.accepted = true;
            }
            Component.onCompleted: forceActiveFocus()
        }
    }

    PlasmaComponents3.ScrollView {
        id: scrollList
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        Column {
            id: rows
            width: scrollList.availableWidth

            PlasmaComponents3.Label {
                visible: list.reply !== null && list.groups.length === 0
                width: parent.width
                height: list.rowHeight
                verticalAlignment: Text.AlignVCenter
                color: Kirigami.Theme.disabledTextColor
                text: list.monitor.query ? "Ninguna app coincide" : "Ninguna app en uso"
            }

            Repeater {
                model: list.groups.length

                Column {
                    id: entry

                    required property int index
                    readonly property var group: list.groups[entry.index] || ({ name: "", key: "", count: 0, targets: "", members: [] })
                    readonly property bool open: entry.group.count > 1 && (entry.group.expanded
                        ? list.monitor.folded[entry.group.key] !== true
                        : list.monitor.opened[entry.group.key] === true)

                    width: rows.width

                    ProcessRow {
                        implicitHeight: list.rowHeight
                        name: entry.group.name
                        value: list.format(entry.group)
                        expandable: entry.group.count > 1
                        expanded: entry.open
                        locked: entry.group.locked || !entry.group.targets
                        armed: list.confirming === "app " + entry.group.key
                        armedColor: list.monitor.colors.cpu
                        onToggle: entry.group.expanded ? list.monitor.toggleFold(entry.group.key) : list.monitor.toggleGroup(entry.group.key)
                        onClose: list.confirm("app " + entry.group.key)
                    }

                    ConfirmBar {
                        visible: list.confirming === "app " + entry.group.key
                        colors: list.monitor.colors
                        question: entry.group.count > 1 ? "¿Cerrar " + entry.group.name + " y todos sus procesos?" : "¿Terminar " + entry.group.name + "?"
                        action: entry.group.count > 1 ? "Cerrar app" : "Terminar proceso"
                        onCancel: list.confirming = ""
                        onTerminate: {
                            list.confirming = "";
                            list.monitor.terminate(entry.group.targets, false);
                        }
                        onForce: {
                            list.confirming = "";
                            list.monitor.terminate(entry.group.targets, true);
                        }
                    }

                    Repeater {
                        model: entry.open ? entry.group.members.length : 0

                        Column {
                            id: member

                            required property int index
                            readonly property var process: entry.group.members[member.index] || ({ name: "", target: "" })

                            width: rows.width

                            ProcessRow {
                                implicitHeight: list.rowHeight
                                nested: true
                                name: member.process.name
                                value: list.format(member.process)
                                locked: member.process.locked
                                armed: list.confirming === "process " + member.process.target
                                armedColor: list.monitor.colors.cpu
                                onClose: list.confirm("process " + member.process.target)
                            }

                            ConfirmBar {
                                visible: list.confirming === "process " + member.process.target
                                colors: list.monitor.colors
                                question: "¿Terminar " + member.process.name + "?"
                                action: "Terminar proceso"
                                onCancel: list.confirming = ""
                                onTerminate: {
                                    list.confirming = "";
                                    list.monitor.terminate(member.process.target, false);
                                }
                                onForce: {
                                    list.confirming = "";
                                    list.monitor.terminate(member.process.target, true);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    PlasmaComponents3.ToolButton {
        visible: list.reply !== null && list.reply.total > 5
        text: list.monitor.more ? "Mostrar menos" : "Mostrar más"
        focusPolicy: Qt.NoFocus
        onClicked: list.monitor.more = !list.monitor.more
    }
}
