import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// A pill button. primary: white, the one main action of a group.
Rectangle {
    id: btn
    property var sys
    readonly property var t: sys.pk
    property string text: ""
    property bool primary: false
    signal clicked()

    Layout.preferredWidth: btnLabel.implicitWidth + 32
    Layout.preferredHeight: 32
    radius: height / 2
    opacity: btn.enabled ? 1 : 0.4
    color: btn.primary ? (ma.pressed ? Qt.darker(t.on, 1.12) : ma.containsMouse ? Qt.darker(t.on, 1.05) : t.on)
                       : (ma.pressed ? t.veil(0.2) : ma.containsMouse ? t.veil(0.15) : t.veil(0.1))
    Behavior on color { ColorAnimation { duration: btn.t.dFast } }

    Text {
        id: btnLabel
        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? btn.t.onInk : btn.t.fg
        font { family: btn.t.font; pixelSize: btn.t.tLabel; weight: Font.DemiBold }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
