import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    property string value
    property string detail
    property color tint

    Layout.fillWidth: true

    PlasmaComponents3.Label {
        text: parent.value
        color: parent.tint
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignBottom
        Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
        horizontalAlignment: Text.AlignRight
        text: parent.detail
        elide: Text.ElideLeft
    }
}
