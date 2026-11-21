import QtQuick

// A bare kit button for the island's mpv bar: an icon (or a short label like "1.5×"), grey at
// rest, white with a soft veil under the pointer.
Item {
    id: b
    property var sys
    readonly property var t: sys.pk
    property string name: ""
    property string label: ""
    property bool filled: false
    property int size: t.iSm
    property color tint: ma.containsMouse ? t.fg : t.soft
    signal clicked()
    width: label !== "" ? Math.max(40, lab.implicitWidth + 16) : 32
    height: 32
    Rectangle {
        anchors.fill: parent; radius: b.t.rSmall
        color: ma.pressed ? b.t.pressed : ma.containsMouse ? b.t.hover : "transparent"
        Behavior on color { ColorAnimation { duration: b.t.dFast } }
    }
    PkIcon { visible: b.label === ""; sys: b.sys; anchors.centerIn: parent; name: b.name; filled: b.filled; size: b.size; color: b.tint }
    Text {
        id: lab; visible: b.label !== ""; anchors.centerIn: parent; text: b.label; color: b.tint
        font { family: b.t.font; pixelSize: b.t.tLabel; weight: Font.DemiBold }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
