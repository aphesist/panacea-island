import QtQuick
import Quickshell
import Quickshell.Io

// The island as mpv's control bar (option A, "Pill"). Shown while an mpv window is focused on
// the island's screen (root.mpvPid, found by portal-patch's window watch); mpv itself hides
// its on-screen controls in a window (~/.config/mpv/scripts/panacea-island.lua) and talks JSON
// IPC on $XDG_RUNTIME_DIR/panacea-mpv/<pid>.sock.
//   idle   a pill: play/pause, the time (dot digits), volume
//   hover  grows down: title + volume slider, the time bar (chapters cut into it), then
//          transport (prev, -10 s, +10 s, next) and options (subtitles, audio, speed, chapters,
//          playlist, screenshot, fullscreen)
//   menu   subtitles / audio / speed open inside the island, in place of the buttons; chapters
//          and the playlist (long, searchable lists) open uosc's menu in the player.
// The island lays the bar out on its animated shape (width/height = the island's own), and
// sizes itself from implicitWidth/implicitHeight here (DESIGN.md, "Morphing").
Item {
    id: bar
    property var sys
    readonly property var t: sys.pk
    property int pid: 0

    // ---- mpv state
    property bool paused: true
    property real pos: 0
    property real dur: 0
    property real buf: 0
    property real vol: 100
    property bool muted: false
    property real speed: 1
    property string title: ""
    property var tracks: []
    property var chapters: []
    property bool connected: sock.connected

    // ---- layout state
    property string menu: ""            // "" | subs | audio | speed
    readonly property bool open: hover.hovered || menu !== "" || seekMa.pressed || volDrag
    property bool volDrag: false
    readonly property int idleW: 300
    readonly property int openW: 560
    readonly property int rowH: sys.pillH
    implicitWidth: open ? openW : idleW
    implicitHeight: !open ? rowH : menu === "" ? rowH + 90 : rowH + 32 + 34 + menuBody.implicitHeight + 12

    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x;
    }

    // ---- IPC
    Socket {
        id: sock
        path: bar.pid > 0 ? Quickshell.env("XDG_RUNTIME_DIR") + "/panacea-mpv/" + bar.pid + ".sock" : ""
        connected: path !== ""
        onConnectedChanged: if (connected) bar.observeAll()
        parser: SplitParser { onRead: line => bar.onLine(line) }
    }
    onPidChanged: { menu = ""; title = ""; pos = 0; dur = 0; tracks = []; chapters = []; }
    Timer {      // the socket may appear a moment after the window: retry until it connects
        interval: 400; repeat: true
        running: bar.pid > 0 && !sock.connected
        onTriggered: { sock.connected = false; sock.connected = true; }
    }
    function send(cmd, rid) {
        if (!sock.connected) return;
        var o = { command: cmd };
        if (rid) o.request_id = rid;
        sock.write(JSON.stringify(o) + "\n");
    }
    readonly property var props: ["pause", "duration", "volume", "mute", "speed", "media-title",
                                  "track-list", "chapter-list", "demuxer-cache-time"]
    function observeAll() {
        for (var i = 0; i < props.length; i++) send(["observe_property", i + 1, props[i]]);
        send(["get_property", "time-pos"], 1);
    }
    // time-pos changes every frame: asked for instead, 4x a second (10x while open)
    Timer {
        interval: bar.open ? 100 : 250; repeat: true
        running: bar.visible && sock.connected && !bar.paused
        onTriggered: bar.send(["get_property", "time-pos"], 1)
    }
    function onLine(line) {
        var m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.request_id === 1 && m.data !== undefined && !seekMa.pressed) { bar.pos = m.data; return; }
        if (m.event !== "property-change") return;
        var d = m.data;
        switch (m.name) {
        case "pause": bar.paused = !!d; send(["get_property", "time-pos"], 1); break;
        case "duration": bar.dur = d || 0; break;
        case "volume": bar.vol = d || 0; break;
        case "mute": bar.muted = !!d; break;
        case "speed": bar.speed = d || 1; break;
        case "media-title": bar.title = d || ""; break;
        case "track-list": bar.tracks = d || []; break;
        case "chapter-list": bar.chapters = d || []; break;
        case "demuxer-cache-time": bar.buf = d || 0; break;
        }
    }
    function tracksOf(type) { return bar.tracks.filter(function (x) { return x.type === type; }); }
    function trackName(x) {
        return x.title || x.lang || ("Track " + x.id);      // the language code only when there's no name
    }

    HoverHandler { id: hover }

    // ---- row 1: play / time or title / volume
    Item {
        id: row1
        width: parent.width; height: bar.rowH
        MpvIconButton {
            id: playBtn
            sys: bar.sys; x: 10; anchors.verticalCenter: parent.verticalCenter
            name: bar.paused ? "play" : "pause"; filled: true; size: bar.t.iMd; tint: bar.t.fg
            onClicked: bar.send(["cycle", "pause"])
        }
        DotText {
            x: 50; anchors.verticalCenter: parent.verticalCenter
            value: bar.fmt(bar.pos); size: 11; color: bar.t.fg
            opacity: bar.open ? 0 : 1; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: bar.t.dFast } }
        }
        Text {
            x: 52; width: parent.width - x - volRow.width - 24
            anchors.verticalCenter: parent.verticalCenter
            text: bar.title; elide: Text.ElideRight
            color: bar.t.soft
            font { family: bar.t.font; pixelSize: bar.t.tBody; weight: Font.DemiBold }
            opacity: bar.open ? 1 : 0; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: bar.t.dFast } }
        }
        Row {
            id: volRow
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Item {
                width: bar.open ? 84 : 0; height: 32; clip: true
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: bar.t.dBase; easing.type: Easing.OutCubic } }
                PkSlider {
                    sys: bar.sys; width: 80; anchors.verticalCenter: parent.verticalCenter
                    value: bar.muted ? 0 : Math.min(1, bar.vol / 100)
                    onMoved: v => { bar.send(["set_property", "volume", Math.round(v * 100)]); if (bar.muted) bar.send(["set_property", "mute", false]); }
                }
            }
            MpvIconButton {
                sys: bar.sys; anchors.verticalCenter: parent.verticalCenter
                name: bar.muted || bar.vol <= 0 ? "speaker-x" : bar.vol < 50 ? "speaker-low" : "speaker-high"
                onClicked: bar.send(["cycle", "mute"])
            }
        }
        // scrolling anywhere on the bar sets the volume
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                var d = event.angleDelta.y !== 0 ? event.angleDelta.y : 0;
                if (d !== 0) bar.send(["add", "volume", d > 0 ? 5 : -5]);
            }
        }
    }

    // ---- row 2: the time bar
    Item {
        id: row2
        x: 18; y: bar.rowH + 2; width: parent.width - 36; height: 24
        opacity: bar.open ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: bar.t.dFast } }
        Text {
            id: el; anchors.verticalCenter: parent.verticalCenter
            text: bar.fmt(seekMa.pressed || seekMa.containsMouse ? seekMa.at : bar.pos)
            color: bar.t.soft; font { family: bar.t.font; pixelSize: bar.t.tCaption }
        }
        Item {
            id: track
            x: el.width + 10; width: parent.width - el.width - rem.width - 20; height: parent.height
            readonly property bool hot: seekMa.containsMouse || seekMa.pressed
            readonly property real th: hot ? 5 : 3
            readonly property real frac: bar.dur > 0 ? Math.max(0, Math.min(1, bar.pos / bar.dur)) : 0
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: track.th
                Behavior on height { NumberAnimation { duration: bar.t.dFast } }
                Rectangle { anchors.fill: parent; radius: height / 2; color: bar.t.track }
                Rectangle { width: bar.dur > 0 ? parent.width * Math.min(1, bar.buf / bar.dur) : 0; height: parent.height; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.26) }
                Rectangle { width: parent.width * track.frac; height: parent.height; radius: height / 2; color: bar.t.fg }
                Repeater {
                    model: bar.dur > 0 ? bar.chapters : []
                    Rectangle {
                        required property var modelData
                        visible: modelData.time > 0
                        x: parent.width * modelData.time / bar.dur - 1; width: 2; height: parent.height; color: "#000000"
                    }
                }
            }
            Rectangle {
                visible: track.hot; width: 12; height: 12; radius: 6; color: bar.t.fg
                x: track.width * (seekMa.pressed ? seekMa.at / Math.max(1, bar.dur) : track.frac) - 6
                anchors.verticalCenter: parent.verticalCenter
            }
            MouseArea {
                id: seekMa
                anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                property real at: 0
                function upd(mx) { at = Math.max(0, Math.min(1, mx / width)) * bar.dur; }
                onPositionChanged: mouse => upd(mouse.x)
                onPressed: mouse => upd(mouse.x)
                onReleased: { bar.pos = at; bar.send(["seek", at, "absolute"]); }
            }
        }
        Text {
            id: rem; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "-" + bar.fmt(bar.dur - bar.pos)
            color: bar.t.muted; font { family: bar.t.font; pixelSize: bar.t.tCaption }
        }
    }

    // ---- row 3: transport left, options right
    Item {
        id: row3
        x: 8; y: bar.rowH + 32; width: parent.width - 16; height: 44
        opacity: bar.open && bar.menu === "" ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: bar.t.dFast } }
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 2
            MpvIconButton { sys: bar.sys; name: "skip-back"; onClicked: bar.send(["playlist-prev"]) }
            MpvIconButton { sys: bar.sys; name: "rewind"; onClicked: bar.send(["seek", -10]) }
            MpvIconButton { sys: bar.sys; name: "fast-forward"; onClicked: bar.send(["seek", 10]) }
            MpvIconButton { sys: bar.sys; name: "skip-forward"; onClicked: bar.send(["playlist-next"]) }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 2
            MpvIconButton { sys: bar.sys; name: "subtitles"; visible: bar.tracksOf("sub").length > 0; onClicked: bar.menu = "subs" }
            MpvIconButton { sys: bar.sys; name: "waveform"; visible: bar.tracksOf("audio").length > 1; onClicked: bar.menu = "audio" }
            MpvIconButton {
                sys: bar.sys; name: ""
                label: (Math.round(bar.speed * 100) / 100) + "×"
                onClicked: bar.menu = "speed"
            }
            MpvIconButton { sys: bar.sys; name: "list-numbers"; visible: bar.chapters.length > 0; onClicked: bar.send(["script-binding", "uosc/chapters"]) }
            MpvIconButton { sys: bar.sys; name: "playlist"; onClicked: bar.send(["script-binding", "uosc/playlist"]) }
            MpvIconButton { sys: bar.sys; name: "camera"; onClicked: bar.send(["screenshot"]) }
            MpvIconButton { sys: bar.sys; name: "corners-out"; onClicked: bar.send(["cycle", "fullscreen"]) }
        }
    }

    // ---- menus inside the island
    Item {
        id: menuBox
        x: 10; y: bar.rowH + 32; width: parent.width - 20
        height: menuBody.implicitHeight + 34
        opacity: bar.menu !== "" ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: bar.t.dFast } }
        Item {
            width: parent.width; height: 30
            Row {
                x: 4; height: 30; spacing: 6
                PkIcon { sys: bar.sys; anchors.verticalCenter: parent.verticalCenter; name: "caret-left"; size: bar.t.iXs; color: bar.t.muted }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bar.menu === "subs" ? "Subtitles" : bar.menu === "audio" ? "Audio" : "Speed"
                    color: bar.t.fg; font { family: bar.t.font; pixelSize: bar.t.tEmph; weight: Font.DemiBold }
                }
            }
            MouseArea { width: 140; height: 30; cursorShape: Qt.PointingHandCursor; onClicked: bar.menu = "" }
            Text {
                visible: bar.menu === "subs"
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                text: "Load file…"; color: lfMa.containsMouse ? bar.t.fg : bar.t.muted
                font { family: bar.t.font; pixelSize: bar.t.tLabel }
                MouseArea { id: lfMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { bar.send(["script-binding", "uosc/load-subtitles"]); bar.menu = ""; } }
            }
        }
        Column {
            id: menuBody
            y: 34; width: parent.width; spacing: 2
            // subtitles / audio: a list of tracks
            Repeater {
                model: bar.menu === "subs" ? [{ id: "no", title: "Off", selected: !bar.tracksOf("sub").some(function (x) { return x.selected; }) }].concat(bar.tracksOf("sub"))
                     : bar.menu === "audio" ? bar.tracksOf("audio") : []
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool on: !!modelData.selected
                    width: menuBody.width; height: 40; radius: bar.t.rControl
                    color: on ? bar.t.selected : rowMa.containsMouse ? bar.t.hover : "transparent"
                    Text {
                        x: 14; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.id === "no" ? "Off" : bar.trackName(row.modelData); elide: Text.ElideRight
                        color: row.on ? bar.t.fg : bar.t.soft
                        font { family: bar.t.font; pixelSize: bar.t.tBody; weight: row.on ? Font.DemiBold : Font.Normal }
                    }
                    PkIcon { sys: bar.sys; visible: row.on; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                             name: "check"; size: bar.t.iSm; color: bar.t.fg }
                    MouseArea {
                        id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.send(["set_property", bar.menu === "subs" ? "sid" : "aid", row.modelData.id])
                    }
                }
            }
            // speed: chips
            Row {
                visible: bar.menu === "speed"
                spacing: 6
                Repeater {
                    model: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: Math.abs(bar.speed - modelData) < 0.01
                        width: chipText.implicitWidth + 22; height: 30; radius: 15
                        color: on ? bar.t.on : chipMa.containsMouse ? bar.t.pressed : bar.t.surface
                        Text { id: chipText; anchors.centerIn: parent; text: chip.modelData + "×"
                               color: chip.on ? bar.t.onInk : bar.t.soft
                               font { family: bar.t.font; pixelSize: bar.t.tLabel; weight: chip.on ? Font.DemiBold : Font.Normal } }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.send(["set_property", "speed", chip.modelData]) }
                    }
                }
            }
        }
    }
    // leaving the island closes a menu after a moment
    Timer { id: menuClose; interval: 900; onTriggered: bar.menu = "" }
    Connections { target: hover; function onHoveredChanged() { if (hover.hovered) menuClose.stop(); else if (bar.menu !== "") menuClose.restart(); } }
}
