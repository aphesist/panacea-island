import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// A page title: left-aligned, no card (the glyph is kept for compatibility, not drawn).
ColumnLayout {
    id: head
    property var sys
    readonly property var t: sys.pk
    property string glyph: ""
    property string title: ""
    property string sub: ""
    Layout.fillWidth: true
    spacing: 4
    Text {
        Layout.fillWidth: true
        text: head.title; color: head.t.fg; elide: Text.ElideRight
        font { family: head.t.font; pixelSize: head.t.tTitle; weight: Font.Bold }
    }
    Text {
        Layout.fillWidth: true
        visible: head.sub.length > 0
        text: head.sub; color: head.t.muted; wrapMode: Text.WordWrap
        font { family: head.t.font; pixelSize: head.t.tLabel }
    }
}
