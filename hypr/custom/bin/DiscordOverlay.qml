pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// written by portal-patch.py (panacea-island) - the Discord voice overlay in the screen's
// top-right corner while you're in a call: everyone's picture, a ring while they talk, a small
// badge when they're muted or deafened. "row": level with the island, like the workspace dots
// on the left; "list": a column with names, like Discord's own overlay. Never takes a click.
// Settings > Discord. State: sys.discord (DiscordVoice.qml).
PanelWindow {
    id: ov
    property var sys
    readonly property var t: sys.pk
    readonly property var dc: sys.discord
    readonly property var cfg: sys.cfg
    readonly property bool listMode: cfg.discordOverlayLayout === "list"
    readonly property int size: cfg.discordOverlaySize || 20
    readonly property color ring: cfg.discordRing === "white" ? t.on : "#23a55a"

    screen: sys.screen
    anchors { top: true; right: true }
    implicitWidth: Math.max(1, (listMode ? lst.implicitWidth : rw.implicitWidth) + 22 + 8)
    implicitHeight: listMode ? Math.max(1, lst.implicitHeight + 20) : Math.max(sys.pillH, size + 12)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: cfg.discordOverlayFull ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "panacea-discord"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    visible: cfg.discordEnabled && cfg.discordOverlay && dc.inCall && (cfg.discordOverlayFull || !sys.fullscreenActive)

    function shown(p) {
        if (p.me && !cfg.discordOverlaySelf) return false;
        return cfg.discordOverlayMode !== "speaking" || (p.speaking && !p.muted);
    }

    // ---- one person: picture, ring, badge
    component Face: Item {
        id: face
        required property var p
        width: ov.size + 8; height: ov.size + 8
        readonly property bool talking: face.p.speaking && !face.p.muted
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"
                    border.width: Math.max(2, Math.round(ov.size / 16)); border.color: ov.ring
                    opacity: face.talking ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: ov.t.dFast } } }
        PkRoundImage { sys: ov.sys; anchors.centerIn: parent; width: ov.size; height: ov.size; radius: ov.size / 2
                       source: face.p.avatar; sourceSize: Qt.size(ov.size * 2, ov.size * 2)
                       opacity: face.talking || !ov.cfg.discordOverlayDim ? 1 : 0.55
                       Behavior on opacity { NumberAnimation { duration: ov.t.dBase } } }
        Rectangle {
            visible: face.p.muted || face.p.deafened
            readonly property int d: Math.max(14, Math.round(ov.size * 0.46))
            width: d; height: d; radius: d / 2; color: "#000000"
            anchors.right: parent.right; anchors.bottom: parent.bottom
            PkIcon { sys: ov.sys; anchors.centerIn: parent; size: parent.d - 5; filled: true
                     name: face.p.deafened ? "speaker-slash" : "microphone-slash"
                     color: face.p.serverMute || face.p.serverDeaf ? ov.t.accent : ov.t.soft }
        }
    }

    // row: right to left from the corner, centred on the island's height
    Row {
        id: rw
        visible: !ov.listMode
        anchors.right: parent.right; anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        layoutDirection: Qt.RightToLeft
        spacing: 4
        Repeater {
            model: ov.dc.people
            delegate: Face {
                required property var model
                p: model
                visible: ov.shown(model)
            }
        }
    }

    // list: a column under the corner, names on the left of the faces
    Column {
        id: lst
        visible: ov.listMode
        anchors.right: parent.right; anchors.rightMargin: 22
        y: 10
        spacing: 4
        Repeater {
            model: ov.dc.people
            delegate: Row {
                id: line
                required property var model
                visible: ov.shown(model)
                anchors.right: parent.right
                layoutDirection: Qt.RightToLeft
                spacing: 8
                Face { p: line.model }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: nm.implicitWidth + 20; height: Math.max(22, ov.size * 0.7); radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Text { id: nm; anchors.centerIn: parent; text: line.model.name
                           color: line.model.speaking && !line.model.muted ? ov.t.fg : ov.t.soft
                           font { family: ov.t.font; pixelSize: ov.t.tLabel; weight: Font.DemiBold } }
                }
            }
        }
    }
}
