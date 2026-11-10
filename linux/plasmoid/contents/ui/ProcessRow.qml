import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: row

    property string name
    property string value
    property bool nested: false
    property bool expandable: false
    property bool expanded: false
    property bool locked: false
    property bool armed: false
    property color armedColor
    signal toggle
    signal close

    width: parent ? parent.width : implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        visible: mouse.containsMouse || row.armed
    }

    Rectangle {
        visible: row.nested
        x: Kirigami.Units.iconSizes.small / 2 + Kirigami.Units.smallSpacing
        width: 1
        height: parent.height
        color: Kirigami.Theme.disabledTextColor
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: row.expandable ? Qt.LeftButton : Qt.NoButton
        cursorShape: row.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.toggle()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: row.nested ? Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 3 : Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            visible: !row.nested
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            source: row.expanded ? "arrow-down" : "arrow-right"
            opacity: row.expandable ? 1 : 0
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: row.name
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            text: row.value
            font.features: { "tnum": 1 }
        }

        Item {
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth

            Kirigami.Icon {
                anchors.fill: parent
                visible: mouse.containsMouse && row.locked
                source: "object-locked"
                color: Kirigami.Theme.disabledTextColor
                isMask: true
            }

            PlasmaComponents3.ToolButton {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                height: width
                visible: (mouse.containsMouse || hovered || row.armed) && !row.locked
                icon.name: "window-close"
                icon.color: row.armed ? row.armedColor : "transparent"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: "Cerrar " + row.name
                onClicked: row.close()
            }
        }
    }
}
