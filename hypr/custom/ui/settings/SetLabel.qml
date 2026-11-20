import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// The small title over a group of rows.
Text {
    id: cap
    property var sys
    readonly property var t: sys.pk
    Layout.fillWidth: true
    Layout.topMargin: 2
    color: t.muted
    elide: Text.ElideRight
    font { family: cap.t.font; pixelSize: cap.t.tCaption; weight: Font.DemiBold }
}
