import QtQuick
import QtQuick.Controls

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
ScrollBar {
    id: sb
    property var sys
    readonly property var t: sys.pk
    policy: ScrollBar.AsNeeded
    implicitWidth: 8
    contentItem: Rectangle {
        implicitWidth: 4
        radius: 2
        color: sb.t.veil(sb.pressed ? 0.4 : sb.hovered ? 0.3 : 0.18)
        opacity: sb.size < 1 ? 1 : 0
        Behavior on color { ColorAnimation { duration: sb.t.dFast } }
        Behavior on opacity { NumberAnimation { duration: sb.t.dBase } }
    }
    background: Item {}
}
