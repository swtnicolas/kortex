import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    property string name
    property string value
    property color swatch: "transparent"
    property color valueColor: Kirigami.Theme.textColor

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
        visible: parent.swatch.a > 0
        implicitWidth: Kirigami.Units.smallSpacing * 2
        implicitHeight: implicitWidth
        radius: 2
        color: parent.swatch
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: parent.name
        elide: Text.ElideRight
    }

    PlasmaComponents3.Label {
        text: parent.value
        color: parent.valueColor
        font.features: { "tnum": 1 }
    }
}
