import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "format.js" as Format

ColumnLayout {
    id: pane

    required property var monitor
    readonly property real barCost: 0.1
    readonly property real detailFixed: 0.25
    readonly property real detailList: 0.4
    readonly property var intervals: monitor.intervals.map(seconds => ({ key: seconds, text: seconds + " s" }))

    spacing: Kirigami.Units.smallSpacing / 2

    SectionTitle {
        text: "Actualizar la barra cada"
    }

    Segmented {
        Layout.fillWidth: true
        options: pane.intervals
        current: Plasmoid.configuration.barInterval
        onPicked: value => Plasmoid.configuration.barInterval = value
    }

    PlasmaComponents3.Label {
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: Format.cost(pane.barCost / Plasmoid.configuration.barInterval)
    }

    SectionTitle {
        text: "Actualizar el detalle cada"
    }

    Segmented {
        Layout.fillWidth: true
        options: pane.intervals
        current: Plasmoid.configuration.detailInterval
        onPicked: value => Plasmoid.configuration.detailInterval = value
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: Format.cost(pane.detailFixed + pane.detailList / Plasmoid.configuration.detailInterval) + " con la lista de RAM abierta"
    }

    PlasmaComponents3.Label {
        Layout.topMargin: Kirigami.Units.largeSpacing
        color: Kirigami.Theme.disabledTextColor
        text: Plasmoid.metaData.name + " " + Plasmoid.metaData.version
    }

    Item {
        Layout.fillHeight: true
    }
}
