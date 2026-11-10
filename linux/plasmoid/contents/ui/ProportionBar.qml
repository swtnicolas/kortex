pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: bar

    property var segments: []
    property color track: Qt.alpha(Kirigami.Theme.textColor, 0.15)
    readonly property real total: segments.reduce((sum, s) => sum + (s.value > 0 ? s.value : 0), 0)

    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.smallSpacing * 1.5

    Rectangle {
        anchors.fill: parent
        color: bar.track
    }

    Row {
        height: parent.height

        Repeater {
            model: bar.segments.length

            Rectangle {
                id: piece
                required property int index
                readonly property var segment: bar.segments[piece.index]
                height: parent.height
                width: bar.total > 0 && piece.segment.value > 0 ? bar.width * piece.segment.value / bar.total : 0
                color: piece.segment.color
            }
        }
    }
}
