import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmaComponents3.Label {
    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.disabledTextColor
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    elide: Text.ElideRight
}
