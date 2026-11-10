import QtQuick
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Rectangle {
    id: button

    property string text
    property color fill
    property color hover
    signal clicked

    implicitWidth: label.implicitWidth + Kirigami.Units.largeSpacing * 2
    implicitHeight: label.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: mouse.containsMouse ? hover : fill
    border.width: 1
    border.color: Qt.darker(fill, 1.1)

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    PlasmaComponents3.Label {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: "white"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
