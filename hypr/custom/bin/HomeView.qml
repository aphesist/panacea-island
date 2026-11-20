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
            case "wifi": case "bt": case "battery":
                if (wifiPage.passwordFor || wifiPage.other) { wifiPage.cancelJoin(); return true; }
                view.sys.page = "main"; return true;
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
    // The rate is the shell's 5-minute average of the draw (battAvgW), not UPower's instant reading,
    // and the result is rounded (5 min under 2 h, 10 min above) so it doesn't flicker.
    readonly property string batteryTime: {
        var cap = sys.batteryCapacity || 0, pct = sys.batteryPct || 0;
        var rate = sys.battAvgW > 0 ? sys.battAvgW : Math.abs(sys.batteryRate || 0);
        if (cap <= 0 || rate < 0.3) return "";
        var hours = sys.batteryCharging ? cap * (100 - pct) / 100 / rate : sys.acOnline ? 0 : cap * pct / 100 / rate;
        var step = hours < 2 ? 5 : 10;
        return hm(Math.round(hours * 60 / step) * step / 60);
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
                visible: (!!view.sys.trayItems && view.sys.trayItems.values.length > 0) || view.sys.rtxAwake
                // the RTX is awake (it powers off when idle): click for what keeps it up
                Rectangle {
                    visible: view.sys.rtxAwake
                    width: 28; height: 28; radius: 14
                    color: rtxMa.containsMouse ? view.t.hover : "transparent"
                    PkIcon { sys: view.sys; anchors.centerIn: parent; name: "graphics-card"; filled: true; size: 16; color: view.t.soft }
                    MouseArea { id: rtxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { view.sys.page = "battery"; view.sys.holdOpen = true; } }
                }
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
                // stop: a round red button with a white square, like the media card's play circle
                Rectangle {
                    visible: view.sys.recActive
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 12
                    width: 32; height: 32; radius: 16
                    color: stopMa.pressed ? Qt.darker(view.t.accent, 1.25) : stopMa.containsMouse ? Qt.lighter(view.t.accent, 1.15) : view.t.accent
                    scale: stopMa.pressed ? 0.92 : 1
                    Behavior on color { ColorAnimation { duration: view.t.dFast } }
                    Behavior on scale { NumberAnimation { duration: view.t.dFast; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.centerIn: parent; width: 11; height: 11; radius: 3; color: "white" }
                    MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: view.sys.toggleRecord() }
                }
                Column {
                    x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 13; spacing: 1
                    PkText { sys: view.sys; role: "label"; text: view.sys.recActive ? view.sys.recTimeText : "Record" }
                    PkText { sys: view.sys; role: "sub"; text: view.sys.recActive ? (view.sys.recPaused ? "Paused" : "Recording") : "Screen" }
                }
            }
        }

        // quick actions: a bare icon over a short label, on one card that pages sideways (a
        // carousel): swipe sideways over it, or click a page dot; the pages slide on the shape spring
        PkCard {
            id: quickCard
            sys: view.sys
            width: parent.width; height: 58 + 12 + (pages > 1 ? 11 : 0)
            readonly property int per: 5
            readonly property real pageW: width - 12
            readonly property var items: [
                { icon: "folder", label: "Files", on: false, dot: false, show: view.sys.cfg.featFiles !== false, act: () => view.sys.togglePage("files") },
                { icon: "gauge", label: "Tasks", on: false, dot: false, show: true, act: () => view.sys.openSub("tasks") },
                { icon: "key", label: "Passwords", on: false, dot: false, show: true, act: () => view.sys.togglePage("vault") },
                { icon: "arrow-circle-down", label: "Updates", on: false, dot: view.updates > 0, show: true, act: () => view.sys.togglePage("updates") },
                { icon: "sun-dim", label: "Night", on: view.sys.nightLight, dot: false, show: view.sys.nightAvailable, act: () => view.sys.toggleNightLight() },
                { icon: "coffee", label: "Awake", on: view.sys.keepAwake, dot: false, show: true, act: () => { view.sys.keepAwake = !view.sys.keepAwake; } },
                { icon: "note-pencil", label: "Editor", on: false, dot: false, show: true, act: () => view.sys.editorOpen("") },
                { icon: "calculator", label: "Calc", on: false, dot: false, show: true, act: () => view.sys.togglePage("calc") },
                { icon: "selection", label: "Screen", on: false, dot: false, show: true, act: () => view.sys.togglePage("screen") },
                { icon: "scroll", label: "Logs", on: false, dot: false, show: true, act: () => view.sys.togglePage("logs") }
            ].filter(q => q.show)
            readonly property int pages: Math.max(1, Math.ceil(items.length / per))
            property int pageIx: 0
            function go(i) { pageIx = Math.max(0, Math.min(pages - 1, i)); }
            onPagesChanged: go(pageIx)
            PkMorph { id: quickSlide; to: -quickCard.pageIx * quickCard.pageW
                      ms: view.sys.animMs; bounce: view.sys.animBounce; still: view.sys.noMotion }

            Item {
                x: 6; y: 6; width: quickCard.pageW; height: 58
                clip: true
                Row {
                    x: quickSlide.value
                    Repeater {
                        model: quickCard.items
                        delegate: Rectangle {
                            id: qa
                            required property var modelData
                            required property int index
                            width: quickCard.pageW / quickCard.per; height: 58; radius: view.t.rControl
                            // the cells of the page sliding in/out fade with the room they have
                            readonly property real cx: quickSlide.value + (index + 0.5) * width
                            opacity: Math.max(0, Math.min(1, Math.min(cx, quickCard.pageW - cx) / (width * 0.5)))
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

            // page dots: the current one is a short white pill
            Row {
                visible: quickCard.pages > 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                spacing: 5
                Repeater {
                    model: quickCard.pages
                    delegate: Rectangle {
                        required property int index
                        readonly property bool cur: index === quickCard.pageIx
                        width: cur ? 14 : 5; height: 5; radius: 2.5
                        color: cur ? view.t.fg : view.t.dotOff
                        Behavior on width { NumberAnimation { duration: view.t.dBase; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: view.t.dFast } }
                        MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor
                                    onClicked: quickCard.go(index) }
                    }
                }
            }

            // sideways swipes over the card page it (the island's tab swipe yields while the
            // pointer is here); vertical scrolling and clicks pass through
            HoverHandler { id: quickHover; onHoveredChanged: view.sys.swipeYield = hovered }
            Component.onDestruction: view.sys.swipeYield = false
            MouseArea {
                anchors.fill: parent; z: 5
                acceptedButtons: Qt.NoButton
                enabled: quickCard.pages > 1
                property real acc: 0
                property bool spent: false
                Timer { id: quickQuiet; interval: 260; onTriggered: { parent.acc = 0; parent.spent = false; } }
                onWheel: wheel => {
                    var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 4;
                    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 4;
                    if (Math.abs(dx) <= Math.abs(dy) && !spent && Math.abs(acc) < 4) { wheel.accepted = false; return; }
                    quickQuiet.restart();
                    if (spent) return;
                    acc += dx;
                    if (Math.abs(acc) < 50) return;
                    spent = true;
                    quickCard.go(quickCard.pageIx + (acc < 0 ? 1 : -1));   // fingers left = next page
                }
            }
        }

    }

    // ------------------------------------------------------------ Wi-Fi (and a network's details)
    // The network you're on as a card; saved and other networks below, strongest first, in a list
    // that scrolls inside the island; (i) on a saved network opens its details ("netmenu").
    Page {
        id: wifiPage
        name: view.pg === "netmenu" ? "netmenu" : "wifi"
        property string passwordFor: ""
        property string passwordSecurity: "psk"
        property bool other: false              // joining a hidden network by name
        property string menuSsid: ""
        property bool menuConnected: false
        property bool menuKnown: false
        property string otherError: ""
        readonly property bool on: view.sys.wifiOn
        readonly property string current: view.sys.wifiSsid || ""
        // the list, split: saved (in range) and the rest; the connected one is the card above
        readonly property var nets: {
            var rev = view.sys.wifiListRev, n = view.sys.wifiNetworks, out = [];
            for (var i = 0; i < n.count; i++) { var e = n.get(i); out.push({ ssid: e.ssid, security: e.security, quality: e.quality, known: e.known, connected: e.connected }); }
            return out.filter(x => x.ssid !== wifiPage.current && !x.connected).sort((a, b) => b.quality - a.quality);
        }
        readonly property var saved: nets.filter(x => x.known)
        readonly property var others: nets.filter(x => !x.known)
        readonly property var currentNet: {
            var rev = view.sys.wifiListRev, n = view.sys.wifiNetworks;
            for (var i = 0; i < n.count; i++) if (n.get(i).ssid === wifiPage.current) return n.get(i);
            return null;
        }
        function signalWord(q) { return q > 75 ? "Excellent signal" : q > 50 ? "Good signal" : q > 25 ? "Fair signal" : "Weak signal"; }
        function securityWord(s) { return s === "open" ? "Open" : s === "eap" ? "Enterprise" : s === "sae" ? "WPA3" : "WPA2"; }
        function join(n) {
            if (n.ssid === view.sys.wifiConnectingSsid) return;
            if (n.security === "open" || n.known) { view.sys.connectWifi(n.ssid, ""); return; }
            wifiPage.other = false; wifiPage.passwordFor = n.ssid; wifiPage.passwordSecurity = n.security;
            view.sys.holdOpen = true; pwFocus.restart();
        }
        function details(ssid, connected, known) {
            wifiPage.menuSsid = ssid; wifiPage.menuConnected = connected; wifiPage.menuKnown = known;
            info.load(); view.sys.page = "netmenu";
        }
        function connectTyped() {
            if (wifiPage.other) {
                if (!ssidField.text.trim()) return;
                hidden.command = ["nmcli", "dev", "wifi", "connect", ssidField.text.trim()].concat(pw.text ? ["password", pw.text] : []).concat(["hidden", "yes"]);
                wifiPage.otherError = ""; hidden.running = true;
                return;
            }
            if (!pw.text.length || (passwordSecurity === "eap" && !user.text.length)) return;
            view.sys.connectWifi(passwordFor, pw.text, user.text, passwordSecurity);
            wifiPage.cancelJoin();
        }
        function cancelJoin() { passwordFor = ""; other = false; pw.text = ""; user.text = ""; ssidField.text = ""; otherError = ""; view.sys.holdOpen = false; }

        Process {
            id: hidden
            stderr: StdioCollector { id: hiddenErr }
            onExited: code => {
                if (code === 0) { wifiPage.cancelJoin(); view.sys.refreshWifiList(); }
                else wifiPage.otherError = (hiddenErr.text.replace(/^Error: */, "").trim() || "Couldn't join that network.");
            }
        }
        // a network's details: address, router, DNS, band, speed, auto-join
        QtObject {
            id: info
            property string ip: ""; property string gateway: ""; property string dns: ""
            property string band: ""; property string rate: ""; property string security: ""
            property bool auto: true; property bool autoKnown: false
            function load() { info.ip = ""; info.gateway = ""; info.dns = ""; info.band = ""; info.rate = ""; info.security = ""; info.autoKnown = false; infoProc.running = false; infoProc.running = true; }
        }
        Process {
            id: infoProc
            command: ["sh", "-c",
                "ssid=\"$1\"; dev=$(nmcli -t -f DEVICE,TYPE dev status | awk -F: '$2==\"wifi\"{print $1; exit}'); " +
                "if [ \"$2\" = yes ]; then nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show \"$dev\"; " +
                "nmcli -t -f ACTIVE,FREQ,RATE,SECURITY dev wifi | grep '^yes:' | head -1 | sed 's/^/@link:/'; fi; " +
                "printf '@auto:%s\\n' \"$(nmcli -g connection.autoconnect connection show id \"$ssid\" 2>/dev/null)\"",
                "_", wifiPage.menuSsid, wifiPage.menuConnected ? "yes" : "no"]
            stdout: SplitParser {
                onRead: line => {
                    var i = line.indexOf(":"), k = line.slice(0, i), v = line.slice(i + 1);
                    if (k.indexOf("IP4.ADDRESS") === 0 && !info.ip) info.ip = v.replace(/\/\d+$/, "");
                    else if (k === "IP4.GATEWAY") info.gateway = v;
                    else if (k.indexOf("IP4.DNS") === 0) info.dns = info.dns ? info.dns + ", " + v : v;
                    else if (k === "@link") {
                        var p = v.split(":");          // yes:5180 MHz:540 Mbit/s:WPA2
                        var mhz = parseInt(p[1]) || 0;
                        info.band = mhz > 5900 ? "6 GHz" : mhz > 4900 ? "5 GHz" : mhz > 0 ? "2.4 GHz" : "";
                        info.rate = p[2] || ""; info.security = p.slice(3).join(":") || "";
                    } else if (k === "@auto") { info.autoKnown = v === "yes" || v === "no"; info.auto = v !== "no"; }
                }
            }
        }
        Process { id: autoProc; onExited: info.load() }

        PkHeader {
            id: wifiHead
            sys: view.sys; width: parent.width
            title: view.pg === "netmenu" ? wifiPage.menuSsid : "Wi-Fi"; back: true
            onBackClicked: view.goBack()
            PkIconButton { sys: view.sys; visible: view.pg === "wifi" && wifiPage.on; icon: "arrows-clockwise"; size: view.t.iMd
                           RotationAnimation on rotation { running: view.sys.wifiBusy && !view.t.still; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                           onClicked: view.sys.scanWifi() }
            PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; visible: view.pg === "wifi"; on: wifiPage.on; onToggled: view.sys.toggleWifi() }
        }

        // ---- details
        PkSection {
            sys: view.sys; width: parent.width; visible: view.pg === "netmenu" && wifiPage.menuConnected
            PkRow { sys: view.sys; title: "IP address"; value: info.ip || "…" }
            PkRow { sys: view.sys; title: "Router"; value: info.gateway || "…" }
            PkRow { sys: view.sys; title: "DNS"; value: info.dns || "…" }
            PkRow { sys: view.sys; visible: info.band !== ""; title: "Band"; value: info.band + (info.rate ? "  ·  " + info.rate : "") }
            PkRow { sys: view.sys; visible: info.security !== ""; title: "Security"; value: info.security }
        }
        PkSection {
            sys: view.sys; width: parent.width; visible: view.pg === "netmenu" && info.autoKnown
            note: "Auto-join connects to this network by itself whenever it's in range."
            PkRow {
                sys: view.sys; title: "Auto-join"
                PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; on: info.auto
                           onToggled: on => { info.auto = on; autoProc.command = ["nmcli", "connection", "modify", "id", wifiPage.menuSsid, "connection.autoconnect", on ? "yes" : "no"]; autoProc.running = true; } }
            }
        }
        PkSection {
            sys: view.sys; width: parent.width; visible: view.pg === "netmenu"
            PkRow { sys: view.sys; visible: !wifiPage.menuConnected; icon: "wifi-high"; title: "Join this network"; interactive: true
                    onClicked: { view.sys.connectWifi(wifiPage.menuSsid, ""); view.sys.page = "wifi"; } }
            PkRow { sys: view.sys; visible: wifiPage.menuConnected; icon: "wifi-slash"; title: "Disconnect"; interactive: true
                    onClicked: { view.sys.disconnectWifi(); view.sys.page = "wifi"; } }
            PkRow { sys: view.sys; visible: wifiPage.menuKnown; icon: "trash"; title: "Forget this network"; danger: true; interactive: true
                    onClicked: { view.sys.forgetWifi(wifiPage.menuSsid); view.sys.page = "wifi"; } }
        }

        // ---- off
        PkCard {
            sys: view.sys; width: parent.width; height: 120; visible: view.pg === "wifi" && !wifiPage.on
            Column {
                anchors.centerIn: parent; spacing: 8
                PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter; name: "wifi-slash"; size: view.t.iXl; color: view.t.faint }
                PkText { sys: view.sys; role: "sub"; anchors.horizontalCenter: parent.horizontalCenter; text: "Wi-Fi is off" }
            }
        }

        // ---- the network you're on
        PkCard {
            id: hero
            sys: view.sys; width: parent.width; height: 72; interactive: true
            visible: view.pg === "wifi" && wifiPage.on && (wifiPage.current !== "" || view.sys.wifiConnectingSsid !== "")
            readonly property bool joining: wifiPage.current === "" && view.sys.wifiConnectingSsid !== ""
            onClicked: if (!joining) wifiPage.details(wifiPage.current, true, true)
            Rectangle {
                x: 14; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44; radius: 22
                color: hero.joining ? view.t.veil(0.1) : view.t.on
                PkIcon { sys: view.sys; anchors.centerIn: parent; name: view.wifiIcon(view.sys.wifiQuality); filled: true; size: view.t.iMd
                         color: hero.joining ? view.t.fg : view.t.onInk }
            }
            Column {
                x: 70; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 50; spacing: 3
                PkText { sys: view.sys; role: "emph"; width: parent.width; text: hero.joining ? view.sys.wifiConnectingSsid : wifiPage.current }
                PkText { sys: view.sys; role: "sub"; width: parent.width
                         text: hero.joining ? "Connecting…"
                             : ["Connected", wifiPage.signalWord(view.sys.wifiQuality),
                                wifiPage.currentNet ? wifiPage.securityWord(wifiPage.currentNet.security) : ""].filter(x => x).join("  ·  ") }
            }
            PkIcon { sys: view.sys; visible: !hero.joining; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                     name: "info"; size: view.t.iMd; color: hero.hovered ? view.t.fg : view.t.muted }
        }

        // ---- joining: a password, or a hidden network by name
        PkCard {
            id: joinCard
            sys: view.sys; width: parent.width; visible: view.pg === "wifi" && (wifiPage.passwordFor.length > 0 || wifiPage.other)
            height: pwCol.implicitHeight + 28
            Column {
                id: pwCol
                x: 14; y: 14; width: parent.width - 28; spacing: 10
                PkText { sys: view.sys; role: "label"; text: wifiPage.other ? "Join a hidden network" : "Join “" + wifiPage.passwordFor + "”" }
                PkField { id: ssidField; sys: view.sys; width: parent.width; visible: wifiPage.other; placeholder: "Network name"; onAccepted: pw.focusIn() }
                PkField { id: user; sys: view.sys; width: parent.width; visible: !wifiPage.other && wifiPage.passwordSecurity === "eap"; placeholder: "Username"
                          onAccepted: pw.focusIn() }
                PkField { id: pw; sys: view.sys; width: parent.width; password: !showPw.selected
                          placeholder: wifiPage.other ? "Password (empty for an open network)" : "Password"
                          onAccepted: wifiPage.connectTyped() }
                PkText { sys: view.sys; visible: wifiPage.otherError !== ""; width: parent.width; wrapMode: Text.Wrap; text: wifiPage.otherError; color: view.t.accentText }
                Item {
                    width: parent.width; height: 34
                    PkIconButton { id: showPw; sys: view.sys; anchors.verticalCenter: parent.verticalCenter; icon: selected ? "eye" : "eye-slash"; size: view.t.iSm
                                   onClicked: selected = !selected }
                    PkText { sys: view.sys; role: "sub"; anchors.left: showPw.right; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
                             text: showPw.selected ? "Hide password" : "Show password" }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        PkButton { sys: view.sys; kind: "ghost"; text: "Cancel"; onClicked: wifiPage.cancelJoin() }
                        PkButton { sys: view.sys; kind: "primary"; text: hidden.running ? "Joining…" : "Join"; enabled: !hidden.running; onClicked: wifiPage.connectTyped() }
                    }
                }
            }
            Timer { id: pwFocus; interval: 80; onTriggered: wifiPage.other ? ssidField.focusIn() : wifiPage.passwordSecurity === "eap" ? user.focusIn() : pw.focusIn() }
        }
        PkText { sys: view.sys; visible: view.pg === "wifi" && !!view.sys.wifiError; x: 6; width: parent.width - 12; wrapMode: Text.Wrap
                 text: view.sys.wifiError || ""; color: view.t.accentText }

        // ---- every other network, in a list that scrolls inside the island
        Flickable {
            id: netList
            visible: view.pg === "wifi" && wifiPage.on
            width: parent.width
            readonly property int room: (view.sys.pageMaxH || 545) - wifiHead.height - view.t.groupGap
                                        - (hero.visible ? hero.height + view.t.groupGap : 0)
                                        - (joinCard.visible ? joinCard.height + view.t.groupGap : 0)
            height: Math.max(120, Math.min(contentHeight, room))
            contentHeight: listCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Column {
                id: listCol
                width: parent.width
                spacing: view.t.groupGap
                PkSection {
                    sys: view.sys; width: parent.width; title: "Saved"; visible: wifiPage.saved.length > 0
                    Repeater { model: wifiPage.saved; delegate: netRow }
                }
                PkSection {
                    sys: view.sys; width: parent.width
                    title: wifiPage.saved.length > 0 || hero.visible ? "Other networks" : "Networks"
                    PkRow { sys: view.sys; visible: wifiPage.others.length === 0; dim: true
                            title: view.sys.wifiBusy ? "Searching…" : "No other networks nearby" }
                    Repeater { model: wifiPage.others; delegate: netRow }
                    PkRow { sys: view.sys; icon: "plus"; title: "Other network…"; interactive: true; visible: !wifiPage.other
                            onClicked: { wifiPage.passwordFor = ""; wifiPage.other = true; view.sys.holdOpen = true; pwFocus.restart(); } }
                }
            }
            // a soft edge where the list continues
            Rectangle {
                parent: netList; visible: netList.interactive && !netList.atYEnd
                anchors.bottom: parent.bottom; width: parent.width; height: 36
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }
        }
        Component {
            id: netRow
            PkRow {
                id: net
                required property var modelData
                readonly property bool connecting: modelData.ssid === view.sys.wifiConnectingSsid
                sys: view.sys; interactive: true
                title: modelData.ssid
                sub: connecting ? "Connecting…" : modelData.security === "open" ? "Open network" : ""
                onClicked: wifiPage.join(modelData)
                PkIcon { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; visible: net.modelData.security !== "open"
                         name: "lock-simple"; size: 14; color: view.t.muted }
                // signal: all three arcs dim, the strength lit over them
                Item {
                    anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
                    PkIcon { sys: view.sys; anchors.centerIn: parent; name: "wifi-high"; size: view.t.iSm; color: view.t.faint }
                    PkIcon { sys: view.sys; anchors.centerIn: parent; name: view.wifiIcon(net.modelData.quality); size: view.t.iSm; color: view.t.fg }
                }
                PkIconButton { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; visible: net.modelData.known; icon: "info"; size: view.t.iSm
                               onClicked: wifiPage.details(net.modelData.ssid, false, true) }
            }
        }
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
        PkHeader { id: batHead; sys: view.sys; width: parent.width; title: "Battery"; back: true; onBackClicked: view.goBack() }
        // everything under the header scrolls inside the island
        Flickable {
            id: batScroll
            width: parent.width
            height: Math.min(contentHeight, (view.sys.pageMaxH || 545) - batHead.height - view.t.groupGap)
            contentHeight: batCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Column {
                id: batCol
                width: parent.width
                spacing: view.t.groupGap
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
            // what the selected mode actually does (TLP sets the CPU and Samsung's firmware profile;
            // scripts/custom/power-mode.sh the refresh rate and NVIDIA Dynamic Boost)
            PkSection {
                id: modeSec
                sys: view.sys; width: parent.width; visible: view.sys.showPowerProfiles
                readonly property string m: view.sys.powerProfile
                readonly property bool sixty: m === "power-saver" && view.sys.cfg.pkSaverHz
                PkRow { sys: view.sys; icon: "monitor"; title: modeSec.sixty ? "Screen at 60 Hz" : "Screen at 120 Hz"
                        sub: modeSec.sixty ? "Half the frames: less work for the GPU and CPU" : "Smooth motion; drops toward 48 Hz on a still screen" }
                PkRow { sys: view.sys; icon: "fan"
                        title: modeSec.m === "performance" ? "Fans: performance" : modeSec.m === "power-saver" ? "Fans: quiet" : "Fans: balanced"
                        sub: modeSec.m === "performance" ? "Samsung's performance profile: higher power limits, fans spin up sooner"
                           : modeSec.m === "power-saver" ? "Samsung's quiet profile: lower power limits, fans stay low"
                           : "Samsung's balanced profile" }
                PkRow { sys: view.sys; icon: "cpu"
                        title: modeSec.m === "power-saver" ? "Processor: saving" : modeSec.m === "performance" ? "Processor: full speed" : "Processor: balanced"
                        sub: modeSec.m === "power-saver" ? "Turbo boost off, prefers efficiency" : modeSec.m === "performance" ? "Turbo boost on, prefers speed" : "Turbo boost on, leans to efficiency" }
                PkRow { sys: view.sys; icon: "graphics-card"; visible: boostUnit.ok
                        title: modeSec.m === "performance" ? "Graphics: Dynamic Boost on" : "Graphics: Dynamic Boost off"
                        sub: modeSec.m === "performance" ? "On AC the GPU can borrow the CPU's power, up to 60 W"
                           : "GPU stays at its 35 W limit and can sleep when idle"
                        FileView { id: boostUnit; property bool ok: false; path: "/usr/lib/systemd/system/nvidia-powerd.service"
                                   printErrors: false; onLoaded: ok = true } }
                PkRow { sys: view.sys; icon: "graphics-card"; visible: view.sys.rtxPath !== ""
                        title: view.sys.rtxAwake ? "RTX: awake" : "RTX: asleep"
                        sub: !view.sys.rtxAwake ? "Powered off; it wakes when something needs it"
                           : rtxUsers.names.length ? "Kept awake by " + rtxUsers.names.join(", ")
                           : "Nothing of yours holds it; it should sleep in a few seconds"
                        Process { id: rtxUsers; property var names: []; property var acc: []
                                  command: [Quickshell.env("HOME") + "/.config/panacea/scripts/custom/gpu-users.sh"]
                                  stdout: SplitParser { onRead: d => rtxUsers.acc.push(String(d).trim()) }
                                  onExited: { rtxUsers.names = rtxUsers.acc; rtxUsers.acc = []; } }
                        Timer { interval: 3000; repeat: true; triggeredOnStart: true
                                running: view.sys.rtxAwake && view.sys.expanded && view.sys.page === "battery"
                                onTriggered: { rtxUsers.acc = []; rtxUsers.running = true; } } }
                PkRow {
                    sys: view.sys; title: "60 Hz in Saver"
                    PkToggle { sys: view.sys; anchors.verticalCenter: parent.verticalCenter; on: !!view.sys.cfg.pkSaverHz
                               onToggled: on => { view.sys.cfg.pkSaverHz = on; view.sys.saveCfg(); view.sys.applyPowerMode(); } }
                }
            }
            PkSection {
                sys: view.sys; width: parent.width; title: "Details"; visible: view.sys.batteryPresent
                PkRow { sys: view.sys; title: "Capacity"; visible: view.sys.batteryCapacity > 0; value: Number(view.sys.batteryCapacity).toFixed(1) + " Wh" }
                PkRow { sys: view.sys; title: "Health"; visible: view.sys.batteryHealth > 0; value: Math.round(view.sys.batteryHealth) + "%" }
                PkRow { sys: view.sys; title: view.sys.batteryCharging ? "Charging at" : "Using"; visible: Math.abs(view.sys.batteryRate) > 0.05
                        value: Math.abs(view.sys.batteryRate).toFixed(1) + " W" }
                PkRow { sys: view.sys; title: "Charging stops at"; visible: chargeLimit.limit > 0 && chargeLimit.limit < 100
                        value: chargeLimit.limit + "%"
                        FileView { id: chargeLimit; property int limit: 0; path: "/sys/class/power_supply/BAT1/charge_control_end_threshold"
                                   printErrors: false; onLoaded: limit = parseInt(text()) || 0 } }
            }
            }
            Rectangle {
                parent: batScroll; visible: batScroll.interactive && !batScroll.atYEnd
                anchors.bottom: parent.bottom; width: parent.width; height: 36
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }
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
            title: trayPage.chain.length ? String(trayPage.chain[trayPage.chain.length - 1].text || "Menu").replace(/&(?!&)/g, "")
                 : view.sys.trayMenuItem ? (view.sys.trayMenuItem.tooltipTitle || view.sys.trayMenuItem.title || "Menu") : "Menu"
            Image { anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; visible: status === Image.Ready
                    source: view.sys.trayMenuItem ? view.sys.trayMenuItem.icon : ""; sourceSize: Qt.size(44, 44); smooth: true; asynchronous: true }
        }
        // the app's menu, compact: separators as hairlines, a left column for checks or the
        // items' own icons when any has one, arrows for submenus, status lines as captions
        readonly property var entries: menuOpener.children ? menuOpener.children.values : []
        readonly property bool anyLead: entries.some(e => !e.isSeparator && ((e.icon && String(e.icon) !== "") || e.buttonType !== QsMenuButtonType.None))
        Rectangle {
            width: parent.width; height: menuCol.implicitHeight + 12
            radius: view.t.rSurface; color: view.t.surface
            Column {
                id: menuCol
                x: 6; y: 6; width: parent.width - 12
                PkRow { sys: view.sys; dim: true; visible: trayPage.entries.length === 0; title: "This menu is empty" }
                Repeater {
                    model: trayPage.entries
                    delegate: Item {
                        id: me
                        required property var modelData
                        readonly property bool sep: modelData.isSeparator
                        readonly property bool info: !modelData.enabled && !modelData.hasChildren && !sep
                        readonly property bool checkable: modelData.buttonType !== QsMenuButtonType.None
                        readonly property string label: String(modelData.text || "").replace(/&(?!&)/g, "").replace(/&&/g, "&")
                        width: parent ? parent.width : 0
                        height: sep ? 13 : info ? 30 : 38
                        visible: sep || label !== "" || !!modelData.icon
                        Rectangle { visible: me.sep; x: 10; width: parent.width - 20; height: 1; anchors.verticalCenter: parent.verticalCenter; color: view.t.veil(0.1) }
                        Rectangle { visible: !me.sep; anchors.fill: parent; radius: view.t.rSmall
                                    color: meMa.containsMouse && me.modelData.enabled ? view.t.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: view.t.dFast } } }
                        Item {
                            visible: !me.sep && trayPage.anyLead
                            x: 12; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                            PkIcon { sys: view.sys; anchors.centerIn: parent; size: 14; color: view.t.fg
                                     visible: me.checkable && me.modelData.checkState === Qt.Checked
                                     name: me.modelData.buttonType === QsMenuButtonType.RadioButton ? "radio-button" : "check"; filled: true }
                            Image { anchors.fill: parent; visible: !me.checkable && status === Image.Ready
                                    source: me.modelData.icon || ""; sourceSize: Qt.size(36, 36); smooth: true; asynchronous: true
                                    opacity: me.modelData.enabled ? 1 : 0.4 }
                        }
                        Text {
                            visible: !me.sep
                            x: trayPage.anyLead ? 42 : 12; width: parent.width - x - 34
                            anchors.verticalCenter: parent.verticalCenter
                            text: me.label; elide: Text.ElideRight
                            color: me.info ? view.t.muted : me.modelData.enabled ? view.t.fg : view.t.faint
                            font { family: view.t.font; pixelSize: me.info ? view.t.tLabel : view.t.tBody }
                        }
                        PkIcon { sys: view.sys; visible: me.modelData.hasChildren; anchors.right: parent.right; anchors.rightMargin: 12
                                 anchors.verticalCenter: parent.verticalCenter; name: "caret-right"; size: 13; color: view.t.muted }
                        MouseArea {
                            id: meMa
                            anchors.fill: parent
                            enabled: !me.sep && me.modelData.enabled
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
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
}
