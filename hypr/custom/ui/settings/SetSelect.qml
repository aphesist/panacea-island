pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// One of a few: a label and a segmented control with a sliding highlight.
RowLayout {
    id: sel
    property var sys
    readonly property var t: sys.pk
    property string label: ""
    property var options: []          // [{id, text}]
    property string value: ""
    signal picked(string id)

    Layout.fillWidth: true
    spacing: 16

    Text {
        Layout.fillWidth: true
        text: sel.label; color: sel.t.fg; elide: Text.ElideRight
        font { family: sel.t.font; pixelSize: sel.t.tBody }
    }
    Rectangle {
        id: track
        Layout.preferredWidth: segs.implicitWidth + 6
        Layout.preferredHeight: 32
        radius: height / 2
        color: sel.t.veil(0.07)
        property Item active: null
        Rectangle {
            visible: track.active !== null
            y: 3; height: track.height - 6; radius: height / 2
            x: track.active ? segs.x + track.active.x : 3
            width: track.active ? track.active.width : 0
            color: sel.t.selected
            Behavior on x { NumberAnimation { duration: sel.t.dSlow; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: sel.t.dSlow; easing.type: Easing.OutCubic } }
        }
        Row {
            id: segs
            x: 3; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: sel.options
                delegate: Item {
                    id: seg
                    required property var modelData
                    readonly property bool on: sel.value === String(seg.modelData.id)
                    width: segText.implicitWidth + 24; height: track.height - 6
                    onOnChanged: if (on) track.active = seg
                    Component.onCompleted: if (on) track.active = seg
                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: seg.modelData.text
                        color: seg.on ? sel.t.fg : segMa.containsMouse ? sel.t.soft : sel.t.muted
                        font { family: sel.t.font; pixelSize: sel.t.tLabel; weight: Font.DemiBold }
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sel.picked(seg.modelData.id)
                    }
                }
            }
        }
    }
}
