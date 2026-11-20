import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// A setting that is on or off: label and explanation on the left, the switch on the right.
RowLayout {
    id: row
    property var sys
    readonly property var t: sys.pk
    property string label: ""
    property string sub: ""
    property bool on: false
    signal toggled(bool value)

    Layout.fillWidth: true
    spacing: 16
    opacity: enabled ? 1 : 0.4

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        Text {
            Layout.fillWidth: true
            text: row.label; color: row.t.fg; elide: Text.ElideRight
            font { family: row.t.font; pixelSize: row.t.tBody }
        }
        Text {
            Layout.fillWidth: true
            visible: row.sub.length > 0
            text: row.sub; color: row.t.muted; wrapMode: Text.WordWrap
            font { family: row.t.font; pixelSize: row.t.tCaption }
            lineHeight: 1.15
        }
    }
    PkToggle {
        Layout.alignment: Qt.AlignVCenter
        sys: row.sys
        on: row.on
        enabled: row.enabled
        onToggled: v => row.toggled(v)
    }
}
