import QtQuick
import QtQuick.Layouts

// written by portal-patch.py (panacea-island) - the island chats' message box (the Claude chat's,
// as patched by chat-patch.py): + (files: off until boopis takes them), the text (Enter sends,
// Shift+Enter a new line), the mic (dictation into this box), send / stop. Used by BotChat and
// BotRoom. `keyHook(event)` sees keys first (the @name picker).
Rectangle {
    id: ch
    property var sys
    readonly property var t: sys.pk
    property string placeholder: ""
    property bool busy: false
    property bool canStop: busy
    property var keyHook: null
    property alias input: input
    property alias text: input.text
    signal send(string text)
    signal stop()
    signal escaped()
    readonly property real islandR: sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real boxR: Math.max(14, islandR - 6)
    readonly property real rInner: Math.max(8, boxR - 6)
    readonly property bool voxHere: sys.voxTo === "chat" && sys.voxState !== ""
    // dictation (the mic, or the voxtype key while this chat is open) lands at the cursor
    Connections {
        target: ch.sys
        function onVoxChatTextArrived(text) {
            if (!ch.visible) return;
            var pos = input.cursorPosition, pre = input.text.slice(0, pos);
            input.insert(pos, (pre.length && !/\s$/.test(pre) ? " " : "") + text);
            input.forceActiveFocus();
        }
    }
    function doSend() { var s = input.text.trim(); if (!s) return; ch.send(s); input.text = ""; }
    implicitHeight: Math.max(50, Math.min(110, input.contentHeight + 20))
    radius: ch.boxR
    color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.055)
    Behavior on color { ColorAnimation { duration: 150 } }
    RowLayout {
        anchors.fill: parent; anchors.margins: 6; spacing: 8
        Rectangle {   // dictating: drop it
            visible: ch.voxHere
            Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: ch.rInner
            color: voxDropMa.containsMouse ? ch.t.hover : "transparent"
            Behavior on color { ColorAnimation { duration: ch.t.dFast } }
            PkIcon { sys: ch.sys; anchors.centerIn: parent; size: 18; name: "x"
                     color: voxDropMa.containsMouse ? ch.t.fg : ch.t.muted }
            MouseArea { id: voxDropMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: ch.sys.voxRun("cancel", "") }
        }
        Item {   // attach: shown as in the Claude chat, off until boopis takes files from the island
            visible: !ch.voxHere
            Layout.preferredWidth: 36; Layout.preferredHeight: 36
            opacity: 0.35
            PanaceaClaudeIcon { anchors.centerIn: parent; width: 18; height: 18; kind: "attach"; tint: ch.sys.colMuted }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            PkVoiceWave {
                sys: ch.sys; anchors.fill: parent; anchors.topMargin: 9; anchors.bottomMargin: 9
                visible: ch.voxHere
                listening: ch.voxHere && ch.sys.voxState === "listening"
                busy: ch.voxHere && ch.sys.voxState === "transcribing"
            }
            Flickable {
                id: inputScroll; anchors.fill: parent; clip: true
                visible: !ch.voxHere
                contentWidth: width; contentHeight: Math.max(height, input.contentHeight)
                TextEdit {
                    id: input; focus: true; width: inputScroll.width; y: Math.max(0, (inputScroll.height - contentHeight) / 2); height: contentHeight
                    color: ch.sys.colFg; font { family: ch.sys.fontBody; pixelSize: 13 }
                    wrapMode: TextEdit.Wrap; selectByMouse: true
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + cursorRectangle.height > inputScroll.contentY + inputScroll.height) inputScroll.contentY = cursorRectangle.y + cursorRectangle.height - inputScroll.height;
                        else if (cursorRectangle.y < inputScroll.contentY) inputScroll.contentY = cursorRectangle.y;
                    }
                    Keys.onEscapePressed: ch.escaped()
                    Keys.onPressed: event => {
                        if (ch.keyHook && ch.keyHook(event)) { event.accepted = true; return; }
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) { ch.doSend(); event.accepted = true; }
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text
                       text: ch.placeholder; color: ch.sys.colMuted
                       font { family: ch.sys.fontBody; pixelSize: 13 } }
            }
        }
        Rectangle {   // the mic; while it listens, a white check that ends it
            readonly property bool rec: ch.voxHere && ch.sys.voxState === "listening"
            readonly property bool wait: ch.voxHere && ch.sys.voxState === "transcribing"
            Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: ch.rInner
            color: rec ? (micMa.containsMouse ? Qt.rgba(1, 1, 1, 0.85) : ch.t.on)
                       : (micMa.containsMouse ? ch.t.hover : "transparent")
            Behavior on color { ColorAnimation { duration: ch.t.dFast } }
            PkIcon { sys: ch.sys; anchors.centerIn: parent; size: 18
                     name: parent.rec || parent.wait ? "check" : "microphone"
                     color: parent.rec ? ch.t.onInk : micMa.containsMouse ? ch.t.fg : ch.t.muted
                     opacity: parent.wait ? 0.45 : 1 }
            MouseArea { id: micMa; anchors.fill: parent; hoverEnabled: true; enabled: !parent.wait
                        cursorShape: Qt.PointingHandCursor; onClicked: ch.sys.voxRun("toggle", "chat") }
        }
        Rectangle {
            visible: !ch.voxHere
            readonly property bool ready: input.text.trim().length > 0
            readonly property bool stop: ch.canStop && !ready
            Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: ch.rInner
            color: ready ? ch.sys.colFg : stop ? (stopMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.1)) : Qt.rgba(1, 1, 1, 0.06)
            Behavior on color { ColorAnimation { duration: 150 } }
            PanaceaClaudeIcon { anchors.centerIn: parent; width: 18; height: 18; kind: "send"; visible: !parent.stop
                                tint: parent.ready ? ch.sys.colBg : ch.sys.colMuted }
            Rectangle { anchors.centerIn: parent; visible: parent.stop; width: 10; height: 10; radius: 2.5; color: ch.sys.colFg }
            MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: parent.ready || parent.stop
                        onClicked: parent.stop ? ch.stop() : ch.doSend() }
        }
    }
}
