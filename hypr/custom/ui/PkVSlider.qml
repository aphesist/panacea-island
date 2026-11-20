import QtQuick

// Panacea kit - a tall slider (volume, brightness): the white fill rises with the value. The fill
// is a full-size copy of the track's rounded shape seen through a straight clip at the fill line,
// so it follows the walls at every level. The icon and
// the value are drawn twice, white over the track and black inside the fill, so they invert
// exactly where the fill's edge crosses them, like a difference blend. Drag, click or scroll.
// iconClicked: e.g. mute.
Item {
    id: vs
    property var sys
    readonly property var t: sys.pk
    property string icon: ""
    property real value: 0.5          // 0..1
    property bool showValue: true
    signal moved(real value)
    signal iconClicked()
    implicitWidth: 64; implicitHeight: 180
    function setFrom(y) { vs.moved(Math.max(0, Math.min(1, 1 - y / height))); }

    // the fill's height, eased when the value changes from outside (not while dragging)
    property real level: Math.max(0, Math.min(1, value))
    Behavior on level { enabled: !ma.pressed; NumberAnimation { duration: vs.t.dFast; easing.type: Easing.OutCubic } }
    readonly property real fillH: height * level

    Rectangle {
        anchors.fill: parent; radius: vs.t.rSurface; color: vs.t.surface
    }
    PkSliderInk { slider: vs; color: vs.t.fg; subColor: vs.t.muted }
    // below the fill line: the white track shape and the same ink in black
    Item {
        anchors.bottom: parent.bottom
        width: parent.width; height: vs.fillH
        clip: true
        Rectangle { y: -(vs.height - parent.height); width: vs.width; height: vs.height; radius: vs.t.rSurface; color: vs.t.on }
        PkSliderInk { slider: vs; y: -(vs.height - parent.height); color: vs.t.onInk; subColor: vs.t.onSub }
    }

    MouseArea {
        id: ma
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; preventStealing: true
        onPressed: m => vs.setFrom(m.y)
        onPositionChanged: m => { if (pressed) vs.setFrom(m.y); }
        onWheel: w => vs.moved(Math.max(0, Math.min(1, vs.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
    // the icon's own hit area (mute, night light)
    MouseArea {
        width: 44; height: 44
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 5
        cursorShape: Qt.PointingHandCursor
        onClicked: vs.iconClicked()
    }
}
