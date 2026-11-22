import QtQuick

// written by portal-patch.py (panacea-island) - PkMorph's spring (same omega and damping from
// ms / bounce, same 4 ms substeps, keeps its speed when `to` changes), driven by BotTick so the
// bots views' clock (and the exact-60-fps tests) moves it like the orbs.
Item {
    id: m
    visible: false
    property var clock: null
    property real to: 0
    property real value: 0
    property real velocity: 0
    property int ms: 300
    property real bounce: 0
    property bool still: false
    readonly property bool moving: tk.active
    readonly property real omega: 5000 / Math.max(16, ms)
    readonly property real zeta: Math.max(0.3, 1 - 1.3 * bounce)
    property bool _ready: false
    function snap() { value = to; velocity = 0; tk.active = false; }
    onToChanged: { if (!_ready || still || ms <= 0) snap(); else if (value !== to || velocity !== 0) tk.active = true; }
    property bool fromZero: false            // start at 0 and spring to `to` (a thing growing in)
    Component.onCompleted: { value = fromZero && !still ? 0 : to; _ready = true; if (value !== to) tk.active = true; }
    BotTick {
        id: tk
        clock: m.clock
        active: false
        onTick: function (dt) {
            dt = Math.min(Math.max(dt, 0), 0.05);
            if (dt <= 0) return;
            var k = m.omega * m.omega, c = 2 * m.zeta * m.omega, x = m.value, v = m.velocity, t = m.to;
            var n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;
            for (var i = 0; i < n; i++) { v += (k * (t - x) - c * v) * h; x += v * h; }
            if (Math.abs(t - x) < 0.0005 && Math.abs(v) < 0.01) { m.snap(); return; }
            m.velocity = v; m.value = x;
        }
    }
}
