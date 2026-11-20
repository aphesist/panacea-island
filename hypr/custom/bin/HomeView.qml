pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// written by portal-patch.py (panacea-config) - the island's Home, built from the Pk kit
// (hypr/custom/ui, DESIGN.md). Replaces ControlsView for the pages main / wifi / netmenu / bt /
// battery / traymenu while cfg.pkHome is on (Settings > Bar & island), same data and actions.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    readonly property string pg: sys.page === "main" || sys.page === "wifi" || sys.page === "netmenu"
                                 || sys.page === "bt" || sys.page === "battery" || sys.page === "traymenu" ? sys.page : "main"

    implicitHeight: pg === "wifi" || pg === "netmenu" ? wifiPage.implicitHeight
                  : pg === "bt" ? btPage.implicitHeight
                  : pg === "battery" ? batteryPage.implicitHeight
                  : pg === "traymenu" ? trayPage.implicitHeight
                  : mainPage.implicitHeight

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: if (!view.goBack()) view.sys.collapse()

    function goBack() {
        switch (view.sys.page) {
            case "netmenu": view.sys.page = "wifi"; return true;
            case "wifi": case "bt": case "battery": view.sys.page = "main"; wifiPage.passwordFor = ""; return true;
            case "traymenu":
                if (trayPage.chain.length) { var c = trayPage.chain.slice(); c.pop(); trayPage.chain = c; return true; }
                view.sys.page = "main"; view.sys.trayMenuItem = null; return true;
        }
        return false;
    }
    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function hm(hours) {
        if (!(hours > 0) || hours > 48) return "";
        var h = Math.floor(hours), m = Math.round((hours - h) * 60);
        if (m === 60) { h++; m = 0; }
        return (h > 0 ? h + " h " : "") + m + " min";
    }
    function fmtTime(sec) {
        var s = Math.max(0, Math.floor(sec)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }
    // battery time left (discharging) or to full (charging), from UPower's rate and capacity
    readonly property string batteryTime: {
        var cap = sys.batteryCapacity || 0, rate = Math.abs(sys.batteryRate || 0), pct = sys.batteryPct || 0;
        if (cap <= 0 || rate < 0.3) return "";
        return sys.batteryCharging ? hm(cap * (100 - pct) / 100 / rate) : sys.acOnline ? "" : hm(cap * pct / 100 / rate);
    }
    // pending updates for the dot on "Updates": the Updates screen's last check, refreshed in the
    // background when Home opens and the check is older than three hours
    property int updates: 0
    FileView {
        id: updCache
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/panacea-updates.json"
        printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { var d = JSON.parse(text()); view.updates = d.count || 0;
                          if (Date.now() / 1000 - d.checked > 3 * 3600 && !updCheck.running) updCheck.running = true; } catch (e) {} }
        onLoadFailed: if (!updCheck.running) updCheck.running = true
    }
    Process { id: updCheck; command: ["python3", Quickshell.env("HOME") + "/.config/panacea/scripts/custom/updates.py"] }
    function wifiIcon(q) { return q > 66 ? "wifi-high" : q > 33 ? "wifi-medium" : "wifi-low"; }

    // ============================================================ pages, cross-faded
    component Page: Column {
        required property string name
        width: view.width
        spacing: view.t.groupGap
        opacity: view.pg === name ? 1 : 0
        visible: opacity > 0.01
        enabled: view.pg === name
        Behavior on opacity { NumberAnimation { duration: view.t.dBase; easing.type: Easing.OutCubic } }
    }

    // ------------------------------------------------------------ main
    Page {
        id: mainPage
        name: "main"
        spacing: view.t.gap

        // clock and date; the weather beside it, in the same dots
        Item {
            width: parent.width; height: clockCol.implicitHeight + 2
            Column {
                id: clockCol
                spacing: 8
                DotText {
                    value: view.sys.timeText
                    size: 36
                    color: view.t.fg
                    MouseArea { anchors.fill: parent; cursorShape: view.sys.cfg.featCalendar ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (view.sys.cfg.featCalendar) view.sys.togglePage("cal") }
                }
                PkText { sys: view.sys; role: "sub"; text: view.sys.dateLong }
            }
            Column {
                anchors.right: parent.right; y: 6
                spacing: 12
                visible: view.sys.weatherReady && !!view.sys.weatherTemp
                Row {
                    anchors.right: parent.right; spacing: 12
                    DotIcon { code: view.sys.weatherIcon; size: 24; color: view.t.fg; anchors.verticalCenter: parent.verticalCenter }
                    DotText { value: String(view.sys.weatherTemp).replace(/[^0-9°.\-]/g, ""); size: 24; color: view.t.fg; anchors.verticalCenter: parent.verticalCenter }
                }
                PkText { sys: view.sys; role: "sub"; anchors.right: parent.right; visible: !trayRow.visible
                         text: String(view.sys.weatherDesc || "").toLowerCase() }
            }
            // tray apps, small, on the date line (left: open, middle: secondary, right: its menu)
            Row {
                id: trayRow
                anchors.right: parent.right; anchors.rightMargin: -4; anchors.bottom: parent.bottom; anchors.bottomMargin: -6
                spacing: 0
                visible: !!view.sys.trayItems && view.sys.trayItems.values.length > 0
                Repeater {
                    model: view.sys.trayItems
                    delegate: Rectangle {
                        id: trayBtn
                        required property var modelData
                        width: 28; height: 28; radius: 14
                        color: trayMa.containsMouse ? view.t.hover : "transparent"
                        Image { anchors.centerIn: parent; width: 16; height: 16; sourceSize: Qt.size(32, 32)
                                source: String(trayBtn.modelData.icon || ""); smooth: true }
                        MouseArea {
                            id: trayMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: m => {
                                if (m.button === Qt.RightButton) {
                                    if (!trayBtn.modelData.hasMenu) return;
                                    view.sys.trayMenuItem = trayBtn.modelData; view.sys.page = "traymenu"; view.sys.holdOpen = true; return;
                                }
                                if (m.button === Qt.MiddleButton) trayBtn.modelData.secondaryActivate();
                                else trayBtn.modelData.activate();
                                view.sys.collapse();
                            }
                        }
                    }
                }
            }
        }

        // tiles (2 x 2) and the two tall sliders
        Item {
            id: ctl
            width: parent.width
            readonly property real tileH: 82
            readonly property bool hasBright: (view.sys.brightList || []).length > 0
            readonly property real sliderW: 66
            readonly property real slidersW: view.sys.cfg.featAudio ? (sliderW * (hasBright ? 2 : 1) + view.t.gap * (hasBright ? 2 : 1)) : (hasBright ? sliderW + view.t.gap : 0)
            height: tileH * 2 + view.t.gap
            Grid {
                id: tiles
                width: parent.width - ctl.slidersW
                columns: 2; spacing: view.t.gap
                readonly property real tw: (width - spacing) / 2
                PkTile {
                    sys: view.sys; width: tiles.tw; height: ctl.tileH
                    hasPage: !view.sys.wiredOn && view.sys.wifiOn && view.sys.cfg.featWifi
                    icon: view.sys.wiredOn ? "network" : !view.sys.wifiOn ? "wifi-slash" : view.wifiIcon(view.sys.wifiQuality)
                    on: view.sys.wiredOn || view.sys.wifiOn
                    title: view.sys.wiredOn ? "Ethernet" : view.sys.wifiOn && view.sys.wifiSsid.length ? view.sys.wifiSsid
                         : view.sys.wifiConnectingSsid.length ? view.sys.wifiConnectingSsid : "Wi-Fi"
                    sub: view.sys.wiredOn ? view.sys.wiredName : !view.sys.wifiOn ? "Off"
                       : view.sys.wifiSsid.length ? "Connected" : view.sys.wifiConnectingSsid.length ? "Connecting…" : "Not connected"
                    onToggled: if (!view.sys.wiredOn) view.sys.toggleWifi()
                    onOpened: { if (!view.sys.wifiOn || !view.sys.cfg.featWifi) return; view.sys.openSub("wifi"); view.sys.refreshWifiList(); view.sys.scanWifi(); }
                }
                PkTile {
                    sys: view.sys; width: tiles.tw; height: ctl.tileH
                    hasPage: view.sys.btOn && view.sys.cfg.featBluetooth
                    icon: view.sys.btOn ? "bluetooth" : "bluetooth-slash"
                    on: view.sys.btOn
                    title: view.sys.btOn && view.sys.btConnectedName.length ? view.sys.btConnectedName : "Bluetooth"
                    sub: !view.sys.btOn ? "Off" : view.sys.btConnectedName.length
                         ? (view.sys.btConnectedBattery >= 0 ? "Battery " + view.sys.btConnectedBattery + "%" : "Connected") : "Not connected"
                    onToggled: view.sys.toggleBt()
                    onOpened: { if (!view.sys.btOn || !view.sys.cfg.featBluetooth) return; view.sys.openSub("bt"); view.sys.scanBt(); }
                }
                PkTile {
                    sys: view.sys; width: tiles.tw; height: ctl.tileH
                    hasPage: true
                    icon: view.sys.vpnConnected ? "shield-check" : "shield"
                    on: view.sys.vpnConnected
                    title: "VPN"
                    sub: view.sys.vpnBusy ? "Connecting…" : view.sys.vpnConnected ? (view.sys.vpnCountryName || view.sys.vpnCountry) : "Off"
                    onToggled: view.sys.togglePreferredVpn()
                    onOpened: { view.sys.page = "vpn"; view.sys.holdOpen = true; }
                }
                PkTile {
                    sys: view.sys; width: tiles.tw; height: ctl.tileH
                    // a plain switch: notifications themselves live behind the bell, top right
                    icon: "moon"
                    on: view.sys.dnd
                    title: "Focus"
                    sub: view.sys.dnd ? "On" : "Off"
                    onToggled: view.sys.toggleDnd()
                }
            }
            Row {
                anchors.right: parent.right
                spacing: view.t.gap
                // volume: Pipewire answers with a signal, so the slider holds what was set for a moment
                PkVSlider {
                    id: vol
                    sys: view.sys; visible: view.sys.cfg.featAudio
                    width: ctl.sliderW; height: ctl.height
                    readonly property var a: view.sys.sinkAudio
                    property real held: -1
                    value: held >= 0 ? held : (a && !a.muted ? a.volume : 0)
                    icon: !a || a.muted || value < 0.01 ? "speaker-x" : value < 0.5 ? "speaker-low" : "speaker-high"
                    onMoved: v => { held = Math.round(v * 20) / 20; volHold.restart(); if (a) { if (a.muted) a.muted = false; a.volume = held; } }
                    onIconClicked: if (a) a.muted = !a.muted
                    Timer { id: volHold; interval: 400; onTriggered: vol.held = -1 }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: view.sys.togglePage("audio") }
                }
                PkVSlider {
                    id: bright
                    sys: view.sys; visible: ctl.hasBright
                    width: ctl.sliderW; height: ctl.height
                    readonly property var b: (view.sys.brightList || [])[0]
                    value: b ? view.clamp(b.pct / 100) : 0
                    icon: "sun"
                    onMoved: v => { if (b) view.sys.brightSet(b.id, Math.max(5, Math.round(v * 20) * 5)); }
                    onIconClicked: if (view.sys.nightAvailable) view.sys.toggleNightLight()
                }
            }
        }

        // now playing: art, title, controls; the seek bar is the music itself (cava bars, the
        // played part white), as in Panacea's own card
        PkCard {
            id: media
            sys: view.sys
            width: parent.width; height: 112
            readonly property var p: view.sys.player
            visible: view.sys.mediaActive && view.sys.cfg.featPlayer && !!p
            Rectangle {
                id: artBox
                x: 12; y: 12
                width: 52; height: 52; radius: view.t.rSmall; color: "transparent"
                PkRoundImage { id: art; sys: view.sys; anchors.fill: parent; radius: view.t.rSmall
                               source: view.sys.mediaArt || ""; sourceSize: Qt.size(104, 104) }
                PkIcon { sys: view.sys; anchors.centerIn: parent; visible: art.status !== Image.Ready; name: "music-note"; filled: true; color: view.t.muted }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.sys.togglePage("media") }
            }
            Column {
                x: artBox.x + artBox.width + 12; width: ctlRow.x - x - 10
                anchors.verticalCenter: artBox.verticalCenter
                spacing: 3
                PkText { sys: view.sys; role: "emph"; width: parent.width; text: media.p ? media.p.trackTitle || "" : "" }
                PkText { sys: view.sys; role: "sub"; width: parent.width; text: media.p ? media.p.trackArtist || "" : "" }
            }
            Row {
                id: ctlRow
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: artBox.verticalCenter
                spacing: 4
                PkIconButton { sys: view.sys; width: 36; height: 36; icon: "skip-back"; selected: true; size: view.t.iSm
                               anchors.verticalCenter: parent.verticalCenter
                               enabled: !!media.p && media.p.canGoPrevious; onClicked: media.p.previous() }
                // the one shape: play / pause, white
                Rectangle {
                    width: 38; height: 38; radius: 19; anchors.verticalCenter: parent.verticalCenter
                    color: playMa.pressed ? Qt.darker(view.t.on, 1.12) : view.t.on
                    PkIcon { sys: view.sys; anchors.centerIn: parent; anchors.horizontalCenterOffset: media.p && media.p.isPlaying ? 0 : 1
                             name: media.p && media.p.isPlaying ? "pause" : "play"; filled: true; size: view.t.iSm; color: view.t.onInk }
                    MouseArea { id: playMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                enabled: !!media.p && media.p.canTogglePlaying; onClicked: media.p.togglePlaying() }
                }
                PkIconButton { sys: view.sys; width: 36; height: 36; icon: "skip-forward"; selected: true; size: view.t.iSm
                               anchors.verticalCenter: parent.verticalCenter
                               enabled: !!media.p && media.p.canGoNext; onClicked: media.p.next() }
            }
            // position: polled while visible; click or drag on the bars seeks
            Item {
                id: seek
                x: 14; width: parent.width - 28; height: 28
                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                readonly property real dur: media.p ? Math.max(0, media.p.length) : 0
                readonly property bool usable: !!media.p && dur > 0 && media.p.positionSupported && media.p.canSeek
                readonly property real frac: dur > 0 ? view.clamp(pos / dur) : 0
                property real pos: 0
                property bool dragging: false
                Timer {
                    interval: 500; repeat: true; triggeredOnStart: true
                    running: media.visible && view.visible && !!media.p
                    onTriggered: { media.p.positionChanged(); if (!seek.dragging) seek.pos = media.p.position; }
                }
                Connections { target: media.p; ignoreUnknownSignals: true
                              function onTrackTitleChanged() { seek.dragging = false; seek.pos = 0; } }
                PkText { id: tNow; sys: view.sys; role: "sub"; anchors.verticalCenter: parent.verticalCenter
                         text: view.fmtTime(seek.pos); visible: seek.dur > 0; width: 40 }
                PkText { id: tEnd; sys: view.sys; role: "sub"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                         text: view.fmtTime(seek.dur); visible: seek.dur > 0; horizontalAlignment: Text.AlignRight; width: 40 }
                Item {
                    id: bars
                    x: seek.dur > 0 ? tNow.width + 6 : 0
                    width: parent.width - (seek.dur > 0 ? tNow.width + tEnd.width + 12 : 0); height: parent.height
                    WaveBars { anchors.fill: parent; barCount: 44; gap: 3; barColor: view.t.track
                               active: !!media.p && media.p.isPlaying && media.visible }
                    Item {
                        width: bars.width * seek.frac; height: bars.height; clip: true
                        WaveBars { width: bars.width; height: bars.height; barCount: 44; gap: 3; barColor: view.t.fg
                                   active: !!media.p && media.p.isPlaying && media.visible }
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4; enabled: seek.usable; cursorShape: Qt.PointingHandCursor; preventStealing: true
                        function at(x) { return view.clamp((x - 4) / bars.width) * seek.dur; }
                        onPressed: m => { seek.dragging = true; seek.pos = at(m.x); }
                        onPositionChanged: m => { if (pressed) seek.pos = at(m.x); }
                        onReleased: { if (seek.usable) media.p.position = seek.pos; seek.dragging = false; }
                        onCanceled: seek.dragging = false
                    }
                }
            }
        }

        // battery (or machine load) and recording
        Row {
            width: parent.width; spacing: view.t.gap
            readonly property real half: (width - spacing) / 2
            PkCard {
                sys: view.sys; interactive: true
                visible: view.sys.batteryPresent
                width: view.sys.cfg.featRecord ? parent.half : parent.width; height: 76
                onClicked: view.sys.openSub("battery")
                Row {
                    x: 14; y: 14; spacing: 4
                    DotText { value: String(view.sys.batteryPct); size: 22; color: view.sys.batteryPct <= 15 && !view.sys.acOnline ? view.t.accentText : view.t.fg }
                    PkText { sys: view.sys; role: "sub"; text: "%"; anchors.bottom: parent.bottom }
                }
                PkIcon { sys: view.sys; visible: view.sys.batteryCharging || view.sys.acOnline; anchors.right: parent.right; anchors.rightMargin: 14; y: 14
                         name: view.sys.batteryCharging ? "lightning" : "plug"; filled: true; size: view.t.iSm; color: view.t.fg }
                PkText { sys: view.sys; role: "sub"; anchors.right: parent.right; anchors.rightMargin: 14; y: 16
                         visible: !view.sys.batteryCharging && !view.sys.acOnline; text: view.batteryTime }
                PkDotBar { sys: view.sys; x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                           n: 16; level: view.sys.batteryPct / 100; low: view.sys.batteryPct <= 15 && !view.sys.acOnline }
            }
            PkCard {
                sys: view.sys
                visible: !view.sys.batteryPresent
                width: view.sys.cfg.featRecord ? parent.half : parent.width; height: 76
                Row {
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 22
                    Repeater {
                        model: [{ k: "CPU", v: view.sys.loadCpu }, { k: "RAM", v: view.sys.loadMem }, { k: "GPU", v: view.sys.loadGpu }]
                        delegate: Column {
                            required property var modelData
                            visible: modelData.v >= 0; spacing: 6
                            DotText { value: String(modelData.v); size: 16; color: view.t.fg }
                            PkText { sys: view.sys; role: "caption"; text: modelData.k }
                        }
                    }
                }
            }
            PkCard {
                sys: view.sys; interactive: true
                visible: view.sys.cfg.featRecord
                width: parent.half; height: 76
                onClicked: view.sys.togglePage("record")
                Rectangle { x: 16; y: 18; width: 10; height: 10; radius: 5; color: view.t.accent
                            opacity: view.sys.recActive && !view.sys.recPaused ? recBlink.v : 1
                            QtObject { id: recBlink; property real v: 1 }
                            SequentialAnimation on opacity { running: view.sys.recActive && !view.sys.recPaused && !view.t.still; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                PkIconButton { sys: view.sys; visible: view.sys.recActive; anchors.right: parent.right; anchors.rightMargin: 8; y: 8
                               icon: "stop"; size: view.t.iMd; onClicked: view.sys.toggleRecord() }
                Column {
                    x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 13; spacing: 1
                    PkText { sys: view.sys; role: "label"; text: view.sys.recActive ? view.sys.recTimeText : "Record" }
                    PkText { sys: view.sys; role: "sub"; text: view.sys.recActive ? (view.sys.recPaused ? "Paused" : "Recording") : "Screen" }
                }
            }
        }

        // quick actions: a bare icon over a short label, on one card
        PkCard {
            sys: view.sys
            width: parent.width; height: quickRow.height + 12
            Grid {
                id: quickRow
                x: 6; anchors.verticalCenter: parent.verticalCenter
                columns: quick.count
                rowSpacing: 2
                readonly property real cell: (parent.width - 12) / Math.max(1, columns)
                Repeater {
                    id: quick
                    model: [
                        { icon: "folder", label: "Files", on: false, dot: false, show: view.sys.cfg.featFiles !== false, act: () => view.sys.togglePage("files") },
                        { icon: "gauge", label: "Tasks", on: false, dot: false, show: true, act: () => view.sys.openSub("tasks") },
                        { icon: "arrow-circle-down", label: "Updates", on: false, dot: view.updates > 0, show: true, act: () => view.sys.togglePage("updates") },
                        { icon: "scroll", label: "Logs", on: false, dot: false, show: true, act: () => view.sys.togglePage("logs") },
                        { icon: "note-pencil", label: "Editor", on: false, dot: false, show: true, act: () => view.sys.editorOpen("") },
                        { icon: "selection", label: "Screen", on: false, dot: false, show: true, act: () => view.sys.togglePage("screen") },
                        { icon: "sun-dim", label: "Night", on: view.sys.nightLight, dot: false, show: view.sys.nightAvailable, act: () => view.sys.toggleNightLight() },
                        { icon: "coffee", label: "Awake", on: view.sys.keepAwake, dot: false, show: true, act: () => { view.sys.keepAwake = !view.sys.keepAwake; } }
                    ].filter(q => q.show)
                    delegate: Rectangle {
                        id: qa
                        required property var modelData
                        width: quickRow.cell; height: 58; radius: view.t.rControl
                        color: qa.modelData.on ? view.t.selected : qaMa.pressed ? view.t.pressed : qaMa.containsMouse ? view.t.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: view.t.dFast } }
                        PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter; y: 9
                                 name: qa.modelData.icon; filled: qa.modelData.on; size: view.t.iMd + 2
                                 color: qa.modelData.on || qaMa.containsMouse ? view.t.fg : view.t.soft }
                        Rectangle { visible: qa.modelData.dot; width: 7; height: 7; radius: 3.5; color: view.t.accent
                                    x: parent.width / 2 + 8; y: 7 }
                        PkText { sys: view.sys; role: "caption"; anchors.horizontalCenter: parent.horizontalCenter; y: 37
                                 text: qa.modelData.label; font.pixelSize: 10
                                 color: qa.modelData.on || qaMa.containsMouse ? view.t.fg : view.t.muted }
                        MouseArea { id: qaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: qa.modelData.act() }
                    }
                }
            }
        }

    }

    // ------------------------------------------------------------ Wi-Fi (and its network menu)
    Page {
        id: wifiPage
        name: view.pg === "netmenu" ? "netmenu" : "wifi"
        property string passwordFor: ""
        property string passwordSecurity: "psk"
        property string menuSsid: ""
        property bool menuConnected: false
        property bool menuKnown: false
        function connectTyped() {
            if (!pw.text.length || (passwordSecurity === "eap" && !user.text.length)) return;
            view.sys.connectWifi(passwordFor, pw.text, user.text, passwordSecurity);
            passwordFor = ""; pw.text = ""; user.text = ""; view.sys.holdOpen = false;
        }

        PkHeader {
            sys: view.sys; width: parent.width
            title: view.pg === "netmenu" ? wifiPage.menuSsid : "Wi-Fi"; back: true
            onBackClicked: view.goBack()
            PkIconButton { sys: view.sys; visible: view.pg === "wifi"; icon: "arrows-clockwise"; size: view.t.iMd
                           RotationAnimation on rotation { running: view.sys.wifiBusy && !view.t.still; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                           onClicked: view.sys.scanWifi() }
            PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; visible: view.pg === "wifi"; on: view.sys.wifiOn; onToggled: view.sys.toggleWifi() }
        }

        // the network menu (right-click on a saved or connected network)
        PkSection {
            sys: view.sys; width: parent.width; visible: view.pg === "netmenu"
            PkRow { sys: view.sys; visible: wifiPage.menuConnected; icon: "wifi-slash"; title: "Disconnect"; interactive: true
                    onClicked: { view.sys.disconnectWifi(); view.sys.page = "wifi"; } }
            PkRow { sys: view.sys; visible: wifiPage.menuKnown; icon: "trash"; title: "Forget this network"; danger: true; interactive: true
                    onClicked: { view.sys.forgetWifi(wifiPage.menuSsid); view.sys.page = "wifi"; } }
        }

        // password for the network being joined
        PkCard {
            sys: view.sys; width: parent.width; visible: view.pg === "wifi" && wifiPage.passwordFor.length > 0
            height: pwCol.implicitHeight + 28
            Column {
                id: pwCol
                x: 14; y: 14; width: parent.width - 28; spacing: 10
                PkText { sys: view.sys; role: "label"; text: "Join “" + wifiPage.passwordFor + "”" }
                PkField { id: user; sys: view.sys; width: parent.width; visible: wifiPage.passwordSecurity === "eap"; placeholder: "Username"
                          onAccepted: pw.focusIn() }
                Row {
                    width: parent.width; spacing: 8
                    PkField { id: pw; sys: view.sys; width: parent.width - joinBtn.width - 8 - cancelBtn.width - 8; password: true; placeholder: "Password"
                              onAccepted: wifiPage.connectTyped() }
                    PkButton { id: cancelBtn; sys: view.sys; kind: "ghost"; text: "Cancel"; anchors.verticalCenter: parent.verticalCenter
                               onClicked: { wifiPage.passwordFor = ""; view.sys.holdOpen = false; } }
                    PkButton { id: joinBtn; sys: view.sys; kind: "primary"; text: "Join"; anchors.verticalCenter: parent.verticalCenter
                               onClicked: wifiPage.connectTyped() }
                }
            }
            Timer { id: pwFocus; interval: 80; onTriggered: wifiPage.passwordSecurity === "eap" ? user.focusIn() : pw.focusIn() }
        }
        PkText { sys: view.sys; visible: view.pg === "wifi" && !!view.sys.wifiError; x: 6; width: parent.width - 12; wrapMode: Text.Wrap
                 text: view.sys.wifiError || ""; color: view.t.accentText }

        PkSection {
            sys: view.sys; width: parent.width; visible: view.pg === "wifi"
            title: view.sys.wifiNetworks.count === 0 ? "" : "Networks"
            PkRow { sys: view.sys; visible: view.sys.wifiNetworks.count === 0; dim: true
                    title: view.sys.wifiBusy ? "Searching…" : view.sys.wifiOn ? "No networks found" : "Wi-Fi is off" }
            Repeater {
                model: view.sys.wifiNetworks
                delegate: PkRow {
                    id: net
                    required property var model
                    readonly property bool connecting: view.sys.wifiConnectingSsid.length > 0 && model.ssid === view.sys.wifiConnectingSsid
                    sys: view.sys; interactive: true
                    hot: model.connected
                    title: model.ssid
                    sub: model.connected ? "Connected" : connecting ? "Connecting…" : model.known ? "Saved" : ""
                    PkIcon { sys: view.sys; visible: net.model.security !== "open"; name: "lock-simple"; size: 14; color: view.t.muted }
                    PkIcon { sys: view.sys; name: view.wifiIcon(net.model.quality); filled: net.model.connected; size: view.t.iSm
                             color: net.model.connected ? view.t.fg : view.t.soft }
                    PkIcon { sys: view.sys; visible: net.model.connected; name: "check"; size: view.t.iSm; color: view.t.fg }
                    onClicked: {
                        if (model.connected || connecting) return;
                        if (model.security === "open" || model.known) { view.sys.connectWifi(model.ssid, ""); return; }
                        wifiPage.passwordFor = model.ssid; wifiPage.passwordSecurity = model.security;
                        view.sys.holdOpen = true; pwFocus.restart();
                    }
                    MouseArea {
                        parent: net; anchors.fill: parent; acceptedButtons: Qt.RightButton
                        onClicked: {
                            if (!net.model.connected && !net.model.known) return;
                            wifiPage.menuSsid = net.model.ssid; wifiPage.menuConnected = net.model.connected; wifiPage.menuKnown = net.model.known;
                            view.sys.page = "netmenu";
                        }
                    }
                }
            }
        }
        PkText { sys: view.sys; visible: view.pg === "wifi" && view.sys.wifiNetworks.count > 0; x: 6; role: "sub"
                 text: "Right-click a saved network to disconnect or forget it." }
    }

    // ------------------------------------------------------------ Bluetooth
    Page {
        id: btPage
        name: "bt"
        readonly property var devs: view.sys.btDevices ? view.sys.btDevices.values : []
        function iconFor(d) {
            var i = String(d.icon || "");
            if (/headset|headphone|audio-card/.test(i)) return "headphones";
            if (/mouse/.test(i)) return "mouse";
            if (/keyboard/.test(i)) return "keyboard";
            if (/speaker|audio/.test(i)) return "speaker-hifi";
            if (/gaming|joystick/.test(i)) return "game-controller";
            if (/phone/.test(i)) return "device-mobile";
            if (/watch/.test(i)) return "watch";
            return "bluetooth";
        }
        function subFor(d) {
            if (d.pairing) return "Pairing…";
            if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
            var b = d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "";
            if (d.connected) return "Connected" + b;
            return (d.paired || d.bonded ? "Not connected" : "Available") + b;
        }
        function act(d) {
            if (d.connected) { d.disconnect(); return; }
            d.trusted = true;
            if (d.paired || d.bonded) d.connect(); else d.pair();
        }
        PkHeader {
            sys: view.sys; width: parent.width; title: "Bluetooth"; back: true
            onBackClicked: view.goBack()
            PkIconButton { sys: view.sys; icon: "arrows-clockwise"; size: view.t.iMd
                           RotationAnimation on rotation { running: !!view.sys.btAdapter && view.sys.btAdapter.discovering && !view.t.still; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                           onClicked: view.sys.scanBt() }
            PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; on: view.sys.btOn; onToggled: view.sys.toggleBt() }
        }
        component DevRow: PkRow {
            id: dr
            required property var modelData
            sys: view.sys; interactive: true
            icon: btPage.iconFor(modelData); iconFilled: modelData.connected
            hot: modelData.connected
            title: modelData.name || modelData.address
            sub: btPage.subFor(modelData)
            PkText { sys: view.sys; role: "label"; text: dr.modelData.connected ? "Disconnect" : (dr.modelData.paired || dr.modelData.bonded) ? "Connect" : "Pair"
                     color: view.t.soft }
            onClicked: btPage.act(modelData)
            Connections { target: dr.modelData; function onPairedChanged() { if (dr.modelData.paired && !dr.modelData.connected) dr.modelData.connect(); } }
        }
        PkSection {
            sys: view.sys; width: parent.width; title: "My devices"
            visible: btPage.devs.some(d => d.paired || d.bonded)
            Repeater { model: btPage.devs.filter(d => d.paired || d.bonded); delegate: DevRow {} }
        }
        PkSection {
            sys: view.sys; width: parent.width
            title: view.sys.btAdapter && view.sys.btAdapter.discovering ? "Nearby · searching…" : "Nearby"
            PkRow { sys: view.sys; dim: true; visible: !btPage.devs.some(d => !(d.paired || d.bonded))
                    title: view.sys.btAdapter && view.sys.btAdapter.discovering ? "Looking for devices…" : "Nothing nearby. Refresh to search again." }
            Repeater { model: btPage.devs.filter(d => !(d.paired || d.bonded)); delegate: DevRow {} }
        }
    }

    // ------------------------------------------------------------ battery
    Page {
        id: batteryPage
        name: "battery"
        PkHeader { sys: view.sys; width: parent.width; title: "Battery"; back: true; onBackClicked: view.goBack() }
        PkCard {
            sys: view.sys; width: parent.width; height: 118
            Row {
                x: 16; y: 18; spacing: 6
                DotText { value: String(view.sys.batteryPct); size: 38; color: view.sys.batteryPct <= 15 && !view.sys.acOnline ? view.t.accentText : view.t.fg }
                PkText { sys: view.sys; role: "sub"; text: "%"; anchors.bottom: parent.bottom }
            }
            Column {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 20; spacing: 3
                PkText { sys: view.sys; role: "label"; anchors.right: parent.right
                         text: view.sys.batteryCharging ? "Charging" : view.sys.acOnline ? "Plugged in" : "On battery" }
                PkText { sys: view.sys; role: "sub"; anchors.right: parent.right; visible: view.batteryTime !== ""
                         text: view.batteryTime + (view.sys.batteryCharging ? " to full" : " left") }
            }
            PkDotBar { sys: view.sys; x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                       n: 24; level: view.sys.batteryPct / 100; low: view.sys.batteryPct <= 15 && !view.sys.acOnline }
        }
        Column {
            width: parent.width; spacing: 8; visible: view.sys.showPowerProfiles
            PkText { sys: view.sys; role: "caption"; x: 6; text: "Power mode" }
            PkSegmented {
                sys: view.sys; width: parent.width
                options: [{ id: "power-saver", text: "Saver" }, { id: "balanced", text: "Balanced" }, { id: "performance", text: "Performance" }]
                value: view.sys.powerProfile
                onPicked: id => view.sys.setPowerProfile(id)
            }
        }
        PkSection {
            sys: view.sys; width: parent.width; title: "Details"; visible: view.sys.batteryPresent
            PkRow { sys: view.sys; title: "Capacity"; visible: view.sys.batteryCapacity > 0; value: Number(view.sys.batteryCapacity).toFixed(1) + " Wh" }
            PkRow { sys: view.sys; title: "Health"; visible: view.sys.batteryHealth > 0; value: Math.round(view.sys.batteryHealth) + "%" }
            PkRow { sys: view.sys; title: view.sys.batteryCharging ? "Charging at" : "Using"; visible: Math.abs(view.sys.batteryRate) > 0.05
                    value: Math.abs(view.sys.batteryRate).toFixed(1) + " W" }
        }
    }

    // ------------------------------------------------------------ a tray app's menu
    Page {
        id: trayPage
        name: "traymenu"
        property var chain: []
        readonly property var rootHandle: view.sys.trayMenuItem ? view.sys.trayMenuItem.menu : null
        readonly property var handle: chain.length ? chain[chain.length - 1] : rootHandle
        onRootHandleChanged: if (chain.length > 0) chain = []
        QsMenuOpener { id: menuOpener; menu: trayPage.handle }
        PkHeader {
            sys: view.sys; width: parent.width; back: true; onBackClicked: view.goBack()
            title: trayPage.chain.length ? (trayPage.chain[trayPage.chain.length - 1].text || "Menu")
                 : view.sys.trayMenuItem ? (view.sys.trayMenuItem.tooltipTitle || view.sys.trayMenuItem.title || "Menu") : "Menu"
        }
        PkSection {
            sys: view.sys; width: parent.width
            PkRow { sys: view.sys; dim: true; visible: menuOpener.children.values.length === 0; title: "This menu is empty" }
            Repeater {
                model: menuOpener.children
                delegate: Item {
                    id: me
                    required property var modelData
                    width: parent ? parent.width : 0
                    height: modelData.isSeparator ? 9 : entry.implicitHeight
                    PkRow {
                        id: entry
                        visible: !me.modelData.isSeparator
                        sys: view.sys; width: parent.width
                        interactive: me.modelData.enabled; dim: !me.modelData.enabled
                        title: String(me.modelData.text || "").replace(/&(?!&)/g, "")
                        caret: me.modelData.hasChildren
                        PkIcon { sys: view.sys; visible: me.modelData.buttonType !== QsMenuButtonType.None && me.modelData.checkState === Qt.Checked
                                 name: "check"; size: view.t.iSm }
                        onClicked: {
                            if (me.modelData.hasChildren) { var c = trayPage.chain.slice(); c.push(me.modelData); trayPage.chain = c; return; }
                            me.modelData.triggered(); view.sys.collapse();
                        }
                    }
                }
            }
        }
    }
}
