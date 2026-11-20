import QtQuick

// Panacea kit - a horizontal slider for settings: a thin track, the white part is the value,
// a round white knob. Drag, click or scroll.
Item {
    id: hs
    property var sys
    readonly property var t: sys.pk
    property real value: 0.5          // 0..1
    signal moved(real value)
    implicitWidth: 240; implicitHeight: 22
    function setFrom(x) { hs.moved(Math.max(0, Math.min(1, (x - 9) / (width - 18)))); }
    Rectangle {
        x: 9; width: parent.width - 18; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter
        color: hs.t.track
        Rectangle { width: parent.width * hs.value; height: 4; radius: 2; color: hs.t.fg }
    }
    Rectangle {
        x: (parent.width - 18) * hs.value; anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18; radius: 9; color: hs.t.fg
        scale: ma.pressed ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: hs.t.dFast } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
        cursorShape: Qt.PointingHandCursor; preventStealing: true
        onPressed: m => hs.setFrom(m.x)
        onPositionChanged: m => { if (pressed) hs.setFrom(m.x); }
        onWheel: w => hs.moved(Math.max(0, Math.min(1, hs.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
