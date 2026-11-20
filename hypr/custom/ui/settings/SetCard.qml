import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// A group of settings: one surface, rows inside.
Rectangle {
    id: card
    property var sys
    readonly property var t: sys.pk
    default property alias content: inner.data
    property alias spacing: inner.spacing
    property int pad: 16

    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + pad * 2
    radius: t.rSurface
    color: t.surface

    ColumnLayout {
        id: inner
        anchors.fill: parent
        anchors.margins: card.pad
        spacing: 14
    }
}
