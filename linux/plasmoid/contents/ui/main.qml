import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property var intervals: [1, 2, 3, 5, 7, 10]
    readonly property string tab: Plasmoid.configuration.tab
    property bool settings: false
    property string query: ""
    property bool more: false
    property var opened: ({})
    property var folded: ({})
    property bool locked: false
    property bool available: true
    property var bar: ({})
    property var list: null
    property string listTab: ""
    property double updated: 0
    property string heard: ""
    property double heardAt: 0

    readonly property int limit: more ? 50 : 5
    readonly property bool tall: more
        || Object.keys(opened).some(key => opened[key])
        || (list !== null && Array.isArray(list.groups) && list.groups.some(group => group.expanded && group.count > 1))
    readonly property int rowHeight: Math.round(Kirigami.Units.gridUnit * 1.15)

    preferredRepresentation: compactRepresentation
    compactRepresentation: CompactView { monitor: root }
    fullRepresentation: DetailView { monitor: root }
    toolTipMainText: ""
    toolTipSubText: ""
    hideOnWindowDeactivate: true

    readonly property alias colors: colorSet

    MetricColors {
        id: colorSet
    }

    function call(member, signature, args, done) {
        DBus.SessionBus.asyncCall({
            service: "local.Kortex",
            path: "/local/Kortex",
            iface: "local.Kortex",
            member: member,
            signature: signature,
            arguments: args
        }, reply => {
            available = true;
            if (!done) {
                return;
            }
            const value = reply.value;
            done(typeof value === "string" || typeof value === "number" ? value : value.value);
        }, () => {
            available = false;
        });
    }

    function barTab() {
        return expanded ? (settings ? "settings" : tab) : "";
    }

    function readBar() {
        const requested = barTab();
        if (requested === "" && heard && Date.now() - heardAt < Plasmoid.configuration.barInterval * 1000 - 500) {
            bar = JSON.parse(heard);
            updated = heardAt;
            return;
        }
        call("Bar", "(s)", [new DBus.string(requested)], text => {
            if (requested !== barTab()) {
                return;
            }
            bar = JSON.parse(text);
            updated = Date.now();
        });
    }

    function readList() {
        if (!expanded || settings) {
            return;
        }
        const wanted = tab;
        call("List", "(ssu)", [new DBus.string(wanted), new DBus.string(query), new DBus.uint32(limit)], text => {
            if (wanted !== tab || !expanded) {
                return;
            }
            const value = JSON.parse(text);
            list = value;
            listTab = wanted;
            if (value.baseline) {
                baseline.restart();
            }
        });
    }

    function refresh() {
        readBar();
        readList();
    }

    function selectTab(name) {
        settings = false;
        if (name === tab) {
            return;
        }
        Plasmoid.configuration.tab = name;
    }

    function toggleGroup(key) {
        const next = Object.assign({}, opened);
        next[key] = !next[key];
        opened = next;
    }

    function toggleFold(key) {
        const next = Object.assign({}, folded);
        next[key] = !next[key];
        folded = next;
    }

    function terminate(targets, force) {
        call("Terminate", "(sb)", [new DBus.string(targets), new DBus.bool(force)], () => readList());
    }

    onTabChanged: {
        root.list = null;
        root.listTab = "";
        root.refresh();
    }
    onSettingsChanged: root.refresh()
    onQueryChanged: {
        root.folded = {};
        search.restart();
    }
    onLimitChanged: root.readList()
    onExpandedChanged: {
        if (!root.expanded) {
            root.call("Close", "", [], null);
            root.settings = false;
            root.query = "";
            root.more = false;
            root.opened = {};
            root.folded = {};
            root.list = null;
            root.listTab = "";
        }
        root.refresh();
    }

    Timer {
        interval: Plasmoid.configuration.barInterval * 1000
        repeat: true
        running: !root.locked
        triggeredOnStart: true
        onTriggered: root.readBar()
    }

    Timer {
        interval: Plasmoid.configuration.detailInterval * 1000
        repeat: true
        running: root.expanded && !root.settings && !root.locked
        onTriggered: root.readList()
    }

    Timer {
        id: baseline
        interval: 1000
        onTriggered: root.readList()
    }

    Timer {
        id: search
        interval: 150
        onTriggered: root.readList()
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"

        function dbusActiveChanged(active) {
            root.locked = active;
            if (!active) {
                root.refresh();
            }
        }
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "local.Kortex"
        path: "/local/Kortex"
        iface: "local.Kortex"

        function dbusReading(text) {
            root.heard = text;
            root.heardAt = Date.now();
        }
    }
}
