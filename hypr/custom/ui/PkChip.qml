import QtQuick

// Panacea kit - a chip: a filter or tag pill. selected: lifted, white text.
Rectangle {
    id: ch
    property var sys
    readonly property var t: sys.pk
    property string text: ""
    property string icon: ""
    property bool selected: false
    signal clicked()
    implicitHeight: 32; implicitWidth: chRow.implicitWidth + 24
    radius: height / 2
    color: selected ? t.selected : ma.containsMouse ? t.veil(0.095) : t.surface
    Behavior on color { ColorAnimation { duration: ch.t.dFast } }
    Row {
        id: chRow; anchors.centerIn: parent; spacing: 6
        PkIcon { sys: ch.sys; visible: ch.icon !== ""; name: ch.icon; size: 14; filled: ch.selected
                 color: ch.selected ? ch.t.fg : ch.t.muted; anchors.verticalCenter: parent.verticalCenter }
        PkText { sys: ch.sys; role: "label"; text: ch.text; anchors.verticalCenter: parent.verticalCenter
                 color: ch.selected ? ch.t.fg : ma.containsMouse ? ch.t.soft : ch.t.muted }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
}
