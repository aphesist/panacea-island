import QtQuick
import Quickshell

// The island's Bots tab: one boopis bot at a time, big, the way grokbot-notch shows them.
// ‹ › (or ← →, or a sideways swipe) cycles: the orb turns round and comes back as the next bot
// (BotOrb's spin-morph), the name and line slide the same way. Under the bot, what it's up to:
// idle = its last activity, listening (the voxtype key) = the voice, working = a live summary,
// steps, time and stop. The orb opens the chat (typing a letter does too, with the letter in the
// box); boopis's bot glyph top right opens the bot's quick actions over the stage.
Item {
    id: v
    property var sys
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    readonly property int n: link.bots.length
    property int idx: 0
    property int dir: 1
    property bool actions: false           // the quick actions sheet is over the stage
    readonly property var bot: n > 0 ? link.bots[Math.min(idx, n - 1)] : null
    property bool heroHidden: false        // the Bots tab's flying hero stands in for the stage orb
    readonly property alias stageOrb: orb
    // talk mode: dictating on the stage (the voxtype key) - the bot listens
    readonly property bool talking: !!(sys && sys.voxTo === "chat" && sys.voxState !== "")
    readonly property string shownReaction: talking ? "listening" : (bot ? bot.reaction : "idle")
    readonly property bool busy: !!bot && link.busyWords.indexOf(bot.reaction) >= 0
    readonly property string mode: talking ? "listening" : busy ? "working" : "idle"
    readonly property var act: link.activity(bot)
    // the working row shows the turn as it was while it fades out (its steps clear when it ends)
    property var workAct: null
    onActChanged: {
        if (mode !== "working" || !act) return;
        if (workAct && act.since === workAct.since && act.of < workAct.of) return;   // the reply clears the steps: same turn, keep them
        workAct = act;
    }
    onModeChanged: if (mode === "working") workAct = act
    // the wall clock for "12 min ago" and the turn's time, a tick a second while it's on screen
    property double now: Date.now()
    Timer { interval: 1000; repeat: true; running: v.visible; triggeredOnStart: true; onTriggered: v.now = Date.now() }
    function ago(ms) {
        if (!ms) return "";
        var s = Math.max(0, (now - ms) / 1000);
        return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + " min ago" : s < 86400 ? Math.floor(s / 3600) + " h ago" : Math.floor(s / 86400) + " d ago";
    }
    function clockText(ms) { var s = ms ? Math.max(0, Math.floor((now - ms) / 1000)) : 0; return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    signal openChat(string botId)
    signal openTeam()
    signal openSettings()

    width: 400
    implicitHeight: col.implicitHeight + 2 * t.pad

    // the position dots' easing, kept here by bot id: the roster array is replaced on every update
    // (the Repeater rebuilds its dots), so state inside a dot would restart at its target and snap
    property var _dots: ({})
    property int _dotRev: 0
    property bool _dotsBusy: true
    onIdxChanged: _dotsBusy = true
    onLinkBotsChanged: _dotsBusy = true
    readonly property var linkBots: link.bots
    BotTick {
        clock: v.sys.clock; active: v._dotsBusy
        onTick: function (dt) {
            var moved = false, bs = v.link.bots;
            for (var i = 0; i < bs.length; i++) {
                var kt = i === v.idx ? 1 : 0, rt = bs[i].attention ? 1 : 0, d = v._dots[bs[i].id];
                if (!d) { v._dots[bs[i].id] = { k: kt, r: rt }; continue; }
                var k = v._toward(d.k, kt, dt / 0.32), r = v._toward(d.r, rt, dt / 0.25);
                if (k !== d.k || r !== d.r) { d.k = k; d.r = r; moved = true; }
            }
            v._dotRev++;
            if (!moved) v._dotsBusy = false;
        }
    }

    function _toward(x, to, step) { return x < to ? Math.min(to, x + step) : Math.max(to, x - step); }

    function cycle(d) {
        if (n < 2) return;
        dir = d; idx = (idx + d + n) % n;
        link.current = bot.id;
    }
    // the line under the name
    function lineFor(b) {
        if (!b) return "";
        if (b.attention) return "needs you · " + b.last;
        if (mode === "listening") return "Listening…";
        if (mode === "working" && act) return act.summary + (act.of > 1 ? ", " + act.n + " of " + act.of : "");
        return b.role || b.last;
    }
    function lastWords(b) { return !b ? "" : b.last ? b.last : b.lastAt ? "Active" : "No activity yet"; }
    function lastWhen(b) { var a = b ? ago(b.lastAt) : ""; return a ? (b.last ? " · " : " ") + a : ""; }

    focus: true
    Keys.onLeftPressed: if (!actions) cycle(-1)
    Keys.onRightPressed: if (!actions) cycle(1)
    Keys.onEscapePressed: function (e) { if (actions) actions = false; else e.accepted = false; }
    Keys.onPressed: function (e) {          // just type: the bot's chat opens with the letter in the box
        if (!actions && bot && e.text.length === 1 && e.text.trim() !== "" && !(e.modifiers & Qt.ControlModifier)) {
            sys.botsDraft = e.text; e.accepted = true; openChat(bot.id);
        }
    }
    // the sheet and the slot's states move on the bots' clock (same spring as everything here)
    BotSpring { id: actSp; clock: v.sys.clock; to: v.actions ? 1 : 0; ms: v.sys.animMs || 380; bounce: 0; still: !!v.sys.noMotion }
    readonly property real ap: Math.max(0, Math.min(1, actSp.value))
    BotSpring { id: idleSp; clock: v.sys.clock; to: v.mode === "idle" ? 1 : 0; ms: v.sys.animMs || 380; bounce: 0; still: !!v.sys.noMotion }
    BotSpring { id: listenSp; clock: v.sys.clock; to: v.mode === "listening" ? 1 : 0; ms: v.sys.animMs || 380; bounce: 0; still: !!v.sys.noMotion }
    BotSpring { id: workSp; clock: v.sys.clock; to: v.mode === "working" ? 1 : 0; ms: v.sys.animMs || 380; bounce: 0; still: !!v.sys.noMotion }
    property real _ph: 0
    BotTick { clock: v.sys.clock; active: v.visible && (v.mode !== "idle" || listenSp.moving || workSp.moving); onTick: function (dt) { v._ph += dt; } }

    Column {
        id: col
        x: v.t.pad; y: v.t.pad; width: v.width - 2 * v.t.pad
        spacing: 0

        // team · position dots · settings
        Item {
            width: parent.width; height: 30
            PkIconButton { sys: v.sys; icon: "users-three"; size: v.t.iSm; anchors.verticalCenter: parent.verticalCenter
                           opacity: 1 - v.ap; visible: opacity > 0.01; onClicked: v.openTeam() }
            PkIconButton { sys: v.sys; icon: "caret-left"; size: v.t.iSm; anchors.verticalCenter: parent.verticalCenter
                           opacity: v.ap; visible: opacity > 0.01; onClicked: v.actions = false }
            Text { anchors.centerIn: parent; opacity: v.ap; visible: opacity > 0.01
                   text: (v.bot ? v.bot.name : "") + " · actions"; color: v.t.fg
                   font { family: v.t.font; pixelSize: 13; bold: true } }
            Row {
                opacity: 1 - v.ap; visible: opacity > 0.01
                anchors.centerIn: parent; anchors.alignWhenCentered: false; spacing: 5
                Repeater { model: v.link.bots
                    Rectangle {
                        // plain numbers: a binding that returns the same object would never re-evaluate users
                        readonly property real sk: { v._dotRev; var d = v._dots[modelData.id]; return d ? d.k : (index === v.idx ? 1 : 0); }
                        readonly property real sr: { v._dotRev; var d = v._dots[modelData.id]; return d ? d.r : (modelData.attention ? 1 : 0); }
                        readonly property real ek: sk * sk * (3 - 2 * sk)
                        readonly property real er: sr * sr * (3 - 2 * sr)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 + 8 * ek; height: 6; radius: 3; antialiasing: true   // sub-pixel widths, no stepping
                        readonly property color base: Qt.rgba(1, 1, 1, 0.14 + 0.86 * ek)
                        color: Qt.rgba(base.r + (0.843 - base.r) * er, base.g + (0.098 - base.g) * er, base.b + (0.129 - base.b) * er,
                                       base.a + (1 - base.a) * er)
                    }
                }
            }
            // boopis's own bot glyph: the bot's quick actions
            Item {
                id: actBtn
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: v.t.iSm + 14; height: width
                opacity: 1 - v.ap; visible: opacity > 0.01
                Rectangle { anchors.fill: parent; radius: width / 2
                            color: actMa.pressed ? v.t.pressed : actMa.containsMouse ? v.t.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: v.t.dFast } } }
                BotsGlyph { anchors.centerIn: parent; size: v.t.iSm; color: actMa.containsMouse ? v.t.fg : v.t.muted }
                MouseArea { id: actMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: v.actions = true }
            }
        }

        Item { width: 1; height: 6 }

        BotOrb {
            id: orb
            anchors.horizontalCenter: parent.horizontalCenter
            store: v.sys.orbs; size: 92; dir: v.dir; clock: v.sys.clock
            botId: v.bot ? v.bot.id : ""; shape: v.bot ? v.bot.shape : "circle"
            color: v.bot ? v.bot.color : "#a6a6ab"; reaction: v.shownReaction
            opacity: (v.heroHidden ? 0 : 1) * (1 - v.ap)
            MouseArea { anchors.fill: parent; enabled: !v.actions; cursorShape: Qt.PointingHandCursor; onClicked: v.openChat(v.bot.id) }
        }

        Item { width: 1; height: 10 }
        BotSlideText { sys: v.sys; width: parent.width; dir: v.dir; px: v.t.tEmph + 1; weight: Font.DemiBold; opacity: 1 - v.ap
                       key: v.bot ? v.bot.id : ""; text: v.bot ? v.bot.name : "" }
        Item { width: 1; height: 4 }
        BotSlideText { id: caption; sys: v.sys; width: parent.width - 40; anchors.horizontalCenter: parent.horizontalCenter
                       dir: v.dir; px: v.t.tLabel; key: v.bot ? v.bot.id : ""; opacity: 1 - v.ap
                       color: v.bot && v.bot.attention ? v.t.accentText : v.mode === "working" ? Qt.rgba(1, 1, 1, 0.85) : v.t.muted
                       text: v.lineFor(v.bot) }
        Item { width: 1; height: 16 }

        // ‹  what the bot is up to  ›
        Item {
            id: bottom
            width: parent.width; height: 34
            opacity: 1 - v.ap
            PkIconButton { id: prev; sys: v.sys; icon: "caret-left"; size: v.t.iMd; anchors.verticalCenter: parent.verticalCenter
                           onClicked: v.cycle(-1) }
            PkIconButton { id: next; sys: v.sys; icon: "caret-right"; size: v.t.iMd; anchors.right: parent.right
                           anchors.verticalCenter: parent.verticalCenter; onClicked: v.cycle(1) }
            Item {
                id: slot
                anchors { left: prev.right; right: next.left; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                height: 32

                // idle: the last thing it did, and when; slides with the bot like the name and line
                Item {
                    id: idleBox
                    anchors.fill: parent
                    readonly property real on: Math.max(0, Math.min(1, idleSp.value))
                    opacity: Math.pow(on, 2.5); visible: on > 0.01     // out mostly gone before in shows
                    clip: true
                    property string key: v.bot ? v.bot.id : ""
                    property var cur: ({ words: v.lastWords(v.bot), when: v.lastWhen(v.bot) })
                    property var old: null
                    property real p: 1
                    property int sd: 1
                    onKeyChanged: { old = { words: rowA.words, when: rowA.when }; sd = v.dir; p = v.sys.noMotion ? 1 : 0; }
                    BotTick { clock: v.sys.clock; active: idleBox.p < 1
                              onTick: function (dt) { idleBox.p = Math.min(1, idleBox.p + dt / 0.34); } }
                    readonly property real e: 1 - Math.pow(1 - p, 3)
                    BotsLastRow { id: rowA; sys: v.sys; width: slot.width; height: slot.height; words: idleBox.cur.words; when: idleBox.cur.when
                              x: idleBox.sd * 24 * (1 - idleBox.e); opacity: idleBox.old ? idleBox.e : 1 }
                    BotsLastRow { sys: v.sys; width: slot.width; height: slot.height; visible: !!idleBox.old && idleBox.p < 1; words: idleBox.old ? idleBox.old.words : ""; when: idleBox.old ? idleBox.old.when : ""
                              x: -idleBox.sd * 24 * idleBox.e; opacity: 1 - idleBox.e }
                    MouseArea { anchors.fill: parent; enabled: v.mode === "idle" && !v.actions; cursorShape: Qt.PointingHandCursor
                                onClicked: if (v.bot) v.openChat(v.bot.id) }
                }
                // listening: the voice, soft at the sides like the chat boxes
                Item {
                    anchors.fill: parent
                    readonly property real on: Math.max(0, Math.min(1, listenSp.value))
                    opacity: Math.pow(on, 2.5); visible: on > 0.01     // out mostly gone before in shows
                    Row {
                        anchors.centerIn: parent; spacing: 3.6
                        Repeater { model: 31
                            Rectangle {
                                readonly property real c: 1 - Math.pow(Math.abs(index - 15) / 16, 1.6)
                                // a voice-like envelope: syllables in words, a breath between phrases
                                readonly property real env: { var ph = v._ph % 3.2; if (ph > 2.4) return 0.05;
                                                              var syl = ph * 4.3, k = syl - Math.floor(syl), pk = 0.55 + 0.45 * Math.abs(Math.sin(Math.floor(syl) * 12.9898));
                                                              return 0.08 + pk * (k < 0.25 ? k / 0.25 : Math.pow(1 - (k - 0.25) / 0.75, 1.5)); }
                                readonly property real j: 0.55 + 0.45 * Math.abs(Math.sin(v._ph * (5.1 + (index % 7) * 0.9) + index * 2.3))
                                width: 2.4; radius: 1.2; anchors.verticalCenter: parent.verticalCenter
                                height: Math.max(2.4, (0.08 + 0.92 * env * c * j * parent.parent.on) * 26)
                                color: Qt.rgba(1, 1, 1, 0.55 + 0.45 * env * c)
                            }
                        }
                    }
                    Rectangle { anchors.left: parent.left; width: 56; height: parent.height
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "#000000" } GradientStop { position: 1; color: "#00000000" } } }
                    Rectangle { anchors.right: parent.right; width: 56; height: parent.height
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#000000" } } }
                }
                // working: steps, the turn's time, stop
                Item {
                    id: workBox
                    anchors.fill: parent
                    readonly property real on: Math.max(0, Math.min(1, workSp.value))
                    opacity: Math.pow(on, 2.5); visible: on > 0.01     // out mostly gone before in shows
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Row { anchors.verticalCenter: parent.verticalCenter
                            // the step bars: six fixed slots (a count model would rebuild them all), each
                            // springing between 0 and its width, so a new step grows in and the row re-centres
                            Repeater { model: 6
                                Item {
                                    id: bar
                                    required property int index
                                    readonly property bool on: !!v.workAct && bar.index < v.workAct.of
                                    BotSpring { id: bw; clock: v.sys.clock; to: bar.on ? 26 : 0; ms: v.sys.animMs || 380; still: !!v.sys.noMotion }
                                    width: 26 * Math.max(0, Math.min(1, bw.value / 26 / 0.85)); height: 4; clip: true   // done by 85 %: no tail creep
                                    Rectangle { width: 22; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.14); opacity: Math.min(1, bar.width / 26)
                                        Rectangle { height: parent.height; radius: 2; color: v.t.fg
                                                    // done steps full; the one running fills and empties, calm (no wrap)
                                                    width: !v.workAct ? 0 : bar.index < v.workAct.n - 1 ? parent.width
                                                         : bar.index === v.workAct.n - 1 ? parent.width * (0.5 - 0.5 * Math.cos(2 * Math.PI * v._ph / 2.4)) : 0 } } } } }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: v.t.muted; font { family: v.t.font; pixelSize: 11 }
                               text: v.clockText(v.workAct ? v.workAct.since : 0) }
                        Item {
                            width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { anchors.fill: parent; radius: 12; color: stopMa.containsMouse ? v.t.veil(0.14) : v.t.surface
                                        Behavior on color { ColorAnimation { duration: v.t.dFast } } }
                            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 2; color: v.t.fg }
                            MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        enabled: v.mode === "working"; onClicked: if (v.bot) v.link.interrupt(v.bot.id) }
                        }
                    }
                }
            }
        }
    }

    // ---- the quick actions, over the stage (same height: the island doesn't move)
    Grid {
        id: sheet
        x: col.x; y: col.y + orb.y; width: col.width
        readonly property real h: bottom.y + bottom.height - orb.y
        columns: 3; spacing: 8
        opacity: v.ap; visible: opacity > 0.01
        transform: Translate { y: 8 * (1 - Math.min(1, v.ap / 0.85)) }
        Repeater {
            model: [
                { icon: "chat-circle", label: "New chat", ok: true },
                { icon: "play", label: "Run now", ok: false },
                { icon: "pause", label: "Pause schedule", ok: false },
                { icon: "stop", label: "Interrupt", ok: v.busy },
                { icon: "article", label: "Logs", ok: false },
                { icon: "arrow-square-out", label: "Open in boopis", ok: true } ]
            Rectangle {
                id: tile
                required property var modelData
                required property int index
                width: (sheet.width - 16) / 3; height: (sheet.h - 8) / 2
                radius: v.t.rSurface
                color: tileMa.containsMouse && modelData.ok ? v.t.veil(0.11) : v.t.surface
                Behavior on color { ColorAnimation { duration: v.t.dFast } }
                Column {
                    anchors.centerIn: parent; spacing: 7
                    opacity: tile.modelData.ok ? 1 : 0.38
                    PkIcon { sys: v.sys; name: tile.modelData.icon; size: 20; color: v.t.fg; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.label; color: v.t.fg; opacity: 0.85
                           font { family: v.t.font; pixelSize: 11 } }
                }
                MouseArea {
                    id: tileMa; anchors.fill: parent; hoverEnabled: true; enabled: v.actions
                    cursorShape: tile.modelData.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!tile.modelData.ok || !v.bot) return;
                        if (tile.index === 0) { v.actions = false; v.openChat(v.bot.id); }
                        else if (tile.index === 3) { v.link.interrupt(v.bot.id); v.actions = false; }
                        else if (tile.index === 5) { Quickshell.execDetached(["gtk-launch", "boopis"]); v.sys.collapse(); }
                    }
                }
            }
        }
    }

    // the stage (orb, name, line): the wheel cycles bots there, both ways, instead of swiping the
    // island's tabs (sys.swipeYield, like Home's carousel). One bot per notch; a touchpad scroll is one
    // bot per gesture; a step waits for the last to get going (debounced), and the event is taken.
    Item {
        id: stage
        x: 0; width: v.width
        y: col.y + orb.y - 8
        height: caption.y + caption.height - orb.y + 16
        HoverHandler {
            id: stageHover
            onHoveredChanged: if (v.sys) v.sys.swipeYield = hovered
        }
        Component.onDestruction: if (v.sys && stageHover.hovered) v.sys.swipeYield = false
        WheelHandler {
            id: wheel
            enabled: !v.actions
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            orientation: Qt.Horizontal | Qt.Vertical
            property real acc: 0
            property bool spent: false        // touchpad: this gesture already stepped
            property double lastStep: 0
            onWheel: function (e) {
                e.accepted = true;
                var touch = e.pixelDelta.x !== 0 || e.pixelDelta.y !== 0;
                var dx = touch ? e.pixelDelta.x : e.angleDelta.x, dy = touch ? e.pixelDelta.y : e.angleDelta.y;
                var d = Math.abs(dx) > Math.abs(dy) ? dx : dy;
                quiet.restart();
                if (touch) {
                    if (spent) return;
                    wheel.acc += d;
                    if (Math.abs(wheel.acc) < 60) return;
                    spent = true;
                } else {
                    wheel.acc += d;
                    if (Math.abs(wheel.acc) < 120) return;     // one notch
                    var now = Date.now();
                    if (now - lastStep < 160) { wheel.acc = 0; return; }
                    lastStep = now;
                }
                var step = wheel.acc < 0 ? 1 : -1;            // down / swipe left = the next bot
                wheel.acc = 0;
                v.cycle(step);
            }
        }
        Timer { id: quiet; interval: 220; onTriggered: { wheel.acc = 0; wheel.spent = false; } }
    }
}
