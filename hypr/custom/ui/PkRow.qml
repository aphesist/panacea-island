import QtQuick

// Panacea kit - a row in a card: title (and a sub line) on the left; on the right a quiet
// value, a caret when it opens something, or any control (children). An optional leading
// icon for lists of things (devices, files), not for settings. hot: lifted (selected).
Rectangle {
    id: rw
    property var sys
    readonly property var t: sys.pk
    property string icon: ""
    property url image: ""            // an app icon instead of a Phosphor icon
    property bool iconFilled: false
    property string title: ""
    property string sub: ""
    property string value: ""
    property bool caret: false
    property bool interactive: caret
    property bool hot: false
    property bool danger: false
    property bool dim: false
    default property alias trailing: trail.data
    signal clicked()
    width: parent ? parent.width : 300
    implicitHeight: sub !== "" ? t.rowH2 : t.rowH
    radius: t.rControl
    color: hot ? t.hover : (interactive && ma.containsMouse) ? t.hover : "transparent"
    Behavior on color { ColorAnimation { duration: rw.t.dFast } }
    MouseArea { id: ma; anchors.fill: parent; enabled: rw.interactive; hoverEnabled: rw.interactive
                cursorShape: rw.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: rw.clicked() }
    Image { visible: rw.image != ""; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24
            source: rw.image; sourceSize: Qt.size(48, 48); smooth: true; asynchronous: true }
    PkIcon { id: lead; sys: rw.sys; visible: rw.icon !== "" && rw.image == ""; x: 12; anchors.verticalCenter: parent.verticalCenter
             name: rw.icon; filled: rw.iconFilled; size: 22; color: rw.iconFilled ? rw.t.fg : rw.t.muted }
    Column {
        x: rw.icon !== "" || rw.image != "" ? 46 : 12; width: parent.width - x - right.width - 24
        anchors.verticalCenter: parent.verticalCenter; spacing: 2
        PkText { sys: rw.sys; width: parent.width; text: rw.title
                 color: rw.danger ? rw.t.accentText : rw.dim ? rw.t.muted : rw.t.fg }
        PkText { sys: rw.sys; role: "sub"; visible: rw.sub !== ""; width: parent.width; text: rw.sub }
    }
    Row {
        id: right
        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        PkText { sys: rw.sys; role: "sub"; visible: rw.value !== ""; text: rw.value; anchors.verticalCenter: parent.verticalCenter }
        Row { id: trail; spacing: 10; anchors.verticalCenter: parent.verticalCenter }
        PkIcon { sys: rw.sys; visible: rw.caret; name: "caret-right"; size: 14; anchors.verticalCenter: parent.verticalCenter
                 color: ma.containsMouse ? rw.t.fg : rw.t.muted }
    }
}
