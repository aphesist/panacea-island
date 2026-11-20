import QtQuick
import QtQuick.Layouts

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// A value on a scale: label and value above, a thin white track below.
ColumnLayout {
    id: sl
    property var sys
    readonly property var t: sys.pk
    property string label: ""
    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property string suffix: ""
    property int decimals: 0
    property string valueText: sl.value.toFixed(sl.decimals) + (sl.suffix ? " " + sl.suffix : "")
    signal moved(real value)

    Layout.fillWidth: true
    spacing: 10
    opacity: enabled ? 1 : 0.4

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: sl.label; color: sl.t.fg; elide: Text.ElideRight
            font { family: sl.t.font; pixelSize: sl.t.tBody }
        }
        Text {
            text: sl.valueText; color: sl.t.soft
            font { family: sl.t.font; pixelSize: sl.t.tLabel; weight: Font.DemiBold }
        }
    }
    Item {
        id: bar
        Layout.fillWidth: true
        implicitHeight: 20
        readonly property real span: Math.max(1e-6, sl.to - sl.from)
        readonly property real frac: Math.max(0, Math.min(1, (sl.value - sl.from) / span))
        function pick(px) {
            var f = Math.max(0, Math.min(1, (px - 9) / Math.max(1, bar.width - 18)));
            var snapped = Math.round((sl.from + f * span) / sl.step) * sl.step;
            sl.moved(Math.max(sl.from, Math.min(sl.to, snapped)));
        }
        Rectangle {
            x: 9; width: parent.width - 18; height: 4; radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: sl.t.track
            Rectangle { width: parent.width * bar.frac; height: parent.height; radius: 2; color: sl.t.fg }
        }
        Rectangle {
            x: (bar.width - 18) * bar.frac
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9; color: sl.t.fg
            scale: grab.pressed ? 1.12 : 1
            Behavior on scale { NumberAnimation { duration: sl.t.dFast } }
        }
        MouseArea {
            id: grab
            anchors.fill: parent
            anchors.topMargin: -6; anchors.bottomMargin: -6
            enabled: sl.enabled
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed: mouse => bar.pick(mouse.x)
            onPositionChanged: mouse => { if (pressed) bar.pick(mouse.x); }
        }
    }
}
