import QtQuick

// Panacea kit - a switch: white with a black knob when on, a grey track when off.
Item {
    id: tg
    property var sys
    readonly property var t: sys.pk
    property bool on: false
    property bool enabled: true
    signal toggled(bool on)
    implicitWidth: 40; implicitHeight: 24
    opacity: enabled ? 1 : 0.4
    Rectangle {
        anchors.fill: parent; radius: height / 2
        color: tg.on ? tg.t.on : tg.t.track
        Behavior on color { ColorAnimation { duration: tg.t.dBase } }
        Rectangle {
            y: 3; width: parent.height - 6; height: width; radius: width / 2
            x: tg.on ? parent.width - width - 3 : 3
            color: tg.on ? tg.t.onInk : Qt.rgba(1, 1, 1, 0.6)
            Behavior on x { NumberAnimation { duration: tg.t.dBase; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: tg.t.dBase } }
        }
    }
    MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: tg.enabled
                cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.on) }
}
