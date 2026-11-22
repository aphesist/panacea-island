import QtQuick

// The bots views' clock: every frame's dt, from the frame clock, or from `clock` when a test drives
// it by hand (clock.manual, clock.tick(dt)), so previews render at an exact 60 fps.
Item {
    id: tk
    property var clock: null
    property bool active: true
    signal tick(real dt)
    readonly property bool manual: !!(clock && clock.manual)
    FrameAnimation { running: tk.active && !tk.manual; onTriggered: tk.tick(Math.min(frameTime, 0.05)) }
    Connections { target: tk.manual ? tk.clock : null; function onTick(dt) { if (tk.active) tk.tick(dt); } }
}
