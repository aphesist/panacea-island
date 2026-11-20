pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// written by portal-patch.py (panacea-config) - Open with, an island screen built from the Pk kit.
// Apps that ask "open this with...?" (the AppChooser portal, panacea-portal.py) land here instead
// of GTK's dialog: the suggested apps, any other installed app, and "always use it" for the type.
// The request lives on the shell (sys.appChoose); folding the island answers "cancelled".
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    readonly property var spec: sys.appChoose || ({})
    readonly property string target: decodeURIComponent(String(spec.target || "").replace(/^file:\/\//, ""))
    readonly property string fileName: target ? target.replace(/\/+$/, "").replace(/.*\//, "") : ""
    readonly property string type: String(spec.type || "")
    property bool always: false
    property bool browsing: false

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: { if (view.browsing) view.browsing = false; else view.sys.endAppChoose(""); }
    Keys.onReturnPressed: if (view.suggested.length > 0) view.pick(view.suggested[0].id)

    function entry(id) {
        id = String(id || "").replace(/\.desktop$/, "");
        return id ? (DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop")) : null;
    }
    function iconFor(e) { return e && e.icon ? Quickshell.iconPath(e.icon, true) : ""; }
    function pick(id) {
        id = String(id).replace(/\.desktop$/, "");
        if (view.always && view.type)
            Quickshell.execDetached(["xdg-mime", "default", id + ".desktop", view.type]);
        view.sys.endAppChoose(id);
    }
    // the portal's choices, last used first; the ones without an installed entry are dropped
    readonly property var suggested: {
        var ids = (spec.choices || []).slice(), last = String(spec.last || "").replace(/\.desktop$/, ""), out = [];
        if (last) ids = [last].concat(ids.filter(x => x.replace(/\.desktop$/, "") !== last));
        for (var i = 0; i < ids.length; i++) {
            var e = view.entry(ids[i]);
            if (e && !out.some(o => o.id === e.id)) out.push({ id: String(e.id).replace(/\.desktop$/, ""), e: e });
        }
        return out;
    }
    // a readable kind for the type: "PDF document" from application/pdf, roughly
    readonly property string kind: {
        if (!type) return "";
        var sub = type.split("/")[1] || type, top = type.split("/")[0];
        sub = sub.replace(/^(x-|vnd\.)/, "").replace(/[-.+]/g, " ");
        var noun = { image: "image", video: "video", audio: "audio", text: "text file", inode: "folder" }[top] || "file";
        return sub.toUpperCase().length <= 5 ? sub.toUpperCase() + " " + noun : sub + " " + noun;
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader {
            sys: view.sys; width: parent.width
            title: "Open with"
            sub: view.fileName || view.kind || "Choose an app"
        }

        PkSection {
            sys: view.sys; width: parent.width
            visible: !view.browsing
            title: view.suggested.length > 0 ? "Suggested" : ""
            PkRow { sys: view.sys; visible: view.suggested.length === 0; dim: true; title: "No app says it opens this" }
            Repeater {
                model: view.suggested
                delegate: PkRow {
                    required property var modelData
                    required property int index
                    sys: view.sys; interactive: true
                    hot: index === 0
                    image: view.iconFor(modelData.e); icon: image == "" ? "app-window" : ""
                    title: modelData.e.name
                    sub: modelData.id === String(view.spec.last || "").replace(/\.desktop$/, "") ? "Last used"
                         : (modelData.e.genericName || modelData.e.comment || "")
                    onClicked: view.pick(modelData.id)
                }
            }
            PkRow { sys: view.sys; icon: "squares-four"; title: "Other apps"; caret: true
                    onClicked: { view.browsing = true; search.input.forceActiveFocus(); } }
        }

        // every installed app, filtered as you type
        Column {
            width: parent.width; spacing: view.t.s2
            visible: view.browsing
            PkSearch { id: search; sys: view.sys; width: parent.width; placeholder: "Find an app"
                       onAccepted: if (others.count > 0) view.pick(others.itemAt(0).modelData.id)
                       Keys.onEscapePressed: view.browsing = false }
            PkSection {
                sys: view.sys; width: parent.width
                Repeater {
                    id: others
                    model: {
                        var q = search.text.toLowerCase(), all = DesktopEntries.applications ? DesktopEntries.applications.values : [];
                        var out = [];
                        for (var i = 0; i < all.length; i++) {
                            var a = all[i];
                            if (!a || a.noDisplay) continue;
                            if (!q || String(a.name).toLowerCase().indexOf(q) >= 0 || String(a.genericName || "").toLowerCase().indexOf(q) >= 0) out.push(a);
                        }
                        out.sort((x, y) => String(x.name).localeCompare(String(y.name)));
                        return out.slice(0, 7);
                    }
                    delegate: PkRow {
                        required property var modelData
                        sys: view.sys; interactive: true
                        image: view.iconFor(modelData); icon: image == "" ? "app-window" : ""
                        title: modelData.name; sub: modelData.genericName || modelData.comment || ""
                        onClicked: view.pick(modelData.id)
                    }
                }
            }
        }

        PkSection {
            sys: view.sys; width: parent.width
            visible: view.type !== ""
            PkRow {
                sys: view.sys
                title: "Always use it"
                sub: "For every " + view.kind + " (" + view.type + ")"
                PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; on: view.always
                           onToggled: on => view.always = on }
            }
        }

        Row {
            anchors.right: parent.right
            PkButton { sys: view.sys; small: true; kind: "ghost"; text: "Cancel"; onClicked: view.sys.endAppChoose("") }
        }
    }
}
