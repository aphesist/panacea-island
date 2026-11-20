import QtQuick

// Panacea kit - a bare icon you click (bell, power, settings, search...). No shape around it:
// grey, white under the pointer, a soft round veil when pressed. dot: the red dot (unread,
// waiting updates). selected: white and filled.
Item {
    id: ib
    property var sys
    readonly property var t: sys.pk
    property string icon: ""
    property int size: t.iMd
    property bool selected: false
    property bool dot: false
    property bool bright: false       // white at rest too (media controls)
    signal clicked()
    implicitWidth: size + 14; implicitHeight: size + 14
    Rectangle {
        anchors.fill: parent; radius: width / 2
        color: ma.pressed ? ib.t.pressed : ma.containsMouse ? ib.t.hover : "transparent"
        Behavior on color { ColorAnimation { duration: ib.t.dFast } }
    }
    PkIcon { id: glyph; sys: ib.sys; anchors.centerIn: parent; name: ib.icon; size: ib.size; filled: ib.selected
             color: ib.selected || ib.bright || ma.containsMouse ? ib.t.fg : ib.t.muted
             opacity: ib.enabled ? 1 : 0.3 }
    Rectangle { visible: ib.dot; x: glyph.x + glyph.width - width / 2 - 1; y: glyph.y - 1
                width: 7; height: 7; radius: 3.5; color: ib.t.accent }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
}
