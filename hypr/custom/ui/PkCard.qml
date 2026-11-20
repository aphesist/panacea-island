import QtQuick

// Panacea kit - a card: one tone above the island, the surface corner, no stroke.
// interactive: lifts under the pointer; clicked(mouse).
Rectangle {
    id: c
    property var sys
    readonly property var t: sys.pk
    property bool interactive: false
    property alias hovered: ma.containsMouse
    property alias pressed: ma.pressed
    signal clicked(var mouse)
    radius: t.rSurface
    color: interactive && ma.pressed ? t.veil(0.12) : interactive && ma.containsMouse ? t.veil(0.095) : t.surface
    Behavior on color { ColorAnimation { duration: c.t.dFast } }
    MouseArea { id: ma; anchors.fill: parent; enabled: c.interactive; hoverEnabled: c.interactive
                cursorShape: c.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: m => c.clicked(m) }
}
