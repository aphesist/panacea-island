import QtQuick
import "PkIcons.js" as Icons

// Panacea kit - a Phosphor icon by name ("wifi-high"). filled: the Fill weight (on/selected),
// otherwise Bold. Plain text: tint it with `color`.
Text {
    id: ic
    property var sys
    readonly property var t: sys.pk
    property string name: ""
    property bool filled: false
    property int size: t.iMd
    text: Icons.map[name] ? String.fromCodePoint(Icons.map[name]) : ""
    font.family: filled ? t.iconFill : t.iconBold
    font.pixelSize: size
    width: size; height: size
    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    color: t.fg
    Behavior on color { ColorAnimation { duration: ic.t.dFast } }
}
