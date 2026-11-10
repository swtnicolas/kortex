import QtQuick
import org.kde.kirigami as Kirigami

Item {
    visible: false

    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark

    readonly property color ram: dark ? "#6CB2FF" : "#1E63C4"
    readonly property color cpu: dark ? "#FF7A73" : "#C4312B"
    readonly property color gpu: dark ? "#5DD98C" : "#1F8A4C"
    readonly property color temperature: dark ? "#F7C95C" : "#A96A00"

    readonly property color system: dark ? "#B57BF5" : "#7A34C4"
    readonly property color compressed: dark ? "#34D0C0" : "#0E8A80"
    readonly property color cache: dark ? "#3F6C99" : "#9DC1EB"
    readonly property color free: dark ? "#55555C" : "#C9C9CF"

    readonly property color terminate: dark ? "#2D4A6E" : "#1E63C4"
    readonly property color terminateBorder: dark ? "#3E679A" : "#1A57AD"
    readonly property color terminateHover: dark ? "#355783" : "#1A57AD"
    readonly property color force: dark ? "#5C2A2A" : "#C4312B"
    readonly property color forceBorder: dark ? "#8A3A3A" : "#A82A25"
    readonly property color forceHover: dark ? "#6C3131" : "#A82A25"

    function metric(key) {
        return key === "ram" ? ram : key === "cpu" ? cpu : key === "gpu" ? gpu : temperature;
    }
}
