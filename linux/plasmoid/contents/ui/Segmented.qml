pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: segmented

    property var options: []
    property var current
    signal picked(var key)

    spacing: 0

    Repeater {
        model: segmented.options

        PlasmaComponents3.ToolButton {
            id: option
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: option.modelData.text
            contentItem: Column {
                PlasmaComponents3.Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: option.modelData.text
                }

                PlasmaComponents3.Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: option.modelData.value !== undefined
                    text: option.modelData.value || ""
                    color: option.modelData.color || Kirigami.Theme.textColor
                    font.features: { "tnum": 1 }
                }
            }
            checkable: true
            checked: option.modelData.key === segmented.current
            focusPolicy: Qt.NoFocus
            onClicked: segmented.picked(option.modelData.key)
        }
    }
}
