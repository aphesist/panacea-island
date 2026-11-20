pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Logs, an island screen built from the Pk kit.
// The journal of this boot (system or user), newest first, filtered by level and text;
// "Live" follows it. A click on an entry opens it whole; Copy puts it on the clipboard.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    property string level: "warning"        // all | warning | error
    property bool user: false
    property bool live: false
    property bool loading: false
    property int open: -1                   // the expanded entry (its seq)
    property int seq: 0
    readonly property string prio: level === "error" ? "3" : level === "warning" ? "4" : "6"

    focus: true
    Component.onCompleted: { forceActiveFocus(); reload(); }
    Keys.onEscapePressed: { if (view.open >= 0) view.open = -1; else view.sys.collapse(); }
    onLevelChanged: reload()
    onUserChanged: reload()
    onLiveChanged: follow.running = live

    function args() { return (view.user ? ["--user"] : []).concat(["-b", "-p", view.prio, "-o", "json", "--no-pager"]); }
    function reload() {
        follow.running = false;
        entries.clear(); view.open = -1; view.loading = true;
        loader.running = false;
        loader.command = ["journalctl"].concat(view.args(), ["-n", "400", "-r"]);
        loader.running = true;
    }
    function entry(line) {
        var j;
        try { j = JSON.parse(line); } catch (e) { return null; }
        var m = j.MESSAGE;
        if (Array.isArray(m)) m = String.fromCharCode.apply(null, m);
        m = String(m || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");   // terminal colours some programs log
        var us = parseInt(j.__REALTIME_TIMESTAMP || "0");
        var d = new Date(us / 1000);
        function two(n) { return (n < 10 ? "0" : "") + n; }
        return { seq: view.seq++, time: two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds()),
                 prio: parseInt(j.PRIORITY || "6"), who: String(j.SYSLOG_IDENTIFIER || j._COMM || "?"),
                 unit: String(j._SYSTEMD_UNIT || j._SYSTEMD_USER_UNIT || ""), msg: String(m || "") };
    }
    // the island chat, asked straight away (the same path as "Ask Claude about this")
    function ask(text) {
        view.sys.chatDraft = "Explain this entry from my system log, and whether I should do anything about it:\n```\n" + text + "\n```";
        view.sys.chatAskSend = true;
        view.sys.chatAskRev++;
        view.sys.page = "chat"; view.sys.expanded = true; view.sys.holdOpen = true;
    }
    function matches(e) {
        var q = search.text.toLowerCase();
        return !q || e.msg.toLowerCase().indexOf(q) >= 0 || e.who.toLowerCase().indexOf(q) >= 0 || e.unit.toLowerCase().indexOf(q) >= 0;
    }

    ListModel { id: entries }
    Process {
        id: loader
        stdout: SplitParser { onRead: line => { var e = view.entry(line); if (e) entries.append(e); } }
        onExited: { view.loading = false; if (view.live) follow.running = true; }
    }
    Process {
        id: follow
        command: ["journalctl"].concat(view.args(), ["-f", "-n", "0"])
        stdout: SplitParser {
            onRead: line => {
                var e = view.entry(line);
                if (!e) return;
                entries.insert(0, e);
                if (entries.count > 1500) entries.remove(1500, entries.count - 1500);
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.s3

        PkHeader {
            sys: view.sys; width: parent.width
            title: "Logs"
            sub: (view.user ? "Your session" : "System") + "  ·  this boot  ·  " + (view.loading ? "loading…" : entries.count + " entries")
            PkChip {
                sys: view.sys; text: "Live"; icon: view.live ? "record" : "pause"; selected: view.live
                anchors.verticalCenter: parent.verticalCenter
                onClicked: view.live = !view.live
            }
        }
        PkSearch { id: search; sys: view.sys; width: parent.width; placeholder: "Filter by text, program or unit" }
        Row {
            width: parent.width; spacing: view.t.s2
            PkSegmented {
                sys: view.sys
                options: [{ id: "all", text: "All" }, { id: "warning", text: "Warnings" }, { id: "error", text: "Errors" }]
                value: view.level
                onPicked: id => view.level = id
            }
            PkSegmented {
                sys: view.sys
                options: [{ id: "sys", text: "System" }, { id: "user", text: "User" }]
                value: view.user ? "user" : "sys"
                onPicked: id => view.user = id === "user"
            }
        }

        Rectangle {
            width: parent.width; height: 430
            radius: view.t.rSurface; color: view.t.surface; clip: true
            PkText { sys: view.sys; anchors.centerIn: parent; role: "sub"; visible: !view.loading && entries.count === 0
                     text: view.level === "error" ? "No errors this boot" : view.level === "warning" ? "No warnings this boot" : "Nothing logged" }
            ListView {
                id: list
                anchors.fill: parent; anchors.margins: 6
                model: entries
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property int seq
                    required property string time
                    required property int prio
                    required property string who
                    required property string unit
                    required property string msg
                    readonly property bool shown: view.matches({ msg: msg, who: who, unit: unit })
                    readonly property bool isOpen: view.open === seq
                    width: list.width
                    height: shown ? body.implicitHeight + 16 : 0
                    visible: shown
                    radius: view.t.rControl
                    color: isOpen ? view.t.selected : rowMa.containsMouse ? view.t.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: view.t.dFast } }
                    MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: view.open = row.isOpen ? -1 : row.seq }
                    // level: red for errors, white for warnings, nothing for the rest
                    Rectangle { x: 10; y: 14; width: 6; height: 6; radius: 3; visible: row.prio <= 4
                                color: row.prio <= 3 ? view.t.accent : view.t.soft }
                    Column {
                        id: body
                        x: 24; y: 8; width: parent.width - x - 10
                        spacing: 3
                        Row {
                            spacing: 8; width: parent.width
                            PkText { sys: view.sys; role: "caption"; text: row.who; color: view.t.fg; width: Math.min(implicitWidth, parent.width * 0.5) }
                            PkText { sys: view.sys; role: "sub"; text: row.time }
                            PkText { sys: view.sys; role: "sub"; visible: row.isOpen && row.unit !== ""; text: row.unit; color: view.t.faint }
                        }
                        PkText {
                            sys: view.sys; width: parent.width
                            text: row.msg
                            color: row.prio <= 3 ? view.t.accentText : view.t.soft
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: row.isOpen ? 40 : 2
                            elide: Text.ElideRight
                            font.pixelSize: view.t.tLabel
                        }
                        Row {
                            visible: row.isOpen; spacing: 8; topPadding: 4
                            PkButton { sys: view.sys; small: true; text: "Copy"; icon: "copy"
                                       onClicked: view.sys.copyText(row.time + " " + row.who + (row.unit ? " (" + row.unit + ")" : "") + ": " + row.msg) }
                            PkButton { sys: view.sys; small: true; text: "Ask Claude"; icon: "sparkle"
                                       onClicked: view.ask(row.time + " " + row.who + (row.unit ? " (" + row.unit + ")" : "") + ": " + row.msg) }
                            PkButton { sys: view.sys; small: true; kind: "ghost"; text: "Only this program"
                                       onClicked: search.text = row.who }
                        }
                    }
                }
            }
        }
    }
}
