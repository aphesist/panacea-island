import QtQuick

// The one motion for anything that changes shape: an island, a panel, a card, a pill.
// `value` follows `to` like a critically damped spring tuned by a duration: about 95% of the
// way at `ms`, then it settles. Bind the shape to `value`:
//
//   PkMorph { id: mw; to: open ? 330 : 190; ms: sys.animMs; bounce: sys.animBounce; still: sys.noMotion }
//   width: mw.value
//
// Why not a Behavior:
// - NumberAnimation restarts from zero speed whenever its target changes mid-flight (hover, a
//   page laying out in two passes, a bar reappearing under the cursor): the shape moves in steps.
// - Qt's SpringAnimation keeps its speed but advances in whole 16 ms ticks, so on a 120 Hz
//   screen it moves only every other frame: a visible stutter.
// This one integrates on every rendered frame with the real frame time and keeps its speed
// when `to` changes, so it bends towards the new target instead of restarting.
//
// The rule (DESIGN.md, "Morphing"): width, height and every corner radius of one shape use
// PkMorph with the same ms and bounce, so its corners match its edges on every frame.
FrameAnimation {
    id: m
    property real to: 0
    property real value: 0
    property real velocity: 0
    property int ms: 300
    property real bounce: 0          // 0..1: the Motion tab's overshoot; 0 never passes the target
    property bool still: false       // Reduce motion: jump straight to the target
    property bool _ready: false

    readonly property real omega: 5000 / Math.max(16, ms)            // rad/s: ~95% at ms
    readonly property real zeta: Math.max(0.3, 1 - 1.3 * bounce)     // damping ratio

    function snap() { m.value = m.to; m.velocity = 0; m.running = false; }

    onToChanged: {
        if (!m._ready || m.still || m.ms <= 0) m.snap();
        else if (m.value !== m.to || m.velocity !== 0) m.running = true;
    }
    onStillChanged: if (m.still) m.snap()
    Component.onCompleted: { m.value = m.to; m._ready = true; }

    onTriggered: {
        var dt = Math.min(Math.max(m.frameTime, 0), 0.05);
        if (dt <= 0) return;
        var k = m.omega * m.omega, c = 2 * m.zeta * m.omega, x = m.value, v = m.velocity, t = m.to;
        var n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;       // 4 ms substeps: stable at any rate
        for (var i = 0; i < n; i++) { v += (k * (t - x) - c * v) * h; x += v * h; }
        if (Math.abs(t - x) < 0.05 && Math.abs(v) < 2) { m.snap(); return; }
        m.velocity = v;
        m.value = x;
    }
}
