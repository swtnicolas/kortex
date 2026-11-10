import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: confirm

    required property var colors
    property string question
    property string action
    signal cancel
    signal terminate
    signal force

    width: parent ? parent.width : implicitWidth
    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: confirm.question
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents3.ToolButton {
            text: "Cancelar"
            onClicked: confirm.cancel()
        }

        ColoredButton {
            text: confirm.action
            fill: confirm.colors.terminate
            hover: confirm.colors.terminateHover
            border.color: confirm.colors.terminateBorder
            onClicked: confirm.terminate()
        }

        ColoredButton {
            text: "Forzar cierre"
            fill: confirm.colors.force
            hover: confirm.colors.forceHover
            border.color: confirm.colors.forceBorder
            onClicked: confirm.force()
        }
    }
}
