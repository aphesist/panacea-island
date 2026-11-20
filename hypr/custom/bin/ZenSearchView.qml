pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Zen's address bar, in the island.
// Talks to Zen through the "Panacea for Zen" add-on (panacea-zen CLI -> native host
// socket): your tabs, bookmarks, history and search suggestions as you type; Enter opens
// in the current tab, Alt/Ctrl+Enter (or middle click) in a new one, a tab row switches to
// that tab. Plain code, no AI. Opened by `qs ipc call pill zen` / `zenNew`.
FocusScope {
    id: view
    property var sys
    implicitHeight: col.implicitHeight
    focus: true

    readonly property real islandR: sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real boxR: Math.max(14, islandR - 6)
    readonly property real rInner: Math.max(8, boxR - 6)
    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/panacea-zen"
    readonly property string focusZen: "hyprctl dispatch 'hl.dsp.focus({ window = \"class:^(zen)$\" })' >/dev/null 2>&1"
    readonly property int maxRows: 8

    property bool newTab: !!sys.zenNewTab
    // Claude mode (the logo at the right of the field; Ctrl+Shift toggles it, Ctrl+Shift+T in
    // Zen opens the search with it on): Enter hands the address or search to the island chat
    // instead of opening it, so Claude opens it and takes your instructions
    property bool claude: false
    FileView { id: claudeFlag; path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/panacea-zen-claude"
               blockLoading: true; printErrors: false }
    Component.onCompleted: {
        var t = Number(String(claudeFlag.text() || "").trim());
        if (t && Math.abs(Date.now() - t) < 3000) view.claude = true;   // written by panacea-dock.uc.js just now
        suggestTimer.start();
    }
    function toggleClaude() { view.claude = !view.claude; if (view.claude) claudeSpin.restart(); }
    function sendClaude(target, isSearch) {
        sys.chatDraft = (isSearch ? "Search in Zen: " : "Open in Zen: ") + target + "\n";
        sys.chatAskSend = false;
        sys.chatAskRev++;
        sys.page = "chat"; sys.expanded = true; sys.holdOpen = true;
    }
    property string query: ""
    property string asked: ""          // the query the shown results belong to
    property var items: []
    property int index: 0
    property bool connected: true
    property string currentUrl: ""
    property bool edited: false        // the field still shows the current address, untouched
    property bool picked: false        // a row was chosen with the arrows or the mouse

    function goBack() { return false; }

    // ---------------------------------------------------------------- talking to Zen
    Process {
        id: pCurrent
        command: [view.cli, "current"]
        running: !view.newTab
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    if (d.error) { view.connected = false; return; }
                    view.currentUrl = d.url || "";
                    if (!view.edited && view.currentUrl && !/^about:/.test(view.currentUrl)) {
                        input.text = view.currentUrl;
                        input.selectAll();
                        view.edited = false;
                    }
                } catch (e) {}
            }
        }
    }
    Process {
        id: pSuggest
        property string q: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    if (d.error) { view.connected = false; view.items = []; }
                    else { view.connected = true; view.items = d.items || []; view.asked = pSuggest.q; }
                } catch (e) {}
                if (pSuggest.q !== view.suggestText()) suggestTimer.restart();   // typed meanwhile
            }
        }
    }
    function suggestText() { return view.edited ? view.query.trim() : ""; }
    Timer {
        id: suggestTimer
        interval: 70
        onTriggered: {
            if (pSuggest.running) return;   // its finish handler re-asks
            pSuggest.q = view.suggestText();
            pSuggest.command = [view.cli, "suggest", pSuggest.q];
            pSuggest.running = true;
        }
    }

    onQueryChanged: { index = 0; picked = false; suggestTimer.restart(); }
    onItemsChanged: if (rows && index >= rows.length) index = Math.max(0, rows.length - 1)

    // what the list shows: the add-on's rows, or a single "open Zen" row when it isn't there
    readonly property var rows: {
        if (!connected) {
            var t = query.trim();
            return [{ type: "launch", title: t ? "Open in Zen: " + t : "Open Zen", text: t }];
        }
        return items;
    }

    // ---------------------------------------------------------------- actions
    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd + " >/dev/null 2>&1; " + view.focusZen]);
    }
    function launch(forceNew) {
        var it = rows[index];
        var nt = view.newTab || !!forceNew;
        var typed = query.trim();
        if (!it && !typed) return;
        if (!it || (!view.edited && !view.picked && typed)) it = { type: "url", url: typed };   // Enter on the untouched address: reload it
        if (view.claude) {
            var tgt = it.type === "launch" ? (it.text || typed) : (it.url || it.text || typed);
            if (tgt) view.sendClaude(tgt, it.type === "search" || it.type === "suggestion");
            return;
        }
        var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; };
        if (it.type === "launch") {
            Quickshell.execDetached(["sh", "-c", "zen-browser \"$@\" >/dev/null 2>&1 &", "_"].concat(it.text ? [it.text] : []));
        } else if (it.type === "tab") {
            run(view.cli + " switch " + Number(it.tabId));
        } else {
            var target = it.url || it.text || typed;
            run(view.cli + " open " + q(target) + (nt ? " --new" : ""));
        }
        sys.collapse();
    }
    function move(d) {
        if (!rows.length) return;
        view.picked = true;
        index = Math.max(0, Math.min(rows.length - 1, index + d));
        list.positionViewAtIndex(index, ListView.Contain);
    }

    function glyphFor(t) {
        switch (t) {
        case "tab":        return String.fromCodePoint(0xF04E9);   // md-tab
        case "bookmark":   return String.fromCodePoint(0xF04CE);   // md-star
        case "history":    return String.fromCodePoint(0xF02DA);   // md-history
        case "url":        return String.fromCodePoint(0xF059F);   // md-web
        case "launch":     return String.fromCodePoint(0xF059F);
        }
        return String.fromCodePoint(0xF0349);                      // md-magnify
    }
    function iconFor(it) {
        if (!it.url || !/^https?:/.test(it.url)) return "";
        var h = it.host || "";
        if (!h) { var m = String(it.url).match(/^https?:\/\/([^\/:?#]+)/); h = m ? m[1] : ""; }
        var f = (view.sys.zenIcons || {})[h];
        return f ? "file://" + f : "";
    }
    function titleFor(it) {
        if (it.type === "search") return it.text;
        if (it.type === "suggestion") return it.text;
        return it.title || it.url || "";
    }
    function subFor(it) {
        switch (it.type) {
        case "search":     return "Search" + (it.engine ? " with " + it.engine : "");
        case "suggestion": return it.engine ? it.engine + " suggestion" : "Suggestion";
        case "tab":        return "Switch to tab · " + (it.host || "");
        case "bookmark":   return "Bookmark · " + (it.host || it.url || "");
        case "history":    return it.host || it.url || "";
        case "url":        return "Go to " + (it.host || it.url || "");
        case "launch":     return "Zen isn't running";
        }
        return "";
    }

    FocusGrabber { target: input }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 8

        // ------------------------------------------------------------ the field
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: view.rInner + 4
            color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.055)
            Behavior on color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: String.fromCodePoint(0xF059F)
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                TextField {
                    id: input
                    focus: true
                    Layout.fillWidth: true
                    placeholderText: view.claude ? "Send to Claude: search or address" : view.newTab ? "New tab: search or address" : "Search or address"
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    selectionColor: Qt.rgba(1, 1, 1, 0.25)
                    selectedTextColor: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 13 }
                    background: null
                    onTextEdited: { view.edited = true; view.query = text; }
                    onTextChanged: if (!view.edited) view.query = text

                    Keys.onDownPressed: view.move(1)
                    Keys.onUpPressed: view.move(-1)
                    Keys.onTabPressed: view.move(1)
                    Keys.onBacktabPressed: view.move(-1)
                    Keys.onEscapePressed: view.sys.collapse()
                    // Ctrl+Shift on its own (either order) toggles Claude mode, on release, so
                    // Ctrl+Shift+arrows (select by word) and the like don't
                    property bool chord: false
                    Keys.onReleased: event => {
                        if (input.chord && (event.key === Qt.Key_Shift || event.key === Qt.Key_Control)) {
                            input.chord = false;
                            view.toggleClaude();
                        }
                    }
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Shift && (event.modifiers & Qt.ControlModifier))
                            || (event.key === Qt.Key_Control && (event.modifiers & Qt.ShiftModifier))) {
                            input.chord = true;
                            return;
                        }
                        input.chord = false;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            view.launch(event.modifiers & (Qt.AltModifier | Qt.ControlModifier));
                            event.accepted = true;
                        }
                    }
                }
                Item {
                    // Claude mode: dim off, orange on (spins once when turned on); click toggles
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Shape {
                        id: claudeLogo
                        anchors.centerIn: parent
                        width: 16; height: 16
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer
                        RotationAnimation on rotation { id: claudeSpin; running: false; from: 0; to: 360; duration: 650; easing.type: Easing.OutCubic }
                        ShapePath {
                            scale: Qt.size(16 / 24, 16 / 24)
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillColor: view.claude ? "#d97757" : (claudeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.28))
                            Behavior on fillColor { ColorAnimation { duration: 200 } }
                            PathSvg { path: "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" }
                        }
                    }
                    MouseArea {
                        id: claudeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.toggleClaude(); input.forceActiveFocus(); }
                    }
                }
            }
        }

        // ------------------------------------------------------------ results
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(view.rows.length, view.maxRows) * 46
            visible: view.rows.length > 0
            clip: true
            model: view.rows
            currentIndex: view.index
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: 44
                radius: view.rInner + 4
                color: index === view.index ? Qt.rgba(1, 1, 1, 0.10)
                     : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        // the site's icon (panacea-dock.uc.js caches them), else a glyph
                        Image {
                            id: fav
                            anchors.centerIn: parent
                            width: 16; height: 16
                            sourceSize: Qt.size(32, 32)
                            smooth: true
                            source: view.iconFor(row.modelData)
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !fav.visible
                            text: view.glyphFor(row.modelData.type)
                            color: row.modelData.type === "tab" ? view.sys.colFg : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 15 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: view.titleFor(row.modelData)
                            color: view.sys.colFg
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font { family: view.sys.fontFam; pixelSize: 13; bold: row.index === view.index }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: view.subFor(row.modelData)
                            color: view.sys.colMuted
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font { family: view.sys.fontFam; pixelSize: 10 }
                        }
                    }
                    Text {
                        visible: row.index === view.index
                        text: "󰌑"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 12 }
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { view.index = row.index; view.picked = true; }
                    onClicked: mouse => view.launch(mouse.button === Qt.MiddleButton)
                }
            }
        }
    }
}
