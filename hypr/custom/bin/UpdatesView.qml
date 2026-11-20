pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Updates, an island screen built from the Pk kit.
// Data: scripts/custom/updates.py (no root: a private copy of the sync databases, yay -Qua,
// the Arch news feed, the package cache). Anything that changes the system runs in a terminal
// where the owner sees and confirms it: yay -Syu, pacman -Sc, removing orphans.
// Layout: a summary, a list that scrolls inside the island (never taller than the island lets
// a page be: sys.pageMaxH), housekeeping as two small cards.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    property var info: null
    property bool busy: false
    property string filter: "all"
    property int now: Date.now() / 1000
    readonly property var repo: info ? info.repo : []
    readonly property var aur: info ? info.aur : []
    readonly property var pkgs: filter === "repo" ? repo : filter === "aur" ? aur : repo.concat(aur)
    readonly property int totalBytes: repo.concat(aur).reduce((a, p) => a + (p.size || 0), 0)
    // packages that only take effect after a restart
    readonly property var restart: repo.concat(aur).filter(p => view.needsRestart(p.n)).map(p => p.n)
    readonly property int rowH: 38
    readonly property int maxH: sys.pageMaxH || 545

    focus: true
    Component.onCompleted: { forceActiveFocus(); cached.reload(); check(); }
    Keys.onEscapePressed: view.sys.collapse()

    function check() { if (!checker.running) { view.busy = true; checker.running = true; } }
    function needsRestart(n) { return /^(linux(-lts|-zen|-hardened)?|nvidia.*|systemd|glibc|mesa|intel-ucode|amd-ucode)$/.test(n); }
    function size(b) {
        if (b >= 1e9) return (b / 1e9).toFixed(1) + " GB";
        if (b >= 1e6) return Math.round(b / 1e6) + " MB";
        if (b >= 1e3) return Math.round(b / 1e3) + " KB";
        return b > 0 ? b + " B" : "";
    }
    function ago(at) {
        var s = Math.max(0, view.now - at);
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        var d = Math.floor(s / 86400);
        return d + (d === 1 ? " day ago" : " days ago");
    }
    // "157.0.8103.79-1" -> "158.0.8127.36-1": the part that stays, the part that changes
    function split(from, to) {
        var i = 0;
        while (i < from.length && i < to.length && from[i] === to[i]) i++;
        while (i > 0 && !/[.\-:+_]/.test(to[i - 1])) i--;
        return [to.slice(0, i), to.slice(i)];
    }
    function inTerminal(cmd) {
        term.command = ["foot", "-e", "sh", "-c", cmd + "; echo; printf 'Done. Press Enter to close. '; read _"];
        term.running = true;
        view.sys.collapse();
    }

    Timer { interval: 30000; running: view.visible; repeat: true; onTriggered: view.now = Date.now() / 1000 }
    FileView {
        id: cached
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/panacea-updates.json"
        printErrors: false
        onLoaded: { if (!view.info) { try { view.info = JSON.parse(text()); } catch (e) {} } }
    }
    Process {
        id: checker
        command: ["python3", Quickshell.env("HOME") + "/.config/panacea/scripts/custom/updates.py"]
        stdout: StdioCollector {
            onStreamFinished: { try { view.info = JSON.parse(text); view.now = Date.now() / 1000; } catch (e) {} view.busy = false; }
        }
        onExited: view.busy = false
    }
    Process { id: term; onExited: view.check() }

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader {
            id: head
            sys: view.sys; width: parent.width
            title: "Updates"
            sub: !view.info ? "Checking…" : (view.busy ? "Checking again…" : "Checked " + view.ago(view.info.checked))
            PkIconButton {
                sys: view.sys; icon: "arrows-clockwise"; size: view.t.iMd; enabled: !view.busy
                RotationAnimation on rotation { running: view.busy && !view.t.still; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                onClicked: view.check()
            }
        }

        // the summary: how many, how big, what needs a restart, and the one action
        PkCard {
            id: hero
            sys: view.sys; width: parent.width
            height: view.restart.length > 0 ? 104 : 80
            Row {
                x: 18; y: 18; spacing: 14
                DotText { anchors.verticalCenter: parent.verticalCenter; size: 30; color: view.t.fg
                          value: !view.info ? "-" : String(view.info.count) }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    PkText { sys: view.sys; role: "label"
                             text: !view.info ? "Looking for updates" : view.info.count === 0 ? "Everything is up to date"
                                 : view.info.count === 1 ? "update waiting" : "updates waiting" }
                    PkText { sys: view.sys; role: "sub"; visible: text !== ""
                             text: !view.info || view.info.count === 0 ? ""
                                 : [view.size(view.totalBytes) ? view.size(view.totalBytes) + " to download" : "",
                                    view.aur.length ? view.aur.length + " from the AUR" : ""].filter(x => x).join("  ·  ") }
                }
            }
            Row {
                visible: view.restart.length > 0
                x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 14; spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: view.t.accent }
                PkText { sys: view.sys; role: "sub"; width: hero.width - 60; elide: Text.ElideRight
                         text: "Restart afterwards  ·  " + view.restart.join(", ") }
            }
            PkButton {
                sys: view.sys; kind: "primary"; text: "Update all"; icon: "download-simple"
                visible: !!view.info && view.info.count > 0
                anchors.right: parent.right; anchors.rightMargin: 14; y: 20
                onClicked: view.inTerminal("yay -Syu")
            }
        }

        // recent Arch news: worth reading before updating (one line each)
        Column {
            id: news
            width: parent.width; spacing: view.t.gap
            visible: newsRep.count > 0
            Repeater {
                id: newsRep
                model: view.info ? view.info.news.slice(0, 2) : []
                delegate: PkCard {
                    id: nw
                    required property var modelData
                    sys: view.sys; width: news.width; height: 48; interactive: true
                    onClicked: { Quickshell.execDetached(["xdg-open", nw.modelData.link]); view.sys.collapse(); }
                    PkIcon { sys: view.sys; x: 16; anchors.verticalCenter: parent.verticalCenter; name: "newspaper"; size: view.t.iSm; color: view.t.accentText }
                    PkText { sys: view.sys; x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 110
                             elide: Text.ElideRight; text: nw.modelData.title }
                    PkText { sys: view.sys; role: "sub"; anchors.right: parent.right; anchors.rightMargin: 16
                             anchors.verticalCenter: parent.verticalCenter; text: view.ago(nw.modelData.at) }
                }
            }
        }

        // the packages: filter, then a dense list that scrolls
        PkCard {
            id: listCard
            sys: view.sys; width: parent.width
            visible: view.repo.length + view.aur.length > 0
            readonly property int fixed: head.height + hero.height + (news.visible ? news.height + view.t.groupGap : 0)
                                         + (house.visible ? house.height + view.t.groupGap : 0) + 2 * view.t.groupGap
            readonly property int listH: Math.max(3 * view.rowH, Math.min(view.pkgs.length * view.rowH, view.maxH - fixed - 58))
            height: 58 + listH
            PkSegmented {
                x: 12; y: 12
                options: [{ id: "all", text: "All  " + (view.repo.length + view.aur.length) },
                          { id: "repo", text: "Official  " + view.repo.length },
                          { id: "aur", text: "AUR  " + view.aur.length }].filter(o => o.id !== "aur" || view.aur.length > 0)
                value: view.filter
                onPicked: id => view.filter = id
                sys: view.sys
            }
            ListView {
                id: list
                x: 0; y: 54; width: parent.width; height: listCard.listH
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: view.pkgs
                delegate: Item {
                    id: pr
                    required property var modelData
                    readonly property var v: view.split(String(modelData.from), String(modelData.to))
                    width: list.width; height: view.rowH
                    Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: view.t.rSmall
                                color: prMa.containsMouse ? view.t.hover : "transparent" }
                    MouseArea { id: prMa; anchors.fill: parent; hoverEnabled: true }
                    Rectangle { visible: view.needsRestart(pr.modelData.n); x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 5; height: 5; radius: 2.5; color: view.t.accent }
                    Text {
                        x: 22; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.44 - x
                        elide: Text.ElideRight
                        text: pr.modelData.n
                        color: view.t.fg; font { family: view.t.font; pixelSize: view.t.tBody }
                    }
                    // the new version: what stays muted, what changes white
                    Text {
                        x: parent.width * 0.44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 76
                        elide: Text.ElideLeft
                        textFormat: Text.StyledText
                        text: "<font color='" + view.t.faint + "'>" + pr.v[0] + "</font>" + pr.v[1]
                        color: view.t.soft; font { family: view.t.font; pixelSize: view.t.tLabel }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        text: pr.modelData.repo === "aur" ? "AUR" : view.size(pr.modelData.size)
                        color: view.t.muted; font { family: view.t.font; pixelSize: view.t.tCaption }
                    }
                }
            }
            // a soft edge where the list continues
            Rectangle {
                visible: !list.atYEnd
                anchors.bottom: parent.bottom; anchors.bottomMargin: 1; x: 1; width: parent.width - 2; height: 28
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0.075, 0.075, 0.075, 0.95) }
                }
            }
        }

        // housekeeping: two small cards, each one action
        Row {
            id: house
            width: parent.width; spacing: view.t.gap
            visible: !!view.info
            Repeater {
                model: !view.info ? [] : [
                    { icon: "broom", title: "Clear cache", sub: view.size(view.info.cache.bytes) + "  ·  " + view.info.cache.files + " files",
                      cmd: "pkexec pacman -Sc", on: view.info.cache.files > 0 },
                    { icon: "package", title: "Unused packages",
                      sub: view.info.orphans.length ? view.info.orphans.length + " no longer needed" : "None",
                      cmd: "pkexec pacman -Rns " + view.info.orphans.join(" "), on: view.info.orphans.length > 0 }]
                delegate: PkCard {
                    id: hc
                    required property var modelData
                    sys: view.sys; width: (house.width - view.t.gap) / 2; height: 62
                    interactive: modelData.on
                    opacity: modelData.on ? 1 : 0.5
                    onClicked: view.inTerminal(hc.modelData.cmd)
                    PkIcon { sys: view.sys; x: 16; anchors.verticalCenter: parent.verticalCenter; name: hc.modelData.icon
                             size: view.t.iMd; filled: hc.hovered; color: view.t.fg }
                    Column {
                        x: 48; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 12; spacing: 2
                        PkText { sys: view.sys; role: "label"; text: hc.modelData.title }
                        PkText { sys: view.sys; role: "sub"; width: parent.width; elide: Text.ElideRight; text: hc.modelData.sub }
                    }
                }
            }
        }
    }
}
