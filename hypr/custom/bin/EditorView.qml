pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Editor, an island screen built from the Pk kit.
// Plain text: open a path (`ipc call pill edit <path>`, the "Panacea Editor" app, or a path typed
// here), edit, save in place (Ctrl+S; never tmp + rename, so watched configs reload), find
// (Ctrl+F), make a new file (+ or Ctrl+N: the island's file picker asks for a name and a folder).
// The buffer lives on the shell (sys.editor*), so folding the island loses nothing.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    readonly property string path: sys.editorPath
    readonly property string name: path ? path.replace(/.*\//, "") : "Editor"
    readonly property string dir: path ? path.replace(/\/[^\/]*$/, "").replace(new RegExp("^" + Quickshell.env("HOME")), "~") : ""
    property bool wrap: false
    property bool finding: false
    property bool confirmClose: false
    property string after: ""          // what to do once the changes are saved or dropped: "close" | "new"
    property string error: ""
    property bool loading: false
    property bool setting: false       // text set by loading, not typed
    readonly property int maxBytes: 4 * 1024 * 1024

    focus: true
    Component.onCompleted: { open(); Qt.callLater(() => (view.path ? ta : pathField.input).forceActiveFocus()); }
    Keys.onEscapePressed: view.leave()

    function leave() {
        if (view.finding) { view.finding = false; ta.forceActiveFocus(); return; }
        if (view.sys.editorDirty && !view.confirmClose) { view.after = "close"; view.confirmClose = true; return; }
        view.confirmClose = false;
        view.sys.collapse();
    }
    // a new file: ask for its name and folder, then it opens here (sys.endIslandPick, kind "editor")
    function newFile() {
        if (view.sys.editorDirty) { view.after = "new"; view.confirmClose = true; return; }
        view.sys.startIslandPick({ kind: "editor", save: true, title: "New text file", accept: "Create",
                                   name: "Untitled.txt",
                                   folder: view.path ? view.path.replace(/\/[^\/]*$/, "") : Quickshell.env("HOME") });
    }
    function proceed() {
        var a = view.after; view.after = ""; view.confirmClose = false;
        if (a === "new") view.newFile(); else view.sys.collapse();
    }
    // the shell keeps the buffer: reopening the page shows what was there, saved or not
    function open() {
        view.error = "";
        if (!view.path) return;
        if (view.sys.editorDirty) { view.setting = true; ta.text = view.sys.editorBuffer; view.setting = false; return; }
        view.loading = true;
        file.reload();
    }
    function save() {
        if (!view.path) return;
        file.setText(ta.text);
    }
    function remember(p) {
        var r = (view.sys.cfg.editorRecent || []).filter(x => x !== p);
        r.unshift(p);
        view.sys.cfg.editorRecent = r.slice(0, 8);
        view.sys.saveCfg();
    }
    function findNext(back) {
        var q = find.text;
        if (!q) return;
        var s = ta.text.toLowerCase(), needle = q.toLowerCase();
        var from = back ? ta.selectionStart - 1 : ta.selectionEnd;
        var i = back ? s.lastIndexOf(needle, Math.max(0, from)) : s.indexOf(needle, from);
        if (i < 0) i = back ? s.lastIndexOf(needle) : s.indexOf(needle);
        if (i >= 0) ta.select(i, i + q.length);
    }
    readonly property int matches: {
        var q = find.text.toLowerCase();
        if (!q || !view.finding) return 0;
        var s = ta.text.toLowerCase(), n = 0, i = s.indexOf(q);
        while (i >= 0 && n < 9999) { n++; i = s.indexOf(q, i + q.length); }
        return n;
    }

    FileView {
        id: file
        path: view.path
        printErrors: false
        atomicWrites: false          // in place: Quickshell and other watchers keep seeing the same file
        blockWrites: true
        onLoaded: {
            view.loading = false;
            var s = text();
            if (s.length > view.maxBytes) { view.error = "This file is too large for the editor."; return; }
            view.setting = true; ta.text = s; view.setting = false;
            view.sys.editorDirty = false;
            view.remember(view.path);
        }
        onLoadFailed: { view.loading = false; view.setting = true; ta.text = ""; view.setting = false; view.sys.editorDirty = false; view.remember(view.path); }   // a new file
        onSaved: { view.sys.editorDirty = false; savedTip.restart(); if (view.after) view.proceed(); }
        onSaveFailed: view.error = "Couldn't save. Is the folder writable?"
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.s3

        PkHeader {
            id: hdr
            sys: view.sys; width: parent.width
            title: view.name; sub: view.dir || "Open a file to edit it"
            dirty: view.sys.editorDirty
            PkText { sys: view.sys; role: "sub"; anchors.verticalCenter: parent.verticalCenter; text: "Saved"
                     opacity: savedTip.running ? 1 : 0; Behavior on opacity { NumberAnimation { duration: view.t.dBase } }
                     Timer { id: savedTip; interval: 1400 } }
            PkIconButton { sys: view.sys; icon: "plus"; size: view.t.iMd; onClicked: view.newFile() }
            PkIconButton { sys: view.sys; visible: !!view.path; icon: "magnifying-glass"; size: view.t.iMd; selected: view.finding
                           onClicked: { view.finding = !view.finding; if (view.finding) find.input.forceActiveFocus(); else ta.forceActiveFocus(); } }
            PkIconButton { sys: view.sys; visible: !!view.path; icon: "text-align-left"; size: view.t.iMd; selected: view.wrap
                           onClicked: view.wrap = !view.wrap }
            PkIconButton { sys: view.sys; visible: !!view.path; icon: "folder-open"; size: view.t.iMd
                           onClicked: { view.sys.editorPath = ""; } }
            PkButton { sys: view.sys; visible: !!view.path; kind: view.sys.editorDirty ? "primary" : "secondary"; small: true; text: "Save"
                       anchors.verticalCenter: parent.verticalCenter; enabled: view.sys.editorDirty; onClicked: view.save() }
        }

        // unsaved changes, asked once on Escape
        PkCard {
            id: confirmCard
            sys: view.sys; width: parent.width; height: 52; visible: view.confirmClose
            PkText { sys: view.sys; role: "label"; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Save your changes?" }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                PkButton { sys: view.sys; small: true; kind: "ghost"; text: "Keep editing"; onClicked: { view.confirmClose = false; view.after = ""; ta.forceActiveFocus(); } }
                PkButton { sys: view.sys; small: true; kind: "danger"; text: "Discard"
                           onClicked: { view.sys.editorDirty = false; view.sys.editorBuffer = ""; view.proceed(); } }
                PkButton { sys: view.sys; small: true; kind: "primary"; text: "Save"; onClicked: view.save() }
            }
        }

        PkText { id: errText; sys: view.sys; visible: view.error !== ""; x: 6; text: view.error; color: view.t.accentText }

        // no file: a path, and the recent ones
        Column {
            width: parent.width; spacing: view.t.groupGap
            visible: !view.path
            PkField {
                id: pathField
                sys: view.sys; width: parent.width
                placeholder: "Path to a file, e.g. ~/.config/hypr/custom/general.lua"
                onAccepted: {
                    var p = text.trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
                    if (!p) return;
                    if (p.charAt(0) !== "/") p = Quickshell.env("HOME") + "/" + p;
                    view.sys.editorPath = p; text = ""; view.open(); ta.forceActiveFocus();
                }
            }
            PkSection {
                sys: view.sys; width: parent.width; title: "Recent"
                visible: (view.sys.cfg.editorRecent || []).length > 0
                Repeater {
                    model: view.sys.cfg.editorRecent || []
                    delegate: PkRow {
                        required property string modelData
                        sys: view.sys; interactive: true; icon: "file-text"
                        title: modelData.replace(/.*\//, "")
                        sub: modelData.replace(/\/[^\/]*$/, "").replace(new RegExp("^" + Quickshell.env("HOME")), "~")
                        onClicked: { view.sys.editorPath = modelData; view.open(); }
                    }
                }
            }
        }

        // the text
        Rectangle {
            id: page
            visible: !!view.path
            width: parent.width
            // as tall as the island lets a page be
            height: Math.max(220, (view.sys.pageMaxH || 545) - hdr.height - statusRow.height - 2 * col.spacing
                                  - (confirmCard.visible ? confirmCard.height + col.spacing : 0)
                                  - (errText.visible ? errText.height + col.spacing : 0))
            radius: view.t.rSurface; color: view.t.surfaceLow; clip: true

            // line numbers (hidden while wrapping: a wrapped line has no single number)
            Text {
                id: gutter
                visible: !view.wrap
                x: 10; y: 10 - fl.contentY + ta.topPadding
                width: 34
                horizontalAlignment: Text.AlignRight
                color: view.t.faint
                font: ta.font
                lineHeight: 1; lineHeightMode: Text.ProportionalHeight
                text: { var n = ta.lineCount, s = ""; for (var i = 1; i <= n; i++) s += i + "\n"; return s; }
            }
            Flickable {
                id: fl
                anchors.fill: parent; anchors.margins: 10
                anchors.leftMargin: view.wrap ? 12 : 52
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                TextArea.flickable: TextArea {
                    id: ta
                    background: null
                    leftPadding: 0; rightPadding: 8; topPadding: 0; bottomPadding: 40
                    color: view.t.fg
                    selectionColor: view.t.veil(0.22); selectedTextColor: view.t.fg
                    selectByMouse: true; persistentSelection: true
                    textFormat: TextEdit.PlainText
                    wrapMode: view.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                    font { family: view.t.font; pixelSize: view.t.tBody }
                    tabStopDistance: 4 * fontMetrics.averageCharacterWidth
                    readOnly: view.loading || view.error !== ""
                    onTextChanged: if (!view.setting) { view.sys.editorDirty = true; view.sys.editorBuffer = text; }
                    Keys.onPressed: e => {
                        if (e.modifiers & Qt.ControlModifier) {
                            if (e.key === Qt.Key_S) { view.save(); e.accepted = true; }
                            else if (e.key === Qt.Key_N) { view.newFile(); e.accepted = true; }
                            else if (e.key === Qt.Key_F) { view.finding = true; find.input.forceActiveFocus(); find.input.selectAll(); e.accepted = true; }
                        } else if (e.key === Qt.Key_Escape) { view.leave(); e.accepted = true; }
                    }
                }
            }
            FontMetrics { id: fontMetrics; font: ta.font }

            // find: a raised pill floating over the text
            Rectangle {
                visible: view.finding
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                width: 300; height: 44; radius: 22; color: view.t.raised
                PkSearch {
                    id: find
                    sys: view.sys; x: 5; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 10 - countText.width - prevBtn.width - nextBtn.width - 8; height: 34
                    placeholder: "Find"
                    color: "transparent"
                    onAccepted: view.findNext(false)
                    Keys.onEscapePressed: { view.finding = false; ta.forceActiveFocus(); }
                }
                PkText { id: countText; sys: view.sys; role: "sub"; anchors.right: prevBtn.left; anchors.rightMargin: 2
                         anchors.verticalCenter: parent.verticalCenter; text: find.text ? String(view.matches) : "" }
                PkIconButton { id: prevBtn; sys: view.sys; icon: "caret-up"; size: 14; anchors.right: nextBtn.left
                               anchors.verticalCenter: parent.verticalCenter; onClicked: view.findNext(true) }
                PkIconButton { id: nextBtn; sys: view.sys; icon: "caret-down"; size: 14; anchors.right: parent.right; anchors.rightMargin: 4
                               anchors.verticalCenter: parent.verticalCenter; onClicked: view.findNext(false) }
            }
        }

        // status line
        Row {
            id: statusRow
            visible: !!view.path
            x: 6; spacing: 14
            PkText { sys: view.sys; role: "sub"; text: "Ln " + (ta.text.slice(0, ta.cursorPosition).split("\n").length) + ", Col " + (ta.cursorPosition - ta.text.lastIndexOf("\n", ta.cursorPosition - 1)) }
            PkText { sys: view.sys; role: "sub"; text: ta.lineCount + " lines" }
            PkText { sys: view.sys; role: "sub"; text: "Ctrl+S save  ·  Ctrl+F find  ·  Ctrl+N new" ; color: view.t.faint }
        }
    }
}
