import QtQuick

// The bots page's wave (grokbot's "tap the waves to type"): rounded bars in the muted ink. Still
// dots while a bot is idle or asleep; bars that move while it works, thinks or replies, taller
// while it speaks. Going between still and moving (and between heights) eases, never snaps.
// Never the bot's colour (an orb's colour stays on the orb).
Item {
    id: w
    property var sys
    readonly property var t: sys.pk
    property var clock: sys ? sys.clock : null
    property string reaction: "idle"
    property int bars: 15
    readonly property bool busy: ["working", "thinking", "compute", "speaking", "listening"].indexOf(reaction) >= 0
    readonly property real ampTo: reaction === "speaking" ? 1.25 : reaction === "listening" ? 0.9 : 0.8
    property real _ph: 0
    property real _m: busy ? 1 : 0          // 0 still .. 1 moving (eased below)
    property real _amp: ampTo
    implicitWidth: bars * 6 - 3.6; implicitHeight: 22
    BotTick {
        clock: w.clock
        active: w.visible && (w.busy || w._m > 0.001 || Math.abs(w._amp - w.ampTo) > 0.001)
        onTick: function (dt) {
            w._ph += dt;
            var to = w.busy ? 1 : 0;
            w._m = to > w._m ? Math.min(1, w._m + dt / 0.4) : Math.max(0, w._m - dt / 0.4);
            w._amp += (w.ampTo - w._amp) * Math.min(1, dt * 6);
        }
    }
    readonly property real _mix: { var q = _m; return q * q * (3 - 2 * q); }
    readonly property var rest: [0.35, 0.55, 0.35, 0.2, 0.2, 0.55, 0.8, 0.55, 0.2, 0.2, 0.35, 0.55, 0.35, 0.2, 0.2]
    Row {
        anchors.centerIn: parent; spacing: 3.6
        Repeater { model: w.bars
            Rectangle {
                readonly property real moving: 0.14 + 0.86 * w._amp * Math.abs(Math.sin(w._ph * (4.2 + (index % 5) * 1.1) + index * 1.9))
                                     * (0.6 + 0.4 * Math.sin(w._ph * 1.7 + index * 0.55)) * (1 - Math.abs(index - (w.bars - 1) / 2) / w.bars)
                readonly property real lvl: w.rest[index % w.rest.length] * (1 - w._mix) + moving * w._mix
                width: 2.4; radius: 1.2
                height: Math.max(2.4, lvl * w.height)
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.45 + 0.25 * w._mix)
            }
        }
    }
}
