pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// written by portal-patch.py (panacea-island) - the island's Discord tab (Vesktop): mute,
// deafen, noise suppression and leave; everyone in the call with a ring while they talk, and
// per person a volume and a mute for you only. State and commands: sys.discord (DiscordVoice.qml).
FocusScope {
    id: view
    property var sys
    readonly property var t: sys.pk
    readonly property var dc: sys.discord
    // The island follows implicitHeight; report the list's final height at once (not its
    // animated one), so the island and the list start on the same spring at the same moment.
    implicitHeight: col.implicitHeight + (view.dc.inCall ? listH.to - list.height : 0)
    focus: true
    readonly property int extraH: 48     // the volume row under an open person
    readonly property real listMax: Math.max(120, (view.sys.pageMaxH || 545) - 260)
    PkMorph { id: listH; ms: view.sys.animMs; bounce: view.sys.animBounce; still: view.sys.noMotion
              to: Math.min(view.dc.people.count * view.t.rowH2 + (view.openId ? view.extraH : 0), view.listMax) }

    property string openId: ""          // the person whose volume is open
    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: view.visible && view.dc.inCall; onTriggered: view.now = Date.now() }

    function goBack() { if (view.openId) { view.openId = ""; return true; } return false; }
    Keys.onEscapePressed: if (!goBack()) sys.collapse()
    function clock(ms) {
        var s = Math.max(0, Math.floor(ms / 1000)), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        s %= 60;
        return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }
    readonly property color ring: view.sys.cfg.discordRing === "white" ? view.t.on : "#23a55a"

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader {
            sys: view.sys; width: parent.width
            title: view.dc.inCall ? view.dc.channel : "Discord"
            sub: view.dc.inCall ? [view.dc.guild, view.clock(view.now - view.dc.since), view.dc.ping ? view.dc.ping + " ms" : ""].filter(x => x).join("  ·  ")
               : view.dc.up ? "Not in a call" : view.dc.why === "restart" ? "Restart Discord to connect" : view.dc.why === "noflag" ? "Not connected" : "Not running"
            PkIconButton { sys: view.sys; icon: "arrow-square-out"; onClicked: { view.dc.focusApp(); view.sys.collapse(); } }
        }

        // ---- your controls
        Row {
            visible: view.dc.inCall
            width: parent.width; spacing: view.t.gap
            readonly property real w: (width - 3 * spacing) / 4
            PkTile { sys: view.sys; width: parent.w; on: view.dc.mute
                     icon: view.dc.mute ? "microphone-slash" : "microphone"; title: "Mute"; sub: view.dc.mute ? "Muted" : "Mic on"
                     onToggled: view.dc.toggleMute() }
            PkTile { sys: view.sys; width: parent.w; on: view.dc.deaf
                     icon: view.dc.deaf ? "speaker-slash" : "headphones"; title: "Deafen"; sub: view.dc.deaf ? "Deafened" : "Hearing"
                     onToggled: view.dc.toggleDeaf() }
            PkTile { sys: view.sys; width: parent.w; on: view.dc.noise === true; opacity: view.dc.noise === null ? 0.4 : 1
                     icon: "waveform"; title: "Noise"; sub: view.dc.noise === null ? "Unavailable" : view.dc.noise ? "Suppressed" : "Off"
                     onToggled: if (view.dc.noise !== null) view.dc.toggleNoise() }
            PkCard {
                id: leave
                sys: view.sys; interactive: true; width: parent.w; height: 86
                onClicked: view.dc.disconnect()
                PkIcon { sys: view.sys; x: 14; y: 14; name: "phone-disconnect"; filled: leave.hovered; size: view.t.iLg; color: view.t.accent }
                Column {
                    x: 14; width: parent.width - 28; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; spacing: 1
                    PkText { sys: view.sys; role: "label"; width: parent.width; text: "Leave" }
                    PkText { sys: view.sys; role: "sub"; width: parent.width; text: "Disconnect" }
                }
            }
        }

        // ---- who's in the call
        PkSection {
            visible: view.dc.inCall
            sys: view.sys; width: parent.width
            title: "In voice  ·  " + view.dc.people.count
            ListView {
                id: list
                width: parent.width
                height: listH.value
                clip: true; interactive: contentHeight > view.listMax + 1
                boundsBehavior: Flickable.StopAtBounds
                model: view.dc.people
                delegate: Item {
                    id: person
                    required property string uid
                    required property string name
                    required property string avatar
                    required property bool me
                    required property bool muted
                    required property bool deafened
                    required property bool serverMute
                    required property bool video
                    required property bool stream
                    required property bool speaking
                    required property bool localMute
                    required property int volume
                    readonly property bool open: view.openId === uid && !me
                    width: list.width
                    // the island's spring, so the row opens with the island
                    PkMorph { id: rowH; ms: view.sys.animMs; bounce: view.sys.animBounce; still: view.sys.noMotion
                              to: view.t.rowH2 + (person.open ? view.extraH : 0) }
                    height: rowH.value
                    readonly property real room: Math.max(0, Math.min(1, (height - view.t.rowH2) / view.extraH))
                    clip: true
                    Component.onDestruction: if (view.openId === uid) view.openId = ""   // they left

                    Rectangle {   // hover: a short tween
                        anchors.fill: parent; anchors.margins: 2; radius: view.t.rControl
                        color: view.t.hover
                        opacity: rowMa.containsMouse && !person.me ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: view.t.dFast } }
                    }
                    Rectangle {   // open: follows the row's spring
                        anchors.fill: parent; anchors.margins: 2; radius: view.t.rControl
                        color: view.t.selected; opacity: person.room
                    }
                    MouseArea { id: rowMa; width: parent.width; height: view.t.rowH2; hoverEnabled: true
                                cursorShape: person.me ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: if (!person.me) view.openId = person.open ? "" : person.uid }

                    // avatar, with the ring while they talk
                    Item {
                        id: av
                        x: 12; y: (view.t.rowH2 - height) / 2; width: 34; height: 34
                        Rectangle { anchors.centerIn: parent; width: parent.width + 6; height: width; radius: width / 2
                                    color: "transparent"; border.width: 2; border.color: view.ring
                                    opacity: person.speaking && !person.muted ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: view.t.dFast } } }
                        PkRoundImage { sys: view.sys; anchors.fill: parent; radius: width / 2; source: person.avatar
                                       sourceSize: Qt.size(96, 96); opacity: person.localMute ? 0.4 : 1 }
                    }
                    Column {
                        anchors.left: av.right; anchors.leftMargin: 12; anchors.right: icons.left; anchors.rightMargin: 8
                        y: (view.t.rowH2 - height) / 2; spacing: 1
                        PkText { sys: view.sys; role: "body"; width: parent.width; text: person.name + (person.me ? "  (you)" : ""); elide: Text.ElideRight }
                        PkText { sys: view.sys; role: "sub"; width: parent.width; elide: Text.ElideRight
                                 visible: text !== ""
                                 text: [person.localMute ? "Muted for you" : (!person.me && person.volume !== 100 ? person.volume + "%" : ""),
                                        person.serverMute ? "Server muted" : "", person.stream ? "Live" : ""].filter(x => x).join("  ·  ") }
                    }
                    Row {
                        id: icons
                        anchors.right: parent.right; anchors.rightMargin: 14; y: (view.t.rowH2 - height) / 2; spacing: 10
                        PkIcon { sys: view.sys; visible: person.stream; name: "screencast"; size: view.t.iSm; color: view.t.soft }
                        PkIcon { sys: view.sys; visible: person.video; name: "video-camera"; size: view.t.iSm; color: view.t.soft }
                        PkIcon { sys: view.sys; visible: person.muted && !person.deafened; name: "microphone-slash"; size: view.t.iSm
                                 color: person.serverMute ? view.t.accent : view.t.muted }
                        PkIcon { sys: view.sys; visible: person.deafened; name: "speaker-slash"; size: view.t.iSm; color: view.t.muted }
                        PkIcon { sys: view.sys; visible: !person.me; name: person.open ? "caret-up" : "caret-down"; size: 13; color: view.t.faint }
                    }

                    // their volume, for you only
                    Item {
                        visible: person.room > 0.01
                        opacity: person.room * person.room   // shows as far as the row has room
                        y: view.t.rowH2; x: 12; width: parent.width - 24; height: 44
                        PkIconButton { id: lm; sys: view.sys; anchors.verticalCenter: parent.verticalCenter
                                       icon: person.localMute ? "speaker-slash" : "speaker-high"; selected: person.localMute
                                       onClicked: view.dc.toggleLocalMute(person.uid) }
                        PkSlider { id: vol; sys: view.sys; anchors.left: lm.right; anchors.leftMargin: 10; anchors.right: pct.left; anchors.rightMargin: 12
                                   anchors.verticalCenter: parent.verticalCenter
                                   value: (pct.live >= 0 ? pct.live : person.volume) / 200
                                   onMoved: v => { pct.live = Math.round(v * 200); setLater.restart(); } }
                        PkText { id: pct; sys: view.sys; role: "label"; property int live: -1
                                 anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 44
                                 horizontalAlignment: Text.AlignRight
                                 text: (live >= 0 ? live : person.volume) + "%" }
                        // sent to Discord once the knob rests for 60 ms
                        Timer { id: setLater; interval: 60; onTriggered: { view.dc.setVolume(person.uid, pct.live); } }
                        Connections { target: person; function onVolumeChanged() { if (!setLater.running) pct.live = -1; } }
                    }
                }
            }
        }

        // ---- not in a call / not reachable
        PkCard {
            visible: !view.dc.inCall
            sys: view.sys; width: parent.width; height: emptyCol.implicitHeight + 40
            Column {
                id: emptyCol
                anchors.centerIn: parent; width: parent.width - 40; spacing: view.t.s3
                PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter; name: "discord-logo"; size: view.t.iXl; color: view.t.soft }
                PkText { sys: view.sys; role: "body"; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                         text: view.dc.up ? "Join a voice channel and its controls show up here."
                             : view.dc.why === "restart" ? "Discord was started before the island could reach it. Restart it once (this leaves any call) and the controls work from then on."
                             : view.dc.why === "noflag" ? "Island controls need one line in ~/.config/vesktop-flags.conf: --remote-debugging-port=9223 (a local-only DevTools port). Then restart Discord."
                             : "Discord isn't running." }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: view.t.gap
                    PkButton { sys: view.sys; small: true; kind: "primary"; visible: view.dc.why !== "restart"
                               text: "Open Discord"; icon: "discord-logo"; onClicked: { view.dc.focusApp(); view.sys.collapse(); } }
                    PkButton { sys: view.sys; small: true; kind: "primary"; visible: view.dc.why === "restart"
                               text: "Restart Discord"; icon: "arrow-clockwise"
                               onClicked: Quickshell.execDetached(["sh", "-c", "pkill -x vesktop; sleep 2; gtk-launch vesktop"]) }
                }
            }
        }
    }
}
