pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Startup, an island screen built from the Pk kit.
// The apps opened at login (hypr/custom/startup-apps.json, run by scripts/custom/startup-apps.py
// from autostart.lua): switch each on or off, delay it, add from the installed apps, remove.
// Below, read-only: the background services that start with the session.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    property bool embedded: false      // inside Settings: no header, no keyboard grab
    implicitHeight: col.implicitHeight

    property var apps: []
    property bool adding: false
    property var services: []
    readonly property var delays: [0, 5, 15, 30]

    focus: true
    Component.onCompleted: { if (!embedded) forceActiveFocus(); store.reload(); svc.running = true; }
    Keys.onEscapePressed: { if (view.adding) view.adding = false; else view.sys.collapse(); }

    function save(list) { view.apps = list; store.setText(JSON.stringify({ apps: list }, null, 2) + "\n"); }
    function set(i, key, value) { var l = view.apps.slice(); l[i] = Object.assign({}, l[i]); l[i][key] = value; view.save(l); }
    function add(e) {
        if (view.apps.some(a => a.id === e.id + ".desktop" || a.id === e.id)) { view.adding = false; return; }
        var id = String(e.id).endsWith(".desktop") ? e.id : e.id + ".desktop";
        view.save(view.apps.concat([{ id: id, name: e.name, icon: e.icon, exec: e.execString, on: true, delay: 0 }]));
        view.adding = false; search.text = "";
    }
    function iconFor(name) { return name ? Quickshell.iconPath(name, true) : ""; }

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.config/hypr/custom/startup-apps.json"
        printErrors: false
        onLoaded: { try { view.apps = JSON.parse(text()).apps || []; } catch (e) { view.apps = []; } }
        onLoadFailed: view.apps = []
    }
    Process {
        id: svc
        command: ["sh", "-c", "for u in $(systemctl --user list-unit-files --state=enabled --type=service --no-legend | cut -d' ' -f1); do printf '%s\\t%s\\n' \"$u\" \"$(systemctl --user show -p Description --value \"$u\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: view.services = text.split("\n").filter(l => l).map(l => { var p = l.split("\t"); return { unit: p[0], desc: p[1] || p[0] }; })
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader { sys: view.sys; visible: !view.embedded; width: parent.width; title: "Startup"; sub: "Opened when you log in" }

        PkSection {
            sys: view.sys; width: parent.width; title: "Apps"
            PkRow { sys: view.sys; visible: view.apps.length === 0 && !view.adding; dim: true; title: "Nothing opens at login yet" }
            Repeater {
                model: view.apps
                delegate: PkRow {
                    id: ar
                    required property var modelData
                    required property int index
                    sys: view.sys
                    image: view.iconFor(modelData.icon)
                    icon: image == "" ? "app-window" : ""
                    title: modelData.name || modelData.id
                    sub: !modelData.on ? "Off" : modelData.delay > 0 ? modelData.delay + " s after login" : "At login"
                    dim: !modelData.on
                    // delay: a click cycles now / 5 / 15 / 30 s
                    PkChip { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; visible: ar.modelData.on
                             text: ar.modelData.delay > 0 ? ar.modelData.delay + " s" : "Now"; icon: "timer"
                             onClicked: view.set(ar.index, "delay", view.delays[(view.delays.indexOf(ar.modelData.delay || 0) + 1) % view.delays.length]) }
                    PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; on: !!ar.modelData.on
                               onToggled: on => view.set(ar.index, "on", on) }
                    PkIconButton { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; icon: "x"; size: 14
                                   onClicked: view.save(view.apps.filter((a, i) => i !== ar.index)) }
                }
            }
            PkRow { sys: view.sys; visible: !view.adding; icon: "plus"; title: "Add an app"; interactive: true
                    onClicked: { view.adding = true; search.input.forceActiveFocus(); } }
        }

        // the installed apps, filtered as you type
        Column {
            width: parent.width; spacing: view.t.s2
            visible: view.adding
            PkSearch { id: search; sys: view.sys; width: parent.width; placeholder: "Find an app to add"
                       onAccepted: if (picks.count > 0) view.add(picks.itemAt(0).modelData)
                       Keys.onEscapePressed: view.adding = false }
            PkSection {
                sys: view.sys; width: parent.width
                Repeater {
                    id: picks
                    model: {
                        var q = search.text.toLowerCase(), all = DesktopEntries.applications ? DesktopEntries.applications.values : [];
                        var out = [];
                        for (var i = 0; i < all.length && out.length < 6; i++) {
                            var a = all[i];
                            if (!a || a.noDisplay) continue;
                            if (!q || String(a.name).toLowerCase().indexOf(q) >= 0 || String(a.genericName || "").toLowerCase().indexOf(q) >= 0) out.push(a);
                        }
                        return out;
                    }
                    delegate: PkRow {
                        required property var modelData
                        sys: view.sys; interactive: true
                        image: view.iconFor(modelData.icon); icon: image == "" ? "app-window" : ""
                        title: modelData.name; sub: modelData.genericName || modelData.comment || ""
                        PkIcon { sys: view.sys; name: "plus"; size: 16; color: view.t.muted }
                        onClicked: view.add(modelData)
                    }
                }
            }
        }

        PkSection {
            sys: view.sys; width: parent.width
            visible: view.services.length > 0
            title: "Also starts with your session"
            note: "Background services. Change these in a terminal: systemctl --user disable <name>."
            Repeater {
                model: view.services
                delegate: PkRow {
                    required property var modelData
                    sys: view.sys; icon: "gear-six"
                    title: modelData.desc; sub: modelData.unit
                }
            }
        }
    }
}
